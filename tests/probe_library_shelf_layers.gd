## 图书馆书架拆层验收：底图、独立物件、移位与倒架；仅输出JPG，不改地图。
extends SceneTree
var main: Node2D
const OUTPUT := "res://.tmp_shelves_shots"
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	root.add_child(main)
	main.boot()
	main.enter_map(&"library", &"from_school_gate", true)
	main.set_process(false)
	main.player.set_physics_process(false)
	main.player.visible = false
	main.toast.visible = false
	main.camera.zoom = Vector2(0.45, 0.45)
	main.camera.position = Vector2(main.current_map.size) * 0.5
	await create_timer(0.4).timeout
	for node: Sprite2D in main.map_view._actor_variant_nodes.values():
		node.visible = false
	await _shot("01_base_only")
	var shelf_count := 0
	for actor: MapDef.Actor in main.current_map.actors:
		if str(actor.id).begins_with("shelf_"):
			shelf_count += 1
			main.map_view._actor_variant_nodes[actor.id].visible = true
	assert(shelf_count == 10)
	await _shot("02_independent_shelves")
	var source: Sprite2D = main.map_view._actor_variant_nodes[&"shelf_se"]
	source.position += Vector2(0, -35)
	await _shot("03_shelf_moved_original_empty")
	main.flags.set_value(&"ch2/library/shelf_fallen", true)
	main.refresh_scene()
	for id: Variant in main.map_view._actor_variant_nodes:
		if not str(id).begins_with("shelf_") and id != &"escape_shelf_barrier":
			main.map_view._actor_variant_nodes[id].visible = false
	await _shot("04_fallen_original_empty")
	print("SHELF_LAYERS_OK count=%d clean_background=%s" % [shelf_count, main.current_map.background])
	main.queue_free()
	await process_frame
	quit()
func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	shot.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	shot.save_jpg(OUTPUT.path_join(label + ".jpg"), 0.95)
