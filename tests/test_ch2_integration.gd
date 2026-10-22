extends RefCounted


class CheckpointMain extends Node2D:
	var saves := 0
	var stage_overlay: StageOverlay

	func save_game() -> bool:
		saves += 1
		return true


static func run(harness: TestHarness) -> void:
	harness.section("第二章整合")
	_test_events_and_maps(harness)
	_test_assets(harness)
	await _test_save_and_caption(harness)


static func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _test_events_and_maps(harness: TestHarness) -> void:
	for event_id: String in ["ch2_flagpole", "ch2_notice", "ch2_sandbox",
			"ch2_sculpture", "ch2_swing", "gatehouse_door"]:
		var raw := _json("res://data/events/%s.json" % event_id)
		var event := StoryEvent.from_dictionary(raw)
		harness.check(event_id + " 剧情 id", str(event.id), event_id)
		harness.check(event_id + " 剧情校验", event.validate(), [])
		harness.check(event_id + " 入口可达", event.entry_node() != null, true)
	var gate := _json("res://data/maps/school_gate.json")
	var yard := _json("res://data/maps/school_yard.json")
	for map_data: Dictionary in [gate, yard]:
		var definition := MapDef.from_dictionary(map_data)
		harness.check(str(definition.id) + " 地图校验", definition.validate(), [])
	var found: Array[String] = []
	for map_data: Dictionary in [gate, yard]:
		for actor: Dictionary in map_data.get("actors", []):
			for action: Dictionary in actor.get("actions", []):
				var event_id := str(action.get("event", ""))
				if event_id in ["ch2_flagpole", "ch2_notice", "ch2_sandbox",
						"ch2_sculpture", "ch2_swing"]:
					found.append(event_id)
					var event := StoryEvent.from_dictionary(_json(
						"res://data/events/%s.json" % event_id))
					harness.check(actor["id"] + " 交互接到有效剧情",
						event.entry_node() != null, true)
					if event_id == "ch2_swing":
						harness.check("秋千事件只触发一次", action.get("once", false), true)
	found.sort()
	harness.check("五处新增交互均可达且不重复", found,
		["ch2_flagpole", "ch2_notice", "ch2_sandbox", "ch2_sculpture", "ch2_swing"])
	var door := StoryEvent.from_dictionary(_json("res://data/events/gatehouse_door.json"))
	var exits := 0
	for step: StageStep in door.entry_node().stage:
		if step.kind == &"goto":
			exits += 1
			harness.check("门卫室出口接学校大门", step.text("map"), str(gate["id"]))
			harness.check("门卫室出口出生点存在", gate["spawns"].has(step.text("spawn")), true)
			if gate["spawns"].has(step.text("spawn")):
				var position: Array = gate["spawns"][step.text("spawn")]
				harness.check("门卫室出口落点可站立", WalkGrid.is_free(
					MapDef.from_dictionary(gate), Vector2(position[0], position[1])), true)
	harness.check("门卫室有且仅有一个出口演出", exits, 1)
	var sandbox := StoryEvent.from_dictionary(_json("res://data/events/ch2_sandbox.json"))
	harness.check("调查沙坑获得学生证", sandbox.entry_node().effects.get("item/student_id"), 1)
	var swing := StoryEvent.from_dictionary(_json("res://data/events/ch2_swing.json"))
	harness.check("秋千先建立保存点", swing.entry_node().stage[0].kind, &"save")
	var meet := StoryEvent.from_dictionary(_json("res://data/events/meet_b.json"))
	var alley_entries := 0
	var new_caption := false
	for node: StoryNode in meet.nodes:
		for step: StageStep in node.stage:
			if step.kind == &"goto" and step.text("map") == "dead_alley":
				alley_entries += 1
			if step.kind == &"caption" and step.flag("wait_click") and step.has("out"):
				new_caption = true
	harness.check("保留第二章直接进入死巷", alley_entries, 1)
	harness.check("第二章新字幕请求点击后收起", new_caption, true)


static func _test_assets(harness: TestHarness) -> void:
	var paths: Array[String] = ["res://art/item/student_id_half.png"]
	for pose: String in ["down", "side", "up"]:
		for frame: int in range(1, 5):
			paths.append("res://art/npc/c/%s%d.png" % [pose, frame])
	for path: String in paths:
		harness.check(path + " 原图存在", FileAccess.file_exists(path), true)
		harness.check(path + " 导入配置存在", FileAccess.file_exists(path + ".import"), true)
		if FileAccess.file_exists(path):
			var image := Image.new()
			var result := image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
			harness.check(path + " PNG 可以解码", result == OK and not image.is_empty(), true)


static func _finish_caption(cutscene: Cutscene, step: StageStep, finished: Array[bool]) -> void:
	await cutscene._perform(step)
	finished[0] = true


static func _test_save_and_caption(harness: TestHarness) -> void:
	var observed_main := CheckpointMain.new()
	observed_main.stage_overlay = StageOverlay.new()
	harness.root.add_child(observed_main)
	observed_main.add_child(observed_main.stage_overlay)
	var cutscene := Cutscene.new()
	cutscene.setup(observed_main)
	var save := StageStep.from_dictionary({"do": "save"})
	harness.check("save 是合法的无参数指令", save.validate(), [])
	await cutscene._perform(save)
	harness.check("正常演出调用一次当前槽位保存", observed_main.saves, 1)
	await cutscene._replay(save)
	harness.check("补演保存点不会覆盖存档", observed_main.saves, 1)
	var resume_steps: Array[StageStep] = [save, save]
	await cutscene.run(resume_steps, 1)
	harness.check("续演只执行尚未演出的保存指令", observed_main.saves, 2)
	cutscene.setup(null)
	await cutscene._apply(save)
	harness.check("没有主场景时不尝试保存", observed_main.saves, 2)
	cutscene.setup(observed_main)
	for should_hide: bool in [true, false]:
		var payload := {"do": "caption", "lines": [{"text": "等待点击"}],
			"fade": 0, "wait_click": true}
		if should_hide:
			payload["out"] = 0
		var finished: Array[bool] = [false]
		_finish_caption(cutscene, StageStep.from_dictionary(payload), finished)
		harness.check("字幕点击前仍在等待", cutscene.is_waiting_click(), true)
		harness.check("字幕点击前没有继续演出", finished[0], false)
		harness.check("字幕点击前可见", observed_main.stage_overlay.caption_lines(), 1)
		harness.check("字幕点击被消费", cutscene.consume_click(), true)
		await harness.root.get_tree().process_frame
		harness.check("字幕点击后演出继续", finished[0], true)
		harness.check("只有指定 out 的字幕点击后收起",
			observed_main.stage_overlay.caption_lines(), 0 if should_hide else 1)
	var replay_caption := StageStep.from_dictionary({"do": "caption",
		"lines": [{"text": "补演字幕"}], "fade": 0, "wait_click": true, "out": 0})
	await cutscene._replay(replay_caption)
	harness.check("补演字幕不会等待玩家点击", cutscene.is_waiting_click(), false)
	harness.check("补演字幕仍恢复画面", observed_main.stage_overlay.caption_lines(), 1)
	await cutscene._perform(StageStep.from_dictionary({"do": "caption",
		"lines": [{"text": "定时字幕"}], "fade": 0, "hold": 0, "out": 0}))
	harness.check("原有定时字幕仍自动收起", observed_main.stage_overlay.caption_lines(), 0)
	observed_main.free()
