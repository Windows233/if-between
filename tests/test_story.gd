## 剧情事件：节点、IF 选项、条件地图元素、分支。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
class_name TestStory
extends RefCounted


static func run(h: TestHarness) -> void:
	test_story_event_data(h)
	test_story_runtime_flow(h)
	test_story_choice_condition(h)
	test_opening_full_run(h)
	test_conditional_map_elements(h)
	test_decline_reaches_end1(h)
	test_accept_sleep_and_rewind(h)


static func test_accept_sleep_and_rewind(h: TestHarness) -> void:
	var main := h.new_main()
	h.start_opening(main)
	h.pick(main, &"accept")
	var bedroom_portal: MapDef.Portal
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.event_id == &"ch1_sleep":
			bedroom_portal = portal
	h.check("接单后卧室入口存在", bedroom_portal != null, true)
	if bedroom_portal == null:
		main.queue_free()
		return
	main.player.position = bedroom_portal.rect.get_center()
	main._take_portal()
	h.check("实际门口进入夜晚卧室", main.current_map.id, &"bedroom_night")
	var reachable := WalkGrid.reachable(main.current_map, main.player.position)
	var bed: MapDef.Actor
	for point: Vector2 in reachable:
		var candidate: MapDef.Actor = main.current_map.actor_near(Vector2(point), 1.0, main.flags)
		if candidate != null and candidate.id == &"bed":
			bed = candidate
			main.player.position = Vector2(point)
			break
	h.check("夜晚卧室有可走到且不被家具抢占的床交互点", bed != null, true)
	if bed == null:
		main.queue_free()
		return
	main.begin_interaction(bed)
	h.check("床提供睡觉选项", h.pick(main, &"sleep"), true)
	h.check("睡觉推进到回溯观察选项", main.choice_menu.is_open(), true)
	h.check("梦醒回到委托屋", main.current_map.id, &"desk_shop")
	h.check("回溯可以观察老人", h.pick(main, &"look"), true)
	h.check("睡觉流程收尾", main.story.is_active(), false)
	h.check("回溯后记录已睡觉", main.flags.get_value(&"gate/slept_once"), true)
	h.check("回溯后解除夜晚出门限制", main.flags.get_value(&"gate/late"), false)
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.label == "门":
			h.check("回溯后大门可用", main._portal_blocked(portal), false)
	main.update_player_control()
	h.check("回溯后恢复走动", main.player.is_physics_processing(), true)
	main.queue_free()


static func test_story_event_data(h: TestHarness) -> void:
	var event := StoryEvent.from_dictionary({
		"id": "t",
		"entry": "a",
		"nodes": [
			{
				"id": "a",
				"talk": [{"speaker": "甲", "text": "一"}],
				"choices": [{"id": "go", "label": "走", "next": "b"}],
			},
			{"id": "b", "talk": [{"text": "二"}]},
		],
	})
	h.check("节点数", event.nodes.size(), 2)
	h.check("入口节点", event.entry_node().id, &"a")
	h.check("按 id 找得到节点", event.node(&"b") != null, true)
	h.check("这份数据没问题", event.validate().size(), 0)

	# 跳到不存在的节点是最容易犯的错，必须被抓住
	var broken := StoryEvent.from_dictionary({
		"id": "bad",
		"entry": "a",
		"nodes": [{"id": "a", "talk": [], "next": "nope"}],
	})
	h.check("坏跳转被抓", broken.validate().size(), 1)

	var no_entry := StoryEvent.from_dictionary({
		"id": "bad2",
		"entry": "zzz",
		"nodes": [{"id": "a", "talk": []}],
	})
	h.check("坏入口被抓", no_entry.validate().size() >= 1, true)

	var dup := StoryEvent.from_dictionary({
		"id": "bad3",
		"nodes": [{"id": "a", "talk": []}, {"id": "a", "talk": []}],
	})
	h.check("重复 id 被抓", dup.validate().size() >= 1, true)


static func test_story_runtime_flow(h: TestHarness) -> void:
	var event := StoryEvent.from_dictionary({
		"id": "t",
		"entry": "start",
		"nodes": [
			{
				"id": "start",
				"talk": [{"speaker": "甲", "text": "选一个"}],
				"choices": [
					{"id": "yes", "label": "好", "set": {"agreed": true}, "next": "yes_node"},
					{"id": "no", "label": "不", "set": {"agreed": false}},
				],
			},
			{"id": "yes_node", "talk": [{"speaker": "甲", "text": "多谢"}]},
		],
	})

	var flags := WorldState.new()
	var runtime := StoryRuntime.new()
	runtime.start(event, flags)

	h.check("从入口开始", runtime.current_node_id(), &"start")
	h.check("拿到对话", runtime.current_dialogue().size(), 1)
	h.check("对话播完该弹选项", runtime.on_dialogue_finished(), true)
	h.check("有两个选项", runtime.current_choices().size(), 2)

	h.check("选得中", runtime.choose(&"yes"), true)
	h.check("选择被记进状态", flags.get_value(&"agreed"), true)
	h.check("跳到指定节点", runtime.current_node_id(), &"yes_node")

	h.check("这个节点没选项", runtime.on_dialogue_finished(), false)
	h.check("走完了", runtime.is_finished(), true)

	# 选一个不存在的选项应当被拒，而不是悄悄走到别处
	var fresh := StoryRuntime.new()
	fresh.start(event, WorldState.new())
	fresh.on_dialogue_finished()
	h.check("选不存在的项被拒", fresh.choose(&"nope"), false)


static func test_story_choice_condition(h: TestHarness) -> void:
	var event := StoryEvent.from_dictionary({
		"id": "t",
		"entry": "start",
		"nodes": [{
			"id": "start",
			"talk": [{"text": "嗯。"}],
			"choices": [
				{"id": "locked", "label": "进去",
				 "if": {"var": "has_key", "op": "==", "value": true}},
				{"id": "leave", "label": "离开"},
			],
		}],
	})

	var flags := WorldState.new()
	var runtime := StoryRuntime.new()
	runtime.start(event, flags)
	runtime.on_dialogue_finished()

	var choices := runtime.current_choices()
	h.check("两个选项都还在", choices.size(), 2)
	var locked: StoryChoice = choices[0]
	h.check("条件不满足时不可选", locked.is_available(flags), false)
	h.check("选了也被拒", runtime.choose(&"locked"), false)

	flags.set_value(&"has_key", true)
	h.check("条件满足后可选了", locked.is_available(flags), true)


static func test_opening_full_run(h: TestHarness) -> void:
	# 走完整链路：新游戏 -> 读文件 -> 演出 -> 台词 -> 选项 -> 分支
	var main := h.new_main()
	h.start_opening(main)

	# 即时演出把「黑屏、章标题、醒来、老人上门、照片、获得」都跑完了，
	# 停在开场那个 IF 选择框上
	h.check("剧情在跑", main.story.is_active(), true)
	h.check("停在选择那一步", main.story.current_node_id(), &"ask")
	h.check("选项框开着", main.choice_menu.is_open(), true)
	# 只有接受 / 不接受两条路。「观察」要回溯之后才解锁，
	# 条件不满足时**整条不列出来**，灰着摆在那儿会把转折提前漏给玩家。
	h.check("两个选项", main.choice_menu.option_count(), 2)

	# 演出的痕迹：老人被放出来过，而且是在场景里（不是常驻 NPC）
	h.check("老人由演出放出来过", main.cutscene.history().has("npc"), true)
	# 照片那一步走完了（淡入 -> 等点击 -> 淡出）
	h.check("照片那一步演过", main.cutscene.history().has("image"), true)
	# 获得了猫的照片：物品走的是 `item/<id>` 键，跟结局一个路子
	h.check("拿到猫的照片", ItemTable.count_of(main.flags, &"cat_photo"), 1)

	# 选项摆在对话框中间，所以这时候面板是留着的
	h.check("面板留着等选择", main.dialogue.is_holding(), true)
	h.check("界面调度认为有东西占着", main.ui_host.is_busy(), true)

	h.pick(main, &"accept")
	h.check("选择写进了 flags", main.flags.get_value(&"quest_cat"), true)
	h.check("选完面板收起来了", main.dialogue.is_holding(), false)
	# ① 那段还没定稿，即时模式下它一路演到底 —— 所以这里直接看「收尾了没」
	h.check("演完收尾", main.story.is_active(), false)
	main.update_player_control()
	h.check("收尾之后角色能动", main.player.is_physics_processing(), true)

	main.queue_free()


static func test_conditional_map_elements(h: TestHarness) -> void:
	var def := MapDef.from_dictionary({
		"id": "c",
		"size": [200, 200],
		"portals": [
			{"rect": [10, 10, 20, 20], "to": "x", "spawn": "y",
			 "if": {"var": "door_open", "op": "==", "value": true}},
		],
		"actors": [
			{"id": "always", "rect": [50, 50, 10, 20], "talk": [{"text": "在"}]},
			{"id": "later", "rect": [100, 50, 10, 20],
			 "if": {"var": "quest_cat", "op": "==", "value": true},
			 "talk": [{"text": "出现了"}]},
		],
	})

	var flags := WorldState.new()
	h.check("默认只有一个角色在场", def.active_actors(flags).size(), 1)
	h.check("条件不满足时找不到", def.actor_near(Vector2(105, 60), 30.0, flags), null)
	h.check("条件不满足时连接也不在", def.portal_at(Vector2(20, 20), flags), null)

	flags.set_value(&"quest_cat", true)
	flags.set_value(&"door_open", true)
	h.check("条件满足后角色出现", def.active_actors(flags).size(), 2)

	var found: MapDef.Actor = def.actor_near(Vector2(105, 60), 30.0, flags)
	h.check("找得到刚出现的角色", found != null, true)
	h.check("找对了人", found.id if found != null else &"", &"later")
	h.check("连接也出现了", def.portal_at(Vector2(20, 20), flags) != null, true)

	# 不传状态就不过滤，方便预览场景
	h.check("不传状态时全显示", def.active_actors(null).size(), 2)


static func test_decline_reaches_end1(h: TestHarness) -> void:
	var main := h.new_main()
	# 这条路测的是**正常流程**：结局即结束、黑幕不揭。调试开关
	# `free_roam_after_ending` 现在是开着的（布洛文要走去卧室试碰撞箱），
	# 所以显式关掉 —— 那条路另有 `test_free_roam_after_ending` 守着。
	main.free_roam_after_ending = false
	h.start_opening(main)
	h.check("老人这会儿在场景里", main.cutscene.actor_ids().has("elder"), true)

	h.pick(main, &"decline")
	# 老人沿着原路走回去、被收走
	h.check("老人走了", main.cutscene.actor_ids().has("elder"), false)
	# **换场景了**：新稿子的分支②接着演夜里那场梦 —— 切到「睡着」那张图
	#（图上本来就画着躺的人），玩家角色在那一步被藏起来。
	h.check("切到「睡着」那张图", main.current_map.id, &"bedroom_night_sleep")
	# 「藏起来」那一步由 `test_cutscene_script` 守着，这里验的是终态：
	# **剧情一结束就露回来**（`_on_story_ended`）——「藏着」是那一幕的安排，
	# 不该跟到剧情之外，不然自由走动时人看不见。
	h.check("剧情结束后人露回来了", main.player.visible, true)
	h.check("也没被按着", main.player.pinned, false)
	main.update_player_control()
	# 演出是在黑屏上收尾的：碎屏那一下把黑幕压下来，结局文字写在黑底上。
	# 回主界面时黑幕**不揭** —— 标题底下露着一个亮着的房间就像没跳干净。
	h.check("黑幕盖着", main.stage_curtain.is_down(), true)

	h.drain_dialogue(main.dialogue)
	h.check("走到了结局", main.story.is_active(), false)
	h.check("达成 end1", EndingTable.is_unlocked(main.flags, &"end1_calm"), true)
	h.check("没达成 end2", EndingTable.is_unlocked(main.flags, &"end2_sweet"), false)
	# 结局文字改成由剧本自己演（黑屏正中那两行），不再弹对话框 ——
	# 演完直接回主界面，控制权不还给玩家
	h.check("结局文字没走对话框", main.dialogue.is_open(), false)
	h.check("回到主界面", main.title_screen.is_open(), true)

	main.queue_free()
