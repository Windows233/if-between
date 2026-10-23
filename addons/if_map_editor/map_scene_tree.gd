@tool
extends Tree

signal hierarchy_drop(source: Dictionary, target: Dictionary, section: int)


func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null or not item.get_metadata(0) is Dictionary:
		return null
	var preview := Label.new()
	preview.text = item.get_text(0)
	set_drag_preview(preview)
	return {"type": "if_map_hierarchy", "source": item.get_metadata(0).duplicate()}


func _can_drop_data(at_position: Vector2, payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("type") != "if_map_hierarchy":
		return false
	drop_mode_flags = Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM
	var target := get_item_at_position(at_position)
	return target != null and target.get_metadata(0) is Dictionary


func _drop_data(at_position: Vector2, payload: Variant) -> void:
	if _can_drop_data(at_position, payload):
		var target := get_item_at_position(at_position)
		hierarchy_drop.emit(payload["source"], target.get_metadata(0), get_drop_section_at_position(at_position))
