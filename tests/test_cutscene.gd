## 演出指令与过场：解析、校验、以及开场整段跑下来的痕迹。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
##
## **写这个文件时注意类型推断。** `h.new_main()` 返回的是 `Node2D`，
## 它身上没有 `player` / `cutscene` / `current_map` 这些属性 —— 取出来是
## `Variant`，用 `:=` 会报 `Cannot infer the type`，而那个报错在 `--script` 下的
## 表现是**整轮测试卡住、没有任何输出**（不是报错，看着像死循环）。
##
## 一律写显式类型：
##
##     var seen: Array = main.cutscene.history()
##     var gap: Vector2 = point - main.player.global_position
##
## 这个坑 2026-09-24 一天踩了五六次，别再有下一次。
##
## 画面上的表现（淡入淡出、老人的走位）靠真窗口烟测和截图看，
## 这里管的是**状态**：演出跑完之后世界变成什么样、剧本有没有写错。
class_name TestCutscene
extends RefCounted


static func run(h: TestHarness) -> void:
	test_step_parsing(h)
	test_step_validation(h)
	test_event_validates_stage(h)
	test_centered_steps(h)
	test_glass_step(h)
	test_opening_data(h)
	test_accepted_and_sleep(h)
	test_sleep_walk(h)
	test_death_text(h)
	test_cg_layers(h)
	test_bag_hidden_on_cg(h)
	test_actor_poses(h)
	test_ch2_scene_data(h)
	test_blackout_before_hiding_cg(h)
	test_if_panel_drag(h)
	test_cg_stays_long_enough(h)
	test_ending_cg_and_music(h)
	test_transient_talks(h)
	test_walk_is_awaited(h)
	test_replay_keeps_picture_drops_words(h)
	test_normal_run_still_says(h)
	test_flash_opens_curtain(h)
	test_walking_npc(h)
	test_cutscene_history(h)
	test_head_anchor(h)
	test_ending_caption(h)
	test_ending_goes_back_to_title(h)
	test_free_roam_after_ending(h)
	test_loading_mid_ending_stays(h)
	test_all_ending_cards(h)


static func test_all_ending_cards(h: TestHarness) -> void:
	var cases := [
		[&"ch1_opening", [&"declined"]],
		[&"ch2_meet_a", [&"end2_cg"]],
		[&"meet_b", [&"distrust"]],
		[&"ch2_swing", [&"failed"]],
		[&"ch2_diary", [&"chase_caught", &"end5_chase_outcome"]],
		[&"ch2_diary", [&"end5_route_cg", &"end5_route_outcome"]],
		[&"ch2_library_cat", [&"dodge_end6"]],
		[&"ch2_library_cat", [&"escape_end6"]],
		[&"ch2_market_b_end", [&"ending_question"]],
	]
	for item: Array in cases:
		var main := h.new_main()
		main.cutscene.instant = true
		main.enter_map(&"school_gate", &"near_yard")
		var event := DataLoader.load_event(item[0])
		for node_id: StringName in item[1]:
			main.cutscene.run(event.node(node_id).stage)
		var label := "%s/%s" % [item[0], item[1][-1]]
		h.check(label + "结局字幕为两行", main.stage_overlay.caption_lines(), 2)
		h.check(label + "字幕下为黑屏", main.stage_curtain.is_down(), true)
		h.check(label + "字幕不叠CG", main.stage_overlay.has_image(), false)
		h.check(label + "没有结局对话框", main.dialogue.is_open(), false)
		main.queue_free()
	var retry := h.new_main()
	retry.enter_map(&"school_gate", &"near_yard")
	retry.capture_ch2_checkpoint("chase")
	retry.stage_overlay.show_caption([{"text": "end 5"}], 0.0)
	retry.restore_ch2_checkpoint("chase")
	h.check("同图重试清理结局字幕", retry.stage_overlay.caption_lines(), 0)
	retry.queue_free()


## 2026-09-23 加的四条指令：黑屏正中的字、左上角的状态、一条提示、一段音效。
##
## 它们都只有一两个字段，写错的地方（空 lines、`at` 拼错）要在**加载时**
## 就报出来，而不是演到那一步才莫名停住。
static func test_centered_steps(h: TestHarness) -> void:
	var caption := StageStep.from_dictionary({
		"do": "caption",
		"lines": [{"text": "如果那天我没有接那个委托……"}, {"text": "你会不会回来……"}],
	})
	h.check("caption 认", caption.kind, &"caption")
	h.check("caption 没问题", caption.validate().size(), 0)
	h.check("空 lines 要报错",
		StageStep.from_dictionary({"do": "caption", "lines": []}).validate().size() > 0, true)
	h.check("完全没写 lines 也要报错",
		StageStep.from_dictionary({"do": "caption"}).validate().size() > 0, true)

	h.check("location 认并放行",
		StageStep.from_dictionary({"do": "location", "text": "傍晚　委托屋"}).validate().size(), 0)
	h.check("location 不写 text 也放行（等于收起）",
		StageStep.from_dictionary({"do": "location"}).validate().size(), 0)

	h.check("hint 认",
		StageStep.from_dictionary({"do": "hint", "text": "此处建议存档"}).validate().size(), 0)
	h.check("hint 的 at 只认 corner / center",
		StageStep.from_dictionary({"do": "hint", "text": "x", "at": "middle"}).validate().size() > 0, true)

	h.check("play_sound 认",
		StageStep.from_dictionary({"do": "play_sound",
			"path": "res://audio/sfx/cat_meow.wav"}).validate().size(), 0)
	h.check("play_sound 少了路径要报错",
		StageStep.from_dictionary({"do": "play_sound"}).validate().size() > 0, true)


static func test_step_parsing(h: TestHarness) -> void:
	var step := StageStep.from_dictionary({
		"do": "npc",
		"sprite": "res://art/portrait/elder.png",
		"at": [132, 272],
		"height": 30,
		"fade": 0.5,
	})
	h.check("认出了指令", step.kind, &"npc")
	h.check("取字符串", step.text("sprite"), "res://art/portrait/elder.png")
	h.check("取坐标", step.point("at"), Vector2(132, 272))
	h.check("取数字", step.number("height"), 30.0)
	h.check("没写的字段退回默认值", step.number("time", 1.5), 1.5)
	h.check("取布尔", step.flag("once", true), true)

	# 坐标缺一半时退回默认值，不能崩
	var half := StageStep.from_dictionary({"do": "npc", "at": [10]})
	h.check("坐标不完整就用默认值", half.point("at", Vector2(1, 2)), Vector2(1, 2))

	# `say` 两种写法都要收：整段 lines，或者一行拆在指令身上
	var many := StageStep.from_dictionary({"do": "say", "lines": [
		{"speaker": "甲", "text": "一"}, {"speaker": "甲", "text": "二"},
	]})
	h.check("lines 写成两行", many.dialogue().size(), 2)

	var one := StageStep.from_dictionary({
		"do": "say", "speaker": "我", "text": "一句话", "side": "right",
		"portrait": "protagonist/quiet",
	})
	var line: DialogueLine = one.dialogue().lines[0]
	h.check("单行写法：说话人", line.speaker, "我")
	h.check("单行写法：正文", line.text, "一句话")
	h.check("单行写法：立绘补全路径", line.portrait_path(),
		"res://art/portrait/protagonist/quiet.png")
	h.check("单行写法：站右边", line.side, DialogueLine.Side.RIGHT)


static func test_step_validation(h: TestHarness) -> void:
	var ok := StageStep.from_dictionary({"do": "wait", "time": 0.5})
	h.check("这条没问题", ok.validate().size(), 0)

	h.check("没写 do 会被抓",
		StageStep.from_dictionary({"time": 1}).validate().size(), 1)
	# 一个字母写错，加载时就该报出来 —— 演到那一步才停住最难查
	h.check("不认识的指令会被抓",
		StageStep.from_dictionary({"do": "teleport"}).validate().size(), 1)
	h.check("少了必填字段会被抓",
		StageStep.from_dictionary({"do": "npc", "id": "a"}).validate().size(), 2)
	h.check("fade 的目标写错会被抓",
		StageStep.from_dictionary({"do": "fade", "to": "dark"}).validate().size(), 1)
	h.check("fade 写对就没事",
		StageStep.from_dictionary({"do": "fade", "to": "black"}).validate().size(), 0)
	h.check("say 什么内容都没有会被抓",
		StageStep.from_dictionary({"do": "say"}).validate().size(), 1)
	# 「把对话框收下去」本来就没有台词，不算错
	h.check("say 只是收起对话框是合法的",
		StageStep.from_dictionary({"do": "say", "slide": "out"}).validate().size(), 0)


static func test_event_validates_stage(h: TestHarness) -> void:
	var event := StoryEvent.from_dictionary({
		"id": "s",
		"entry": "a",
		"nodes": [
			{"id": "a", "stage": [
				{"do": "npc", "id": "elder", "sprite": "x.png", "at": [0, 0]},
				{"do": "npc_move", "id": "elder", "to": [1, 1], "time": 1},
			]},
			{"id": "b", "stage": [
				{"do": "npc_remove", "id": "elder"},
			]},
		],
	})
	# 临时角色是跨节点活的：a 放出来、b 收走，这是对的
	h.check("跨节点使唤临时角色没问题", event.validate().size(), 0)

	var broken := StoryEvent.from_dictionary({
		"id": "s2",
		"entry": "a",
		"nodes": [
			{"id": "a", "stage": [
				{"do": "npc_move", "id": "nobody", "to": [1, 1], "time": 1},
			]},
		],
	})
	var problems := broken.validate()
	h.check("使唤没出场的临时角色会被抓", problems.size(), 1)
	h.check("说的是哪一条", problems[0].find("还没放出来") >= 0, true)


## 开场的剧本本身要能过校验。写错一个指令名，加载时就报出来。
static func test_opening_data(h: TestHarness) -> void:
	var event := DataLoader.load_event(&"ch1_opening", [&"end1_calm"])
	h.check("读到开场", event != null, true)
	if event == null:
		return

	h.check("入口是章标题", event.entry, &"title")
	h.check("开场没有校验问题", event.validate([&"end1_calm"]).size(), 0)

	var title := event.node(&"title")
	# **按「有没有」查，不钉死在第几条。** 编排顺序会变 ——
	# 开场那三条黑屏旁白前面后来插了一条 `music`（先静音，
	# 等画面亮起再起前奏），按序号写的断言就会跟着碎一片。
	var banner: StageStep = null
	var caption: StageStep = null
	var saw_fade := false
	var quiet := false
	for step: StageStep in title.stage:
		match step.kind:
			&"fade":
				saw_fade = true
			&"banner":
				banner = step
			&"caption":
				caption = step
			&"music":
				if step.text("path") == "":
					quiet = true
	h.check("章标题节点：有黑屏", saw_fade, true)
	h.check("章标题节点：有章标题", banner != null, true)
	h.check("章标题节点：有三行心声", caption != null, true)
	h.check("标题写的是第一章",
		banner != null and banner.text("text") == "第一章　猫", true)
	# 第三句是黑屏正中浮现的三行心声 —— **不走对话框**，
	# 那会儿没有人在说话，底下冒一块面板像有人在念旁白
	h.check("心声有三行",
		caption != null and (caption.data["lines"] as Array).size() == 3, true)
	# 那三行是黑屏上念的，**这一段得安静** —— 前奏压到画面亮起才起
	h.check("黑屏旁白那段先静音", quiet, true)

	# 醒来那一节：先把人摆到桌后，画面才亮起来 —— 反了会先闪一下角色站在别处
	var wake := event.node(&"wake")
	var put: StageStep = null
	var clear: StageStep = null
	var loc: StageStep = null
	var music_at := -1
	var fade_at := -1
	for i: int in wake.stage.size():
		var step: StageStep = wake.stage[i]
		match step.kind:
			&"place_player":
				put = step
			&"fade":
				clear = step
				fade_at = i
			&"location":
				loc = step
			&"music":
				music_at = i
	h.check("醒来：有摆人", put != null, true)
	h.check("醒来：有亮起来", clear != null, true)
	h.check("醒来：有注明日期地点", loc != null, true)
	h.check("摆的是桌后、面朝屏幕下方",
		put != null and put.point("at").round() == Vector2(224, 130), true)
	h.check("朝下", put != null and put.text("facing") == "down", true)
	h.check("亮起来", clear != null and clear.text("to") == "clear", true)
	# 左上角那行状态（稿子：需要于左上角注明状态，字体不用很小）
	h.check("写的是傍晚委托屋",
		loc != null and loc.text("text").contains("委托屋"), true)

	# **前奏在「画面开始亮」那一步起，不是等亮完了才响。**
	# `fade to clear` 本身就是 0.9 秒的淡入，它在动画开始时生效 ——
	# 所以音乐要排在它**前一步**，两边才算同时。
	h.check("前奏排在亮起来之前",
		music_at >= 0 and fade_at >= 0 and music_at < fade_at, true)
	h.check("起的是委托屋那首",
		wake.stage[music_at].text("path") if music_at >= 0 else "",
		"res://audio/bgm/主角店内.mp3")

	# 老人是在演出里放出来的，不再是地图上的常驻 NPC
	var elder_in := event.node(&"elder_in")
	var kinds: Array[StringName] = []
	for step: StageStep in elder_in.stage:
		kinds.append(step.kind)
	# 先摆出来、再让他走过去。前面可能还有镜头指令，所以按「有没有」查，
	# 不钉死在第几条 —— 编排顺序会变，考的顺序不该跟着碎。
	h.check("老人先出场", kinds.has(&"npc"), true)
	h.check("再走到桌前", kinds.has(&"npc_move"), true)
	h.check("先出场再走", kinds.find(&"npc") < kinds.find(&"npc_move"), true)
	h.check("镜头框住这一幕", kinds.has(&"focus"), true)
	# 老人站在**会挡人的书桌前面**，层级要给到桌子之上，不然被切掉半截
	var elder_step: StageStep = elder_in.stage[kinds.find(&"npc")]
	h.check("老人站在书桌之上", int(elder_step.number("z", 9.0)) > 11, true)

	# 选择那一步：面板留着、选项框浮在它上方
	var ask := event.node(&"ask")
	h.check("选择节点有演出", ask.stage.size(), 2)
	h.check("演出是「摆好两个人」", ask.stage[0].kind, &"hold")
	# 稿子①：主角立绘在框左侧、其他人统一在右侧
	h.check("左边是我", ask.stage[0].data["left"]["speaker"], "我")
	h.check("右边是老人", ask.stage[0].data["right"]["speaker"], "老人")
	h.check("再报一句「此处建议存档」", ask.stage[1].kind, &"hint")
	h.check("提示落在画面中线上方", ask.stage[1].text("at"), "center")
	h.check("两条路", ask.choices.size(), 2)
	h.check("① 接受", ask.choices[0].id, &"accept")
	h.check("② 不接受", ask.choices[1].id, &"decline")

	h.check("结局是 end1", event.node(&"calm_death").ending, &"end1_calm")

	# 分支②：老人走掉 → 那场梦 → **切到夜间卧室**，人躺床上 → 猫叫 → 碎屏
	# → 黑屏上的结局文字
	var declined := event.node(&"declined")
	var decline_kinds: Array[StringName] = []
	for step: StageStep in declined.stage:
		decline_kinds.append(step.kind)

	var goto_at := decline_kinds.find(&"goto")
	h.check("切到夜间卧室", goto_at >= 0, true)
	if goto_at >= 0:
		var onto: StageStep = declined.stage[goto_at]
		# **用的是「床上躺着人」那张图**（2026-09-25 策划改的）：
		# 不再把小人摆到床上，图上本来就画着躺着的人。
		h.check("去的是「睡着」那张图", onto.text("map"), "bedroom_night_sleep")
		h.check("用的出生点是门口内侧", onto.text("spawn"), "from_desk")

	# **接下来不是摆小人，是把他藏起来、再把镜头推到床上。**
	# 图上画着躺的人，再叠一个小人上去就是两个主角。
	var hid_at := decline_kinds.find(&"hide_player")
	h.check("切过去把玩家藏起来", hid_at > goto_at, true)
	if hid_at > goto_at:
		h.check("藏起来（不是显示）",
			declined.stage[hid_at].flag("visible", true), false)
	# **从 `goto` 往后找** —— 这一节里 `focus` 有两处：
	# 前面那处是老人说话时镜头跟着他，后面那处才是切完场景推上床。
	var look_at := -1
	for i: int in range(goto_at + 1, decline_kinds.size()):
		if decline_kinds[i] == &"focus":
			look_at = i
			break
	h.check("切完场景把镜头推到床上", look_at > goto_at, true)
	if look_at > goto_at:
		h.check("推到床那儿", declined.stage[look_at].point("at").x, 336.0)
	h.check("不再有「把小人摆到床上」那一步",
		decline_kinds.has(&"place_player"), false)

	h.check("旧那套切屏飞散不用了", decline_kinds.has(&"shatter"), false)
	h.check("猫叫接碎屏", decline_kinds.has(&"play_sound")
		and decline_kinds.find(&"play_sound") < decline_kinds.find(&"glass"), true)
	var dream_at := -1
	for i: int in declined.stage.size():
		if declined.stage[i].kind == &"image" \
				and declined.stage[i].text("path") == "res://art/cg/梦境破碎.png":
			dream_at = i
	var glass_at := decline_kinds.find(&"glass")
	h.check("end1先展示梦境破碎CG再碎屏", dream_at >= 0 and dream_at < glass_at, true)
	if dream_at >= 0:
		h.check("梦境CG保留给碎屏和OS作底图", declined.stage[dream_at].flag("hide", true), false)
	if glass_at >= 0 and glass_at + 1 < declined.stage.size():
		var os: StageStep = declined.stage[glass_at + 1]
		h.check("碎屏后用下方对话框显示OS", os.kind, &"say")
		h.check("主角OS不带半身立绘", os.text("side"), "none")
		h.check("内心OS使用括号", os.text("text"), "（这是……！！）")
	h.check("碎屏之后是黑屏上的结局文字",
		decline_kinds[decline_kinds.size() - 1], &"caption")
	var death: StageStep = declined.stage[declined.stage.size() - 1]
	h.check("结局两行", (death.data["lines"] as Array).size(), 2)


## 开场整段跑下来，演过的指令顺序要是个说得通的故事。
static func test_cutscene_history(h: TestHarness) -> void:
	var main := h.new_main()
	h.start_opening(main)
	h.pick(main, &"decline")

	# 类型写死：main 是 Node2D，取出来的成员是 Variant，推断不了
	var cut: Cutscene = main.cutscene
	var seen: Array = cut.history()
	# 黑屏 -> 章标题 -> 三行心声 -> 摆人 -> 亮起 -> 地点 -> 台词
	# -> 老人出场 -> 走位 -> 收起对话框 -> 大图 -> 摆回两个人 -> 建议存档
	# -> 猫叫 -> 换场景 -> 摆到床上 -> 碎玻璃 -> 黑屏上的结局文字
	for kind: String in ["fade", "banner", "caption", "say", "location", "npc",
			"npc_move", "image", "place_player", "hold", "hint", "play_sound",
			"glass", "goto"]:
		h.check("演过 %s" % kind, seen.has(kind), true)

	# 顺序：章标题在黑屏之后、心声在标题之后：先报章名，再浮心声
	h.check("先黑屏再出标题", seen.find("fade") < seen.find("banner"), true)
	h.check("心声在标题之后", seen.find("banner") < seen.find("caption"), true)

	# 结局：夜里那场梦切到卧室、人摆到床上，碎玻璃之后才是那两行字
	h.check("整段只换过一次场景", seen.count("goto"), 1)
	var g: int = seen.find("goto")
	# **换场景之后紧接着是「把玩家藏起来」**（2026-09-25 起不再往床上摆小人）
	h.check("换场景之后紧接着把玩家藏起来", seen[g + 1], "hide_player")
	h.check("换场景在碎玻璃之前", g < seen.find("glass"), true)
	h.check("碎玻璃在结局文字之前",
		seen.find("glass") < seen.rfind("caption"), true)

	main.queue_free()


## 「按头定位」：`place_player` 写 `anchor: "head"` 时，那个坐标指的是
## 头的正中央，不是脚底。床上那一幕靠它把头摆进枕头。
static func test_head_anchor(h: TestHarness) -> void:
	var main := h.new_main()
	var who: Player = main.player

	var head := Vector2(100, 50)
	who.place_head_at(head)
	h.check("头的正中央落在给定点上",
		(who.global_position + who.head_offset()).round(), head.round())
	h.check("脚在头的下面", who.global_position.y > head.y, true)
	h.check("头的偏移是往上", who.head_offset().y < 0.0, true)

	# 不写 anchor 时还是老规矩：那个点是脚底
	#
	# `run()` 要的是 `Array[StageStep]`，**字面量 `[...]` 是没类型的 Array**，
	# 直接塞进去会在运行时抛错、后面的断言全不执行（看着还是绿的）。
	# 必须先落到一个声明了类型的变量上。
	main.cutscene.instant = true
	var walk: Array[StageStep] = [StageStep.from_dictionary({
		"do": "place_player", "at": [40, 60], "facing": "left",
	})]
	main.cutscene.run(walk)
	h.check("不写 anchor 就是脚底", who.global_position, Vector2(40, 60))

	# `pin` 是给「脚落在实体里」的场合用的（下一幕要躺到床上）。
	# 换场景要放开 —— 那是上一个场景里的剧情安排，不该跟过来。
	var lie: Array[StageStep] = [StageStep.from_dictionary({
		"do": "place_player", "at": [40, 60], "facing": "down", "pin": true,
	})]
	main.cutscene.run(lie)
	h.check("强制落位之后被按住", who.pinned, true)
	main.enter_map(&"desk_shop", &"start")
	h.check("换场景就放开", who.pinned, false)

	main.queue_free()


## 黑屏正中的那几行字：`caption` 一条指令摆出来，**不走对话框**。
##
## 稿子里那两行是分开写的：第一行大字报出结局名，第二行小两号，
## 「两行文字呈现中心对称」。字号差靠每行自己的 `size`。
static func test_ending_caption(h: TestHarness) -> void:
	var main := h.new_main()
	var overlay: StageOverlay = main.stage_overlay

	main.cutscene.instant = true
	var steps: Array[StageStep] = [StageStep.from_dictionary({
		"do": "caption",
		"lines": [
			{"text": "end 1 平静即死亡", "size": 16},
			{"text": "你没有做错什么。你只是没有去", "size": 14},
		],
	})]
	main.cutscene.run(steps)

	h.check("摆出两行", overlay.caption_lines(), 2)
	var caption := overlay.get_node_or_null("Root/Caption") as VBoxContainer
	h.check("挂在一个垂直居中的容器里", caption != null, true)
	if caption != null and caption.get_child_count() == 2:
		var big := caption.get_child(0) as Label
		var small := caption.get_child(1) as Label
		h.check("第一行写的是结局名", big.text, "end 1 平静即死亡")
		h.check("第二行小两号",
			big.get_theme_font_size("font_size")
				- small.get_theme_font_size("font_size"), 2)
	else:
		h.check("两行都在", false, true)

	# 场上已经有剧本写的结局文字了，这时候演结局**不该**再拿对话框念一遍
	main.show_ending(&"end1_calm")
	h.check("结局不重复说一遍", main.dialogue.is_open(), false)
	# `show_ending()` 管的是「记进图鉴 + 念文字」。**推进度是另一回事**：
	# `flags` 里那个标记由导演在走到结局节点时写，这条测试没跑剧情，
	# 所以只能验图鉴。（这一行以前写的是 `EndingTable.is_unlocked(flags)`，
	# 一直红不了 —— 上面那句 `run()` 在运行时抛错，这之后的断言根本没执行。）
	h.check("结局照样记进图鉴", main.gallery.has(&"end1_calm"), true)

	main.queue_free()


## 结尾那一段：结局文字由**剧本自己**演（黑屏正中那两行），演完回主界面。
##
## **走到结局就回主界面**，不把控制权还回玩家 —— 分支②到那儿人已经死了，
## 死后再让他在黑屋子里走动没有意义。
static func test_ending_goes_back_to_title(h: TestHarness) -> void:
	var main := h.new_main()
	# 正常流程：结局即结束。调试开关现在是开着的（布洛文要走去卧室试碰撞箱），
	# 所以**显式关掉**再测这条路 —— 另一条路见 `test_free_roam_after_ending`。
	main.free_roam_after_ending = false
	h.play_to_end1(main)

	# 新稿子的分支②：最后一幕切到「睡着」那张图，**玩家角色藏起来了**
	h.check("落在「睡着」那张图", main.current_map.id, &"bedroom_night_sleep")
	# **剧情演完要把人露回来**（`_on_story_ended`）—— 那一幕把他藏了，
	# 「藏着」是那一幕的安排，不该跟到剧情之外。
	h.check("人已经露回来了", main.player.visible, true)
	h.check("也没被按着", main.player.pinned, false)

	# 结局那两行是 `caption` 演出来的，所以这时候**不该有对话框**：
	# 底下再冒一块面板写「结局达成 · 平静即死亡」是把同一件事说两遍。
	h.check("结局文字没走对话框", main.dialogue.is_open(), false)
	# 那两行字回标题时收掉了 —— 覆盖层在标题**上面**（26 对 21），
	# 不收的话结局文字会飘在标题上
	h.check("结局文字已收起", main.stage_overlay.caption_lines(), 0)

	h.check("回到主界面", main.title_screen.is_open(), true)
	h.check("剧情不会自己往下走", main.story.is_active(), false)
	h.check("结局还是记下来了",
		EndingTable.is_unlocked(main.flags, &"end1_calm"), true)

	main.queue_free()


## 调试开关 `free_roam_after_ending`：结局之后不回主界面，把画面交回玩家。
##
## 它存在的理由很实际：委托屋那段演完就是 end1，正常流程直接回标题，
## 人走不到卧室去。碰撞箱这种东西得自己走两步才算验过 ——
## 光看碰撞对照图看不出「贴墙走会不会卡」。
static func test_free_roam_after_ending(h: TestHarness) -> void:
	var main := h.new_main()
	main.free_roam_after_ending = true
	h.play_to_end1(main)

	h.check("没被顶回主界面", main.title_screen.is_open(), false)
	h.check("还在「睡着」那张图里", main.current_map.id, &"bedroom_night_sleep")
	h.check("调试口子上人是露着的", main.player.visible, true)
	# 剧本把最后一幕的人按在床上，剧情一结束就松手了（`_on_story_ended`）——
	# 不松的话人钉在床上走不动，这个调试口子等于没有
	h.check("从床上松开手了", main.player.pinned, false)
	# 碎屏那一下把黑幕压下来了，得揭掉 —— 不揭就是一片黑里走动
	h.check("黑幕揭开了", main.stage_curtain.is_down(), false)
	# 结局那两行字一直挂在屏上（剧本里是 `wait_click`，不会自己淡）
	h.check("结局文字收掉了", main.stage_overlay.caption_lines(), 0)
	h.check("结局还是记下来了",
		EndingTable.is_unlocked(main.flags, &"end1_calm"), true)

	# 控制权真的回来了：能走
	main.update_player_control()
	h.check("能动了", main.player.is_physics_processing(), true)

	main.queue_free()


## 结局文字念到一半时读档：**不该**被顶回主界面。
##
## 「念完回标题」挂在 `dialogue.finished` 上，而对话框被关掉（`close()`）
## 也发同一个信号 —— 换场景就会把它收掉。少了那道闸，玩家在结局文字
## 念到一半按 F9，读完档看到的会是标题。
##
## 开场的分支②不走这条路了（它的结局文字由 `caption` 演、演完当场回标题），
## 但凡是「结局文字用对话框念」的结局都踩得到，所以这条得留着。
static func test_loading_mid_ending_stays(h: TestHarness) -> void:
	var main := h.new_main()
	# 摆出「结局文字正用对话框念着」的那一刻
	main.awaiting_title = true
	main.dialogue.play(Dialogue.from_array([{"text": "结局达成 · 某某"}]))
	h.check("结局文字正念着", main.dialogue.is_open(), true)

	# 模拟读档：换场景会把覆盖的界面一起收掉
	main.enter_map(&"desk_shop", &"start")
	h.check("读档之后没被顶回主界面", main.title_screen.is_open(), false)
	h.check("人还在场景里", main.current_map.id, &"desk_shop")

	main.queue_free()


## `glass` 指令：一张黑底素材从正中炸开，叠在画面上。
##
## **它不压黑** —— 压黑是 `StageCurtain` 的事。演出里正常是
## 「先 glass 裂开、再 fade 黑下去」。这条守的就是「裂开」那一步。
##
## 即时模式下它把「已经碎好了」的状态摆上就返回：截图和无头跑都要这一幕的样子。
static func test_glass_step(h: TestHarness) -> void:
	var main := h.new_main()
	main.cutscene.instant = true
	var burst: Array[StageStep] = [StageStep.from_dictionary({
		"do": "glass", "hold": 0.2, "fade": 0.3,
	})]
	main.cutscene.run(burst)

	h.check("演过 glass", main.cutscene.history().has("glass"), true)
	h.check("碎玻璃在场上", main.stage_overlay.is_glass(), true)
	# 它只是叠一层，底还是亮的 —— 压黑不归它管
	h.check("没顺手把屏幕压黑", main.stage_curtain.is_down(), false)

	main.stage_overlay.clear()
	h.check("收得掉", main.stage_overlay.is_glass(), false)

	main.queue_free()


## 会走路的临时角色。
##
## 素材只给了**正面和背面**，所以规矩是「往上走露背面、其余露正面」。
## 老人那段正好把两面都用满：进屋是往上走（背面，一张静态的），
## 离开是往下走（正面，四帧走路）。
##
## 这条守三件事：帧目录**真被建成了动画**（不是悄悄退回静态图）、帧数对、方向选对。
static func test_walking_npc(h: TestHarness) -> void:
	var main := h.new_main()
	var scene: Cutscene = main.cutscene

	# 指**目录** → 会走路的那种。指一张图 → 静态的（老路子，还在）。
	var actor := scene.add_actor("elder", "res://art/npc/elder", Vector2(224, 330), 45, 12)
	h.check("指着目录建出动画角色", actor is AnimatedSprite2D, true)
	if not (actor is AnimatedSprite2D):
		main.queue_free()
		return
	var sprite := actor as AnimatedSprite2D
	var frames := sprite.sprite_frames

	h.check("有正面走路的动画", frames.has_animation(&"walk_down"), true)
	h.check("正面走四步", frames.get_frame_count(&"walk_down"), 4)
	h.check("有背面的动画", frames.has_animation(&"walk_up"), true)
	# 背面策划只给了一张，走起来也是那一张
	h.check("背面只有一帧", frames.get_frame_count(&"walk_up"), 1)
	h.check("正面站着是一帧", frames.get_frame_count(&"idle_down"), 1)
	h.check("背面站着也是一帧", frames.get_frame_count(&"idle_up"), 1)
	# 站姿就是走路那组的第 1 帧 —— 策划给的素材里 1 号是站着的
	h.check("站立和走路第 1 帧是同一张",
		frames.get_frame_texture(&"walk_down", 0)
			== frames.get_frame_texture(&"idle_down", 0), true)

	# 往上走（屏幕 y 变小）→ 露背面
	sprite.position = Vector2(224, 330)
	scene._walk_actor(sprite, Vector2(224, 160))
	h.check("往上走露背面", sprite.animation, &"walk_up")
	scene._stop_actor(sprite)
	h.check("停下换成背面的站立", sprite.animation, &"idle_up")

	# 往下走（y 变大）→ 露正面。
	# **先把位置挪到桌前** —— 方向是拿「目标 y」和「当前 y」比的，
	# 不挪的话他还停在 330，往 318 走会被判成继续往上（这一条自己踩过）。
	sprite.position = Vector2(224, 160)
	scene._walk_actor(sprite, Vector2(222, 318))
	h.check("往下走露正面", sprite.animation, &"walk_down")
	scene._stop_actor(sprite)
	h.check("停下换成正面的站立", sprite.animation, &"idle_down")

	# 老的静态路子没坏：给一张图还是建 Sprite2D
	var portrait := scene._make_actor("res://art/portrait/elder.png", 45, 12)
	h.check("给一张图仍然建静态的", portrait is Sprite2D, true)
	if portrait != null:
		portrait.queue_free()

	# 剧本里老人用的是帧目录，不是那张立绘
	var event := DataLoader.load_event(&"ch1_opening", [&"end1_calm"])
	var npc_step: StageStep = null
	for step: StageStep in event.node(&"elder_in").stage:
		if step.kind == &"npc":
			npc_step = step
	h.check("老人用的是帧目录",
		npc_step != null and npc_step.text("sprite") == "res://art/npc/elder", true)

	main.queue_free()


## 睡前走向床边那一段（`ch1_sleep` 的 `walk_in`）。
##
## 2026-09-24 策划报了两件事，这条一件一条地钉：
##
## 1. **人没走到床边，黑屏就下来了。** 根子是 `_perform` 里
##    `place_player` 漏了 `await` —— GDScript 允许「把协程当普通函数调用」，
##    于是走路补间还在后台跑，后面几步已经压上来了。**编译器不会报这个**，
##    所以只能拿演过的痕迹去查：`await` 在的时候，`run()` 会卡在走路上，
##    后面的指令一条都不会被记下来。
## 2. **向右走却露背面。** 朝向要跟着**这一段的位移**走，不能一路沿用
##    上一步设的朝向，也不能把斜的位移交给补间（那是漂移）。
static func test_sleep_walk(h: TestHarness) -> void:
	var main := h.new_main()
	var scene: Cutscene = main.cutscene

	# ---- 一、路径点：解析、拦错、拆段 ----
	var step := StageStep.from_dictionary({
		"do": "place_player",
		"path": [[96, 306], [118, 306], [118, 190], [336, 190]],
	})
	h.check("路径点读得出来", step.points("path").size(), 4)
	h.check("第一个点对得上", step.points("path")[0], Vector2(96, 306))
	h.check("最后一个点对得上", step.points("path")[3], Vector2(336, 190))
	h.check("没写路径点时是空的", step.points("at").size(), 0)

	# 两个点之间同时差着 x 和 y 时，必须拆成「先横后竖」两段。
	# 不拆就是斜着飘 —— 画面上像在水上漂。
	var diagonal := StageStep.from_dictionary({
		"do": "place_player", "path": [[0, 0], [40, 20]],
	})
	var legs: Array[Vector2] = scene._legs_of(diagonal.points("path"))
	h.check("斜的位移拆成两段", legs.size(), 2)
	h.check("第一段只走横的", legs[0], Vector2(40, 0))
	h.check("第二段只走竖的", legs[1], Vector2(0, 20))
	var all_axis := true
	for leg: Vector2 in legs:
		if leg.x != 0.0 and leg.y != 0.0:
			all_axis = false
	h.check("每一段都只在一个轴上", all_axis, true)

	# 一个地方都不去是不行的 —— 那一步没有意义，多半是漏了一行
	var nothing := StageStep.from_dictionary({"do": "place_player"})
	h.check("既没 at 也没 path 要报出来",
		"演出指令 place_player 既没有 at 也没有 path" in nothing.validate(), true)
	var broken := StageStep.from_dictionary({"do": "place_player", "path": "336,190"})
	h.check("path 写成一串字符串要报出来", broken.validate().is_empty(), false)

	# ---- 二、即时模式下落到最后一个路径点 ----
	main.cutscene.instant = true
	main.enter_map(&"bedroom_night", &"from_desk")
	var who: Player = main.player
	var walk: Array[StageStep] = [StageStep.from_dictionary({
		"do": "place_player",
		"path": [[96, 306], [118, 306], [118, 190], [336, 190]],
		"facing": "up",
	})]
	main.cutscene.run(walk)
	h.check("即时模式落到终点", who.global_position.round(), Vector2(336, 190))
	h.check("朝向按写的来", who.facing, Vector2.UP)

	# ---- 三、躺床上那一步：黑屏在前，摆位在后 ----
	#
	# **进卧室和上床现在是两件事**（2026-09-25 策划改的）：原来 `walk_in` 会自己
	# 把人走到床边，现在走进卧室就交还控制权，玩家走到床前按交互才睡。
	# 所以剧本里不再有路径点 —— 但「摆到床上必须在黑屏底下做」这条要守着，
	# 不然会看见人凭空跳上去。
	var enter := DataLoader.load_event(&"ch1_sleep")
	h.check("读得到 ch1_sleep", enter != null, true)
	if enter != null and enter.node(&"walk_in") != null:
		var walked := false
		for s: StageStep in enter.node(&"walk_in").stage:
			if s.kind == &"place_player":
				walked = true
		h.check("进卧室不再自动走路", walked, false)

	var event := DataLoader.load_event(&"ch1_bed")
	h.check("读得到 ch1_bed", event != null, true)
	if event != null:
		var bed := event.node(&"bed")
		h.check("有躺床上那一段", bed != null, true)
		if bed != null:
			# 2026-09-25 改成**换一张「床上躺着主角」的图**（`bedroom_night_sleep`），
			# 不再把人摆到床上 —— 那张图上本来就画着躺着的人。
			# 要守的规矩没变：切图必须在黑屏底下做，不然会看见画面凭空换掉。
			var black_at := -1
			var sleep_at := -1
			for i: int in bed.stage.size():
				var s: StageStep = bed.stage[i]
				if s.kind == &"fade" and s.text("to") == "black":
					black_at = i
				if s.kind == &"goto" and s.text("map") == "bedroom_night_sleep":
					sleep_at = i
			h.check("躺下那一步是切到「睡着」那张图", sleep_at >= 0, true)
			h.check("切图排在黑屏之后", black_at >= 0 and sleep_at > black_at, true)

	main.queue_free()


## 沿路径点每一步都踩一遍，看有没有蹭到墙。
##
## **采样按 2 像素来**（`WalkGrid.STEP`）：隔得比这还疏，一条恰好穿过
## 一堵薄墙的边就可能被漏掉，而那正是「人贴着墙角走不过去」的成因。
static func _check_route_free(h: TestHarness, main: Node2D, points: Array[Vector2]) -> void:
	var def: MapDef = main.current_map
	var bad: Array[String] = []
	for i: int in range(1, points.size()):
		var gap := points[i] - points[i - 1]
		var steps := int(ceilf(gap.length() / WalkGrid.STEP))
		for s: int in steps + 1:
			var at := points[i - 1] + gap * (float(s) / maxf(1.0, float(steps)))
			if not WalkGrid.is_free(def, at):
				bad.append("%s→%s 卡在 %s" % [points[i - 1], points[i], at])
	h.check("那条路每一步都站得住", bad, [] as Array[String])
	# 采样密一点也顺带守一下：路径点之间不该是斜的（斜的就是漂移）
	var slanted := false
	for i: int in range(1, points.size()):
		var gap := points[i] - points[i - 1]
		if gap.x != 0.0 and gap.y != 0.0:
			slanted = true
	h.check("路径点之间都是正方向", slanted, false)


## `place_player` 走路的时长不用手写：不写 `time` 就按脚程算
## （总长 ÷ `Player.SPEED`），和玩家自己走一个速度。
##
## 这条顺带守住了**「有没有 await」**：`_perform` 等走路的时候，
## 后面的指令一条都不该被记下来。少了 `await`，它们会当场全跑完 ——
## 策划看到的就是「人还在走，画面已经黑了」。
##
## **必须在非即时模式下测。** 即时模式本来就不走、直接落位（那是给
## 无头测试用的短路），拿它测这件事测不出任何东西。
static func test_walk_is_awaited(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"bedroom_night", &"from_desk")
	# 故意**不开**即时模式。树里没有帧循环，走路补间永远推不动 ——
	# 正要的就是这个「卡在半路」的状态。
	var steps: Array[StageStep] = [
		StageStep.from_dictionary({
			"do": "place_player", "path": [[96, 306], [118, 306], [336, 306]],
		}),
		StageStep.from_dictionary({"do": "wait", "time": 0.1}),
		StageStep.from_dictionary({"do": "place_player", "at": [10, 10]}),
	]
	main.cutscene.run(steps)
	var seen: Array = main.cutscene.history()
	h.check("演到走位就停住了", seen.size(), 1)
	h.check("停的那一步是走位", seen[0] if not seen.is_empty() else "", "place_player")

	main.cutscene.cancel()
	main.queue_free()


## 读档重入：已经演过的那几步要**把画面补上、但不重念台词**。
##
## 用户报的就是这里 —— 在「等选择」那一步存档，读回来整段对白又从头放了一遍。
## 「画面补上」同样要紧：不补的话对话框是空的、场上也没人，
## 而剧情正停在「跟神秘人说话」上（同一轮报的「小人图像不见了」）。
static func test_replay_keeps_picture_drops_words(h: TestHarness) -> void:
	var main := h.new_main()
	var cut: Cutscene = main.cutscene
	cut.instant = true

	var steps: Array[StageStep] = []
	for raw: Dictionary in [
		{"do": "say", "lines": [{"speaker": "甲", "text": "这句读过了"}]},
		{"do": "npc", "id": "old", "sprite": "res://art/portrait/elder.png",
			"at": [132.0, 272.0], "height": 30.0},
		{"do": "hold",
			"left": {"speaker": "甲", "portrait": "protagonist/quiet"},
			"right": {"speaker": "乙", "portrait": "elder"}},
	]:
		steps.append(StageStep.from_dictionary(raw))

	# 这三条当成「上次已经演过」：从第 3 条（越界＝整段都演完了）接着。
	cut.run(steps, 3)

	# 画面补回来了
	h.check("场上的人补回来了", cut.actor_ids().has("old"), true)
	h.check("对话框补成等选择", main.dialogue.is_holding(), true)
	h.check("补回的等选择上正文是空的", main.dialogue.current_text(), "")
	h.check("补回的等选择上立绘在", main.dialogue.slot_portrait(
		DialogueLine.Side.RIGHT) != null, true)

	# 台词一句没念：对话历史里一条都没有。
	# 这条是这次修复的正身 —— 补演把 `say` 跳过之前，这里会是一。
	h.check("补演不重念台词", main.dialogue.log_panel().entry_count(), 0)
	# 补演也不该冒充「演过」：`_log` 是查「这段演了哪几条」用的，
	# 混进补演的条目之后就没法看了。
	var seen: Array = cut.history()
	h.check("补演不记进流水", seen.size(), 0)

	main.queue_free()


## 同上的反面：**正常演（不带 replay）什么都照旧** —— 台词记进历史、
## 流水照记。不钉这一条的话，「补演跳过 say」的那个改动可以靠
## 把 say 整个废掉来蒙混过关。
static func test_normal_run_still_says(h: TestHarness) -> void:
	var main := h.new_main()
	var cut: Cutscene = main.cutscene
	cut.instant = true

	var steps: Array[StageStep] = [
		StageStep.from_dictionary({
			"do": "say", "lines": [{"speaker": "甲", "text": "正常演的一句"}],
		}),
		StageStep.from_dictionary({
			"do": "hold", "left": {"speaker": "甲"},
		}),
	]
	cut.run(steps)

	h.check("正常演会念台词", main.dialogue.log_panel().entry_count(), 1)
	var seen: Array = cut.history()
	h.check("正常演照样记流水", seen.size(), 2)
	h.check("say 在流水里", seen.has("say"), true)

	main.queue_free()


## 黑白闪：**进来先要把遮罩打开**。
##
## `reveal()` 收尾时会把那一层藏起来，而「闪」平时都排在切场景之后 ——
## 忘了打开的话，这条指令什么都不会发生，画面上完全看不出闪没闪
## （2026-09-24 策划报「闪太快没看清」，根子有一半在这儿）。
static func test_flash_opens_curtain(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"desk_shop", &"start")

	# 先把遮罩摆成 `reveal()` 收尾时那个样子（淡开完、藏起来）。
	# **这一步不能省**：无头环境里 `reveal()` 的补间推不动，`visible` 还留着
	# true，不摆的话这条断言会白过 —— 测的是别的东西。
	main.fade.fade_to(0.0, 0.0)
	h.check("摆好之后遮罩是收着的", main.fade.is_covering(), false)

	var colors := PackedColorArray([Color.WHITE, Color(0.02, 0.02, 0.03), Color.WHITE])
	main.fade.flash(colors, 0.3, 0.12)
	h.check("闪的时候遮罩是打开的", main.fade.is_covering(), true)
	h.check("还没亮起来（亮起是补间的事）", main.fade.alpha(), 0.0)

	# 剧本里那一次：白黑交替、闪三下，一下要比一帧长得多
	var event := DataLoader.load_event(&"ch1_bed")
	var flash_step: StageStep = null
	if event != null and event.node(&"cat") != null:
		for s: StageStep in event.node(&"cat").stage:
			if s.kind == &"flash":
				flash_step = s
	h.check("cat 那一段有闪", flash_step != null, true)
	if flash_step != null:
		h.check("是白黑交替", flash_step.flag("mono", false), true)
		h.check("闪三下", int(flash_step.number("times", 0.0)), 3)
		# 一下 = time/2 + hold + time/2，三下加起来要够人反应过来
		var one := flash_step.number("time", 0.0) + flash_step.number("hold", 0.0)
		h.check("三下加起来超过一秒", one * 3.0 > 1.0, true)

	# ---- 梦境破碎那一下：碎玻璃叠上去，台词换成惊吓立绘 ----
	#
	# 2026-09-25 策划要的两样，一条钉一样。
	var cg: StageStep = null
	var glass: StageStep = null
	var lines: Array = []
	if event != null and event.node(&"cat") != null:
		for s: StageStep in event.node(&"cat").stage:
			if s.kind == &"image" and s.text("path") == "res://art/cg/梦境破碎.png":
				cg = s
			if s.kind == &"glass":
				glass = s
			if s.kind == &"say":
				lines = s.data.get("lines", [])

	h.check("梦境破碎那张 CG 在", cg != null, true)
	# **CG 要留着给碎玻璃叠。** `image` 的 `hide` 默认是 true —— 不写就自己收掉，
	# 碎玻璃就叠在空背景上，看着不像「这张图碎了」。
	if cg != null:
		h.check("CG 播完留在屏上", cg.flag("hide", true), false)
	h.check("碎玻璃排在 CG 之后", glass != null, true)

	# **碎裂那一下要响。** `glass` 是协程、await 到底，所以音效得排在它**前面** ——
	# 排在后面的话画面已经碎完了才听见声（同 `music` 那条的先后道理）。
	var sound_at := -1
	var glass_at := -1
	if event != null and event.node(&"cat") != null:
		var cat_stage := event.node(&"cat").stage
		for i: int in cat_stage.size():
			var s: StageStep = cat_stage[i]
			if s.kind == &"play_sound" \
					and s.text("path").ends_with("glass_break.wav"):
				sound_at = i
			if s.kind == &"glass":
				glass_at = i
	h.check("碎裂配了音效", sound_at >= 0, true)
	h.check("音效排在碎玻璃前面",
		sound_at >= 0 and glass_at >= 0 and sound_at < glass_at, true)

	# 「猫！猫！！」那两行都要用惊吓立绘 —— 人在那一下是吓着的
	var portraits: Array = []
	for raw: Variant in lines:
		if raw is Dictionary:
			portraits.append(str((raw as Dictionary).get("portrait", "")))
	# 「……猫？」是刚瞥见、还没认准（普通惊讶）；「……猫！！」才是认出来了（强烈震惊）。
	# 两张分开的素材，别写成一个。
	h.check("两行是有层次的惊吓", portraits,
		["protagonist/startled", "protagonist/shocked"])

	main.queue_free()


## 大图 / 屏幕中央的字 / 对话框 —— 这三样谁盖谁。
##
## **规矩：大图是背景，人物要在它上面说话。**
## 所以大图挂在 `StageOverlay.PICTURE_LAYER`（9）、在**对话框下面**；
## 章标题 / 结局文字 / 碎玻璃留在演出层（14），它们的职责正好相反 —— 盖住对话框。
##
## 2026-09-24 策划报的「梦里那两句旁白该出现在对话框里」就是这条：
## 大图原先和它们挤在 14、铺满整屏时把对话框整个盖住，那两句一个字都看不见
##（按空格其实在推进一段看不见的对话，观感是「CG 播放时间太长、按空格不灵」）。
static func test_cg_layers(h: TestHarness) -> void:
	var main := h.new_main()
	var overlay: StageOverlay = main.stage_overlay
	var box: DialogueBox = main.dialogue

	h.check("大图在对话框下面（人才能在图上面说话）",
		StageOverlay.PICTURE_LAYER < box.layer, true)
	h.check("演出层还在对话框上面（章标题 / 结局文字要压住它）",
		overlay.layer > box.layer, true)
	# 大图真的挪出去了，不是还赖在演出层里
	h.check("大图不在演出层那棵树下",
		overlay._image.get_parent() != overlay._root, true)
	h.check("大图那层的层号就是 PICTURE_LAYER",
		overlay._picture_layer.layer, StageOverlay.PICTURE_LAYER)
	h.check("大图那层在演出层下面",
		overlay._picture_layer.layer < overlay.layer, true)

	# 铺满的大图就是整个视口那么大，一寸都不留
	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0)))
	overlay.show_image("res://art/cg/梦中死亡.png", 0.0, true)
	h.check("铺满的大图占满视口", overlay._image.size, view)
	h.check("大图从左上角起", overlay._image.position, Vector2.ZERO)

	# 屏幕中央那几行字还在演出层里（它要压在大图上面）
	h.check("字在演出层那棵树下",
		overlay.get_node("Root/Caption") == overlay._caption, true)

	main.queue_free()


## 过 CG 的时候，右下角那个背包图标要让开。
##
## 大图在第 9 层、图标在第 19 层 —— **压不住它**，只能主动收
## （`StageOverlay.picture_changed` → `main.update_player_control()`）。
## 不收的话，一张片尾那种 CG 的右下角会杵着一个「背包」按钮
##（2026-09-24 策划报的）。
static func test_bag_hidden_on_cg(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"desk_shop", &"start")
	main.stage_curtain.snap_up()
	main.update_player_control()
	h.check("平时图标在", main.inventory.is_button_visible(), true)

	main.stage_overlay.show_image("res://art/cg/梦中死亡.png", 0.0, true)
	h.check("CG 摆着的时候图标收起来", main.inventory.is_button_visible(), false)

	main.stage_overlay.hide_image(0.0)
	h.check("CG 收掉之后图标回来", main.inventory.is_button_visible(), true)

	# **`clear()` 收图也要报信。** 不报的话「让开」那个状态一直挂着，
	# 换个场景回来图标就再也不出现了 —— 这种错很难查，因为画面看着正常。
	main.stage_overlay.show_image("res://art/cg/梦中死亡.png", 0.0, true)
	main.stage_overlay.clear()
	h.check("clear() 收图之后图标回来", main.inventory.is_button_visible(), true)

	main.queue_free()


## `ch1_sleep` 的 `death`（梦里那一下）：大图留着，**两句旁白走对话框**。
##
## 这两句是策划指定要在对话框里出现的，所以大图必须让开位置 ——
## 见 `test_cg_layers`（大图在对话框下面，压不住它）。
static func test_death_text(h: TestHarness) -> void:
	var event := DataLoader.load_event(&"ch1_bed")
	h.check("读得到 ch1_bed", event != null, true)
	if event == null:
		h.check("有 death 节点", false, true)
		return

	var death := event.node(&"death")
	h.check("有 death 节点", death != null, true)
	if death == null:
		return

	var kinds: Array[StringName] = []
	for step: StageStep in death.stage:
		kinds.append(step.kind)
	# 大图 → 对话框两行（压在 CG 上说）→ 等玩家点 → **黑屏** → 收图 → 中央的字
	#
	# **「黑屏」那一步是 2026-09-25 加的**（策划 bug 单第 13 条：
	# 「播放 cg 后闪烁回原来场景」）。收掉 CG 的那半秒，露出来的本来就是
	# 背后的场景；前面先下黑幕，收的时候透出来的就是黑。
	var want: Array[StringName] = [&"image", &"say", &"wait_click", &"fade",
		&"image_hide", &"caption"]
	h.check("六步：大图 / 对话 / 等点击 / 黑屏 / 收图 / 中央的字", kinds, want)

	var cg: StageStep = death.stage[0]
	h.check("大图铺满", cg.flag("fill", false), true)
	h.check("大图留在屏上（两句压在它上面说）", cg.flag("hide", true), false)
	# 停一下可以，别按着人看好几秒。**上限 2026-09-25 放到 3.5** ——
	# 策划说 CG 留得太短（bug 单第 14 条），「适当延长」。
	h.check("停得不超过 3.5 秒", cg.number("hold", 0.0) <= 3.5, true)
	# 下限也钉一条：`hold` 不写是 0、`hide` 不写是 true —— 合起来就是
	# 「淡入完立刻淡出」，一闪而过。**CG 得停够时间。**
	h.check("也别短到一闪而过", cg.number("hold", 0.0) >= 1.5, true)

	# 两句走对话框，而且压在 CG 上说的前提是**大图不能盖住对话框**
	var lines: StageStep = death.stage[1]
	h.check("两句走对话框", lines.kind, &"say")
	h.check("两句，不是一句", (lines.data["lines"] as Array).size(), 2)


## 接受委托之后那一段（`accepted` + `ch1_sleep`）。
##
## 2026-09-24 新加，顺带做了三样机制，这里一条守一样：
##
## 1. **门口那道禁制** —— 「今天已经晚了，明天再去吧」：门还在、但推不开，
##    踩上去只弹一句话（`blocked_by` / `blocked_text`）。和 `condition`
##    不是一回事，那个是让连接整个消失。
## 2. **去卧室那扇门交给事件演** —— 进门之后还有一整段过程动画
##    （走进去、走向床、睡着、做梦），光靠 `to` 只会瞬移过去接不上。
## 3. **IF 条件框**（`if_panel` 指令）—— 老人脑子里的「如果…就会…」。
static func test_accepted_and_sleep(h: TestHarness) -> void:
	var main := h.new_main()
	main.cutscene.instant = true
	main.enter_map(&"desk_shop", &"start")

	# ---- 一、门口那道禁制 ----
	# **别拿「最后一个写了 `blocked_by` 的」当大门。** 2026-09-25 起卧室门也有一个
	# 拦着的口（「现在我不想睡觉。」），按那个找会挑错门、后面跟着一串假红。
	# 大门认它的去向：通向大地图的那个。
	var gate: MapDef.Portal = null
	var door: MapDef.Portal = null
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.outcome == MapDef.Portal.Outcome.TO_OVERWORLD:
			gate = portal
		if portal.event_id == &"ch1_sleep":
			door = portal
	h.check("大门上挂着门禁", gate != null, true)
	h.check("卧室门口挂着事件", door != null, true)

	# **卧室那扇门是两个口、一个位置。** 第一次进去演 `ch1_sleep`（把人带进屋），
	# 睡过之后那个口**不再演任何东西，只负责拦住**（「现在我不想睡觉。」）——
	# 2026-09-25 策划改的：死过一次的人不会再往那张床上躺。
	# 条件是互补的，所以任何时刻只有一个活着 —— 这条要真拿 flags 去问。
	#
	# 两个口里现在只有一个带 `event`，所以**按「同一块矩形上成对出现、且都带条件」找**。
	# 2026-09-27 之前这里钉的是 `Vector2(73, 79)`，策划把门挪了 11 像素就红了 ——
	# 门摆在哪是他调的，测试只该盯「是不是一对、条件是不是互补」。
	var pair_counts: Dictionary = {}
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.condition != null:
			var key := portal.rect.position
			pair_counts[key] = int(pair_counts.get(key, 0)) + 1
	var bedroom_doors: Array[MapDef.Portal] = []
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.condition != null and int(pair_counts.get(portal.rect.position, 0)) == 2:
			bedroom_doors.append(portal)
	h.check("卧室门是两个口", bedroom_doors.size(), 2)
	if bedroom_doors.size() == 2:
		h.check("两个口在同一块地方",
			bedroom_doors[0].rect, bedroom_doors[1].rect)
		var has_condition := bedroom_doors[0].condition != null \
			and bedroom_doors[1].condition != null
		h.check("两个口都写了条件", has_condition, true)
		if has_condition:
			main.flags.unset_value(&"gate/slept_once")
			var first: Array[MapDef.Portal] = main.current_map.active_portals(main.flags)
			var first_events: Array = []
			for portal: MapDef.Portal in first:
				if portal.event_id != &"":
					first_events.append(portal.event_id)
			h.check("没睡过的时候只开着 ch1_sleep",
				first_events, [&"ch1_sleep"] as Array)

			# 睡过之后：这扇门不演了，改成拦着的
			main.flags.set_value(&"gate/slept_once", true)
			var second_events: Array = []
			var shut: MapDef.Portal = null
			for portal: MapDef.Portal in main.current_map.active_portals(main.flags):
				if portal.event_id != &"":
					second_events.append(portal.event_id)
				elif bedroom_doors.has(portal):
					# 那一对里**不带事件**的那个，就是睡过之后拦人的
					shut = portal
			h.check("睡过之后这扇门不再演剧情", second_events.is_empty(), true)
			h.check("睡过之后这扇门是拦着的",
				shut != null and main._portal_blocked(shut), true)
			h.check("拦下来说的是那句",
				shut.blocked_text if shut != null else "", "现在我不想睡觉。")
			main.flags.unset_value(&"gate/slept_once")

	if gate != null:
		main.flags.set_value(&"gate/late", false)
		h.check("没封的时候不拦", main._portal_blocked(gate), false)
		main.flags.set_value(&"gate/late", true)
		h.check("封上就拦", main._portal_blocked(gate), true)
		h.check("拦着时写了要说的话", gate.blocked_text != "", true)
		# 站在门口按交互：人不动，也不传送
		main.player.global_position = gate.rect.get_center()
		main.interact()
		h.check("被拦着时人还在原地", main.current_map.id, &"desk_shop")

	# ---- 二、走卧室那扇门 → 演 ch1_sleep，不是传送 ----
	if door != null:
		h.check("挂的是 ch1_sleep", door.event_id, &"ch1_sleep")
		main.flags.set_value(&"gate/late", false)
		main.player.global_position = door.rect.get_center()
		main.interact()
		# **进门这一段只到「屋里亮起来」。** 2026-09-25 起不再自动走到床边 ——
		# 演完就交还控制权，玩家自己走到床前按交互才睡（策划改的）。
		h.check("进门那一下走的是 goto", main.cutscene.history().has("goto"), true)
		h.check("人落在夜间卧室", main.current_map.id, &"bedroom_night")
		h.check("进门演完就交还控制权", main.story.is_active(), false)

		# 睡觉那一段是**另一个事件**（`ch1_bed`），从 `bed` 节点起。
		main.start_story(&"ch1_bed")
		# 这一段只有一个选择点（老人那块 IF 的「观察」）。选完就一路演到
		# 「again」收尾，那之后**不带 next** —— 交出控制权。
		if main.choice_menu.is_open():
			main.choice_menu.select_id(&"look")
			main.choice_menu.confirm()
		h.check("这一段只有一个选择点", main.choice_menu.is_open(), false)

		# 即时模式下整段会同步跑完，所以直接看「演过哪些指令」
		var seen: Array = main.cutscene.history()
		h.check("演了 image（猫闪过 / 梦中死亡）", seen.has("image"), true)
		h.check("演了 glass（梦境破碎那一下）", seen.has("glass"), true)
		h.check("演了 if_panel（IF 条件框）", seen.has("if_panel"), true)
		h.check("演了 eye_open（回到委托屋时睁眼）", seen.has("eye_open"), true)
		h.check("演了 npc_remove（老人走出门）", seen.has("npc_remove"), true)
		# 走完之后人落在委托屋（那一段最后回到了这里）
		h.check("最后回到了委托屋", main.current_map.id, &"desk_shop")
		# **这一段演完要交还控制权**（玩家自己走到卧室门口），
		# 并且把「睡过了」那个标记立起来 —— 卧室门靠它换第二个口。
		h.check("演完交还控制权", main.story.is_active(), false)
		h.check("立起了「睡过了」的标记",
			main.flags.get_value(&"gate/slept_once"), true)
		# **交还控制权之后，玩家要真的能走。**
		# 这一段就是「进入主角可操控阶段」，走不动的话整个设计落空。
		main.update_player_control()
		h.check("人能动（物理开着）", main.player.is_physics_processing(), true)

		# 大门这会儿该拦着（「今天已经晚了，明天再去吧」）。
		# 真实流程里这个标记是接受委托那一步立的，测试里显式摆上。
		if gate != null:
			main.flags.set_value(&"gate/late", true)
			h.check("这段之后大门还拦着", main._portal_blocked(gate), true)
			main.player.global_position = gate.rect.get_center()
			main.interact()
			h.check("拦着的时候出不去", main.current_map.id, &"desk_shop")

		# 换了个场景再回来，卧室门该换成「拦着」的那个口了
		main.enter_map(&"desk_shop", &"start")
		var next_door: MapDef.Portal = main.current_map.portal_at(
			Vector2(87, 91), main.flags)
		h.check("再走这扇门不再演剧情",
			next_door.event_id if next_door != null else &"", &"")
		h.check("而且它拦着",
			next_door != null and main._portal_blocked(next_door), true)
		h.check("拦下来说的是那句",
			next_door.blocked_text if next_door != null else "", "现在我不想睡觉。")

	# ---- 三、IF 框本身 ----
	h.check("IF 框建起来了", main.if_panel != null, true)
	h.check("一开始是收着的", main.if_panel.is_open(), false)
	main.if_panel.open("猫不见了", "来找主角帮忙")
	h.check("开得起来", main.if_panel.is_open(), true)
	h.check("条件填进去了", main.if_panel.condition_text(), "猫不见了")
	h.check("结果填进去了", main.if_panel.result_text(), "来找主角帮忙")
	h.check("四个事项块", main.if_panel.slot_count(), 4)
	main.if_panel.set_slot_state(0, IfPanel.SlotState.DISABLED)
	h.check("能切成禁用", main.if_panel.slot_state(0), IfPanel.SlotState.DISABLED)
	main.if_panel.close()
	h.check("收得起来", main.if_panel.is_open(), false)

	main.queue_free()


## **黑幕要排在收 CG 之前。**
##
## `StageCurtain` 是**第 5 层**、演出层（CG 待的）是**第 14 层** ——
## CG 盖在黑幕**上面**。所以「先收 CG、再黑屏」的写法，会让那 0.6 秒淡出
## 透出**背后的场景**：2026-09-25 策划报的「出现 cg 后不应该再出现角色在
## 委托屋站着」，根子就是这个。反过来写才对 —— 先下黑幕，CG 淡出时透出的是黑。
##
## 这条**扫全部剧本**，谁写反了都会红（写的时候 `end2_cg` 和 `meet_b` 的
## `distrust` 都是反的）。
static func test_blackout_before_hiding_cg(h: TestHarness) -> void:
	var dir := DirAccess.open("res://data/events")
	if dir == null:
		h.check("读得到剧情目录", false, true)
		return

	var bad: Array[String] = []
	var scanned := 0
	for raw: String in dir.get_files():
		var base := raw
		if base.ends_with(".import"):
			base = base.substr(0, base.length() - ".import".length())
		if not base.ends_with(".json"):
			continue
		var event := DataLoader.load_event(StringName(base.trim_suffix(".json")))
		if event == null:
			continue
		scanned += 1
		for node: StoryNode in event.nodes:
			var black_at := -1
			var hide_at := -1
			for i: int in node.stage.size():
				var s: StageStep = node.stage[i]
				if s.kind == &"fade" and s.text("to") == "black":
					black_at = i
				if s.kind == &"image_hide":
					hide_at = i
			if black_at >= 0 and hide_at >= 0 and hide_at < black_at:
				bad.append("%s/%s" % [event.id, node.id])
	h.check("扫到了剧本（%d 份）" % scanned, scanned > 0, true)
	h.check("没有「先收 CG 再黑屏」的节点", bad, [] as Array[String])


## IF 框的**拖动**：把下面某一块搬到 `then` 上，**两块换位置**。
##
## 2026-09-25 加的教学关卡就靠它 —— 策划要的是「拖动「立即离开」顶替
## `then` 里原本那个「观察」，**被顶掉的自动回到原本位置**」。
##
## 走的是 `move_to_then()`，它里面就是拖动松手时那条路（`_swap_with_then`）——
## 不另写一套，免得两边分叉。
static func test_if_panel_drag(h: TestHarness) -> void:
	var main := h.new_main()
	var panel: IfPanel = main.if_panel
	panel.setup()
	panel.open("", "观察", "发现异常")
	panel.set_slot_block(0, "")
	panel.set_slot_block(1, "立即离开")
	panel.set_slot_block(2, "")
	panel.set_slot_block(3, "")
	panel.remember_layout()

	# 开局的样子：`if` 后面是「发现异常」、`then` 里是「观察」，
	# 第一格和第三格都空着（它们的内容摆上去了）
	h.check("if 后面摆着「发现异常」", panel.if_block(), "发现异常")
	h.check("then 里是「观察」", panel.then_block(), "观察")
	h.check("第一格空着", panel.slot_block(0), "")
	h.check("第三格空着", panel.slot_block(2), "")

	h.check("搬得动", panel.move_to_then(1), true)
	h.check("then 换成「立即离开」", panel.then_block(), "立即离开")
	h.check("被顶掉的「观察」回到第二格", panel.slot_block(1), "观察")
	h.check("原来空着的第一格还是空的", panel.slot_block(0), "")

	# **排乱了就丢回开局那套**（2026-09-25 策划要的：玩家排出预设之外的组合、
	# 按了确定之后，让他重新排）
	panel.reset_blocks()
	h.check("回位：then 又是「观察」", panel.then_block(), "观察")
	h.check("回位：第二格又是「立即离开」", panel.slot_block(1), "立即离开")
	h.check("回位：if 后面还是「发现异常」", panel.if_block(), "发现异常")

	# 空位搬不动；禁用的也搬不动
	h.check("空位搬不动", panel.move_to_then(0), false)
	panel.set_slot_block(3, "别动我")
	panel.set_slot_state(3, IfPanel.SlotState.DISABLED)
	h.check("禁用的搬不动", panel.move_to_then(3), false)
	h.check("搬不动就没改数据", panel.slot_block(3), "别动我")

	# **两个块位都得有锚点。** 2026-09-25 截图里的毛病：`_blank_at` 里塞了
	# 固定段的占位，索引一错，两个块全被当成「没位置」藏起来 ——
	# 框里只剩两个虚线洞，块一个都看不见。
	var blanks := panel.blank_positions()
	h.check("两个块位都有位置", blanks.size(), 2)
	if blanks.size() == 2:
		h.check("两个位置不一样", blanks[0] != blanks[1], true)
		h.check("if 那个在 then 那个左边", blanks[0].x < blanks[1].x, true)

	# ---- 按「确定」算哪种结果 ----
	# 这一组是 2026-09-25 策划报的毛病：「什么都不做按确定就能往下演」。
	# 判定本来夹在 `cutscene._if_panel` 的协程里、测不到，所以抽成了
	# `IfPanel.judge()` 这个纯函数。
	panel.reset_blocks()
	h.check("什么都没改 → 算「没动过」",
		panel.judge("立即离开"), IfPanel.Verdict.UNTOUCHED)
	h.check("没动过就不该算过",
		panel.judge("立即离开") == IfPanel.Verdict.SOLVED, false)
	var moved := panel.move_to_then(1)
	h.check("搬对了 → 算「过」", panel.judge("立即离开"), IfPanel.Verdict.SOLVED)
	panel.set_then_block("别的什么")
	h.check("排成第三种组合 → 算「排错」",
		panel.judge("立即离开"), IfPanel.Verdict.WRONG)
	panel.reset_blocks()

	# **`if` 位被动过也算排错。** 2026-09-25 策划试出来的：光判 `then` 的话，
	# 把「立即离开」拖到 `if` 上、`then` 没动，照样蒙混过关。
	h.check("把答案拖到 if 上也过不了",
		panel.move_to_slot(1, IfPanel.FROM_IF), true)
	h.check("if 位现在不是「发现异常」了", panel.if_block(), "立即离开")
	h.check("于是判成排错", panel.judge("立即离开"), IfPanel.Verdict.WRONG)
	panel.reset_blocks()
	h.check("回位之后 if 上又是「发现异常」", panel.if_block(), "发现异常")
	h.check("回位之后就是「没动过」",
		panel.judge("立即离开"), IfPanel.Verdict.UNTOUCHED)

	# ---- 四种图各用在哪（2026-09-25 策划专门重新明确的）----
	# 显示逻辑抽成了 `block_state()`，就是为了能这样断言。
	h.check("空位 = 禁用图", panel.block_state(0), IfPanel.SlotState.DISABLED)
	h.check("有内容的格子 = 常态图", panel.block_state(1), IfPanel.SlotState.NORMAL)
	h.check("if 那块 = 选中图", panel.block_state(IfPanel.FROM_IF),
		IfPanel.SlotState.ACTIVE)
	h.check("then 那块 = 选中图", panel.block_state(IfPanel.FROM_THEN),
		IfPanel.SlotState.ACTIVE)

	# ---- 只读的框：**两块也拖不动**（老人那一步就是纯展示）----
	# 2026-09-25 策划报的：「两个选项块左右调换依然能接着往下演」。
	panel.set_read_only(true)
	h.check("只读时确实标上了", panel.is_read_only(), true)
	panel.set_slot_block(0, "试试")
	h.check("只读时空位也拖不动", panel.move_to_slot(0, IfPanel.FROM_THEN), false)
	panel.set_slot_block(0, "")
	panel.set_read_only(false)

	# **「确定」按钮**：在框里、压在四个选项栏右边，而且**和四格在同一条线上**
	#（原来 y 贴的是框底，歪在格子下面一截）
	var confirm := panel.confirm_rect()
	h.check("确定按钮在框内", panel.box_rect().encloses(confirm), true)
	h.check("确定按钮在四格右边",
		confirm.position.x >= panel.slot_position(3).x + IfPanel.SLOT_SIZE, true)
	h.check("确定按钮和四格一条线",
		absf(confirm.get_center().y
			- (panel.slot_position(0).y + IfPanel.SLOT_SIZE * 0.5)) < 0.5, true)
	h.check("而且没贴着右边框",
		panel.box_rect().end.x - confirm.end.x > IfPanel.PAD.x, true)

	panel.close()
	main.queue_free()


## **每一张铺满的 CG 都得停够时间。**
##
## `_image` 那两条默认值凑在一起是个坑：`hold` 不写是 **0**、`hide` 不写是 **true**
## —— 合起来就是「淡入完立刻淡出」，一闪而过。2026-09-25 策划的 bug 单
## 第 14 条报的就是这个（「cg 的留存时间太短了」）。
##
## 扫全部剧本，每张**铺满的** CG 满足下面任意一条就算过：
##
##   - 写了够长的 `hold`（≥1.5 秒）
##   - `wait_click: true` —— 等玩家点，不算短
##   - `hide: false` —— 图留着不收，靠后面的台词撑
##
## **道具小图不算**（没写 `fill`）：它们不铺满，背后本来就是场景。
static func test_cg_stays_long_enough(h: TestHarness) -> void:
	var bad: Array[String] = []
	var scanned := 0
	for eid: StringName in [&"ch1_opening", &"ch1_bed", &"ch2_meet_a", &"meet_b"]:
		var event := DataLoader.load_event(eid)
		if event == null:
			continue
		for node: StoryNode in event.nodes:
			for step: StageStep in node.stage:
				if step.kind != &"image":
					continue
				scanned += 1
				if not step.flag("fill", false):
					continue                      # 道具小图，不算
				if not step.flag("hide", true):
					continue                      # 留着不收，靠台词撑
				if step.flag("wait_click", false):
					continue                      # 等玩家点
				if step.number("hold", 0.0) >= 1.5:
					continue
				bad.append("%s/%s 的 %s" % [eid, node.id,
					step.text("path").get_file()])
	h.check("扫到了 CG（%d 张里含道具图）" % scanned, scanned > 0, true)
	h.check("铺满的 CG 都停够了（或等玩家点 / 留着不收）", bad, [] as Array[String])


## **结局那三张 CG：配乐 + 等玩家点。**
##
## 2026-09-25 策划要的：end CG 图和对应的音乐**一起放**，而且**不自动往下走** ——
## 玩家点一下才进后面的内容（黑屏写 end 名称那一段）。
##
## 四条一起钉：CG 在、是那张、**等玩家点**、音乐配上了。
static func test_ending_cg_and_music(h: TestHarness) -> void:
	var cases := [
		# **`declined` 这个名字不达意** —— 它演的是「拒绝委托之后睡着、
		# 梦里死掉」那一段，end1 的 CG 在它末尾。`calm_death` 是它下游那个
		# 空的终点节点（只写着 `ending`）。
		{"event": &"ch1_opening", "node": &"declined", "cg": "end1平静即死亡.png",
			"music": "res://audio/bgm/end1.wav"},
		{"event": &"ch2_meet_a", "node": &"end2_cg", "cg": "end2甜蜜咬痕.png",
			"music": "res://audio/bgm/end2.wav"},
		{"event": &"meet_b", "node": &"distrust", "cg": "end3碌碌无为.png",
			"music": "res://audio/bgm/end3.wav"},
	]
	for item: Dictionary in cases:
		var eid: StringName = item["event"]
		var event := DataLoader.load_event(eid)
		if event == null:
			h.check("读得到 %s" % eid, false, true)
			continue
		var node: StoryNode = event.node(StringName(str(item["node"])))
		h.check("%s 里有 %s" % [eid, item["node"]], node != null, true)
		if node == null:
			continue
		var cg_step: StageStep = null
		var music_step: StageStep = null
		for step: StageStep in node.stage:
			if step.kind == &"image":
				cg_step = step
			if step.kind == &"music":
				music_step = step
		h.check("%s 摆了 end CG" % eid, cg_step != null, true)
		if cg_step != null:
			h.check("%s 的 CG 是那张" % eid,
				cg_step.text("path").get_file(), str(item["cg"]))
			h.check("%s 的 CG 铺满" % eid, cg_step.flag("fill", false), true)
			h.check("%s 的 CG 等玩家点才往下走" % eid,
				cg_step.flag("wait_click", false), true)
			h.check("%s 的 CG 留着不收" % eid, cg_step.flag("hide", true), false)
		h.check("%s 配了 end 音乐" % eid, music_step != null, true)
		if music_step != null:
			h.check("%s 的音乐是那首" % eid,
				music_step.text("path"), str(item["music"]))


## 过场里临时角色的**姿势和翻面**，以及「一边平移一边淡出」。
##
## A（2026-09-24 加的角色）只有两张图：侧站、蹲着，**没有走路动画** ——
## 所以「转过去走掉」只能靠翻侧面图 + 平移淡出，而不是切走路帧。
static func test_actor_poses(h: TestHarness) -> void:
	var main := h.new_main()
	var scene: Cutscene = main.cutscene

	# 帧目录里两个姿势都建成了动画，出场时按 `pose` 摆好
	var actor := scene.add_actor("a", "res://art/npc/a", Vector2(368, 172), 45.0, 9,
		"crouch")
	h.check("A 建成了动画角色", actor is AnimatedSprite2D, true)
	if not (actor is AnimatedSprite2D):
		main.queue_free()
		return
	var sprite := actor as AnimatedSprite2D
	var frames := sprite.sprite_frames
	h.check("有侧面这组帧", frames.has_animation(&"idle_side"), true)
	h.check("有蹲着这组帧", frames.has_animation(&"idle_crouch"), true)
	h.check("出场就是蹲着的", sprite.animation, &"idle_crouch")

	# 向主角一侧站着：换姿势 + 不翻面
	scene._npc_pose(StageStep.from_dictionary({"do": "npc_pose", "id": "a", "pose": "side"}))
	h.check("换成侧站", sprite.animation, &"idle_side")
	h.check("默认不翻面", sprite.flip_h, false)

	# 转过去走：翻面（侧面图水平翻转就是「面朝另一边」）
	scene._npc_pose(StageStep.from_dictionary({"do": "npc_pose", "id": "a", "flip": true}))
	h.check("翻面了", sprite.flip_h, true)

	# 要一个他没有的姿势 —— **不能把动画置空**，退到他有的那组
	var fallback := scene.add_actor("b", "res://art/npc/a", Vector2.ZERO, 45.0, 9, "down")
	if fallback is AnimatedSprite2D:
		var fs := fallback as AnimatedSprite2D
		h.check("没有的姿势要退回他有的第一组",
			fs.sprite_frames.has_animation(fs.animation), true)

	# 一边平移一边淡出：走完人是全透明的
	var steps: Array[StageStep] = [StageStep.from_dictionary({
		"do": "npc_move", "id": "a", "to": [413, 172], "time": 1.2, "fade": true})]
	main.cutscene.instant = true
	scene.run(steps)
	h.check("淡出之后是全透明的", sprite.modulate.a, 0.0)
	h.check("位置也走到了", sprite.position, Vector2(413, 172))

	main.queue_free()


## 集市那一幕（轮回第二遍 → 集市 → end2）的剧本数据。
##
## 这一段最要紧的一条是策划反复叮嘱的：**「复制粘贴」但不进 CG** ——
## 走向床那一段和第一遍一模一样，**不能接回 `cat`**（接了就会又演一遍梦）。
## 所以这里钉住它的 `next`。
static func test_ch2_scene_data(h: TestHarness) -> void:
	var event := DataLoader.load_event(&"ch1_bed")
	h.check("读得到 ch1_bed", event != null, true)
	if event == null:
		return

	var ids: Array = []
	for n: StoryNode in event.nodes:
		ids.append(n.id)
	# 睡觉那一段从 `bed` 起、到 `again` 交还控制权。
	# **进卧室那一步不在这个文件里** —— 2026-09-25 起走进卧室只把画面带到屋里，
	# 玩家自己走到床前按交互才演这一段（`ch1_sleep` 进场 / `ch1_bed` 睡觉）。
	for want: StringName in [&"bed", &"cat", &"death", &"back", &"observe",
			&"peek", &"again"]:
		h.check("ch1_bed 有节点 %s" % want, ids.has(want), true)
	h.check("这一夜到 again 就完了（没有 bed_again）", ids.has(&"bed_again"), false)

	# 第二遍（`again`）：老人又来。
	#
	# **重复的是那句问话，不是「缺耳角」。** 2026-09-25 策划先报了一次、
	# 我改反了，他再指出来的：`back` 里老人刚问过「……你这里，接找猫的活吗？」，
	# `again` 开头又问一遍 —— 删的是**这句**。
	# 「它左耳缺一角。尾巴尖是白的。」只在 `again` 出现（`back` 里没说过），
	# 得留着。
	var again := event.node(&"again")
	var copied: Array[String] = []
	for step: StageStep in again.stage:
		for raw: Variant in step.data.get("lines", []):
			if raw is Dictionary:
				copied.append(str((raw as Dictionary).get("text", "")))
	h.check("第二遍不再重复那句问话",
		copied.has("……你这里，接找猫的活吗？"), false)
	for want: String in ["它左耳缺一角。尾巴尖是白的。", "然后……没有然后了。",
			"好，我会尽快给您消息。"]:
		h.check("复刻了「%s」" % want.left(6), copied.has(want), true)

	# 收场那两句换了（2026-09-25 策划给的新词）
	h.check("改成「这老人真奇怪」", copied.has("这老人真奇怪......"), true)
	h.check("改成「不行，我得赶紧出去找」", copied.has("不行，我得赶紧出去找"), true)
	h.check("老的「明天再出去找吧」没了",
		copied.has("这么晚了，明天再出去找吧。先休息吧。"), false)
	# 老人走出去那三下
	var again_kinds: Array[StringName] = []
	for step: StageStep in again.stage:
		again_kinds.append(step.kind)
	h.check("老人先走位再淡出",
		again_kinds.find(&"npc_move") < again_kinds.find(&"npc_remove"), true)
	# **演完交还控制权**：不带 next，玩家自己走到卧室门口
	h.check("again 不带 next（交还控制权）", again.next_id, &"")
	h.check("并且立起「睡过了」的标记",
		again.effects.get(&"gate/slept_once", false), true)

	# 回到委托屋那一下是**睁眼**，不是普通的淡入
	var back := event.node(&"back")
	var back_kinds: Array[StringName] = []
	for step: StageStep in back.stage:
		back_kinds.append(step.kind)
	h.check("回去那一幕有睁眼", back_kinds.has(&"eye_open"), true)
	var eye_at := back_kinds.find(&"eye_open")
	# **往前找最近的那一条 `fade`** —— 2026-09-25 在 `eye_open` 前面插了一条
	# 回溯音效（`play_sound`），不能再看 `eye_at - 1` 了。
	var clear_at := -1
	for i: int in range(eye_at - 1, -1, -1):
		if back.stage[i].kind == &"fade":
			clear_at = i
			break
	h.check("睁眼之前先把幕瞬揭",
		back.stage[clear_at].text("to") if clear_at >= 0 else "", "clear")
	h.check("幕那一下是瞬揭（时间 0）",
		back.stage[clear_at].number("time", 1.0) if clear_at >= 0 else 1.0, 0.0)

	# **回溯音在睁眼那一下**（策划要的：梦醒睁眼的时机放「时间回溯」）
	var back_sound := -1
	for i: int in back_kinds.size():
		if back_kinds[i] == &"play_sound" \
				and back.stage[i].text("path").get_file() == "时间回溯.wav":
			back_sound = i
	h.check("这儿放了回溯音", back_sound >= 0, true)
	if back_sound >= 0:
		h.check("而且排在睁眼之前", back_sound < eye_at, true)

	# **「观察」整篇只该出现一次。**
	# 2026-09-24 策划报的「观察选项重复出现两次、要点两次才接上」，
	# 就是 `again` 里又抄了一份 `observe` 的那个选项。
	var looks := 0
	for n: StoryNode in event.nodes:
		for c: StoryChoice in n.choices:
			if c.label == "观察":
				looks += 1
	h.check("「观察」整篇只出现一次", looks, 1)

	# 白天集市那一段是**第二个事件**了（`ch2_market`），从那儿读
	var second_event := DataLoader.load_event(&"ch2_market")
	h.check("读得到 ch2_market", second_event != null, true)
	if second_event == null:
		return

	# IF 框弹出来的时候要跟一句提示，而且**排在 if_panel 前面** ——
	# `if_panel` 会停在那儿等玩家点，排在后面就要等点完才出现。
	var peek := event.node(&"peek")
	var kinds_peek: Array[StringName] = []
	for step: StageStep in peek.stage:
		kinds_peek.append(step.kind)
	h.check("IF 框那一步有提示", kinds_peek.has(&"hint"), true)
	h.check("提示排在 IF 框之前",
		kinds_peek.find(&"hint") < kinds_peek.find(&"if_panel"), true)
	h.check("提示写的就是那句话",
		peek.stage[kinds_peek.find(&"hint")].text("text"), "（你看到了老人脑海中的if）")

	# **老人那个框里的块要真的摆上去。** 2026-09-25 坏过一次：`then` 那个位置
	# 那时候还叫 `result`，改名之后漏改，静默变成空块 —— 不报错，画面上只是少一块。
	var peek_panel: StageStep = peek.stage[kinds_peek.find(&"if_panel")]
	h.check("if 后面摆着「猫不见了」", peek_panel.text("if_block"), "猫不见了")
	h.check("then 里是「来找<昵称>帮忙」", peek_panel.text("then"),
		"来找%s帮忙" % PlayerName.current)
	h.check("而且这一框是纯展示（拖不动）",
		peek_panel.data.get("disabled", false), true)

	# ---- 下面这一串现在在 `ch2_market` 里（上床睡觉 → 第二天集市）----
	var second := DataLoader.load_event(&"ch2_market")
	h.check("读得到 ch2_market", second != null, true)
	if second == null:
		return
	var market_ids: Array = []
	for n: StoryNode in second.nodes:
		market_ids.append(n.id)
	# **这一段现在只剩「把人带进集市」。** 2026-09-25 拆的：原来它接着「进卧室
	# 睡觉」那条链（`sleep` 节点），现在第二遍进不了卧室了（怕了，门口就拦），
	# 后面从跟 A 搭话起全搬到 `ch2_meet_a`。
	h.check("ch2_market 只留一个进场节点", market_ids, [&"market_day"] as Array)

	var meet := DataLoader.load_event(&"ch2_meet_a")
	h.check("读得到 ch2_meet_a", meet != null, true)
	if meet == null:
		return
	var meet_ids: Array = []
	for n: StoryNode in meet.nodes:
		meet_ids.append(n.id)
	for want: StringName in [&"aside", &"market_talk", &"market_invite",
			&"market_dusk", &"market_after_days", &"home_after_days", &"end2_cg",
			&"tutorial"]:
		h.check("ch2_meet_a 有节点 %s" % want, meet_ids.has(want), true)

	# A 身上那一段：**先走过去再说话。** 策划要的是「玩家自己走到 A 旁边，
	# 选了互动之后才自动补上最后几步、然后开始对话」。
	var aside := meet.node(&"aside")
	h.check("A 那段从头是「走过去」", aside != null, true)
	if aside == null:
		return
	var aside_kinds: Array[StringName] = []
	for step: StageStep in aside.stage:
		aside_kinds.append(step.kind)
	h.check("第一步就是走位", aside_kinds.has(&"place_player"), true)
	h.check("走完接着说话", aside.next_id, &"market_talk")
	var walk_step: StageStep = aside.stage[aside_kinds.find(&"place_player")]
	h.check("落在 A 左边", walk_step.point("at").x < 368.0, true)
	h.check("和 A 齐（同一条 y）", walk_step.point("at").y, 172.0)
	h.check("走过去之后朝右", walk_step.text("facing"), "right")

	# 进集市：A 蹲在店门口修留声机，**玩家自己走进来**。
	# 时间 2026-09-25 改成傍晚了（策划要的：出门到集市就是傍晚）。
	var day := second.node(&"market_day")
	h.check("这一幕是 goto 过去的", day.stage[0].kind, &"goto")
	h.check("去的是夜晚集市", day.stage[0].text("map"), "market_night")
	var npc_step: StageStep = null
	var auto_walked := false
	for step: StageStep in day.stage:
		if step.kind == &"npc":
			npc_step = step
		if step.kind == &"place_player":
			auto_walked = true
	h.check("集市那一段不再自动走位", auto_walked, false)
	h.check("A 摆出来了", npc_step != null, true)
	if npc_step != null:
		h.check("A 出场是蹲着的", npc_step.text("pose"), "crouch")
		h.check("A 身上挂着那段", npc_step.text("talk"), "ch2_meet_a")
	h.check("演完交还控制权（不带 next）", day.next_id, &"")

	# **赴约那一幕改成白天了**（2026-09-25）：约定从「傍晚碰头」改成了
	# 「明早碰头」，所以再来的时候是白天。节点名还叫 `market_dusk` ——
	# 改名会动一堆引用，就没改，记一笔以免以后被名字骗了。
	var dusk_meet := meet.node(&"market_dusk")
	h.check("赴约那一幕的 goto 在第二条", dusk_meet.stage[1].kind, &"goto")
	h.check("赴约用的是白天集市", dusk_meet.stage[1].text("map"), "market")

	# 邀请那一步：A 转过去 + 边走边淡出
	var invite := meet.node(&"market_invite")
	var invite_kinds: Array[StringName] = []
	for step: StageStep in invite.stage:
		invite_kinds.append(step.kind)
	h.check("有翻面那一步", invite_kinds.has(&"npc_pose"), true)
	h.check("走的时候是边淡出", invite.stage[invite_kinds.find(&"npc_move")].flag("fade", false), true)
	h.check("黑屏之前就淡没了（淡出只占前 80%）", Cutscene.MOVE_FADE_RATIO, 0.8)

	# 傍晚那三行字：「却」要停一秒才浮出来
	var dusk := meet.node(&"market_dusk")
	var cap: StageStep = null
	for step: StageStep in dusk.stage:
		if step.kind == &"caption":
			cap = step
	h.check("傍晚有三行字", (cap.data["lines"] as Array).size() if cap != null else 0, 3)
	if cap != null:
		var lines: Array = cap.data["lines"]
		h.check("最后那行停一秒", float(lines[2].get("gap", 0.0)), 1.0)

	# **黑屏那三行字之后要切回白天**：路人那两句是在白天说的，
	# 而傍晚/夜里那一幕是 `market_night` —— 不切回去的话，
	# 玩家看到的是「大半夜有人在外面议论」。
	var after := meet.node(&"market_after_days")
	h.check("三天之后那一步先换场景", after.stage[0].kind, &"goto")
	h.check("换回的是白天集市", after.stage[0].text("map"), "market")
	h.check("换的是白天的图，不是夜版",
		DataLoader.load_map(StringName(after.stage[0].text("map"))).background,
		"res://art/map/market.png")
	h.check("人还站在先前和 A 说话的地方",
		after.stage[1].point("at"), Vector2(336, 172))
	h.check("而且那次换场景在黑幕底下做的（后一步才亮）",
		after.stage[3].text("to"), "clear")

	# 委托屋那两行：第二行加大两号 + 震屏
	var home := meet.node(&"home_after_days")
	var big: Dictionary = {}
	for step: StageStep in home.stage:
		if step.kind != &"say":
			continue
		for raw: Variant in step.data.get("lines", []):
			if raw is Dictionary and (raw as Dictionary).has("size_delta"):
				big = raw
	h.check("那句「真的 是我吗」加大两号", int(big.get("size_delta", 0)), 2)
	h.check("而且要震一下屏", float(big.get("shake", 0.0)) > 0.0, true)
	h.check("文本一个字没动", str(big.get("text", "")), "真的是 因为我吗？？？？！")

	# 结局：end2，还留了个教程占位
	# **教程那一步是中途的一步，不是终点。**
	#
	# 2026-09-24 踩过一次：改了它的 `stage` 和 `next`，却忘了删 `ending` ——
	# 那个字段一写节点就是终点，`next` 会被忽略，整段接不下去；
	# 而那条断言恰好查的是 `ending == end2_sweet`，于是它绿着。
	# 现在两边都钉住：`ending` 必须空、`next` 必须指向后面那一幕。
	var tutorial := meet.node(&"tutorial")
	h.check("教程那一步不是终点", tutorial.ending, &"")
	h.check("教学先演对话、再进 IF 框", tutorial.next_id, &"tutorial_choose")
	# **教学那一段现在是真内容了**（2026-09-25 补的）：回溯到集市、和 A 说话、
	# 弹 IF 框让玩家拖块改掉 A 的想法。原来是句占位台词「此处应有…动画」。
	h.check("教学第一步是回集市", tutorial.stage[0].kind, &"goto")
	# **教学那一幕是夜里**（2026-09-25 策划要的：「改变 A 的想法那个场景
	# 环境也应该是黑夜」—— 它回溯的就是第一次见他那一刻，那时是傍晚）。
	h.check("去的是夜晚集市", tutorial.stage[0].text("map"), "market_night")
	# **地图一出现就播回溯音**（策划要的：这一幕就是「又回到见 A 那一刻」）
	var recall_sound := false
	for step: StageStep in tutorial.stage:
		if step.kind == &"play_sound" \
				and step.text("path").get_file() == "时间回溯.wav":
			recall_sound = true
	h.check("回到集市的那一刻报了回溯音", recall_sound, true)

	var choose := meet.node(&"tutorial_choose")
	h.check("有拖块那一步", choose != null, true)
	if choose != null:
		var panel: StageStep = null
		for step: StageStep in choose.stage:
			if step.kind == &"if_panel":
				panel = step
		h.check("那一步里有 IF 框", panel != null, true)
		if panel != null:
			h.check("if 后面摆着「发现异常」", panel.text("if_block"), "发现异常")
			h.check("then 里先放着「观察」", panel.text("then"), "观察")
			h.check("要玩家拖的是「立即离开」", panel.text("solve"), "立即离开")
			# **不再靠 `wrong` 硬跳分岔**（2026-09-25 策划纠正的）：
			# 两条出口**走同一段对话**（`again_day`），分岔交给
			# `again_day` 的 `next_when` 读这个 flag。
			h.check("把结果记进 flag", panel.text("flag"), "gate/saved_a")
			h.check("不再用 wrong 硬跳", panel.text("wrong"), "")
			var blocks: Array = panel.data.get("blocks", [])
			h.check("下面摆了四格", blocks.size(), 4)
			if blocks.size() == 4:
				# 两块都摆上去了，原位就空着 —— 策划说的「选项A一开始就是空着的」
				# 和「发现异常原本位置为选项C」都是这个意思。
				h.check("第一格空着（「观察」的原位）", str(blocks[0]), "")
				h.check("第二格是「立即离开」", str(blocks[1]), "立即离开")
				h.check("第三格空着（「发现异常」的原位）", str(blocks[2]), "")
		h.check("拖对了接着往下演", choose.next_id, &"again_day")
		# **拖对之后不另加台词**（2026-09-25 策划说的：那两句自己加的删掉，
		# 直接接原文案的「（猛吸气）」）。所以这儿只剩「起身」那个动作。
		var choose_says := 0
		for step: StageStep in choose.stage:
			if step.kind == &"say":
				choose_says += 1
		h.check("拖完不另加台词", choose_says, 0)

	# **「没改」不是复刻一段对话，是回溯到前面那个节点。**
	#
	# 两条出口都走 `again_day`（**对话一模一样**），出来之后靠 `next_when`
	# 读 IF 框记下的 flag 分岔：
	#   - 改过了 → `again_dusk`（新剧情）
	#   - 没改   → `market_dusk`（回溯到「白天等不到 A」那一幕）
	#
	# 2026-09-25 策划纠正的：「这个与老人两次委托不同，是单纯的回溯到前面的
	# 剧情节点」。我上一版自己编了一段「碰头找不到 A」，删掉了。
	var day2_node := meet.node(&"again_day")
	h.check("again_day 有 next_when 分岔", day2_node.next_when.is_empty(), false)
	if not day2_node.next_when.is_empty():
		var condition: Condition = day2_node.next_when["condition"]
		h.check("条件读得出来", condition != null, true)
		if condition != null:
			var probe := WorldState.new()
			probe.set_value(&"gate/saved_a", false)
			h.check("没改 → 回溯到「等不到 A」那一幕",
				day2_node.resolved_next(probe), &"market_dusk")
			probe.set_value(&"gate/saved_a", true)
			h.check("改过 → 走新剧情", day2_node.resolved_next(probe), &"again_dusk")
	h.check("没有多余的复刻节点", meet.node(&"tutorial_miss"), null)
	h.check("而且在这儿记下 end2 达成",
		tutorial.effects.get(&"ending/end2_sweet", false), true)

	# 通关之后那一幕：**仍在夜里**（2026-09-25 策划要的：改完想法不该切回白天）
	var day2 := meet.node(&"again_day")
	h.check("仍在夜晚集市", day2.stage[0].text("map"), "market_night")
	h.check("A 又站在对面", day2.stage[2].point("at"), Vector2(368, 172))
	h.check("A 身上挂着「再说话」那段", day2.stage[2].text("talk"), "ch2_talk_a")
	h.check("接着是傍晚那一幕", day2.next_id, &"again_dusk")

	var dusk2 := meet.node(&"again_dusk")
	var dusk_kinds: Array[StringName] = []
	for step: StageStep in dusk2.stage:
		dusk_kinds.append(step.kind)
	h.check("傍晚切的是夜版集市", dusk2.stage[2].text("map"), "market_night")
	h.check("A 是从远处淡入的", dusk_kinds.has(&"npc"), true)
	h.check("A 会跑到主角跟前", dusk_kinds.has(&"npc_move"), true)
	h.check("A 最后蹲下不再动", dusk_kinds.has(&"npc_pose"), true)
	h.check("神秘人 B 也出场了",
		dusk2.stage[dusk2.stage.size() - 2].text("talk"), "meet_b")
	h.check("这一幕演完交还控制权", dusk2.next_id, &"")
	h.check("结局文字两行",
		(meet.node(&"end2_cg").stage[meet.node(&"end2_cg").stage.size() - 1]
			.data["lines"] as Array).size(), 2)

	# **end2 之后接的是教学，不是直接回委托屋。**
	#
	# 2026-09-25 策划报过「出现 cg 后不应该再出现角色在委托屋站着」——
	# 那一条的真根在「先收 CG 再黑屏」（见下面那条顺序断言，已经在 `end2_cg` 里）。
	# 后来策划要补 IF 框的教学，链路就接回 `tutorial` 了：
	# 结局 → 教学（回溯集市、改掉 A 的想法）→ 重来。
	h.check("end2_cg 之后接教学", meet.node(&"end2_cg").next_id, &"tutorial")
	h.check("end2_cg 不是终点", meet.node(&"end2_cg").ending, &"")

	# **黑幕要排在收 CG 前面。**
	#
	# 2026-09-25 策划报的「出现 cg 后不应该再出现角色在委托屋站着」——
	# 根子在这儿：`StageCurtain` 是**第 5 层**、演出层（CG 待的）是**第 14 层**，
	# CG 盖在黑幕**上面**。所以先收 CG 的话，那 0.6 秒淡出透出来的是
	# **背后的委托屋和站着的人**；先下黑幕再收，透出来的就是黑幕。
	var cg_stage := meet.node(&"end2_cg").stage
	var black_at := -1
	var hide_at := -1
	for i: int in cg_stage.size():
		var s: StageStep = cg_stage[i]
		if s.kind == &"fade" and s.text("to") == "black":
			black_at = i
		if s.kind == &"image_hide":
			hide_at = i
	h.check("有黑屏那一步", black_at >= 0, true)
	h.check("有收 CG 那一步", hide_at >= 0, true)
	h.check("黑幕排在收 CG 之前", black_at >= 0 and hide_at > black_at, true)


## 自由活动那一阶段的两位：A 和神秘人 B。
##
## 他们不是地图上的常驻 NPC，而是**演出放出来、演完留在场上**的临时角色
##（`npc` 的 `talk`）。这条守的是「他们身上到底挂着哪段对话」。
static func test_transient_talks(h: TestHarness) -> void:
	var a_talk := DataLoader.load_event(&"ch2_talk_a")
	h.check("读得到 ch2_talk_a", a_talk != null, true)
	if a_talk != null:
		var start := a_talk.node(&"start")
		h.check("A 那句「又有什么事情吗」",
			(start.stage[0].data["lines"] as Array)[0]["text"], "又有什么事情吗")
		h.check("两个选项", start.choices.size(), 2)
		h.check("① 邀请李淳罡", start.choices[0].label, "邀请李淳罡")
		h.check("② 离开", start.choices[1].label, "离开")
		h.check("两条路都演完就收（不带 next）",
			a_talk.node(&"invited").next_id, &"")

	# **A 的台词都要挂立绘。** 2026-09-25 策划指出来的：老人有立绘、A 没有，
	# 对话框里就只有名字。素材（`art/portrait/a.png`）一直在，缺的只是剧本里那个字段。
	for eid: StringName in [&"ch2_meet_a", &"ch2_talk_a"]:
		var ev := DataLoader.load_event(eid)
		if ev == null:
			h.check("读得到 %s" % eid, false, true)
			continue
		var a_lines := 0
		var no_face: Array[String] = []
		for n: StoryNode in ev.nodes:
			for step: StageStep in n.stage:
				for raw: Variant in step.data.get("lines", []):
					if not (raw is Dictionary):
						continue
					var line: Dictionary = raw
					if str(line.get("speaker", "")) != "李淳罡":
						continue
					a_lines += 1
					if str(line.get("portrait", "")) == "":
						no_face.append(str(line.get("text", "")))
		h.check("%s 里 A 有台词（%d 句）" % [eid, a_lines], a_lines > 0, true)
		h.check("%s 里 A 每句都挂了立绘" % eid, no_face, [] as Array[String])

	var b_talk := DataLoader.load_event(&"meet_b")
	h.check("读得到 meet_b", b_talk != null, true)
	if b_talk != null:
		var b_start := b_talk.node(&"start")
		h.check("B 那段是两个选项", b_start.choices.size(), 2)
		h.check("① 不相信", b_start.choices[0].label, "不相信")
		h.check("② 去就去", b_start.choices[1].label, "去就去")
		h.check("选项之前提示存档", b_start.stage[b_start.stage.size() - 2].text("at"), "center")
		h.check("不相信那条走到 end3",
			b_talk.node(&"distrust").ending, &"end3_nothing")
		# **去就去那条不是终点**：它把玩家送回委托屋（第二章没定稿）
		var deal := b_talk.node(&"deal")
		h.check("答应之后不是终点", deal.ending, &"")
		# 拿到吊坠单独成一步 —— **`set` 是进节点时生效的**，
		# 挂在 `deal` 上会让「获得」提示抢在图片前面弹出来（策划报的）。
		h.check("拿吊坠那一步在答应之后", deal.next_id, &"pendant")
		h.check("`deal` 自己不发道具", deal.effects.has(&"item/pendant"), false)
		var pendant := b_talk.node(&"pendant")
		h.check("吊坠在这一步发", pendant.effects.get(&"item/pendant", 0), 1)
		var pk: Array[StringName] = []
		for step: StageStep in pendant.stage:
			pk.append(step.kind)
		h.check("这一步先亮出吊坠的图", pk[1], &"image")
		h.check("有背景闪烁那一步", pk.has(&"bg_blink"), true)
		h.check("闪六下（黑/亮 走三遍）",
			int(pendant.stage[pk.find(&"bg_blink")].number("times", 0.0)), 6)
		h.check("闪完**连主角一起盖住**",
			pk[pk.find(&"bg_blink") + 1], &"fade")
		h.check("等玩家点一下", pk.has(&"wait_click"), true)
		h.check("点完出第二章标题", pk.has(&"banner"), true)
		# **去就去那条改道了**：第二章正文从死巷开始（人类定的），
		# 第二章标题之后的黑屏直接把人传送到死巷+铁门。
		h.check("最后把人送进死巷",
			pendant.stage[pk.find(&"goto")].text("map"), "dead_alley")


## 夜晚版集市：**几何一个字都不许差**（两张插画是一模一样的），
## 只该差 `id` / `name` / `background` 三样。
static func test_market_night_same_geometry(h: TestHarness) -> void:
	var day := DataLoader.load_map(&"market")
	var night := DataLoader.load_map(&"market_night")
	h.check("两张图都读得到", day != null and night != null, true)
	if day == null or night == null:
		return

	h.check("大小一样", night.size, day.size)
	h.check("墙一样多", night.walls.size(), day.walls.size())
	h.check("墙的位置一样", str(night.walls), str(day.walls))
	h.check("传送区一样", night.portals.size(), day.portals.size())
	h.check("出生点一样", night.spawn_point(&"from_overworld"),
		day.spawn_point(&"from_overworld"))
	h.check("夜里也是露天", night.indoor, false)
	h.check("名字不一样", night.name != day.name, true)
	h.check("背景图不一样", night.background != day.background, true)
