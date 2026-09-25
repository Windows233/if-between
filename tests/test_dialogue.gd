## 对话与选项：对话框、立绘、动作菜单、选项框。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
class_name TestDialogue
extends RefCounted


static func run(h: TestHarness) -> void:
	test_interact_and_dialogue(h)
	test_dialogue_data(h)
	test_dialogue_playback(h)
	test_dialogue_auto_and_log(h)
	test_actor_actions_and_menu(h)
	test_interaction_picks_menu(h)
	test_choice_menu_navigation(h)
	test_choices_float_above_box(h)
	test_portrait_path(h)
	test_portrait_in_dialogue(h)
	test_line_font_and_shake(h)
	test_keep_open(h)
	test_photo_line_keeps_open(h)


## 「获得东西」的提示弹出来时，底下那句话不该被抹掉。
##
## 2026-09-25 策划报的：拿到猫的照片、右上角弹「获得 猫的照片」，
## 而正在说的那句「给的照片什么也看不清啊。」已经不见了。
## 根子在 `_finish()` —— 一段话播完它一律 `_hide_panel()`。
## 现在 `say` 多一个 `keep_open`：播完留着面板，最后一句原地不动。
static func test_keep_open(h: TestHarness) -> void:
	var main := h.new_main()
	var box: DialogueBox = main.dialogue
	var one := Dialogue.from_array([{"speaker": "我", "text": "给的照片什么也看不清啊。"}])

	# 基线：不写就是老样子，播完收起来
	box.play(one)
	box.skip()
	h.check("默认播完就收", box.is_open(), false)

	# 写了 `keep_open`：最后一句留着
	box.play(one, false, true)
	box.skip()
	h.check("写了 keep_open 就留着", box.is_open(), true)
	h.check("留下的还是那一句", box.current_text(), "给的照片什么也看不清啊。")
	# 玩家再点一下才收掉 —— 不是卡住了
	box.advance()
	h.check("再点一下才收", box.is_open(), false)

	main.queue_free()


## 剧本里那一句确实写了这个开关 —— 引擎认它，剧本不用它也是白搭。
static func test_photo_line_keeps_open(h: TestHarness) -> void:
	var event := DataLoader.load_event(&"ch1_opening")
	h.check("读得到 ch1_opening", event != null, true)
	if event == null:
		return
	var node := event.node(&"photo_line")
	h.check("有 photo_line 那一段", node != null, true)
	if node == null:
		return
	var said: StageStep = null
	for step: StageStep in node.stage:
		if step.kind == &"say":
			said = step
	h.check("那一段有台词", said != null, true)
	if said != null:
		h.check("拿照片那句播完不收面板", said.flag("keep_open", false), true)


## 台词行上的两个额外项：**字号大几号**、**浮出来时震一下屏**。
##
## 策划那一段用的就是它们：「真的是 因为我吗？？？？！」要大字 + 轻微震动。
## 对话框只报一声（`shook`），真去摇镜头的是 `main`（它接了这个信号）——
## 所以这一条两边都验：字号是它自己套的，震动是信号有没有发出来。
static func test_line_font_and_shake(h: TestHarness) -> void:
	var main := h.new_main()
	var box: DialogueBox = main.dialogue

	# 数据那层先读得进
	var big := DialogueLine.from_dictionary({
		"speaker": "我", "text": "真的 是我吗？？？？！", "size_delta": 2, "shake": 2.0})
	h.check("大的号数读得进", big.size_delta, 2)
	h.check("震动强度读得进", big.shake, 2.0)
	var plain := DialogueLine.from_dictionary({"text": "平时的一句"})
	h.check("不写就是不大", plain.size_delta, 0)
	h.check("不写就是不震", plain.shake, 0.0)

	# 界面那层：字号真的换了，信号真的发了
	var heard: Array[float] = []
	box.shook.connect(func(strength: float) -> void: heard.append(strength))
	box.play(Dialogue.from_array([{"text": "小的一行"}]))
	h.check("普通行的字号就是正文那号",
		box._label.get_theme_font_size("font_size"), DialogueBox.FONT_SIZE)
	box.close()

	box.play(Dialogue.from_array([
		{"speaker": "我", "text": "真的 是我吗？？？？！", "size_delta": 2, "shake": 2.0}]))
	h.check("加大号的行真的变大两号",
		box._label.get_theme_font_size("font_size"), DialogueBox.FONT_SIZE + 2)
	h.check("这一行报了一声要震屏", heard.size(), 1)
	h.check("报的强度对得上", heard[0] if not heard.is_empty() else 0.0, 2.0)
	box.close()

	# **字号是每行重设的** —— 上一行是大号、下一行不重设的话会跟着变大。
	# `advance()` 第一次把字显示完、第二次才翻到下一行（`skip()` 是整段跳过，
	# 它不逐行经过 `_show_line`，拿它验这条验不出来）。
	heard.clear()
	box.play(Dialogue.from_array([
		{"text": "先来一行大的", "size_delta": 2},
		{"text": "再来一行普通的"}]))
	h.check("第一行是大号",
		box._label.get_theme_font_size("font_size"), DialogueBox.FONT_SIZE + 2)
	box.advance()
	box.advance()
	h.check("翻到下一行时字号收回正文",
		box._label.get_theme_font_size("font_size"), DialogueBox.FONT_SIZE)
	h.check("没写 shake 的行一声都不报", heard.size(), 0)

	main.queue_free()


static func test_interact_and_dialogue(h: TestHarness) -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	h.root.add_child(main)
	main.boot()

	h.check("对话框一开始是关的", main.dialogue.is_open(), false)

	# 委托屋的猫窝在 [320,235,40,36]，它挂着一句旁观词。
	# 猫窝左边紧贴着墙，人只能站在它左侧够（reach 往前铺了一格）。
	main.player.global_position = Vector2(296, 255)
	main.player.facing = Vector2.RIGHT
	main.interact()
	h.check("靠近物件按交互键会开对话", main.dialogue.is_open(), true)
	h.check("对话里是那句旁观词", main.dialogue.current_text() != "", true)

	main.update_player_control()
	h.check("对话时角色不能被操控", main.player.is_physics_processing(), false)

	main.dialogue.close()
	main.update_player_control()
	h.check("对话结束后恢复操控", main.player.is_physics_processing(), true)

	# 离谁都远的时候按交互键，不该弹对话
	main.player.global_position = Vector2(240, 230)
	main.player.facing = Vector2.DOWN
	main.interact()
	h.check("附近没有目标时不弹对话", main.dialogue.is_open(), false)

	main.queue_free()


static func test_dialogue_data(h: TestHarness) -> void:
	var d := Dialogue.from_array([
		{"speaker": "甲", "text": "一"},
		{"speaker": "乙", "text": "二", "side": "right"},
		{"text": "旁白"},
	])
	h.check("行数", d.size(), 3)

	var l0: DialogueLine = d.lines[0]
	h.check("第一行说话人", l0.speaker, "甲")
	h.check("不写 side 时默认站左边", l0.side, DialogueLine.Side.LEFT)

	var l1: DialogueLine = d.lines[1]
	h.check("side 能指定右边", l1.side, DialogueLine.Side.RIGHT)

	# 没有说话人的一定是旁白，不该占着一侧立绘
	var l2: DialogueLine = d.lines[2]
	h.check("没有说话人算旁白", l2.side, DialogueLine.Side.NONE)

	h.check("单行简写可用", Dialogue.single("丙", "三").size(), 1)
	h.check("空数组不炸", Dialogue.from_array([]).is_empty(), true)
	h.check("传错类型不炸", Dialogue.from_array("不是数组").is_empty(), true)


static func test_dialogue_playback(h: TestHarness) -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	h.root.add_child(main)
	main.boot()

	var dlg := Dialogue.from_array([
		{"speaker": "甲", "text": "一"},
		{"speaker": "乙", "text": "二", "side": "right"},
		{"text": "三"},
	])

	main.dialogue.play(dlg)
	h.check("开始播放", main.dialogue.is_open(), true)
	h.check("停在第 0 行", main.dialogue.current_index(), 0)
	h.check("说话人是甲", main.dialogue.current_speaker(), "甲")
	h.check("开场是逐字显示状态", main.dialogue.is_revealing(), true)

	# 第一次推进只把当前行显示完，不跳行
	main.dialogue.advance()
	h.check("第一次推进停在原行", main.dialogue.current_index(), 0)
	h.check("文字已全部显示", main.dialogue.is_revealing(), false)

	main.dialogue.advance()
	h.check("第二次推进到第 1 行", main.dialogue.current_index(), 1)
	h.check("说话人换成乙", main.dialogue.current_speaker(), "乙")

	main.dialogue.skip()
	h.check("跳过之后关掉了", main.dialogue.is_open(), false)
	h.check("三行都进了历史", main.dialogue.log_panel().entry_count(), 3)

	main.queue_free()


static func test_dialogue_auto_and_log(h: TestHarness) -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	h.root.add_child(main)
	main.boot()

	main.dialogue.play(Dialogue.single("甲", "一"))
	h.check("默认不开自动", main.dialogue.is_auto(), false)

	main.dialogue.handle_key(KEY_A)
	h.check("按 A 开启自动", main.dialogue.is_auto(), true)

	main.dialogue.handle_key(KEY_L)
	h.check("按 L 打开记录", main.dialogue.log_panel().is_open(), true)

	main.dialogue.handle_key(KEY_L)
	h.check("再按 L 关掉记录", main.dialogue.log_panel().is_open(), false)

	# 对话框关着时按键不该有反应
	main.dialogue.close()
	h.check("关着时按键无效", main.dialogue.handle_key(KEY_A), false)

	main.queue_free()


static func test_actor_actions_and_menu(h: TestHarness) -> void:
	# 数据里写了 `actions` 才走菜单那条路
	var def := MapDef.from_dictionary({
		"id": "m",
		"size": [100, 100],
		"actors": [{
			"id": "desk",
			"rect": [10, 10, 10, 20],
			"label": "讲台",
			"actions": [
				{"id": "look", "label": "查看", "talk": [{"text": "一本书。"}]},
				{"id": "take", "label": "拿走", "talk": [{"text": "拿走了。"}]},
			],
		}],
	})
	var actor: MapDef.Actor = def.actors[0]
	h.check("有两个动作", actor.interactions.size(), 2)
	var first: MapDef.Interaction = actor.interactions[0]
	h.check("第一个动作 id", first.id, &"look")
	h.check("第一个动作标签", first.label, "查看")


static func test_interaction_picks_menu(h: TestHarness) -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	h.root.add_child(main)
	main.boot()

	# 委托屋的猫窝只有一个动作（看）：不该弹菜单，直接开始
	main.player.global_position = Vector2(296, 255)
	main.player.facing = Vector2.RIGHT
	main.interact()
	h.check("单动作不弹菜单", main.choice_menu.is_open(), false)
	h.check("直接开始", main.dialogue.is_open(), true)
	main.dialogue.close()

	# 第一章的角色都只有一个动作，多动作的情况自己拼一张小地图来测
	var multi := MapDef.from_dictionary({
		"id": "multi",
		"kind": "room",
		"size": [320, 180],
		"spawns": {"start": [160, 90]},
		"actors": [{
			"id": "thing",
			"rect": [140, 90, 24, 20],
			"label": "讲台",
			"actions": [
				{"id": "look", "label": "看看", "talk": [{"text": "上面有粉笔灰。"}]},
				{"id": "touch", "label": "摸一摸",
					"talk": [{"text": "还是别乱动别人的东西。"}]},
			],
		}],
	})
	main.current_map = multi
	var desk: MapDef.Actor = multi.actor_near(Vector2(152, 100), 30.0)
	if desk == null:
		h.check("找到讲台", false, true)
		main.queue_free()
		return

	main.begin_interaction(desk)
	h.check("多动作时弹菜单", main.choice_menu.is_open(), true)
	h.check("菜单里有两项", main.choice_menu.option_count(), 2)
	h.check("此时还没开始对话", main.dialogue.is_open(), false)

	main.choice_menu.select_index(1)
	main.choice_menu.confirm()
	h.check("选完菜单收起", main.choice_menu.is_open(), false)
	h.check("对话接上了", main.dialogue.is_open(), true)
	h.check("播的是第二项的内容", main.dialogue.current_text(), "还是别乱动别人的东西。")

	main.queue_free()


static func test_choice_menu_navigation(h: TestHarness) -> void:
	var menu := ChoiceMenu.new()
	h.root.add_child(menu)
	menu.setup()

	var options: Array[ChoiceOption] = [
		ChoiceOption.make(&"a", "甲"),
		ChoiceOption.make(&"b", "乙", false),
		ChoiceOption.make(&"c", "丙"),
	]
	menu.open("选一个", options)
	h.check("打开了", menu.is_open(), true)
	h.check("光标落在第一个可选项", menu.current_id(), &"a")

	menu.handle_key(KEY_DOWN)
	h.check("下移跳过灰项", menu.current_id(), &"c")

	menu.handle_key(KEY_DOWN)
	h.check("到底绕回第一项", menu.current_id(), &"a")

	menu.handle_key(KEY_UP)
	h.check("上移绕到最后一个可选项", menu.current_id(), &"c")

	menu.handle_key(KEY_ESCAPE)
	h.check("ESC 收起来", menu.is_open(), false)

	menu.queue_free()


## 剧情里的 IF 选项**浮在对话框上方**（稿子③：「选项框直接出现在对话框
## 上方一点」），不是摆进面板里面。
##
## 改这一条的理由：面板现在只占屏幕下三分之一、里面还站着两个人，
## 中间那一列放不下两行选项。
static func test_choices_float_above_box(h: TestHarness) -> void:
	var main := h.new_main()
	var box: DialogueBox = main.dialogue

	# 走到「等玩家选」那一步：面板留着、两个人摆好
	box.hold_open({
		"left": {"speaker": "我", "portrait": "protagonist/quiet"},
		"right": {"speaker": "老人", "portrait": "elder"},
	})
	h.check("面板留着", box.is_holding(), true)

	var options: Array[ChoiceOption] = [
		ChoiceOption.make(&"accept", "接受委托"),
		ChoiceOption.make(&"decline", "不接受委托"),
	]
	main.choice_menu.open_above(options, box.hold_top())
	h.check("选项框开着", main.choice_menu.is_open(), true)
	h.check("两项都在", main.choice_menu.option_count(), 2)

	var panel: Rect2 = main.choice_menu.panel_rect()
	h.check("底边停在对话框上沿之上",
		panel.position.y + panel.size.y <= box.hold_top(), true)
	# 靠右摆：正上方是两个人站着的地方，居中的话选项框会把他们盖住
	h.check("靠右摆、让开中间的人",
		panel.position.x > 160.0, true)
	h.check("右边不出屏",
		panel.position.x + panel.size.x <= 320.0, true)

	# 选完：面板收掉，剧情接着走（这时候对话框还在「等选择」的状态里）
	main.choice_menu.select_id(&"decline")
	main.choice_menu.confirm()
	h.check("选完选项框收起", main.choice_menu.is_open(), false)
	h.check("对话框不自己关", box.is_holding(), true)

	main.queue_free()


static func test_portrait_path(h: TestHarness) -> void:
	# 数据里写短名，自动补成 art/portrait 下的完整路径
	var short := DialogueLine.from_dictionary({"speaker": "我", "text": "x"})
	short.portrait = "protagonist/quiet"
	h.check("短名补全", short.portrait_path(), "res://art/portrait/protagonist/quiet.png")

	# 写全路径就原样用，不重复拼前缀
	var full := DialogueLine.new()
	full.portrait = "res://art/portrait/protagonist/smile.png"
	h.check("全路径原样", full.portrait_path(), "res://art/portrait/protagonist/smile.png")

	# 不写就是空，界面退回色块占位
	var none := DialogueLine.from_dictionary({"speaker": "邻居", "text": "x"})
	h.check("没写立绘就是空", none.portrait_path(), "")


static func test_portrait_in_dialogue(h: TestHarness) -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	h.root.add_child(main)
	main.boot()

	var box: DialogueBox = main.dialogue
	# 真素材存在，能载出来
	h.check("载得到真立绘", box.load_portrait("res://art/portrait/protagonist/quiet.png") != null, true)
	# 不存在的图返回 null，不该让对话框崩掉
	h.check("缺图返回 null", box.load_portrait("res://art/portrait
obody
one.png"), null)

	# 播一段带立绘的对话，看槽里到底有没有挂上
	var d := Dialogue.new()
	d.lines = [
		DialogueLine.from_dictionary({
			"speaker": "邻居", "text": "今天天气不错。", "side": "left",
		}),
		DialogueLine.from_dictionary({
			"speaker": "我", "text": "嗯。", "side": "right",
			"portrait": "protagonist/quiet",
		}),
	]
	box.play(d)
	box.advance()
	box.advance()
	h.check("主角那侧挂上了立绘", box.slot_portrait(DialogueLine.Side.RIGHT) != null, true)
	# 邻居没写立绘，退回占位色块
	h.check("没立绘的一侧是空", box.slot_portrait(DialogueLine.Side.LEFT), null)

	main.queue_free()
