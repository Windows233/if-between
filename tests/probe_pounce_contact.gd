## 输出真实运行贴图的JPG连续动作格，不录制视频。
extends SceneTree
var main: Node2D
const OUTPUT := "res://.tmp_pounce_shots"
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
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
	main.chase_session.set_process(false)
	main.player.visible = false
	main.toast.visible = false
	main.set_process(false)
	main.chase_session._mist.position = main.player.position + Vector2(30, 0)
	main.camera_focus = main.chase_session._mist.position + Vector2(0, -15)
	main.update_camera()
	await create_timer(0.4).timeout
	var directions := {"side": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}
	for direction: String in directions:
		for i: int in 4:
			main.chase_session._hop_clock = [0.10, 0.33, 0.54, 0.75][i]
			main.chase_session._animate_mist(0.0, directions[direction])
			await _shot("cat_%s_%d" % [direction, i])
	main.chase_session.cancel()
	main.enter_map(&"library", &"from_school_gate", true)
	main.player.visible = false
	main.set_process(false)
	main.camera.global_position = Vector2(main.current_map.size) * 0.5
	main.camera.zoom = Vector2(0.45, 0.45)
	await create_timer(0.4).timeout
	preload("res://scenes/library_shelf_fall.gd").hide_source(main.map_view)
	var node: Sprite2D = main.map_view._actor_variant_nodes[&"escape_shelf_barrier"]
	node.z_index = 16
	var rect := preload("res://scenes/library_shelf_fall.gd").source_rect(main.current_map)
	for i: int in 4:
		preload("res://scenes/library_shelf_fall.gd").pose(node, rect, [0.0, PI * 0.125, PI * 0.33, PI * 0.5][i])
		await _shot("shelf_%d" % i)
	print("CONTACT_OK source=shelf_se rect=%s" % rect)
	main.queue_free()
	await process_frame
	quit()
func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	shot.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	shot.save_jpg(OUTPUT.path_join(label + ".jpg"), 0.95)
