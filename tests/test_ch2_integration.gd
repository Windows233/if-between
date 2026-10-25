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
			"ch2_sculpture", "ch2_swing", "ch2_swing_repeat",
			"ch2_register",
			"ch2_class_door", "ch2_blackboard", "ch2_diary",
			"ch2_c_wait", "ch2_gate_entry",
			"ch2_yard_entry", "gatehouse_door"]:
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
	var yard_exit: Dictionary = {}
	for portal: Dictionary in yard.get("portals", []):
		if portal.get("to", "") == "school_gate":
			yard_exit = portal
	harness.check("操场存在回校门出口", not yard_exit.is_empty(), true)
	harness.check("操场出口使用校门 near_yard", yard_exit.get("spawn", ""), "near_yard")
	harness.check("回校门出生点存在", gate.get("spawns", {}).has("near_yard"), true)
	if gate.get("spawns", {}).has("near_yard"):
		var yard_return: Array = gate["spawns"]["near_yard"]
		harness.check("回校门落点可站立", WalkGrid.is_free(
			MapDef.from_dictionary(gate), Vector2(yard_return[0], yard_return[1])), true)
	var main := harness.new_main()
	main.enter_map(&"school_gate", &"near_yard")
	var classroom_portal: MapDef.Portal = null
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.id == &"to_classroom":
			classroom_portal = portal
			break
	harness.check("校门教学楼入口存在", classroom_portal != null, true)
	if classroom_portal != null:
		var gate_definition := MapDef.from_dictionary(gate)
		var reachable_stands: Array[Vector2] = []
		for point: Vector2 in WalkGrid.reachable(gate_definition,
				gate_definition.spawn_point(&"near_yard")):
			if classroom_portal.rect.has_point(point) and WalkGrid.has_landing_room(gate_definition, point):
				reachable_stands.append(point)
		harness.check("校门教学楼入口从操场侧可走到", not reachable_stands.is_empty(), true)
		main.player.global_position = classroom_portal.rect.get_center()
		main.interact()
		harness.check("教学楼门触发钥匙检查剧情", main.story.event_id, &"ch2_class_door")
		harness.check("门剧情开始时仍在校门", main.current_map.id, &"school_gate")
	main.queue_free()
	var classroom_door := StoryEvent.from_dictionary(
		_json("res://data/events/ch2_class_door.json"))
	var key_check := _node(classroom_door, &"key_check")
	var no_key := WorldState.new()
	harness.check("无钥匙时教学楼门保持关闭",
		key_check.resolved_next(no_key), &"door_locked")
	var has_key := WorldState.new()
	ItemTable.add(has_key, &"key", 1)
	harness.check("持钥匙时教学楼门进入教室",
		key_check.resolved_next(has_key), &"class_enter")
	var classroom := MapDef.from_dictionary(_json("res://data/maps/classroom.json"))
	for binding: Array in [[&"blackboard", &"ch2_blackboard"], [&"diary_desk", &"ch2_diary"]]:
		var actor: MapDef.Actor = null
		for candidate: MapDef.Actor in classroom.actors:
			if candidate.id == binding[0]:
				actor = candidate
				break
		harness.check(str(binding[0]) + " 教室物件存在", actor != null, true)
		if actor != null:
			harness.check(str(binding[0]) + " 剧情动作已绑定", actor.interactions.size(), 1)
			harness.check(str(binding[0]) + " 绑定正确剧情",
				actor.interactions[0].event_id, binding[1])
	var swing_actor: Dictionary = {}
	for actor: Dictionary in yard.get("actors", []):
		if actor.get("id", "") == "swing":
			swing_actor = actor
	harness.check("秋千交互框使用R2尺寸", swing_actor.get("rect", []), [194.0, 38.0, 56.0, 38.0])
	var found: Array[String] = []
	var swing_action_event_id := ""
	for map_data: Dictionary in [gate, yard]:
		for actor: Dictionary in map_data.get("actors", []):
			for action: Dictionary in actor.get("actions", []):
				var event_id := str(action.get("event", ""))
				if actor.get("id", "") == "swing":
					swing_action_event_id = event_id
				if event_id in ["ch2_flagpole", "ch2_notice", "ch2_sandbox",
						"ch2_sculpture", "ch2_swing"]:
					found.append(event_id)
					var event := StoryEvent.from_dictionary(_json(
						"res://data/events/%s.json" % event_id))
					harness.check(actor["id"] + " 交互接到有效剧情",
						event.entry_node() != null, true)
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
	var sandbox_flags := WorldState.new()
	harness.check("首次沙坑调查进入首次获得",
		sandbox.entry_node().resolved_next(sandbox_flags), &"sand_gain")
	ItemTable.add(sandbox_flags, &"student_id", 1)
	harness.check("持有学生证后进入重复调查",
		sandbox.entry_node().resolved_next(sandbox_flags), &"sand_again")
	harness.check("展示学生证后才登记数量",
		sandbox.node(&"sand_reward").effects.get(&"item/student_id"), 1)
	var notice_event := StoryEvent.from_dictionary(_json("res://data/events/ch2_notice.json"))
	var notice_read := _node(notice_event, &"read")
	var notice_image := notice_read.stage[1]
	harness.check("校门通知演出使用空白公告栏",
		notice_image.text("path"), "res://art/props/ch2_notice_board_blank.png")
	harness.check("公告栏出现不额外等待点击", notice_image.flag("wait_click"), false)
	harness.check("公告阅读期间公告栏保持显示", notice_image.flag("hide"), false)
	var notices := _node(notice_event, &"notices")
	harness.check("公告文字展示后收起近景",
		notices.stage.back().kind, &"image_hide")
	var rescue_event := StoryEvent.from_dictionary(_json("res://data/events/ch2_swing.json"))
	harness.check("C救援入口使用当前节点名", rescue_event.entry_node().id, &"rescue_entry")
	harness.check("救援先建立独立检查点", rescue_event.entry_node().stage[0].kind, &"ch2_checkpoint_save")
	harness.check("救援检查点标识", rescue_event.entry_node().stage[0].text("checkpoint"), "rescue")
	var swing_rescue_steps := 0
	if not swing_action_event_id.is_empty():
		var swing_event := StoryEvent.from_dictionary(_json(
			"res://data/events/%s.json" % swing_action_event_id))
		for node: StoryNode in swing_event.nodes:
			for step: StageStep in node.stage:
				if step.kind == &"rescue":
					swing_rescue_steps += 1
	harness.check("秋千交互触发一次C救援小游戏", swing_rescue_steps, 1)
	var c_wait := StoryEvent.from_dictionary(_json("res://data/events/ch2_c_wait.json"))
	var wait_node := _node(c_wait, &"wait")
	var wait_flags := WorldState.new()
	harness.check("准备出发不依赖走廊配置", wait_node.choices[0].is_available(wait_flags), true)
	harness.check("C始终允许玩家继续探索", wait_node.choices[1].is_available(wait_flags), true)
	var depart := _node(c_wait, &"depart")
	var depart_goto: StageStep = null
	for step: StageStep in depart.stage:
		if step.kind == &"goto":
			depart_goto = step
	harness.check("C出发直达校门地图", depart_goto != null, true)
	if depart_goto != null:
		harness.check("C出发不经过走廊", depart_goto.text("map"), "school_gate")
		harness.check("C出发落到校门操场侧", depart_goto.text("spawn"), "near_yard")
	harness.check("教学楼门事件保留开门音效",
		_node(StoryEvent.from_dictionary(_json("res://data/events/ch2_class_door.json")), &"class_enter").stage[0].text("path"),
		"res://audio/sfx/door_open.wav")
	harness.check("旧走廊演出指令已移除",
		StageStep.KINDS.has(&"ch2_enter_teaching_hall"), false)
	var diary_event := StoryEvent.from_dictionary(_json("res://data/events/ch2_diary.json"))
	var caught_node := _node(diary_event, &"chase_caught")
	harness.check("QTE失败保留追逐重试类型",
		caught_node.effects.get(&"ch2/end5_retry_kind"), "chase")
	harness.check("QTE失败的重试目标独立于路线重试",
		_choice_ids(_node(diary_event, &"end5_chase_outcome")),
		[&"retry_chase", &"return_title"])
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
	var paths: Array[String] = [
		"res://art/item/student_id_half.png",
		"res://art/props/ch2_notice_board_blank.png",
		"res://art/props/ch2_diary_blank.png",
		"res://art/props/ch2_blackboard.png",
		"res://art/props/ch2_mirror.png",
		"res://art/props/ch2_register.png",
		"res://art/props/ch2_sculpture_inscription.png",
		"res://art/props/ch2_teaching_notice_board.png",
		"res://art/cg/ch2_rescue_injury.png",
		"res://art/cg/ch2_chase_failure.png",
		"res://art/npc/shadow_cat/chase_mist_right.png",
	]
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


static func _node(event: StoryEvent, id: StringName) -> StoryNode:
	for node: StoryNode in event.nodes:
		if node.id == id:
			return node
	return StoryNode.new()


static func _choice_ids(node: StoryNode) -> Array[StringName]:
	var ids: Array[StringName] = []
	for choice: StoryChoice in node.choices:
		ids.append(choice.id)
	return ids
