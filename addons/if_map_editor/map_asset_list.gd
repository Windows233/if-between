@tool
extends ItemList

const DRAG_TYPE := "if_map_asset"


func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index < 0:
		return null
	var path := str(get_item_metadata(index))
	var texture := get_item_icon(index)
	if path.is_empty() or texture == null:
		return null
	var preview := TextureRect.new()
	preview.texture = texture
	preview.size = Vector2(64, 64)
	preview.custom_minimum_size = Vector2(64, 64)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return {"type": DRAG_TYPE, "path": path}
