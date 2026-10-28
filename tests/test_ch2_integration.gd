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
	await _test_bugfixes(harness)
	await _test_save_and_caption(harness)


static func _test_bugfixes(h: TestHarness) -> void:
	var main := h.new_main()
	main.cutscene.instant = true
	main.enter_map(&"school_gate", &"near_classroom")
	main.flags.set_value(&"ch2/diary_read", true)
	main.flags.set_value(&"ch2/teamed_c", true)
	ItemTable.add(main.flags, &"charm")
	h.check("追逐可实际启动", main.chase_session.begin(), true)
	var mist: CharacterBody2D = main.chase_session._mist
	h.check("追逐猫是独立物理实体", mist is CharacterBody2D, true)
	if mist != null:
		var mist_sprite := mist.get_node("Visual") as Sprite2D
		h.check("追逐猫视觉贴图已加载", mist_sprite != null and mist_sprite.texture != null, true)
		h.check("追逐猫碰撞体只检测场景障碍", mist.collision_layer, 0)
		h.check("追逐猫碰撞体检测场景墙体", mist.collision_mask, 1)
		h.check("追逐猫从可站立位置开始", WalkGrid.is_free(
		main.current_map, mist.global_position), true)
		h.check("追逐猫是独立追兵类型", mist is Ch2ChasePursuer, true)
		var pursuer := mist as Ch2ChasePursuer
		var classroom_door := Rect2()
		for portal: MapDef.Portal in main.current_map.portals:
			if portal.id == &"to_classroom":
				classroom_door = portal.rect
		h.check("黑猫在教学楼门口左侧的地图边缘出现",
			mist.global_position.x < classroom_door.position.x and mist.global_position.x <= 16.0, true)
		h.check("黑猫与主角出教学楼处同一高度带",
			absf(mist.global_position.y - main.player.global_position.y) <= 12.0, true)
		h.check("黑猫出现时先淡入不移动", pursuer.is_emerging() and mist.modulate.a < 0.05, true)
		h.check("开场保护期内贴身也不触发追上", main.chase_session._mist_caught_player(), false)
		# 绕障：从喷泉正上方追到正下方，路线必须绕开喷泉，长度明显大于直线。
		var above := Vector2(210, 70)
		var below := Vector2(210, 170)
		var around := pursuer.find_path(above, below)
		var around_length := 0.0
		var crosses_fountain := false
		for index in range(1, around.size()):
			around_length += around[index - 1].distance_to(around[index])
		for point in around:
			crosses_fountain = crosses_fountain or not WalkGrid.is_free(main.current_map, point)
		h.check("追兵路线绕开喷泉", not around.is_empty() and not crosses_fountain, true)
		h.check("追兵绕障路程大于直线", around_length > above.distance_to(below) + 60.0, true)
		h.check("喷泉挡住追兵直线视线", pursuer.has_clear_line(above, below), false)
		h.check("脚底框相贴才算追上", pursuer.is_touching(main.player), false)
		var screen_height: float = mist_sprite.texture.get_height() * mist_sprite.scale.y \
			* mist.scale.y * main.camera.zoom.y
		var player_height: float = Player.DISPLAY_HEIGHT * main.player.scale.y * main.camera.zoom.y
		h.check("追逐猫不超过主角两倍高", screen_height <= player_height * 2.0, true)
		h.check("追逐猫脚底贴着追踪路径",
			mist_sprite.offset.y + mist_sprite.texture.get_height() * 0.5, 0.0)
		var chase_start: Vector2 = main.player.global_position
		main.chase_overlay._set_freeze_reason(ChaseOverlay.FREEZE_FOCUS, false)
		main.chase_session._update_mist_hold()
		pursuer._emerge_left = 0.0
		mist.modulate.a = 1.0
		var mist_start: Vector2 = mist.global_position
		var physics_dt := 1.0 / float(Engine.physics_ticks_per_second)
		# physics_frame 在节点物理回调之前发出，等两次才确保跑过一帧。
		await h.root.get_tree().physics_frame
		await h.root.get_tree().physics_frame
		var first_step: float = mist.global_position.distance_to(mist_start)
		h.check("追逐实体按物理帧连续移动 %.2f" % first_step,
			first_step > 0.0 and first_step <= pursuer.speed() * physics_dt * 2.0 + 0.01, true)
		for _frame: int in 7:
			await h.root.get_tree().physics_frame
		var mist_distance := mist.global_position.distance_to(mist_start)
		h.check("黑猫按独立常速追击 %.2f" % mist_distance,
			mist_distance > 0.0 and mist_distance <= pursuer.speed() * physics_dt * 9.0 + 0.5, true)
		h.check("黑猫比主角快，能追上", pursuer.speed() > main.player.movement_speed(), true)
		# 贴身 + 过保护期 → 追上；QTE 进行中原地不动。
		mist.global_position = chase_start + Vector2(-8.0, 0.0)
		h.check("脚底框相贴判定为追上", pursuer.is_touching(main.player), true)
		main.chase_session._elapsed = Ch2ChaseSession.CATCH_GRACE + 0.1
		h.check("过保护期贴身触发追上", main.chase_session._mist_caught_player(), true)
		main.chase_session.qte_pending = true
		main.chase_session._update_mist_hold()
		var held_at: Vector2 = mist.global_position
		main.player.global_position = chase_start + Vector2(40.0, 0.0)
		for _frame: int in 4:
			await h.root.get_tree().physics_frame
		h.check("QTE进行中追兵原地不动", mist.global_position, held_at)
		main.chase_session.qte_pending = false
		main.player.global_position = chase_start
		main.player.global_position = chase_start
		mist.global_position = main.player.global_position + Vector2.RIGHT * 40.0
		await main.chase_session.prepare_rescue_c()
		var c_actor: Node2D = main.cutscene._actor("c")
		h.check("救援C按碰撞推动方向生成", c_actor != null, true)
		if c_actor != null:
			h.check("救援C紧邻主角出场", c_actor.global_position,
				main.player.global_position - main.chase_session._rescue_direction \
				* Ch2ChaseSession.RESCUE_C_SPACING * main.player.scale.x)
			h.check("救援C淡入后可见", c_actor.modulate.a, 1.0)
			h.check("救援C没有碰撞体", c_actor.get_node_or_null("Body"), null)
			var facing: Vector2 = main.chase_session._rescue_direction
			h.check("救援方向只取东南西北",
				facing.is_equal_approx(Vector2.UP) or facing.is_equal_approx(Vector2.DOWN) \
				or facing.is_equal_approx(Vector2.LEFT) or facing.is_equal_approx(Vector2.RIGHT), true)
			h.check("猫在右侧时救援方向垂直于追击线", absf(facing.x), 0.0)
		main.cutscene.clear_actors()
		await _test_door_rescue(h, main)
	main.chase_session.cancel()
	var chase_event := DataLoader.load_event(&"ch2_diary", DataLoader.load_endings().ids())
	var q1 := _node(chase_event, &"run_q1")
	var q2 := _node(chase_event, &"run_q2")
	var arrival := _node(chase_event, &"arrive")
	var direct := _node(chase_event, &"library_direct")
	h.check("追逐首个接近点使用实际距离而非路线坐标", q1.stage[0].data.has("trigger_x"), false)
	h.check("第二次追逐可在门口交互前结束QTE", q2.next_id, &"arrive")
	h.check("第三次追上分流到C救援", arrival.next_when.get("next"), &"c_door_cover")
	h.check("未三次追上直接入馆", arrival.next_id, &"library_direct")
	var direct_has_c := false
	var direct_has_os := false
	for step: StageStep in direct.stage:
		direct_has_c = direct_has_c or (step.kind == &"npc" and step.text("id") == "c")
		if step.kind == &"say":
			var lines: Array = step.data.get("lines", [])
			direct_has_os = direct_has_os or (lines.size() == 1 \
				and str(lines[0].get("text", "")) == "他怎么能到得这么快，而且，他怎么知道我在这里")
	h.check("普通入馆节点带有C和OS台词", direct_has_c and direct_has_os, true)
	var rescue := _node(chase_event, &"c_door_cover")
	h.check("C救援按当前主角位置和推动方向出场",
		rescue.stage[0].kind, &"ch2_chase_rescue_appear")
	# 正式入馆演出，再不调查直接往返；恢复应与初次入馆完全一致。
	main.start_story(&"ch2_diary", &"library_enter")
	var original: Array = main.cutscene.snapshot_actors()
	h.check("正式入馆C在场", main.cutscene.actor_ids().has("c"), true)
	main.enter_map(&"school_gate", &"from_library")
	main.enter_map(&"library", &"from_school_gate")
	h.check("未调查直接往返后C仍在场", main.cutscene.snapshot_actors(), original)
	main.enter_map(&"school_gate", &"from_library")
	main.enter_map(&"library", &"from_school_gate")
	h.check("多次往返不重复生成C", main.cutscene.actor_ids(), ["c"])
	var saved_actors: Array = original.duplicate(true)
	saved_actors[0]["at"] = [225.0, 250.0]
	main.cutscene.restore_actors(saved_actors)
	h.check("入口补位不覆盖存档中的C位置", main.cutscene._actor("c").position, Vector2(225, 250))
	main.flags.set_value(&"ch2/left_library", true)
	main.enter_map(&"library", &"from_school_gate")
	h.check("逃离完成后不复活追兵C", main.cutscene.actor_ids(), [])
	# 普通物件、多部件与无切图物件都能完整放进对话框上方。
	var actor := MapDef.Actor.new()
	actor.rect = Rect2(50, 50, 10, 12)
	actor.sprite = "res://art/props/ch2_blackboard.png"
	var inter := MapDef.Interaction.new()
	inter.dialogue = Dialogue.from_array([{"text": "调查物件。"}])
	actor.interactions.append(inter)
	main.begin_interaction(actor)
	main.object_preview._process(0.0)
	h.check("普通调查自动显示物件近景", main.object_preview.content != null, true)
	var preview: Node2D = main.object_preview.content
	if preview != null:
		var area: Rect2 = preview.transform * main.object_preview.bounds
		h.check("近景按可用高度放大", area.size.y > actor.rect.size.y, true)
		h.check("近景完整位于对话框上方", area.end.y < main.dialogue.hold_top(), true)
		h.check("近景横向不出屏", area.position.x >= 0 and area.end.x <= main.get_viewport_rect().size.x, true)
	main.stage_overlay.show_image(actor.sprite, 0.0)
	main.object_preview._process(0.0)
	h.check("剧情专用道具图优先展示", preview.visible, false)
	h.check("专用道具图也不被对话框压住", main.stage_overlay._image.position.y + main.stage_overlay._image.size.y < main.dialogue.hold_top(), true)
	h.check("透明画布不会把物件压成小图", main.stage_overlay._image.texture.get_size().x < load(actor.sprite).get_width(), true)
	main.stage_overlay.hide_image(0.0)
	h.drain_dialogue(main.dialogue)
	h.check("调查结束自动收起近景", main.object_preview.content, null)
	actor.sprite = ""
	main.begin_interaction(actor)
	h.check("无独立切图时从背景裁取近景", main.object_preview.content != null, true)
	main.enter_map(&"school_gate", &"from_library")
	h.check("换图时清理物件近景", main.object_preview.content, null)
	main.queue_free()


## 图书馆门口窄道里第三次被追上：左右都被门洞墙挡住，C 仍须出场并推着主角冲出去，流程不卡。
static func _test_door_rescue(h: TestHarness, main: Variant) -> void:
	var session: Ch2ChaseSession = main.chase_session
	var door: Rect2 = session._door_area
	var at := Vector2(door.get_center().x, door.end.y - 4.0)
	main.player.global_position = at
	session._mist.global_position = at + Vector2(0.0, 18.0)
	var perpendicular := maxf(main.player.burst_clearance(Vector2.LEFT, 118.0),
		main.player.burst_clearance(Vector2.RIGHT, 118.0))
	h.check("门口窄道两侧冲刺距离不足 %.1f" % perpendicular,
		perpendicular < Ch2ChaseSession.RESCUE_MIN_BURST, true)
	session._catch_count = 2
	session._arrived = true
	session._rescue_pending = true
	await session.prepare_rescue_c()
	var c_actor: Node2D = main.cutscene._actor("c")
	h.check("门口窄道C仍然出场", c_actor != null, true)
	h.check("门口窄道改选空旷方向冲刺",
		session._rescue_distance >= Ch2ChaseSession.RESCUE_MIN_BURST, true)
	var before: Vector2 = main.player.global_position
	var done := [false]
	var retreat := func() -> void:
		await session.retreat_mist(0.05)
		done[0] = true
	retreat.call()
	h.check("门口已到达时救援冲刺仍放行主角物理", session.can_move_player(), true)
	for _frame: int in 120:
		if done[0]:
			break
		await h.root.get_tree().physics_frame
	h.check("门口救援冲刺结束不卡流程", done[0], true)
	h.check("门口救援主角被推离门口",
		main.player.global_position.distance_to(before) > 4.0, true)
	if c_actor != null and is_instance_valid(c_actor):
		h.check("门口救援C贴着主角停下",
			c_actor.global_position.distance_to(main.player.global_position) <= \
			Ch2ChaseSession.RESCUE_C_SPACING * main.player.scale.x + 0.5, true)
	h.check("救援后主角输入锁释放", main.player.chase_input_locked, false)
	main.cutscene.clear_actors()


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
		harness.check("缺少三项条件时教学楼入口拦截交互", main.story.event_id, &"")
		harness.check("门剧情开始时仍在校门", main.current_map.id, &"school_gate")
		var all_missing_hint: String = main._teaching_entry_hint(classroom_portal)
		harness.check("缺项提示暗示三项尚未齐备",
			all_missing_hint.contains("等的人") and all_missing_hint.contains("要紧的东西") \
			and all_missing_hint.contains("约定"), true)
		ItemTable.add(main.flags, &"key", 1)
		main._travel_through_portal(classroom_portal.rect.get_center())
		harness.check("仅有钥匙时地图入口仍留在校门", main.current_map.id, &"school_gate")
		main.use_portal_at(classroom_portal.rect.get_center())
		harness.check("仅有钥匙时直接传送仍留在校门", main.current_map.id, &"school_gate")
		var no_c_hint: String = main._teaching_entry_hint(classroom_portal)
		harness.check("缺少C时提示随未达条件变化",
			no_c_hint.contains("等的人") and not no_c_hint.contains("要紧的东西"), true)
		main.flags.set_value(&"ch2/rescued_c", true)
		var no_ready_hint: String = main._teaching_entry_hint(classroom_portal)
		harness.check("未选择准备好时出现对应暗示",
			no_ready_hint.contains("约定") and not no_ready_hint.contains("等的人"), true)
		main.flags.set_value(&"ch2/c_at_school_gate", true)
		main.flags.set_value(&"item/key", 0)
		var no_key_hint: String = main._teaching_entry_hint(classroom_portal)
		harness.check("缺少钥匙时出现对应暗示",
			no_key_hint.contains("要紧的东西") and not no_key_hint.contains("约定"), true)
		main.flags.set_value(&"item/key", 1)
		harness.check("三项齐备后可启动教学楼门剧情",
			main._teaching_entry_hint(classroom_portal), "")
		harness.check("三项齐备后教学楼目标有效",
			main.portal_destination(classroom_portal.rect.get_center()),
			[&"classroom", classroom_portal.target_spawn])
		main.interact()
		harness.check("三项齐备后进入钥匙门剧情", main.story.event_id, &"ch2_class_door")
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
	harness.check("校门通知演出使用新版规则公告栏",
		notice_image.text("path"), "res://art/props/ch2_notice_board.png")
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
	var ready_check := _node(c_wait, &"ready_check")
	harness.check("准备选择先检查C所在位置",
		wait_node.choices[0].next_id, &"ready_check")
	harness.check("操场首次准备仍进入出发节点",
		ready_check.resolved_next(wait_flags), &"depart")
	var arrived_flags := WorldState.new()
	arrived_flags.set_value(&"ch2/c_at_school_gate", true)
	harness.check("校门再次准备进入后续节点",
		ready_check.resolved_next(arrived_flags), &"departed")
	var depart := _node(c_wait, &"depart")
	harness.check("首次准备记录C已到校门", depart.effects.get(&"ch2/c_at_school_gate"), true)
	harness.check("取消走廊连接的旧出发台词不再执行", depart.stage[0].kind, &"fade")
	var depart_goto: StageStep = null
	for step: StageStep in depart.stage:
		if step.kind == &"goto":
			depart_goto = step
	harness.check("C出发直达校门地图", depart_goto != null, true)
	if depart_goto != null:
		harness.check("C出发不经过走廊", depart_goto.text("map"), "school_gate")
		harness.check("C出发落到校门操场侧", depart_goto.text("spawn"), "near_yard")
	var arrived_node := _node(c_wait, &"departed")
	var arrived_gotos := 0
	for step: StageStep in arrived_node.stage:
		if step.kind == &"goto":
			arrived_gotos += 1
	harness.check("校门再次准备不会循环传送", arrived_gotos, 0)
	harness.check("校门准备后恢复地图控制",
		arrived_node.stage[0].kind, &"focus")
	harness.check("校门后续仍由教学楼门事件检查钥匙",
		_node(StoryEvent.from_dictionary(_json("res://data/events/ch2_class_door.json")),
			&"key_check").resolved_next(arrived_flags), &"door_locked")
	harness.check("教学楼门事件保留开门音效",
		_node(StoryEvent.from_dictionary(_json("res://data/events/ch2_class_door.json")), &"class_enter").stage[0].text("path"),
		"res://audio/sfx/door_open.wav")
	harness.check("旧走廊演出指令已移除",
		StageStep.KINDS.has(&"ch2_enter_teaching_hall"), false)
	var diary_event := StoryEvent.from_dictionary(_json("res://data/events/ch2_diary.json"))
	harness.check("QTE失败仍沿追逐流程进入后续判定",
		_node(diary_event, &"run_q1").next_id, &"run_q2")
	harness.check("追逐失败不再直接进入死亡CG节点",
		_node(diary_event, &"arrive").next_id, &"library_direct")
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
