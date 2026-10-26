## 调查物件时的近景：按地图实际贴图/部件绘制，缺独立贴图时裁取背景。
## 独立屏幕层不受地图相机缩放影响，不接管输入；正式剧情大图显示时让位。
## 生命周期跟随当前交互，换图、对话/选项结束自动收起，不写入存档。
extends CanvasLayer

const TextureSource = preload("res://scenes/map_texture_source.gd")
var host: Node2D
var content: Node2D
var bounds := Rect2()


func show_actor(actor: MapDef.Actor, definition: MapDef) -> void:
	clear()
	if actor == null or actor.person or definition == null:
		return
	layer = StageOverlay.PICTURE_LAYER - 1
	content = Node2D.new()
	add_child(content)
	var paths := actor.visual_sprites()
	var rects := actor.world_visual_rects()
	var first := true
	for index: int in paths.size():
		if paths[index].is_empty() or not ResourceLoader.exists(paths[index]):
			continue
		var texture := load(paths[index]) as Texture2D
		if texture == null:
			continue
		texture = TextureSource.resolve(paths[index], texture)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.transform = actor.visual_texture_transform(index, texture.get_size())
		content.add_child(sprite)
		var visible_rect := rects[index]
		var pixels := texture.get_image()
		if pixels != null and pixels.get_used_rect().has_area():
			visible_rect = sprite.transform * Rect2(pixels.get_used_rect())
		bounds = visible_rect if first else bounds.merge(visible_rect)
		first = false
	if first and not definition.background.is_empty() and ResourceLoader.exists(definition.background):
		var texture := load(definition.background) as Texture2D
		if texture != null and definition.size.x > 0 and definition.size.y > 0:
			texture = TextureSource.resolve(definition.background, texture)
			var ratio := texture.get_size() / Vector2(definition.size)
			var region := Rect2(actor.rect.position * ratio, actor.rect.size * ratio)
			region = region.intersection(Rect2(Vector2.ZERO, texture.get_size()))
			if region.has_area():
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = region
				var sprite := Sprite2D.new()
				sprite.texture = atlas
				sprite.centered = false
				sprite.position = region.position / ratio
				sprite.scale = Vector2.ONE / ratio
				content.add_child(sprite)
				bounds = Rect2(sprite.position, region.size / ratio)
	if not bounds.has_area():
		clear()
	else:
		layout()


func _process(_delta: float) -> void:
	if content == null or host == null:
		return
	if not host.story.is_active() and not host.dialogue.is_open() and not host.choice_menu.is_open():
		clear()
		return
	content.visible = not host.stage_overlay.has_image()
	layout()


func layout() -> void:
	if content == null or not bounds.has_area():
		return
	var view := get_viewport().get_visible_rect().size
	var bottom := view.y - DialogueBox.BOX_MAX_HEIGHT - 6.0
	if host != null and host.dialogue.is_open():
		bottom = host.dialogue.hold_top() - 6.0
	var available := Vector2(maxf(view.x - 24.0, 1.0), maxf(bottom - 6.0, 1.0))
	var factor := minf(available.x / bounds.size.x, available.y / bounds.size.y)
	content.scale = Vector2.ONE * factor
	content.position = Vector2(view.x * 0.5, (bottom + 6.0) * 0.5) - bounds.get_center() * factor


func clear() -> void:
	if content != null:
		remove_child(content)
		content.queue_free()
		content = null
	bounds = Rect2()
