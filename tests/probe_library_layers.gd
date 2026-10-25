## 真渲染核查独立猫、个人回溯与旧血迹；输出全图对照。
extends SceneTree

var main: Variant
var output := "user://library_layers_probe"


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	root.add_child(main)
	main.boot()
	main.enter_map(&"library", &"from_school_gate", true)
	main.set_process(false)
	main.player.set_physics_process(false)
	main.camera.zoom = Vector2.ONE * 0.46
	main.camera.position = main.current_map.size * 0.5
	main.capture_personal_anchor()
	await create_timer(0.35).timeout
	await _shot("01_cat_visible")
	main.flags.set_value(&"ch2/personal/library_cat_hidden", true)
	main.refresh_scene()
	await _shot("02_cat_hidden_blood_remains")
	main.restore_personal_anchor()
	main.camera.zoom = Vector2.ONE * 0.46
	main.camera.position = main.current_map.size * 0.5
	await _shot("03_rewind_cat_returns")
	main.flags.set_value(&"ch2/personal/library_cat_hidden", true)
	main.flags.set_value(&"ch2/library/shelf_fallen", true)
	main.refresh_scene()
	await _shot("04_fallen_shelf_placeholder")
	print("[图层GPU] PASS 四状态真实渲染；血迹flag=", main.flags.get_value(&"map_blood/library/entrance"))
	main.queue_free()
	await process_frame
	quit(0)


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
