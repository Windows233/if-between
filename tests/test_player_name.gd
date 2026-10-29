## 主角昵称：输入校验、剧情/地图 `{name}` 替换、存读档、NPC 改名后的数据。
extends RefCounted

const TEST_SLOT := 2


static func run(h: TestHarness) -> void:
	h.section("主角昵称与NPC改名")
	test_rules(h)
	test_fill(h)
	test_data_has_no_old_names(h)
	test_save_round_trip(h)
	test_panel_layout(h)
	PlayerName.current = PlayerName.DEFAULT


static func test_rules(h: TestHarness) -> void:
	h.check("中文名合法", PlayerName.problem("林小满"), "")
	h.check("英文名合法", PlayerName.problem("Alice"), "")
	h.check("英文名可带空格", PlayerName.normalize("  Tom   Lee "), "Tom Lee")
	h.check("间隔号译名合法", PlayerName.problem("艾米·李"), "")
	h.check("中英混合合法", PlayerName.problem("小A"), "")
	h.check("空名不合法", PlayerName.problem("   "), "请输入昵称")
	h.check("数字不合法", PlayerName.problem("abc1"), "只能使用中文或英文字母")
	h.check("符号不合法", PlayerName.problem("[b]"), "只能使用中文或英文字母")
	h.check("日文假名不合法", PlayerName.problem("さくら"), "只能使用中文或英文字母")
	h.check("超长不合法", PlayerName.problem("一二三四五六七八九"),
		"最多 %d 个字" % PlayerName.MAX_LENGTH)
	h.check("八个字刚好合法", PlayerName.problem("一二三四五六七八"), "")
	h.check("间隔号不能打头", PlayerName.problem("·李"), "间隔号不能放在开头或结尾")
	h.check("不合法时规整为空", PlayerName.normalize("abc1"), "")

	var flags := WorldState.new()
	PlayerName.sync_from(flags)
	h.check("没起过名时用默认名", PlayerName.current, PlayerName.DEFAULT)
	PlayerName.assign(flags, " Bob ")
	h.check("起名写进世界状态", flags.get_value(PlayerName.FLAG), "Bob")
	h.check("起名更新缓存", PlayerName.current, "Bob")
	flags.set_value(PlayerName.FLAG, "坏名字123")
	PlayerName.sync_from(flags)
	h.check("存档里的非法名退回默认", PlayerName.current, PlayerName.DEFAULT)


static func test_fill(h: TestHarness) -> void:
	PlayerName.current = "林小满"
	h.check("占位符被替换", PlayerName.apply("{name}，和我组队吧"), "林小满，和我组队吧")
	h.check("没占位符原样返回", PlayerName.apply("你好"), "你好")
	var nested: Variant = DataLoader.fill_player_name({"a": ["{name}", {"{name}": "x{name}"}], "n": 3})
	h.check("嵌套值都被替换、键不动", nested, {"a": ["林小满", {"{name}": "x林小满"}], "n": 3})

	# 剧情正文：原稿 yn 的五处与第三人称旁白
	var expect := {
		&"ch2_swing": ["林小满，自己经营一家事务所", "算了算了，遇见就是缘分。林小满，和我组队吧"],
		&"ch2_library_cat": ["这就不行了吗，林小满还是得多练呐", "这下彻底再见咯，林小满",
			"林小满用力推向身旁的书架，挡住裴予安的去路。"],
		&"ch2_market_b_end": ["林小满是吗，你比我想象中的做得还要好呢"],
		&"ch2_register": ["xxxx  xxxx  xxxx  林小满"],
		&"ch1_bed": ["来找林小满帮忙"],
	}
	for event_id: StringName in expect:
		var dump := _event_text(event_id)
		for want: String in expect[event_id]:
			h.check("%s 含「%s」" % [event_id, want], dump.contains(want), true)
		h.check("%s 不残留占位符" % event_id, dump.contains(PlayerName.TOKEN), false)

	var gate := DataLoader.load_map(&"gatehouse")
	var register_line := ""
	for actor: MapDef.Actor in gate.actors:
		for inter: MapDef.Interaction in actor.interactions:
			for line: DialogueLine in inter.dialogue.lines:
				if line.text.begins_with("xxxx"):
					register_line = line.text
	h.check("地图台词也替换", register_line, "xxxx  xxxx  xxxx  林小满")


## 所有剧情与地图 JSON：读进来后不残留占位符、不再出现旧代号 A/B/C 或 yn。
static func test_data_has_no_old_names(h: TestHarness) -> void:
	PlayerName.current = "Amy"
	var leaks: Array[String] = []
	var old_names: Array[String] = []
	var letter := RegEx.create_from_string("(?<![A-Za-z0-9_/.\\-])[ABC](?![A-Za-z0-9_/.\\-])")
	var cjk := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
	var yn := RegEx.create_from_string("(?<![A-Za-z])yn(?![A-Za-z])")
	for dir: String in ["res://data/events/", "res://data/maps/"]:
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".json"):
				continue
			var raw := FileAccess.get_file_as_string(dir + file)
			var parsed: Variant = DataLoader.fill_player_name(JSON.parse_string(raw))
			var strings: Array[String] = []
			_collect_strings(parsed, strings)
			for text: String in strings:
				if text.contains(PlayerName.TOKEN):
					leaks.append("%s: %s" % [file, text])
				if text in ["A", "B", "C"] or (cjk.search(text) != null and letter.search(text) != null) \
						or yn.search(text) != null:
					old_names.append("%s: %s" % [file, text])
	h.check("剧情/地图不残留 {name}", leaks, [] as Array[String])
	h.check("剧情/地图不再有 A/B/C/yn 代号", old_names, [] as Array[String])

	var speakers := {}
	for event_id: StringName in [&"meet_a", &"meet_b", &"ch2_swing"]:
		var ev := DataLoader.load_event(event_id)
		for node: StoryNode in ev.nodes:
			for step: StageStep in node.stage:
				for raw_line: Variant in step.data.get("lines", []):
					if raw_line is Dictionary:
						speakers[str((raw_line as Dictionary).get("speaker", ""))] = true
			for line: DialogueLine in node.dialogue.lines:
				speakers[line.speaker] = true
	h.check("陈遇在说话", speakers.has("陈遇"), true)
	h.check("神秘人在说话", speakers.has("神秘人"), true)
	h.check("裴予安在说话", speakers.has("裴予安"), true)


static func test_save_round_trip(h: TestHarness) -> void:
	var main := h.new_main()
	main.skip_opening = true
	main.new_game(&"", &"", "Bob")
	h.check("开局即带上昵称", main.flags.get_value(PlayerName.FLAG), "Bob")
	main.save_game(TEST_SLOT)
	main.new_game(&"", &"", "林小满")
	h.check("新局换了名", PlayerName.current, "林小满")
	main.load_game(TEST_SLOT)
	h.check("读档恢复存档里的昵称", PlayerName.current, "Bob")
	h.check("读档后世界状态里也是它", main.flags.get_value(PlayerName.FLAG), "Bob")
	# 老存档没有昵称：读回来用默认名
	main.flags.unset_value(PlayerName.FLAG)
	main.save_game(TEST_SLOT)
	main.new_game(&"", &"", "林小满")
	main.load_game(TEST_SLOT)
	h.check("老存档读回默认名", PlayerName.current, PlayerName.DEFAULT)
	SaveStore.delete(TEST_SLOT)
	main.skip_opening = false
	main.queue_free()


static func test_panel_layout(h: TestHarness) -> void:
	var panel := NameEntryPanel.new()
	panel.setup()
	panel.open()
	var view := Vector2(320, 180)
	var screen := Rect2(Vector2.ZERO, view)
	h.check("确定按钮在画面内", screen.encloses(panel.confirm_rect()), true)
	h.check("返回按钮在画面内", screen.encloses(panel.cancel_rect()), true)
	h.check("两个按钮不重叠", panel.confirm_rect().intersects(panel.cancel_rect()), false)
	h.check("开着时提示规则", panel.message(), NameEntryPanel.HINT)
	var got := [""]
	panel.confirmed.connect(func(value: String) -> void: got[0] = value)
	panel.set_text("Tom  Lee")
	h.check("回车确认", panel.handle_key(KEY_ENTER), true)
	h.check("确认发出规整后的名字", got[0], "Tom Lee")
	h.check("确认后收起", panel.is_open(), false)
	panel.free()

	# IF 面板 then 块：最长昵称也只折两行（放不下就缩字号）
	var if_panel := IfPanel.new()
	if_panel.setup()
	if_panel.open("", "来找一二三四五六七八帮忙", "猫不见了")
	var then_label: Label = if_panel._then_nodes["label"]
	h.check("长昵称的 then 块不超过两行", then_label.get_line_count() <= 2, true)
	if_panel.open("", "来找无名帮忙", "猫不见了")
	h.check("短名字保持原字号", then_label.get_theme_font_size("font_size"), IfPanel.BLOCK_LABEL_SIZE)
	if_panel.free()


static func _event_text(event_id: StringName) -> String:
	var raw := FileAccess.get_file_as_string("res://data/events/%s.json" % event_id)
	var strings: Array[String] = []
	_collect_strings(DataLoader.fill_player_name(JSON.parse_string(raw)), strings)
	return "\n".join(strings)


static func _collect_strings(value: Variant, out: Array[String]) -> void:
	if value is String:
		out.append(value)
	elif value is Array:
		for item: Variant in value:
			_collect_strings(item, out)
	elif value is Dictionary:
		for key: Variant in value:
			_collect_strings(value[key], out)
