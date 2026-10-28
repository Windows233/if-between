## 同一个书架绕右下脚连续倾倒；最终变换也用于重建/读档，避免换图下沉。
## 复用原画第一格，不再播放五张轮廓和画布不同的姿势。
extends RefCounted

static var upright: Texture2D

static func texture() -> Texture2D:
	if upright == null:
		var sheet := load("res://art/props/library_shelf_fall_sheet.png") as Texture2D
		var image := sheet.get_image()
		var cell := image.get_region(Rect2i(0, 0, image.get_width() / 5, image.get_height()))
		upright = ImageTexture.create_from_image(cell.get_region(cell.get_used_rect()))
	return upright

static func pose(node: Sprite2D, rect: Rect2, angle: float) -> void:
	node.texture = texture()
	node.centered = false
	node.offset = -node.texture.get_size()
	var ratio := rect.size.x / node.texture.get_height()
	node.scale = Vector2.ONE * ratio
	node.position = Vector2(rect.position.x, rect.end.y)
	node.rotation = angle

static func play(view: Node2D, node: Sprite2D, actor: MapDef.Actor,
		token: int, final_variant: StringName) -> void:
	node.z_index = view.ABOVE_OVERLAY_Z
	pose(node, actor.rect, 0.0)
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
		pose(node, actor.rect, angle)
	pose(node, actor.rect, PI * 0.5)
	actor.sprite_variant = str(final_variant)
