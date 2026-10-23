@tool
extends ItemList

const DRAG_TYPE := "if_map_asset"

var canvas: Control = null


func preview_size_for_asset(path: String, texture: Texture2D) -> Vector2:
	if texture == null or not is_instance_valid(canvas) or canvas.model == null:
		return Vector2.ZERO
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return Vector2.ZERO
	var zoom_factor: float = canvas.zoom
	if not is_finite(zoom_factor) or zoom_factor <= 0.0:
		return Vector2.ZERO
	return canvas.model.world_size_for_image(Vector2(image.get_size())) * zoom_factor


func drag_data_for_asset(path: String) -> Dictionary:
	return {"type": DRAG_TYPE, "path": path}


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
	if preview_size_for_asset(path, texture) == Vector2.ZERO:
		if is_instance_valid(canvas) and canvas.has_signal("status"):
			canvas.emit_signal("status", "无法按背景比例放置素材；请先载入可读取且尺寸有效的地图背景。")
		return null
	set_drag_preview(make_drag_preview(path, texture))
	return drag_data_for_asset(path)
