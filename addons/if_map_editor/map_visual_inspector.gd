@tool
extends VBoxContainer

signal edited
signal rebuild_requested

const Transform := preload("res://addons/if_map_editor/map_object_transform.gd")
const LAYERS := ["back", "auto", "front"]
var model
var actor_index := -1
var selection: Array[int] = []


func configure(source, index: int, selected: Array[int] = []) -> void:
	model = source
	actor_index = index
	selection.assign(selected if not selected.is_empty() else [index])
	var title := Label.new()
	title.text = "视觉部件与变换"
	add_child(title)
	var tools := HFlowContainer.new()
	for action: Array in [["水平翻转", "flip_h"], ["垂直翻转", "flip_v"], ["顺时针 90°", "rotate_cw"], ["逆时针 90°", "rotate_ccw"]]:
		var button := Button.new()
		button.text = action[0]
		button.pressed.connect(_transform.bind(str(action[1])))
		tools.add_child(button)
	var scale := SpinBox.new()
	scale.min_value = 0.01
	scale.max_value = 100
	scale.step = 0.01
	scale.value = 1
	scale.custom_minimum_size.x = 100
	tools.add_child(scale)
	var apply := Button.new()
	apply.text = "等比缩放"
	apply.pressed.connect(func() -> void: _transform("scale", scale.value))
	tools.add_child(apply)
	add_child(tools)
	var note := Label.new()
	note.text = "变换会同步局部碰撞与交互区。部件矩形相对物件左上角；自动层使用物件基线加偏移。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var parts: Array = model.actor_field(index, "visual_parts", [])
	for part_index: int in parts.size():
		if parts[part_index] is Dictionary:
			_build_part(part_index, parts[part_index])
	var add := Button.new()
	add.text = "添加视觉部件"
	add.pressed.connect(add_part)
	add_child(add)


func _build_part(index: int, part: Dictionary) -> void:
	var box := VBoxContainer.new()
	var row := HFlowContainer.new()
	var identity := LineEdit.new()
	identity.text = str(part.get("id", ""))
	identity.placeholder_text = "部件 ID"
	identity.custom_minimum_size.x = 90
	identity.text_submitted.connect(func(text: String) -> void: set_part(index, "id", text))
	row.add_child(identity)
	var layer := OptionButton.new()
	layer.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for text: String in ["固定后层", "按基线遮挡", "固定前层"]:
		layer.add_item(text)
	layer.select(maxi(LAYERS.find(str(part.get("layer", "auto"))), 0))
	layer.item_selected.connect(func(value: int) -> void: set_part(index, "layer", LAYERS[value]))
	row.add_child(layer)
	var remove := Button.new()
	remove.text = "删除部件"
	remove.pressed.connect(remove_part.bind(index))
	row.add_child(remove)
	box.add_child(row)
	var texture := LineEdit.new()
	texture.text = str(part.get("sprite", ""))
	texture.placeholder_text = "res:// 贴图路径（Enter 应用）"
	texture.text_submitted.connect(func(text: String) -> void: set_part(index, "sprite", text))
	box.add_child(texture)
	var geometry := HFlowContainer.new()
	var rect: Array = part.get("rect", [0, 0, 1, 1])
	for component: int in 4:
		var label := Label.new()
		label.text = ["x", "y", "宽", "高"][component]
		geometry.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = -100000
		spin.max_value = 100000
		spin.step = 0.1
		spin.value = float(rect[component])
		spin.custom_minimum_size.x = 80
		spin.value_changed.connect(func(value: float) -> void:
			var updated: Array = model.actor_field(actor_index, "visual_parts", [])[index].get("rect").duplicate()
			updated[component] = value
			set_part(index, "rect", updated))
		geometry.add_child(spin)
	box.add_child(geometry)
	var baseline := HBoxContainer.new()
	var baseline_label := Label.new()
	baseline_label.text = "遮挡基线偏移"
	baseline.add_child(baseline_label)
	var offset := SpinBox.new()
	offset.min_value = -100000
	offset.max_value = 100000
	offset.step = 0.1
	offset.value = float(part.get("sort_offset", 0))
	offset.value_changed.connect(func(value: float) -> void: set_part(index, "sort_offset", value))
	baseline.add_child(offset)
	box.add_child(baseline)
	add_child(box)


func set_part(index: int, field: String, value: Variant) -> bool:
	var parts: Array = model.actor_field(actor_index, "visual_parts", []).duplicate(true)
	if index < 0 or index >= parts.size():
		return false
	if field == "rect" and (not value is Array or value.size() != 4 or float(value[2]) <= 0 or float(value[3]) <= 0):
		return false
	parts[index][field] = value
	model.set_actor_field(actor_index, "visual_parts", parts)
	edited.emit()
	return true


func add_part() -> void:
	var parts: Array = model.actor_field(actor_index, "visual_parts", []).duplicate(true)
	var rect: Array = model.actor_field(actor_index, "rect", [0, 0, 1, 1])
	var number := parts.size() + 1
	while parts.any(func(part: Variant) -> bool: return part is Dictionary and str(part.get("id", "")) == "part_%d" % number):
		number += 1
	parts.append({"id": "part_%d" % number, "sprite": model.actor_field(actor_index, "sprite", ""),
		"rect": [0, 0, rect[2], rect[3]], "layer": "auto"})
	model.set_actor_field(actor_index, "visual_parts", parts)
	edited.emit()
	rebuild_requested.emit()


func remove_part(index: int) -> void:
	var parts: Array = model.actor_field(actor_index, "visual_parts", []).duplicate(true)
	if index < 0 or index >= parts.size():
		return
	parts.remove_at(index)
	if parts.is_empty():
		model.erase_actor_field(actor_index, "visual_parts")
	else:
		model.set_actor_field(actor_index, "visual_parts", parts)
	edited.emit()
	rebuild_requested.emit()


func _transform(operation: String, value: Variant = null) -> void:
	if Transform.apply(model, selection, operation, value, false):
		edited.emit()
		rebuild_requested.emit()
