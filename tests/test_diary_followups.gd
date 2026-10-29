## 日记选项保图及两种错误路线End5重试后入馆的非即时回归。
extends RefCounted
static func run(h: TestHarness) -> void:
	for wrong: StringName in [&"choose_wrong_gate", &"choose_wrong_yard"]:
		await _route(h, wrong)
static func _route(h: TestHarness, wrong: StringName) -> void:
	var main := h.new_main()
	main.flags.set_value(&"ch2/teamed_c", true)
	main.flags.set_value(&"ch2/rescued_c", true)
	main.flags.set_value(&"ch2/c_left_for_classroom", true)
	ItemTable.add(main.flags, &"charm")
	main.enter_map(&"classroom", &"from_gate")
	main.start_story(&"ch2_diary")
	var errors := 0
	var retried := false
	var saw_diary := false
	var saw_reveal := false
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		await h.root.get_tree().process_frame
		if main.cutscene.is_waiting_click(): main.cutscene.consume_click()
		if main.dialogue.is_open():
			main.dialogue.advance()
			main.dialogue.advance()
		if main.choice_menu.is_open() and main.story.runtime.current_node() != null:
			var node: StringName = main.story.runtime.current_node().id
			if node == &"route_choice":
				var picture: Texture2D = main.stage_overlay._image.texture
				if picture is AtlasTexture: picture = picture.atlas
				saw_diary = main.stage_overlay.has_image() and picture.resource_path.ends_with("ch2_diary_written.png")
				if retried:
					saw_reveal = main.fade.alpha() < 0.01
					main._on_choice_chosen(&"choose_library")
				else:
					errors += 1
					main._on_choice_chosen(wrong)
			elif node == &"end5_route_outcome":
				h.check("错误路线两次选择后进入End5", errors, 2)
				retried = true
				main._on_choice_chosen(&"retry_route")
		if main.chase_session.active:
			main.player.global_position = main.chase_session._door_area.get_center()
			main.chase_session.confirm_door_interaction()
		if main.current_map.id == &"library" and not main.story.is_active(): break
	await h.root.get_tree().process_frame
	await h.root.get_tree().process_frame
	h.check(str(wrong)+"选项保持有字日记图", saw_diary, true)
	h.check(str(wrong)+"End5重试后揭开黑幕", saw_reveal, true)
	h.check(str(wrong)+"重试后成功进入图书馆", main.current_map.id, &"library")
	h.check(str(wrong)+"入馆后有C", main.cutscene.actor_ids().has("c"), true)
	h.check(str(wrong)+"入馆后无残留遮图", main.stage_overlay.has_image(), false)
	h.check(str(wrong)+"入馆后恢复可操作状态", main.player.is_physics_processing(), true)
	h.check(str(wrong)+"入馆后黑幕收起", main.fade.alpha() < 0.01, true)
	main.queue_free()
	await h.root.get_tree().process_frame
