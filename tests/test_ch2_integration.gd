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
	await preload("res://tests/test_diary_followups.gd").run(harness)
	await _test_bugfixes(harness)
	await preload("res://tests/test_cutscene_actor_lifetime.gd").run(harness)
	await preload("res://tests/test_chase_motion.gd").run(harness)
	await preload("res://tests/test_library_flow_revision.gd").run(harness)
	await _test_fairy_tale_and_shelf_animation(harness)
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
		var cat_lift_min := INF
		var cat_lift_max := -INF
		var cat_scale_min := INF
		var cat_scale_max := -INF
		var frames_seen := {}
		for _pose: int in 12:
			main.chase_session._animate_mist(1.0 / main.chase_session.RUN_FPS, Vector2.RIGHT)
			cat_lift_min = minf(cat_lift_min, mist_sprite.position.y)
			cat_lift_max = maxf(cat_lift_max, mist_sprite.position.y)
			cat_scale_min = minf(cat_scale_min, mist_sprite.scale.y)
			cat_scale_max = maxf(cat_scale_max, mist_sprite.scale.y)
			frames_seen[mist_sprite.texture.get_instance_id()] = true
		h.check("黑猫跃起高度受控", cat_lift_max - cat_lift_min <= 6.0, true)
		h.check("黑猫完整覆盖蓄力起跳腾空落地", frames_seen.size(), 4)
		h.check("蓄力阶段实际停步", Ch2ChaseSession.hop_rate(0.1), 0.0)
		h.check("腾空阶段向前跃出", Ch2ChaseSession.hop_rate(0.5) > 1.0, true)
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN]:
			main.chase_session._animate_mist(0.01, direction)
			h.check("上下方向选择对应动画", main.chase_session._vertical_frames[
				"up" if direction.y < 0 else "down"].has(mist_sprite.texture), true)
		main.chase_session._animate_mist(0.0, Vector2.RIGHT)
		var smoke_time: float = mist_sprite.material.get_shader_parameter("smoke_time")
		h.check("黑猫雾气时间连续推进", smoke_time > 0.5, true)
		h.check("黑猫跑动保持身体比例", is_equal_approx(cat_scale_max, cat_scale_min), true)
		h.check("追逐猫从可站立位置开始", WalkGrid.is_free(
		main.current_map, mist.global_position), true)
		var start_distance: float = main.player.global_position.distance_to(mist.global_position)
		h.check("黑猫从图书馆门左侧开场", mist.global_position.x < main.chase_session._door_area.position.x, true)
		h.check("黑猫开场不贴近主角", start_distance > 180.0, true)
		h.check("初始追逐距离计入喷泉绕行",
			main.chase_session._mist_gap() >= start_distance, true)
		var screen_height: float = mist_sprite.texture.get_height() * mist_sprite.scale.y \
			* mist.scale.y * main.camera.zoom.y
		var player_height: float = Player.DISPLAY_HEIGHT * main.player.scale.y * main.camera.zoom.y
		h.check("追逐猫不超过主角两倍高", screen_height <= player_height * 2.0, true)
		h.check("追逐猫脚底贴着追踪路径",
			mist_sprite.offset.y + mist_sprite.texture.get_height() * 0.5, 0.0)
		var chase_start: Vector2 = main.player.global_position
		var mist_start: Vector2 = mist.global_position
		main.player.global_position = chase_start + Vector2(20.0, 0.0)
		await h.root.get_tree().physics_frame
		var first_step: float = mist.global_position.distance_to(mist_start)
		h.check("追逐实体按物理帧连续移动 %.2f" % first_step, first_step < 3.0, true)
		for _frame: int in 8:
			await h.root.get_tree().physics_frame
		var mist_distance := mist.global_position.distance_to(mist_start)
		h.check("黑猫停步后沿路径跃出 %.2f" % mist_distance,
			mist_distance > 0.0 and mist_distance <= Ch2ChaseSession.MIST_CHASE_SPEED \
			* main.player.scale.x * 0.25 + 0.5, true)
		h.check("冲刺加速时主角能与黑猫拉开",
			main.player.global_position.distance_to(mist.global_position) > mist_distance, true)
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
		main.cutscene.clear_actors()
	main.chase_session.cancel()
	h.check("救援测试可重新启动追逐", main.chase_session.begin(), true)
	main.chase_session._rescue_pending = true
	var rescue_arrived: bool = await main.chase_session.wait_for_arrival()
	h.check("救援分支不等待玩家抵达门口", rescue_arrived, false)
	h.check("救援分支写入救援状态", main.flags.get_value(&"ch2/chase_rescued"), true)
	h.check("进入救援剧情前已结束追逐会话", main.chase_session.active, false)
	h.check("进入救援剧情前已清除门口等待", main.chase_session._awaiting_door, false)
	main.chase_session.cancel()
	var chase_event := DataLoader.load_event(&"ch2_diary", DataLoader.load_endings().ids())
	var q1 := _node(chase_event, &"run_q1")
	var q2 := _node(chase_event, &"run_q2")
	var arrival := _node(chase_event, &"arrival_result")
	var direct := _node(chase_event, &"library_direct")
	h.check("追逐首个接近点使用实际距离而非路线坐标", q1.stage[0].data.has("trigger_x"), false)
	h.check("第二次追逐可在门口交互前结束QTE", q2.next_id, &"arrive")
	h.check("累计第三次失败分流到C救援", arrival.next_when.get("next"), &"c_door_cover")
	h.check("未触发救场时直接入馆", arrival.next_id, &"library_direct")
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
	h.check("C救援对白后进入图书馆入场演出", rescue.next_id, &"library_enter")
	var library_enter := _node(chase_event, &"library_enter")
	var library_state := _node(chase_event, &"library_state")
	var fade_to_black := -1
	var library_goto := -1
	var fade_to_clear := -1
	for index: int in library_enter.stage.size():
		var step: StageStep = library_enter.stage[index]
		if step.kind == &"fade" and step.text("to") == "black":
			fade_to_black = index
		elif step.kind == &"goto" and step.text("map") == "library":
			library_goto = index
	if library_state != null and not library_state.stage.is_empty():
		var reveal := library_state.stage[0]
		if reveal.kind == &"fade" and reveal.text("to") == "clear":
			fade_to_clear = 0
	h.check("救援入馆先黑屏再切到图书馆并揭幕",
		fade_to_black >= 0 and fade_to_black < library_goto \
		and library_goto >= 0 and fade_to_clear >= 0, true)
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
	h.check("无独立贴图时不从地图背景伪造近景", main.object_preview.content, null)
	main.enter_map(&"school_gate", &"from_library")
	h.check("换图时清理物件近景", main.object_preview.content, null)
	main.queue_free()


static func _test_fairy_tale_and_shelf_animation(h: TestHarness) -> void:
	var shelf_event := DataLoader.load_event(&"ch2_library_shelf")
	for node_id: StringName in [&"first", &"second"]:
		var node := shelf_event.node(node_id)
		var has_book_image := false
		if node != null:
			for step: StageStep in node.stage:
				has_book_image = has_book_image or step.kind in [&"image", &"image_hide"]
		h.check("童话书 %s 展示对应童话书页" % node_id,
			has_book_image, true)
	var cat_event := DataLoader.load_event(&"ch2_library_cat")
	var approach := cat_event.node(&"approach")
	var second_scene := cat_event.node(&"second_scene")
	var c_faces_rug := false
	var c_waits_at_entry := true
	if approach != null:
		for step: StageStep in approach.stage:
			if step.kind == &"npc_pose" and step.text("id") == "c" and not step.flag("flip"):
				c_faces_rug = true
	if second_scene != null:
		for step: StageStep in second_scene.stage:
			if step.kind in [&"npc", &"npc_move"] and step.text("id") == "c":
				c_waits_at_entry = false
	h.check("地毯场景中的C面向左", c_faces_rug, true)
	h.check("二次猫对话期间C留在入口", c_waits_at_entry, true)

	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	main.flags.set_value(&"ch2/library/shelf_fallen", true)
	main.refresh_scene()
	var barrier: MapDef.Actor = null
	for actor: MapDef.Actor in main.current_map.actors:
		if actor.id == &"escape_shelf_barrier":
			barrier = actor
			break
	h.check("撬棍倒架动画有正式物件承接", barrier != null and barrier.sprite_variants.has("fallen"), true)
	var animation_step := StageStep.from_dictionary({
		"do": "map_actor_animation",
		"actor": "escape_shelf_barrier",
		"path": "res://art/props/library_shelf_fall_sheet.png",
		"frames": 5,
		"columns": 5,
		"frame_time": 0.01,
		"final_variant": "fallen",
	})
	await main.cutscene._perform(animation_step)
	h.check("撬棍剧情实际播放倒架序列并切到fallen",
		barrier != null and barrier.sprite_variant == "fallen", true)
	var sprite := main.map_view._actor_variant_nodes.get(&"escape_shelf_barrier") as Sprite2D
	h.check("倒架动画结束后保留静态倒地贴图",
		sprite != null and sprite.texture != null \
			and barrier != null and barrier.sprite_variant == "fallen", true)
	if sprite != null and barrier != null:
		h.check("落地使用重绘俯视散书贴图", sprite.texture,
			preload("res://scenes/library_shelf_fall.gd").fallen_texture())
		h.check("倒地透视不靠旋转正面卡片", is_zero_approx(sprite.rotation), true)
		h.check("已取消触地扬尘", main.map_view._built.has_node("ShelfImpactDust"), false)
		h.check("无书架底图不再用临时地砖遮盖", main.map_view._built.has_node("ShelfFloor"), false)
		h.check("图书馆接入无书架底图", main.current_map.background,
			"res://art/map/library_no_shelves.png")
		h.check("拆层底图保留原画布像素尺寸以保持素材拖入比例",
			Image.load_from_file(main.current_map.background).get_size(),
			Image.load_from_file("res://art/map/library_no_cat.png").get_size())
		for original: MapDef.Actor in main.current_map.actors:
			if original.id == &"shelf_d":
				h.check("倒下的是指定的shelf_d书架", original.sprite_variant, "hidden")
				h.check("原书架碰撞同步移走", original.collision_rects().is_empty(), true)
		var bottom := -INF
		var bounds := sprite.get_rect()
		var original_rect := preload("res://scenes/library_shelf_fall.gd").source_rect(main.current_map)
		var configured := DataLoader.load_map(&"library")
		var expected := preload("res://scenes/library_shelf_fall.gd").target_rect(configured)
		h.check("倒地碰撞区域采用编辑器倒塌书架落点", barrier.rect, expected)
		var stage_positions := preload("res://scenes/library_shelf_fall.gd").positions(main.current_map)
		h.check("C位于阻隔上方", stage_positions["c"].y < expected.position.y, true)
		h.check("主角位于阻隔下方靠近门口", stage_positions["player"].y > expected.end.y, true)
		h.check("门口主角脚点合法", WalkGrid.is_free(main.current_map, stage_positions["player"]), true)
		var direct_blocked := false
		for i: int in range(1, 41):
			var sample: Vector2 = stage_positions["c"].lerp(stage_positions["player"], i / 40.0)
			direct_blocked = direct_blocked or not WalkGrid.is_free(main.current_map, sample)
		h.check("倒地书架阻挡C直线追上主角", direct_blocked, true)
		var around := WalkGrid.path_to(main.current_map, stage_positions["c"], stage_positions["player"])
		h.check("C只能沿合法路线绕过书架", not around.is_empty() and around[-1].distance_to(stage_positions["player"]) < 3.0, true)
		h.check("书架向左倒到原位置左侧", (sprite.transform * bounds.get_center()).x < original_rect.position.x, true)
		for corner: Vector2 in [bounds.position, bounds.end,
				Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.end.x, bounds.position.y)]:
			bottom = maxf(bottom, (sprite.transform * corner).y)
		var body := preload("res://scenes/library_shelf_fall.gd").FALLEN_BODY
		h.check("落地书架本体长边保持原高度", is_equal_approx(body.size.x * sprite.scale.x, original_rect.size.y), true)
		h.check("落地书架等比显示不拉扁", is_equal_approx(sprite.scale.x, sprite.scale.y), true)
		h.check("书架本体底边贴地，散书位于外围", is_equal_approx((sprite.transform * body.end).y, barrier.rect.end.y), true)
		var settled := sprite.transform
		main.refresh_scene()
		sprite = main.map_view._actor_variant_nodes.get(&"escape_shelf_barrier") as Sprite2D
		h.check("重建地图后倒架位置和角度保持一致", sprite.transform.is_equal_approx(settled), true)
		# 用户可以删除独立书架：没有原物件时不能再凭空生成一只倒架。
		for i: int in range(main.current_map.actors.size() - 1, -1, -1):
			if main.current_map.actors[i].id == &"shelf_d":
				main.current_map.actors.remove_at(i)
		main.refresh_scene()
		h.check("手动删除shelf_d书架后不凭空生成倒架", barrier.sprite_variant, "hidden")
		h.check("删除后不留下倒架碰撞", barrier.collision_rects().is_empty(), true)
	main.queue_free()


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
	var classroom_window := _node(StoryEvent.from_dictionary(
		_json("res://data/events/ch2_classroom_window.json")), &"throw")
	var throw_has_center_image := false
	var throw_has_coin_sound := false
	for step: StageStep in classroom_window.stage:
		throw_has_center_image = throw_has_center_image or step.kind == &"image"
		throw_has_coin_sound = throw_has_coin_sound or (step.kind == &"play_sound" \
			and step.text("path") == "res://audio/sfx/coin_throw.wav")
	harness.check("抛币演出不显示居中图片并播放抛币音效",
		not throw_has_center_image and throw_has_coin_sound, true)
	var window_main := harness.new_main()
	window_main.enter_map(&"classroom", &"from_gate", true)
	var window_actor := MapDef.Actor.new()
	window_actor.id = &"window"
	window_main.begin_interaction(window_actor)
	harness.check("当前窗户物件ID触发抛币剧情",
		window_main.story.event_id, &"ch2_classroom_window")
	window_main.story.cancel()
	window_main.flags.set_value(&"ch2/window_marker_active", true)
	window_main.refresh_scene()
	harness.check("窗户提示标记适配当前window物件ID",
		window_main.map_view._actor_markers.has(&"window"), true)
	window_main.queue_free()
	# 大地图的异界裂缝不能手动进：第二章只由第一章末尾剧情（meet_b）直接送进死巷。
	var overworld := DataLoader.load_map(&"overworld")
	var rift_ok := false
	for portal: MapDef.Portal in overworld.portals:
		if portal.id == &"rift":
			rift_ok = portal.is_locked() and portal.target_map == &""
	harness.check("大地图异界裂缝未开放，不能手动进入第二章", rift_ok, true)
	var swing_actor: Dictionary = {}
	for actor: Dictionary in yard.get("actors", []):
		if actor.get("id", "") == "swing":
			swing_actor = actor
	# 位置由策划在编辑器里调，只校验R2尺寸（坑#10：别钉死坐标）。
	harness.check("秋千交互框使用R2尺寸", swing_actor.get("rect", []).slice(2, 4), [56.0, 38.0])
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
	harness.check("旧校门状态再次准备也直接出发入楼",
		ready_check.resolved_next(arrived_flags), &"depart")
	var depart := _node(c_wait, &"depart")
	harness.check("准备出发保留同行约定兼容标记", depart.effects.get(&"ch2/c_at_school_gate"), true)
	harness.check("取消走廊连接的旧出发台词不再执行", depart.stage[0].kind, &"fade")
	var depart_goto: StageStep = null
	for step: StageStep in depart.stage:
		if step.kind == &"goto":
			depart_goto = step
	harness.check("C同行出发有直接转场", depart_goto != null, true)
	if depart_goto != null:
		harness.check("同行后主角直接进入教学楼教室", depart_goto.text("map"), "classroom")
		harness.check("同行后主角落在教室入口", depart_goto.text("spawn"), "from_gate")
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
	harness.check("抵达结果统一检查失败与救场状态",
		_node(diary_event, &"arrive").next_id, &"arrival_result")
	var failed_chase := WorldState.new()
	failed_chase.set_value(&"ch2/chase_failed", true)
	for phase: StringName in [&"run_q1", &"run_q2", &"arrive"]:
		harness.check(str(phase)+"前两次失败进入End5",
			_node(diary_event, phase).resolved_next(failed_chase), &"chase_caught")
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
