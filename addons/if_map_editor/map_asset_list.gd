@tool
extends ItemList

const DRAG_TYPE := "if_map_asset"

var canvas: Control = null


func preview_size_for_asset(path: String, texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	if is_instance_valid(canvas) and canvas.model != null:
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			return canvas.model.world_size_for_image(Vector2(image.get_size())) * canvas.zoom
	return Vector2(texture.get_size())


func make_drag_preview(path: String, texture: Texture2D) -> Control:
	var dimensions := preview_size_for_asset(path, texture)
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview := TextureRect.new()
	preview.texture = texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.size = dimensions
	preview.position = -dimensions * 0.5
	wrapper.add_child(preview)
	return wrapper


func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index < 0:
		return null
	var path := str(get_item_metadata(index))
	var texture := get_item_icon(index)
	if path.is_empty() or texture == null:
		return null
	set_drag_preview(make_drag_preview(path, texture))
	return {"type": DRAG_TYPE, "path": path}
