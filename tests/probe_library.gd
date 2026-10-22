extends SceneTree

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, result: bool) -> void:
	checks += 1
	if not result:
		failures.append(label)
		push_error(label)


func _run() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/library.json"))
	var definition := MapDef.from_dictionary(raw)
	_check("地图定义合法", definition.validate().is_empty())
	var spawn := definition.spawn_point("start")
	for name: String in definition.spawns:
		_check("出生点可站立 " + name, WalkGrid.has_landing_room(definition, definition.spawn_point(name)))
	var reached := WalkGrid.reachable(definition, spawn)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(definition.size) * 2
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node2D.new()
	stage.scale = Vector2(2, 2)
	viewport.add_child(stage)
	var view := MapView.new()
	stage.add_child(view)
	view.build(definition)
	var player := Player.create()
	stage.add_child(player)
	player.set_physics_process(false)
	player.position = spawn
	await physics_frame
	await physics_frame
	var cover_index := 0
	for actor: MapDef.Actor in definition.actors:
		if not actor.cover:
			continue
		_check("独立透明贴图 " + str(actor.id), ResourceLoader.exists(actor.sprite))
		var shape := _collider_for(definition, actor)
		_check("物件匹配地图碰撞 " + str(actor.id), shape.has_area())
		_check("遮挡基线对齐碰撞上缘 " + str(actor.id), is_equal_approx(actor.effective_cover_y(), shape.position.y))
		if not actor.decor:
			var reachable := false
			for point: Vector2 in reached:
				if actor.reach.grow(12).has_point(point):
					reachable = true
					break
			_check("保留书柜交互可接近 " + str(actor.id), reachable)
			var behind := Vector2(shape.get_center().x, shape.position.y - WalkGrid.STEP)
			var front := Vector2(shape.get_center().x, shape.end.y + WalkGrid.FOOT_UP + WalkGrid.STEP)
			_check("书柜后可到达 " + str(actor.id), _contains(reached, behind))
			_check("书柜前可到达 " + str(actor.id), _contains(reached, front))
			view.set_player_y(behind.y)
			var behind_z := view.cover_z(cover_index)
			player.position = behind
			await _capture(viewport, str(actor.id) + "_behind")
			view.set_player_y(front.y)
			_check("前后遮挡切换 " + str(actor.id), behind_z > view.cover_z(cover_index))
			player.position = front
			await _capture(viewport, str(actor.id) + "_front")
			var hit := player.move_and_collide(Vector2(0, -shape.size.y - WalkGrid.FOOT_UP * 3))
			_check("物理碰撞阻止穿柜 " + str(actor.id), hit != null and player.position.y >= shape.end.y + WalkGrid.FOOT_UP - 0.2)
		cover_index += 1
	player.position = spawn
	view.set_player_y(spawn.y)
	await _capture(viewport, "library_runtime")
	viewport.queue_free()
	await process_frame
	print("LIBRARY: %d/%d checks passed; %d reachable cells" % [checks - failures.size(), checks, reached.size()])
	quit(0 if failures.is_empty() else 1)


func _collider_for(definition: MapDef, actor: MapDef.Actor) -> Rect2:
	if actor.has_local_collision and not actor.collisions.is_empty():
		return actor.collision_rects()[0]
	for wall: Rect2 in definition.walls:
		if is_equal_approx(wall.position.y, actor.cover_y) and actor.rect.has_point(wall.get_center()):
			return wall
	return Rect2()


func _contains(cells: Array[Vector2], point: Vector2) -> bool:
	for cell: Vector2 in cells:
		if cell.distance_to(point) <= WalkGrid.STEP:
			return true
	return false


func _capture(viewport: SubViewport, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	_check("截图保存 " + label, image.save_png("res://.godot/library_review/" + label + ".png") == OK)
