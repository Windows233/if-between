@tool
extends ItemList

var library: RefCounted
var canvas: Control


class TemplatePreview extends Control:
	var actor
	var zoom := 1.0


	func _draw() -> void:
		if actor == null:
			return
		var rects: Array[Rect2] = actor.world_visual_rects()
		var sprites: PackedStringArray = actor.visual_sprites()
		for index: int in rects.size():
			if sprites[index].is_empty() or not ResourceLoader.exists(sprites[index]):
				continue
			var texture := load(sprites[index]) as Texture2D
			if texture == null:
				continue
			var bounds := Rect2((rects[index].position - actor.rect.get_center()) * zoom, rects[index].size * zoom)
			draw_set_transform_matrix(MapDef.texture_transform(bounds, texture.get_size(), actor.quarter_turns, actor.flip_h, actor.flip_v))
			draw_texture(texture, Vector2.ZERO)
			draw_set_transform_matrix(Transform2D.IDENTITY)


func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index < 0 or library == null:
		return null
	var name := str(get_item_metadata(index))
	var resolved: Dictionary = library.resolve_template(name)
	if not resolved.get("ok", false):
		return null
	var preview := TemplatePreview.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.actor = MapDef._actor_from(resolved["actor"])
	preview.zoom = canvas.zoom if is_instance_valid(canvas) else 1.0
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_drag_preview(preview)
	return {"type": "if_map_template", "name": name}
