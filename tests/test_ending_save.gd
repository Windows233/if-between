## 结局与存档：结局表、达成标记、存档读写与恢复。
##
## 存档存的是**当前全部状态**：场景、坐标、朝向、剧情进度、世界状态、结局进度。
## 读档要回到玩家离开的那一步，不是把他丢回场景开头 ——
## 所以这里一半的用例在盯「读回来是不是当时那个样」。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
class_name TestEndingSave
extends RefCounted

## 存档测试用一个专门的槽位，不碰玩家真正会用的槽位 0。
const TEST_SLOT := 2


static func run(h: TestHarness) -> void:
	test_ending_def_and_table(h)
	test_ending_marks_on_story(h)
	test_ending_from_real_data(h)
	test_save_data_roundtrip(h)
	test_save_store_file(h)
	test_save_and_load_game(h)
	test_save_during_story(h)
	test_save_resumes_mid_node(h)
	test_load_does_not_replay(h)
	test_load_does_not_replay_talk(h)
	test_save_menu_does_not_close_choices(h)
	test_save_keeps_transient_actors(h)
	test_ending_reconcile(h)
	test_once_interaction(h)
	test_v1_save_readable(h)


static func test_ending_def_and_table(h: TestHarness) -> void:
	var table := EndingTable.from_array([
		{"id": "good_end", "title": "重逢", "summary": "找到了。", "kind": "good"},
		{"id": "bad_end", "title": "没能找到", "kind": "bad"},
	])
	h.check("解析出两个结局", table.endings.size(), 2)
	h.check("查得到", table.get_ending(&"good_end").title, "重逢")
	h.check("查不到返回 null", table.get_ending(&"nope"), null)
	h.check("类型识别", table.get_ending(&"good_end").kind, EndingDef.Kind.GOOD)
	h.check("没写 kind 是普通结局", table.get_ending(&"bad_end").kind, EndingDef.Kind.BAD)
	h.check("表没问题时没有报错", table.validate().is_empty(), true)

	# 标题没写就退回 id，界面上不至于空白
	var bare := EndingDef.from_dictionary({"id": "x"})
	h.check("没标题退回 id", bare.display_title(), "x")

	# 重复 id 要报出来
	var dup := EndingTable.from_array([{"id": "a"}, {"id": "a"}])
	h.check("重复 id 报错", dup.validate().is_empty(), false)

	var flags := WorldState.new()
	h.check("一开始没达成", EndingTable.is_unlocked(flags, &"good_end"), false)
	EndingTable.unlock(flags, &"good_end")
	h.check("标记后达成了", EndingTable.is_unlocked(flags, &"good_end"), true)
	h.check("只算一次", table.count_unlocked(flags), 1)
	h.check("进度键带前缀", EndingTable.flag_key(&"good_end"), &"ending/good_end")


static func _ending_event() -> StoryEvent:
	return StoryEvent.from_dictionary({
		"id": "e",
		"entry": "ask",
		"nodes": [
			{
				"id": "ask",
				"talk": [{"text": "……"}],
				"choices": [
					{"id": "go", "label": "去", "next": "found"},
					{"id": "stay", "label": "留", "next": "missed"},
				],
			},
			{"id": "found", "ending": "good_end", "talk": [{"text": "找到了。"}]},
			{"id": "missed", "ending": "bad_end", "talk": [{"text": "错过了。"}]},
		],
	})


static func test_ending_marks_on_story(h: TestHarness) -> void:
	var event := _ending_event()
	h.check("结局表对得上", event.validate([&"good_end", &"bad_end"]).is_empty(), true)
	# 结局写错名字要能查出来
	var wrong := _ending_event()
	var node: StoryNode = wrong.nodes[1]
	node.ending = &"typo"
	h.check("结局名写错会报", wrong.validate([&"good_end", &"bad_end"]).is_empty(), false)

	var flags := WorldState.new()
	var story := StoryRuntime.new()
	story.start(event, flags)

	# 走到结局节点之前不该标记
	story.on_dialogue_finished()
	h.check("还没走到结局", story.take_ending(), &"")

	h.check("选了去找", story.choose(&"go"), true)
	h.check("进了结局节点", story.current_node_id(), &"found")
	h.check("结局节点的对话在", story.current_dialogue().lines.size(), 1)

	# 对话播完才标记 —— 台词没看到就发「达成」很怪
	h.check("结局节点播完不再弹选项", story.on_dialogue_finished(), false)
	h.check("剧情到此结束", story.is_finished(), true)
	h.check("取到结局 id", story.take_ending(), &"good_end")
	h.check("取走之后清空", story.take_ending(), &"")
	h.check("写进了世界状态", EndingTable.is_unlocked(flags, &"good_end"), true)
	h.check("另一个没达成", EndingTable.is_unlocked(flags, &"bad_end"), false)

	# 结局节点是终点：写了 next 也不走
	var tailed := StoryEvent.from_dictionary({
		"id": "t", "entry": "a",
		"nodes": [
			{"id": "a", "ending": "good_end", "next": "b", "talk": [{"text": "x"}]},
			{"id": "b", "talk": [{"text": "不该走到这"}]},
		],
	})
	h.check("结局节点带 next 会警告", tailed.validate([&"good_end"]).is_empty(), false)
	var s2 := StoryRuntime.new()
	s2.start(tailed, WorldState.new())
	s2.on_dialogue_finished()
	h.check("结局后不再往下走", s2.is_finished(), true)


static func test_ending_from_real_data(h: TestHarness) -> void:
	var main := h.new_main()

	h.check("结局表读进来了", main.endings.endings.size(), 4)
	h.check("一开始一个都没达成", main.unlocked_endings().size(), 0)

	# 第一章开场整段跑完：接受/不接受那一步选「不接受」，一路走到 end1
	h.play_to_end1(main)

	h.check("达成了一个结局", main.unlocked_endings().size(), 1)
	h.check("达成的是平静即死亡", EndingTable.is_unlocked(main.flags, &"end1_calm"), true)
	h.check("另一个没达成", EndingTable.is_unlocked(main.flags, &"end2_sweet"), false)

	main.queue_free()


static func test_save_data_roundtrip(h: TestHarness) -> void:
	var data := SaveData.new()
	data.slot = 1
	data.saved_at = "2026-09-21 20:00"
	data.map_id = &"desk_shop"
	data.spawn = &"start"
	data.player_position = Vector2(96, 132)
	data.facing = Vector2.LEFT
	data.story_event = &"elder_commission"
	data.story_node = &"start"
	data.flags = {"quest_opened": true, "ending/end1_calm": true}

	var back := SaveData.from_dictionary(data.to_dictionary())
	h.check("场景回来了", back.map_id, &"desk_shop")
	h.check("出生点回来了", back.spawn, &"start")
	h.check("状态回来了", back.flags.get("quest_opened"), true)

	# 坐标和朝向：走了一半的路不该白走
	h.check("坐标回来了", back.player_position, Vector2(96, 132))
	h.check("朝向回来了", back.facing, Vector2.LEFT)
	h.check("记了坐标", back.has_position(), true)

	# 剧情进度：读档要从那个节点接着演
	h.check("剧情事件回来了", back.story_event, &"elder_commission")
	h.check("剧情节点回来了", back.story_node, &"start")
	h.check("算是在剧情里", back.in_story(), true)

	# 结局进度
	h.check("结局倒出来一个", back.ending_ids().size(), 1)
	h.check("倒出来的是 end1", back.ending_ids()[0], &"end1_calm")
	h.check("摘要里有场景名", back.summary().begins_with("desk_shop"), true)

	var table := EndingTable.from_array([{"id": "end1_calm", "title": "平静即死亡"}])
	h.check("摘要能翻成标题", back.summary(table).find("平静即死亡") >= 0, true)

	h.check("完好的存档没问题", back.validate().is_empty(), true)
	var broken := SaveData.new()
	h.check("没写场景会报错", broken.validate().is_empty(), false)

	# 坏数据不该把游戏搞崩，读出来是个空壳
	var junk := SaveData.from_dictionary("不是字典")
	h.check("坏数据不崩", junk.map_id, &"")
	h.check("坏数据没坐标", junk.has_position(), false)
	h.check("坏数据不在剧情里", junk.in_story(), false)

	# 零向量算「没记」，读档要退回出生点
	var no_pos := SaveData.new()
	no_pos.player_position = Vector2.ZERO
	h.check("零向量不算记了坐标", no_pos.has_position(), false)


static func test_save_store_file(h: TestHarness) -> void:
	SaveStore.delete(TEST_SLOT)
	h.check("删完之后没有存档", SaveStore.exists(TEST_SLOT), false)
	h.check("读不存在的槽位返回 null", SaveStore.read(TEST_SLOT), null)

	var data := SaveData.new()
	data.map_id = &"desk_shop"
	data.spawn = &"start"
	data.flags = {"quest_opened": true}
	h.check("写成功", SaveStore.write(TEST_SLOT, data), true)
	h.check("写完之后有了", SaveStore.exists(TEST_SLOT), true)

	var read := SaveStore.read(TEST_SLOT)
	h.check("读回来了", read != null, true)
	h.check("槽位号对", read.slot, TEST_SLOT)
	h.check("状态对", read.flags.get("quest_opened"), true)

	h.check("列表里有它", SaveStore.list_all().size() >= 1, true)
	h.check("删成功", SaveStore.delete(TEST_SLOT), true)
	h.check("删完真没了", SaveStore.exists(TEST_SLOT), false)


static func test_save_and_load_game(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)

	# 先做出一点值得一存的状态：开场演完（选①，不走到结局）
	h.start_opening(main)
	h.pick(main, &"accept")
	h.drain_dialogue(main.dialogue)
	h.check("开场记下了", ItemTable.count_of(main.flags, &"cat_photo"), 1)

	# 走到房间另一头再存：读档要回到这个坐标，不是出生点
	main.player.global_position = Vector2(120, 160)
	main.player.facing = Vector2.LEFT
	h.check("能存档", main.can_save(), true)
	h.check("存成功", main.save_game(TEST_SLOT), true)

	# 把状态搅乱：换个场景，把标记清掉
	main.enter_map(&"overworld", &"default")
	main.flags.clear()
	h.check("标记被清掉了", ItemTable.count_of(main.flags, &"cat_photo"), 0)

	h.check("读档成功", main.load_game(TEST_SLOT), true)
	h.check("回到存档时的场景", main.current_map.id, &"desk_shop")
	h.check("回到存档时的坐标", main.player.global_position, Vector2(120, 160))
	h.check("朝向也回来了", main.player.facing, Vector2.LEFT)
	h.check("标记也回来了", ItemTable.count_of(main.flags, &"cat_photo"), 1)
	h.check("读档后有提示", main.toast.is_open(), true)

	SaveStore.delete(TEST_SLOT)
	h.check("空槽位读不出来", main.load_game(TEST_SLOT), false)

	main.queue_free()


## 剧情演到一半存档。以前是「剧情中不给存」，现在反过来：
## 存的是当前全部状态，剧情进度也在里面，读档从那个节点接着演。
static func test_save_during_story(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)

	# 剧情跑到一半：开场演到了「等玩家选」那一步，面板还留着
	h.start_opening(main)
	h.check("面板留着", main.dialogue.is_holding(), true)
	h.check("剧情中也能存", main.can_save(), true)
	h.check("剧情中存成功", main.save_game(TEST_SLOT), true)

	var saved := SaveStore.read(TEST_SLOT)
	h.check("存档记了事件", saved.story_event, &"ch1_opening")
	h.check("存档记了节点", saved.story_node, &"ask")
	h.check("存档记了坐标", saved.player_position, Vector2(224, 130))
	h.check("存档算在剧情里", saved.in_story(), true)
	h.check("那时还没结局", saved.ending_ids().size(), 0)
	main.queue_free()

	# 读回来该接着「正在选」那一步：面板留着、选项还在
	var revived := h.new_main()
	# 即时模式要在读档**之前**开：开场那几个演出节点读档时会重跑一遍
	revived.cutscene.instant = true
	h.check("读档成功", revived.load_game(TEST_SLOT), true)
	h.check("回到存档时的场景", revived.current_map.id, &"desk_shop")
	h.check("剧情接着演", revived.story.is_active(), true)
	h.check("接回存档时的节点", revived.story.current_node_id(), &"ask")
	h.check("选项又摆出来了", revived.choice_menu.is_open(), true)
	h.check("面板还留着", revived.dialogue.is_holding(), true)

	h.pick(revived, &"accept")
	h.check("选择照样生效", revived.flags.get_value(&"quest_cat"), true)

	revived.queue_free()
	SaveStore.delete(TEST_SLOT)


## 存的是**演到一半**的一段：读回来要从那个节点接着演，
## 而不是从入口再来一遍。这里用合成事件测 —— 开场的演出是即时跑的，
## 卡在中间反而不好摆。
static func test_save_resumes_mid_node(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)

	var event := StoryEvent.from_dictionary({
		"id": "mid",
		"entry": "a",
		"nodes": [
			{"id": "a", "talk": [{"speaker": "甲", "text": "第一句"},
				{"speaker": "甲", "text": "第二句"}], "next": "b"},
			{"id": "b", "talk": [{"text": "到了 b"}]},
		],
	})
	main.story.start(event, main.flags)
	h.check("停在第一个节点", main.story.current_node_id(), &"a")
	h.check("对话开着", main.dialogue.is_open(), true)
	h.check("存成功", main.save_game(TEST_SLOT), true)

	var saved := SaveStore.read(TEST_SLOT)
	h.check("记了事件", saved.story_event, &"mid")
	h.check("记了节点", saved.story_node, &"a")
	main.queue_free()

	# 接着演：用同一段事件、从记下的那个节点接回去。
	# （合成的「mid」没有数据文件，走不了 `load_game` 那条读文件的路；
	#   那条路由 `test_save_during_story` 用真实事件覆盖。）
	var revived := h.new_main()
	revived.story.start(event, revived.flags, saved.story_node)
	h.check("接着演", revived.story.is_active(), true)
	h.check("接回那个节点", revived.story.current_node_id(), &"a")
	h.check("对话重新开着", revived.dialogue.is_open(), true)

	# 从接着的地方往下走，能走到下一个节点。
	# **一行按两下**：先显示完，再翻页；一次 `drain` 会把后面全走光，
	# 那就什么都看不到了。
	h.check("当前是第一句", revived.dialogue.current_index(), 0)
	revived.dialogue.advance()
	revived.dialogue.advance()
	revived.dialogue.advance()
	revived.dialogue.advance()
	h.check("走到了下一个节点", revived.story.current_node_id(), &"b")

	revived.queue_free()
	SaveStore.delete(TEST_SLOT)


## 在「等选择」那一步存档，读回来**不能把整段台词重新念一遍**。
##
## 用户原话：「加载到神秘人选项阶段，会回到对话开头重新放」。
## 根子在于存档只记到**节点**，而一个节点的 `stage` 会从第一条重跑 ——
## 神秘人那段的对白全在 `stage` 里，于是十五句从头再说一遍。
static func test_load_does_not_replay(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)
	main.enter_map(&"desk_shop", &"start")

	# 神秘人那段：一整段对白 + 一句提示 + 摆成等选择，全在 `stage` 里。
	# 存档这一边开即时模式 —— 无头里没有帧循环，不等点击。
	main.cutscene.instant = true
	main.start_story(&"meet_b")
	h.check("停在选项上", main.choice_menu.is_open(), true)
	h.check("对话框在等选择", main.dialogue.is_holding(), true)
	h.check("说了整整十五句", main.dialogue.log_panel().entry_count(), 15)
	# 舞台三条全部演完 —— 存档要记的就是这个数。
	#
	# 这一段的对白写在 `stage` 里、节点自己没有 `talk`，所以只需要它一位；
	# 「整段话写在 talk 里」的那种节点另有一条测试（`test_load_does_not_replay_talk`）。
	h.check("舞台演完了", main.story.stage_step(), 3)

	h.check("存成功", main.save_game(TEST_SLOT), true)
	var saved := SaveStore.read(TEST_SLOT)
	h.check("存档记了步数", saved.story_step, 3)
	main.queue_free()

	# **读档这一边故意不开即时模式。** 真玩法里读档就是这个样子：
	# 走「从头念一遍」那条路的话，对话框会停在第一句等玩家点，
	# 得点十几下才轮到选项 —— 选项框根本不会出现。
	var revived := h.new_main()
	h.check("读档成功", revived.load_game(TEST_SLOT), true)
	h.check("接回那个节点", revived.story.current_node_id(), &"start")
	h.check("选项直接就在", revived.choice_menu.is_open(), true)
	h.check("对话框还在等选择", revived.dialogue.is_holding(), true)
	# 一步都没重演：补演不记流水，而三步都已经演过了，正常演那一段是空的
	var seen: Array = revived.cutscene.history()
	h.check("一条演出都没重来", seen.size(), 0)

	# 选下去照样往下走
	h.pick(revived, &"doubt")
	h.check("选择生效", revived.flags.get_value(&"seen/meet_b"), true)
	h.check("走到了不信那一段", revived.story.current_node_id(), &"distrust")

	revived.queue_free()
	SaveStore.delete(TEST_SLOT)


## 同上，但换一种节点：整段话写在 `talk` 里、压根没有舞台。
##
## 「接老人委托」那段就是这样，而且它用户也报过（「保存之后对话框文字
## 和选项都没了」，同一份存档读回来还会把话重说一遍）。
## 这一种 `stage_step` 帮不上忙 —— 它没有舞台，得单独记「这段话说过了没有」。
static func test_load_does_not_replay_talk(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)
	main.enter_map(&"desk_shop", &"start")

	main.cutscene.instant = true
	main.start_story(&"elder_commission")
	h.check("停在选项上", main.choice_menu.is_open(), true)
	h.check("对话框在等选择", main.dialogue.is_holding(), true)
	h.check("说了四句", main.dialogue.log_panel().entry_count(), 4)
	h.check("这个节点没有舞台", main.story.stage_step(), 0)
	h.check("记下了这段话说过了", main.story.spoke(), true)

	h.check("存成功", main.save_game(TEST_SLOT), true)
	var saved := SaveStore.read(TEST_SLOT)
	h.check("存档记了念过", saved.story_spoke, true)
	main.queue_free()

	var revived := h.new_main()
	h.check("读档成功", revived.load_game(TEST_SLOT), true)
	h.check("接回那个节点", revived.story.current_node_id(), &"start")
	h.check("选项直接就在", revived.choice_menu.is_open(), true)
	h.check("对话框还在等选择", revived.dialogue.is_holding(), true)
	h.check("没重念一遍", revived.cutscene.history().size(), 0)

	revived.queue_free()
	SaveStore.delete(TEST_SLOT)


## 开存档菜单**不能把剧情选项框收掉**。
##
## 选项框不是「一个面板」，是**剧情正停在那儿等你选**。收掉它，对话框就卡在
## `hold_open` 那个空壳上（`_begin_hold()` 会把正文清空），选项再也点不出来。
## 用户报的「按下保存之后对话框文字和选项都没了，再次加载才正常」就是这个 ——
## 看着像文字被吃了，其实是剧情被关在了「等选择」上。
static func test_save_menu_does_not_close_choices(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)
	main.enter_map(&"desk_shop", &"start")
	main.cutscene.instant = true
	main.start_story(&"meet_b")
	h.check("先有选项框", main.choice_menu.is_open(), true)

	main.open_save_menu()
	h.check("存档菜单开着", main.save_menu.is_open(), true)
	h.check("选项框还留着", main.choice_menu.is_open(), true)
	h.check("对话框还在等选择", main.dialogue.is_holding(), true)

	# 关掉存档菜单，选项照样选得动 —— 死锁的表现就是这一步点不动。
	# `distrust` 是结局节点，选完这一段就收尾了，所以看的是 flags 不是下一个节点。
	main.save_menu.close()
	h.check("关掉之后还能选", h.pick(main, &"doubt"), true)
	h.check("选完确实走到结局了",
		main.flags.get_value(&"ending/end3_nothing"), true)

	main.queue_free()
	SaveStore.delete(TEST_SLOT)


## 场上站着的**临时角色**要跟着存档走。
##
## 他们不是地图数据的一部分，是演出现造的（`Cutscene._actors`）——
## 不存的话读档回来人就不见了：剧情正停在「跟神秘人说话」上，
## 那个「神秘人」是空的（用户报的「小人图像不见了」）。
static func test_save_keeps_transient_actors(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)
	main.enter_map(&"desk_shop", &"start")

	main.cutscene.instant = true
	main.cutscene.add_actor_with_talk("b", "res://art/portrait/mysterious.png",
		Vector2(150.0, 215.0), 30.0, 9, "", "meet_b")
	h.check("人放上来了", main.cutscene.actor_ids().has("b"), true)
	var where: Vector2 = main.cutscene.talkable_at("b")[1]

	h.check("存成功", main.save_game(TEST_SLOT), true)
	var saved := SaveStore.read(TEST_SLOT)
	h.check("存档记了这个人", saved.actors.size(), 1)
	main.queue_free()

	var revived := h.new_main()
	h.check("读档成功", revived.load_game(TEST_SLOT), true)
	h.check("人又站回来了", revived.cutscene.actor_ids().has("b"), true)
	h.check("站在原来的地方", revived.cutscene.talkable_at("b")[1], where)
	h.check("还挂着那段对话", revived.cutscene.talkable_at("b")[0], &"meet_b")

	revived.queue_free()
	SaveStore.delete(TEST_SLOT)


## 存档记的结局列表和 flags 里的结局进度是同一件事的两面，
## 对不上说明有一边坏了 —— 静默按一边算，玩家会莫名少一个结局。
static func test_ending_reconcile(h: TestHarness) -> void:
	# 存档记了，flags 里丢了 → 补回 flags
	var data := SaveData.new()
	data.map_id = &"desk_shop"
	data.flags = {"ending/end1_calm": true}
	data.endings.append(&"end1_calm")
	data.endings.append(&"end2_sweet")

	var flags := WorldState.new()
	flags.set_value(&"ending/cat_lost", true)
	h.check("补之前缺一个", EndingTable.is_unlocked(flags, &"end2_sweet"), false)

	var restored := data.reconcile_endings(flags)
	h.check("补回了一个", restored.size(), 1)
	h.check("补回的是 end2", EndingTable.is_unlocked(flags, &"end2_sweet"), true)
	h.check("补完两边一致", data.endings.size(), 2)

	# 反过来：flags 里有，存档列表没记 → 补进列表
	var other := SaveData.new()
	other.map_id = &"desk_shop"
	other.flags = {"ending/end2_sweet": true}
	var f2 := WorldState.new()
	f2.set_value(&"ending/end2_sweet", true)

	h.check("补之前列表是空的", other.endings.size(), 0)
	other.reconcile_endings(f2)
	h.check("列表补上了", other.endings.has(&"end2_sweet"), true)

	# 两边本来就一致 → 什么都不补
	other.reconcile_endings(f2)
	h.check("一致的不再补", other.endings.size(), 1)


## 一次性事件：演过就不再触发。「演过」记在 `seen/<事件 id>` 里，
## 跟着存档走，所以读档回到过去也不会再送一遍。
static func test_once_interaction(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)

	var real_map: MapDef = main.current_map
	main.current_map = _once_map()
	var inter: MapDef.Interaction = main.current_map.actors[0].interactions[0]
	h.check("once 读进来了", inter.once, true)

	main.play_interaction(inter)
	h.check("第一次会演", main.story.is_active(), true)
	h.check("记下了演过", main.has_seen(&"ch1_opening"), true)

	# 演完就收工：同一个存档里再碰也不会重演
	main.story.cancel()
	main.play_interaction(inter)
	h.check("演过就不再演", main.story.is_active(), false)
	h.check("也不会再弹对话", main.dialogue.is_open(), false)

	main.current_map = real_map
	h.check("存成功", main.save_game(TEST_SLOT), true)
	main.queue_free()

	# 换一个新的游戏读这个档：seen 得跟着存档过来
	var revived := h.new_main()
	h.check("读档成功", revived.load_game(TEST_SLOT), true)
	h.check("读档后记得演过", revived.has_seen(&"ch1_opening"), true)

	revived.current_map = _once_map()
	var again: MapDef.Interaction = revived.current_map.actors[0].interactions[0]
	revived.play_interaction(again)
	h.check("读档后也不会再演", revived.story.is_active(), false)
	h.check("读档后也不会弹对话", revived.dialogue.is_open(), false)

	revived.queue_free()
	SaveStore.delete(TEST_SLOT)


## 老存档（v1：只有场景 + 出生点 + flags）还得读得出来。
## 缺的坐标退回出生点，缺的结局列表从 flags 倒出来。
static func test_v1_save_readable(h: TestHarness) -> void:
	_write_raw(TEST_SLOT, {
		"version": 1,
		"slot": TEST_SLOT,
		"saved_at": "2026-01-01 10:00",
		"map": "desk_shop",
		"spawn": "start",
		"flags": {"quest_opened": true, "ending/end1_calm": true},
	})

	var data := SaveStore.read(TEST_SLOT)
	h.check("v1 读得出来", data != null, true)
	h.check("版本是 1", data.version, 1)
	h.check("没有坐标", data.has_position(), false)
	h.check("不在剧情里", data.in_story(), false)
	h.check("结局从 flags 倒出来", data.ending_ids().size(), 1)

	var main := h.new_main()
	h.check("v1 能读档", main.load_game(TEST_SLOT), true)
	h.check("落到出生点", main.player.global_position, Vector2(173, 293))
	h.check("标记回来了", main.flags.get_value(&"quest_opened"), true)
	h.check("结局进度回来了", main.unlocked_endings().size(), 1)
	h.check("回来的是 end1", EndingTable.is_unlocked(main.flags, &"end1_calm"), true)

	main.queue_free()
	SaveStore.delete(TEST_SLOT)


# ---------------------------------------------------------------- 工具

## 一个带「一次性事件」的角色。数据文件里暂时还没用到 `once`，
## 所以这里自己拼一张小地图来测。
static func _once_map() -> MapDef:
	return MapDef.from_dictionary({
		"id": "once_room",
		"kind": "room",
		"size": [320, 180],
		"spawns": {"start": [60, 140]},
		"actors": [
			{
				"id": "neighbor",
				"rect": [72, 110, 16, 24],
				"label": "邻居",
				"actions": [
					{"id": "talk", "label": "看看", "event": "ch1_opening", "once": true},
				],
			},
		],
	})


## 绕过 SaveData 直接写一份原始 JSON。用来造「老版本的存档」。
static func _write_raw(slot: int, payload: Dictionary) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if not dir.dir_exists(SaveStore.SAVE_DIR):
		dir.make_dir_recursive(SaveStore.SAVE_DIR)
	var file := FileAccess.open(SaveStore.path_for(slot), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
