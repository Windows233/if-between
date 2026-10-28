## shelf_d独立书架向左倾倒；最终变换也用于重建/读档，避免换图下沉。
## 起倒使用原物件，落地使用重绘俯视散书姿态；不生成扬尘。
extends RefCounted

static var upright: Texture2D
static var grounded: Texture2D
const FALLEN_PATH := "res://art/props/library_shelf_d_fallen_perspective.png"
## 重绘图中的书架本体范围；外围散书/蜡烛不能参与本体尺寸标定。
const FALLEN_BODY := Rect2(200, 0, 1690, 710)

static func body_scale(source: Rect2) -> float:
	return source.size.y / FALLEN_BODY.size.x

static func fallen_texture() -> Texture2D:
	if grounded == null:
		var source := (load(FALLEN_PATH) as Texture2D).get_image()
		grounded = ImageTexture.create_from_image(source.get_region(source.get_used_rect()))
	return grounded

static func source_rect(def: MapDef) -> Rect2:
	for actor: MapDef.Actor in def.actors:
		if actor.id == &"shelf_d":
			return actor.rect
	return Rect2()

static func texture() -> Texture2D:
	if upright == null:
		upright = load("res://art/props/library_shelf_d_cover.png") as Texture2D
	return upright

static func target_rect(def: MapDef) -> Rect2:
	for actor: MapDef.Actor in def.actors:
		if actor.id == &"escape_shelf_barrier":
			return actor.rect
	return Rect2()

static func pose(node: Sprite2D, rect: Rect2, angle: float, target := Rect2()) -> void:
	node.texture = texture()
	node.centered = false
	node.offset = Vector2(0, -node.texture.get_height())
	if target.size == Vector2.ZERO:
		target = Rect2(rect.position.x - rect.size.y, rect.end.y - rect.size.x, rect.size.y, rect.size.x)
	var t := clampf(angle / (PI * 0.5), 0.0, 1.0)
	if is_equal_approx(t, 1.0):
		node.texture = fallen_texture()
		node.offset = Vector2.ZERO
		var ratio := body_scale(rect)
		node.scale = Vector2.ONE * ratio
		node.position = Vector2(target.get_center().x - FALLEN_BODY.get_center().x * ratio,
			target.end.y - FALLEN_BODY.end.y * ratio)
		node.rotation = 0.0
		return
	var initial_scale := rect.size / node.texture.get_size()
	# 倾倒时保持原书架尺寸；落点框只提供中心和地面锚点，不强迫贴图缩进框里。
	node.scale = initial_scale
	var final_pivot := Vector2(target.get_center().x + rect.size.y * 0.5, target.end.y)
	node.position = Vector2(rect.position.x, rect.end.y).lerp(final_pivot, t)
	node.rotation = -angle

static func positions(def: MapDef) -> Dictionary:
	var target := target_rect(def)
	var hero := _free_near(def, def.spawn_point(&"from_school_gate"))
	var c := _free_near(def, Vector2(target.get_center().x, target.position.y - 10.0))
	return {"player": hero, "c": c}

static func _free_near(def: MapDef, preferred: Vector2) -> Vector2:
	if WalkGrid.has_landing_room(def, preferred):
		return preferred
	for radius: int in range(2, 82, 2):
		for offset: Vector2 in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN,
			Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var point := preferred + offset * radius
			if WalkGrid.has_landing_room(def, point):
				return point
	return preferred

## 原书架也烘焙在背景里；以同图的空地砖补回被移走的区域，前景墙仍正常遮挡。
static func hide_source(view: Node2D) -> void:
	view.set_actor_alpha(&"shelf_d", 0.0)
	if view.map_def.background == "res://art/map/library_no_shelves.png":
		return
	if view._built.has_node("ShelfFloor"):
		return
	var source := source_rect(view.map_def)
	var background := load(view.map_def.background) as Texture2D
	var scale := background.get_size() / Vector2(view.map_def.size)
	var sample := Rect2i(Vector2(80, 200) * scale, Vector2(20, 20) * scale)
	var patch := TextureRect.new()
	patch.name = "ShelfFloor"
	patch.texture = ImageTexture.create_from_image(background.get_image().get_region(sample))
	patch.stretch_mode = TextureRect.STRETCH_TILE
	patch.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	patch.position = source.position
	patch.scale = Vector2.ONE / scale
	patch.size = source.size * scale
	patch.z_index = -19
	view._built.add_child(patch)

static func play(view: Node2D, node: Sprite2D, actor: MapDef.Actor,
		token: int, final_variant: StringName) -> void:
	if source_rect(view.map_def).size == Vector2.ZERO:
		return
	node.z_index = view.ABOVE_OVERLAY_Z
	hide_source(view)
	pose(node, source_rect(view.map_def), 0.0, target_rect(view.map_def))
	var landing := Sprite2D.new()
	landing.name = "ShelfPerspectiveLanding"
	landing.z_index = view.ABOVE_OVERLAY_Z
	pose(landing, source_rect(view.map_def), PI * 0.5, target_rect(view.map_def))
	landing.modulate.a = 0.0
	view._built.add_child(landing)
	# 重心越过支点后加速，触地只做一次小幅回弹；每个渲染帧都有新角度。
	var elapsed := 0.0
	var impact := false
	while elapsed < 1.45:
		await view.get_tree().process_frame
		if not is_instance_valid(node) or int(view._actor_animation_generation.get(actor.id, 0)) != token:
			return
		if view.get_tree().paused:
			continue
		elapsed += minf(view.get_process_delta_time(), 0.05)
		var angle: float
		if elapsed < 1.12:
			angle = PI * 0.5 * pow(clampf(elapsed / 1.12, 0.0, 1.0), 2.2)
		else:
			if not impact:
				impact = true
				if view.get_parent().has_method("play_sound"):
					view.get_parent().play_sound("res://audio/sfx/shelf_fall.wav")
			var t := clampf((elapsed - 1.12) / 0.38, 0.0, 1.0)
			angle = PI * 0.5 - sin(t * PI) * (1.0 - t) * 0.045
		pose(node, source_rect(view.map_def), angle, target_rect(view.map_def))
		# 触地前将直立正面过渡到重绘的俯视倒地姿态，不能把卡片平转当成落地。
		var blend := smoothstep(0.7, 1.0, angle / (PI * 0.5)) if not impact else 1.0
		node.modulate.a = 1.0 - blend
		landing.modulate.a = blend
	pose(node, source_rect(view.map_def), PI * 0.5, target_rect(view.map_def))
	node.modulate.a = 1.0
	landing.queue_free()
	actor.sprite_variant = str(final_variant)
