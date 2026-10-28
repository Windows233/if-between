## 真窗口专项：无血迹前置跑两轮图书馆，QTE成功后退到门口、倒架、交还控制。
## 只保存关键帧 JPG，使用现有素材和正式事件，不录制视频。
extends SceneTree

var main: Node2D
var shots := {}
var errors: Array[String] = []
var tear_seen := false
var previous_c_y := 0.0
var pursuit_seen := false
const OUT := "res://.tmp_library_flow_shots/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	main.debug_start_map = ""
	root.add_child(main)
	main.boot()
	main.toast.visible = false
	ItemTable.add(main.flags, &"diary")
	ItemTable.add(main.flags, &"key")
	main.start_story(&"ch2_diary", &"library_enter")
	await _until(func() -> bool: return not main.story.is_active(), 8.0)
	await _shot("01_entry")
	var shelf := _actor(&"shelf_a")
	main.player.position = Vector2(shelf.reach.get_center().x, shelf.reach.end.y - 4)
	main.begin_interaction(shelf)
	await _until(func() -> bool: return not main.story.is_active(), 8.0)
	var cat := _actor(&"cat_monster")
	main.player.position = Vector2(cat.reach.position.x + 4, cat.reach.end.y - 4)
	main._update_map_triggers()
	await _until(func() -> bool: return main.flags.get_value(&"ch2/library/rewound") == true and not main.story.is_active(), 22.0)
	_check("回溯主角回到门口", main.player.position.distance_to(main.current_map.spawn_point(&"from_school_gate")) < 2)
	_check("回溯C回到门口并向左", main.cutscene._actor("c").position.distance_to(preload("res://scenes/library_staging.gd").point(main.current_map, "entry_c")) < 2 and not main.cutscene._actor("c").flip_h)
	await _shot("04_rewind_entry")
	main.player.position = Vector2(shelf.reach.get_center().x, shelf.reach.end.y - 4)
	main.begin_interaction(shelf)
	await _until(func() -> bool: return not main.story.is_active(), 8.0)
	var box := _actor(&"box")
	main.player.position = Vector2(box.reach.get_center().x, box.reach.end.y + 8)
	main.begin_interaction(box)
	await _until(func() -> bool: return main.escape_session.active, 30.0)
	_check("跳过两次血迹也能进入逃跑", main.flags.get_value(&"ch2/library/blood_seen") != true and main.flags.get_value(&"ch2/library/blood_second_seen") != true)
	_check("未拿撬棍也完成倒架", main.flags.get_value(&"ch2/library/shelf_fallen") == true)
	_check("倒架后源书架隐藏且碰撞移除", _actor(&"shelf_d").sprite_variant == "hidden" and _actor(&"shelf_d").collision_rects().is_empty())
	_check("先到门口再交还控制", main.player.position.y > preload("res://scenes/library_shelf_fall.gd").target_rect(main.current_map).end.y)
	_check("拿到夜幕之泪后C随主角向下追而非向上走", pursuit_seen)
	await _shot("10_escape_ready")
	print("LIBRARY_FLOW_GPU shots=%s errors=%s" % [shots.keys(), errors])
	main.escape_session.cancel()
	main.story.cancel()
	main.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)

func _until(done: Callable, timeout: float) -> void:
	var until := Time.get_ticks_msec() + int(timeout * 1000)
	while not done.call() and Time.get_ticks_msec() < until:
		await process_frame
		await _observe()
		if main.cutscene.is_inventory_select_active():
			main.cutscene.choose_inventory_selection(&"diary")
		if main.chase_overlay.is_running():
			main.chase_overlay._warning_until_usec = Time.get_ticks_usec() - 1
			main.chase_overlay._process(0)
			var key := InputEventKey.new()
			key.pressed = true
			key.physical_keycode = KEY_Q
			main.chase_overlay.handle_input(key)
		if main.dialogue.is_open():
			main.dialogue.skip()
	_check("流程在时限内继续", done.call())

func _observe() -> void:
	var node: StringName = main.story.current_node_id()
	if main.flags.get_value(&"ch2/library/second_cat_mediation") == true:
		var c: Node2D = main.cutscene._actor("c")
		if c != null:
			if tear_seen:
				_check("拿到夜幕之泪后C没有向上折返", c.position.y >= previous_c_y - 0.1)
			previous_c_y = c.position.y
			tear_seen = true
			var carpet := preload("res://scenes/library_staging.gd").point(main.current_map, "carpet_c")
			if node == &"crowbar_used" and c.position.y > carpet.y + 6 and main.player.position.y > 255:
				pursuit_seen = true
				await _shot("08_before_fall")
	if main.stage_overlay.has_image() and main.stage_overlay._image.modulate.a > 0.99:
		if main.story.event_id == &"ch2_library_shelf":
			# StageOverlay裁透明边后使用内存纹理，按节点和演出步判读新页。
			var second: bool = node == &"second" and main.story.runtime.stage_step >= 4
			await _shot("05_book_second" if second else "02_book_first")
		elif main.story.event_id == &"ch2_library_box":
			await _shot("06_photo")
	if node == &"approach_talk" and main.dialogue.is_open():
		await _shot("03_c_walked_up")
	if node == &"second_scene" and main.dialogue.is_open():
		_check("猫对话时C仍在入口", main.cutscene._actor("c").position.distance_to(preload("res://scenes/library_staging.gd").point(main.current_map, "entry_c")) < 2)
		await _shot("07_cat_portrait")
	var shelf := main.map_view._actor_variant_nodes.get(&"escape_shelf_barrier") as Sprite2D
	if shelf != null and shelf.z_index == 16:
		_check("倒架期间玩家不可操控", not main.player.is_physics_processing())
		await _shot("09_falling" if absf(shelf.rotation) > 0.65 else "08_before_fall")

func _shot(label: String) -> void:
	if shots.has(label):
		return
	shots[label] = true
	if label in ["02_book_first", "03_c_walked_up", "05_book_second", "06_photo", "07_cat_portrait"]:
		await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(OUT + label + ".jpg", 0.95)

func _check(label: String, ok: bool) -> void:
	if not ok and label not in errors:
		errors.append(label)

func _actor(id: StringName) -> MapDef.Actor:
	for actor: MapDef.Actor in main.current_map.actors:
		if actor.id == id:
			return actor
	return null
