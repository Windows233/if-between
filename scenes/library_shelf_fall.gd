## 同一个书架绕右下脚连续倾倒；最终变换也用于重建/读档，避免换图下沉。
## 复用原画第一格，不再播放五张轮廓和画布不同的姿势。
extends RefCounted

static var upright: Texture2D

static func source_rect(def: MapDef) -> Rect2:
	for actor: MapDef.Actor in def.actors:
		if actor.id == &"shelf_se":
			return actor.rect
	return Rect2()

static func texture() -> Texture2D:
	if upright == null:
		upright = load("res://art/props/library_shelf_se_cover.png") as Texture2D
	return upright

static func pose(node: Sprite2D, rect: Rect2, angle: float) -> void:
	node.texture = texture()
	node.centered = false
	node.offset = Vector2(0, -node.texture.get_height())
	node.scale = rect.size / node.texture.get_size()
	node.position = Vector2(rect.position.x, rect.end.y)
	node.rotation = -angle

## 原书架也烘焙在背景里；以同图的空地砖补回被移走的区域，前景墙仍正常遮挡。
static func hide_source(view: Node2D) -> void:
	view.set_actor_alpha(&"shelf_se", 0.0)
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
	node.z_index = view.ABOVE_OVERLAY_Z
	hide_source(view)
	pose(node, source_rect(view.map_def), 0.0)
	# 重心越过支点后加速，触地只做一次小幅回弹；每个渲染帧都有新角度。
	var elapsed := 0.0
	var impact := false
	while elapsed < 1.5:
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
		pose(node, source_rect(view.map_def), angle)
	pose(node, source_rect(view.map_def), PI * 0.5)
	actor.sprite_variant = str(final_variant)
