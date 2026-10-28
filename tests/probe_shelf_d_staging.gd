## 实际剧情验收：shelf_d → 编辑器倒塌落点；C在上、主角在门口、触地扬尘。
extends SceneTree
var main: Node2D
var seen_dust := false
var shots := {}
var dust_done := false
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.tmp_dfall_shots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	root.add_child(main)
	main.boot()
	main.enter_map(&"library", &"from_school_gate", true)
	main.toast.visible = false
	await create_timer(0.4).timeout
	ItemTable.add(main.flags, &"crowbar")
	main.start_story(&"ch2_library_cat", &"crowbar_used")
	var elapsed := 0.0
	while elapsed < 20.0 and not main.escape_session.active:
		await process_frame
		elapsed += main.get_process_delta_time()
		if main.dialogue.is_open():
			main.dialogue.skip()
		var shelf := main.map_view._actor_variant_nodes.get(&"escape_shelf_barrier") as Sprite2D
		if is_instance_valid(shelf) and shelf.z_index == 16:
			var phase := 0 if absf(shelf.rotation) < 0.15 else (1 if absf(shelf.rotation) < 1.0 else 2)
			if not shots.has(phase):
				shots[phase] = true
				await _shot("phase_%d" % phase)
			var dust: Node = main.map_view._built.get_node_or_null("ShelfImpactDust")
			if dust != null:
				seen_dust = true
				if dust.age > 0.2 and not dust_done:
					dust_done = true
					await _shot("impact_dust")
	var staging := preload("res://scenes/library_shelf_fall.gd").positions(main.current_map)
	var target := preload("res://scenes/library_shelf_fall.gd").target_rect(main.current_map)
	var c: Node2D = main.cutscene._actor("c")
	var source_hidden := false
	var original_collider_gone := false
	for actor: MapDef.Actor in main.current_map.actors:
		if actor.id == &"shelf_d":
			source_hidden = actor.sprite_variant == "hidden"
			original_collider_gone = actor.collision_rects().is_empty()
	var at_exit: bool = WalkGrid.is_free(main.current_map, main.player.position)
	var ok: bool = seen_dust and source_hidden and original_collider_gone and at_exit and main.escape_session.active \
		and c != null and c.position.y < target.position.y and main.player.position.y > target.end.y
	print("SHELF_D_STAGING dust=%s hidden=%s old_collision_removed=%s C=%s player=%s target=%s free=%s PASS=%s" % [seen_dust, source_hidden, original_collider_gone, c.position if c else Vector2.ZERO, main.player.position, target, at_exit, ok])
	await _shot("finished")
	main.escape_session.cancel()
	main.queue_free()
	await process_frame
	quit(0 if ok else 1)
func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	picture.save_jpg("res://.tmp_dfall_shots/" + label + ".jpg", 0.95)
