## 真窗口检查追逐换帧、倒架完整播放和恢复操作的先后顺序。
extends SceneTree

var main: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	root.add_child(main)
	main.boot()
	main.enter_map(&"school_gate", &"near_classroom", true)
	main.flags.set_value(&"ch2/diary_read", true)
	main.flags.set_value(&"ch2/teamed_c", true)
	ItemTable.add(main.flags, &"charm")
	assert(main.chase_session.begin())
	main.chase_session.set_physics_process(false)
	main.chase_session._mist.global_position = main.player.global_position + Vector2(65, 0)
	for i: int in 4:
		main.chase_session._animate_mist(0.125, Vector2.RIGHT)
		await create_timer(0.1).timeout
		await _shot("cat_%d" % i)
	main.chase_session.cancel()
	main.enter_map(&"library", &"from_school_gate", true)
	main.player.position = Vector2(233, 258)
	main.update_camera()
	ItemTable.add(main.flags, &"crowbar")
	main.start_story(&"ch2_library_cat", &"crowbar_used")
	var textures := {}
	var locked := true
	var elapsed := 0.0
	while elapsed < 12.0 and not main.escape_session.active:
		await process_frame
		elapsed += main.get_process_delta_time()
		if main.dialogue.is_open():
			main.dialogue.skip()
		var sprite := main.map_view._actor_variant_nodes.get(&"escape_shelf_barrier") as Sprite2D
		if is_instance_valid(sprite) and sprite.z_index == main.map_view.ABOVE_OVERLAY_Z:
			locked = locked and not main.player.is_physics_processing()
			if not textures.has(sprite.texture.get_instance_id()):
				textures[sprite.texture.get_instance_id()] = true
				await _shot("shelf_%d" % textures.size())
	print("ANIMATION_PROBE frames=%d locked=%s escape=%s movable=%s" % [
		textures.size(), locked, main.escape_session.active, main.player.is_physics_processing()])
	var ok: bool = textures.size() == 5 and locked and main.escape_session.active and main.player.is_physics_processing()
	main.escape_session.cancel()
	main.queue_free()
	await process_frame
	quit(0 if ok else 1)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var folder := "user://cat_shelf_animation"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
