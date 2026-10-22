@tool
extends VBoxContainer

const MapDef := preload("res://core/map_def.gd")

signal edited
signal rebuild_requested

var model
var index := -1


func configure(source, actor_index: int) -> void:
	model = source
	index = actor_index
	var caption := Label.new()
	caption.text = "物件局部属性（相对贴图左上角；移动、复制时一起跟随）"
	add_child(caption)
	var item: Dictionary = model.actor_dict(index)
	if not item.has("collision"):
		var convert := Button.new()
		convert.text = "启用物件独立碰撞与交互（不会移除旧地图墙）"
		convert.pressed.connect(func() -> void:
			model.use_local_geometry(index)
			edited.emit()
			rebuild_requested.emit())
		add_child(convert)
		return
	var shapes: Array = item.get("collision", [])
	for shape_index: int in shapes.size():
		var row := _rect_fields("碰撞 #%d" % shape_index, shapes[shape_index],
			func(values: Array) -> void:
				var updated: Array = model.actor_field(index, "collision", []).duplicate(true)
				updated[shape_index] = values
				model.set_actor_field(index, "collision", updated)
				edited.emit())
		var remove := Button.new()
		remove.text = "删除"
		remove.pressed.connect(func() -> void:
			var updated: Array = model.actor_field(index, "collision", []).duplicate(true)
			updated.remove_at(shape_index)
			var reference := int(model.actor_field(index, "sort_collider", 0))
			if reference >= shape_index:
				model.set_actor_field(index, "sort_collider", maxi(0, reference - 1))
			model.set_actor_field(index, "collision", updated)
			if updated.is_empty():
				model.set_actor_field(index, "cover", false)
			edited.emit()
			rebuild_requested.emit())
		row.add_child(remove)
		add_child(row)
	var add := Button.new()
	add.text = "添加局部碰撞箱"
	add.pressed.connect(func() -> void:
		var updated: Array = model.actor_field(index, "collision", []).duplicate(true)
		var rect: Rect2 = model.rect_of(model.Kind.ACTOR, index)
		updated.append([0, roundf(rect.size.y * 0.65), rect.size.x, maxf(1, roundf(rect.size.y * 0.35))])
		model.set_actor_field(index, "collision", updated)
		model.set_actor_field(index, "cover", true)
		edited.emit()
		rebuild_requested.emit())
	add_child(add)
	var reference := HBoxContainer.new()
	var label := Label.new()
	label.text = "自动排序参考（取上边缘）"
	reference.add_child(label)
	var picker := OptionButton.new()
	for shape_index: int in shapes.size():
		picker.add_item("碰撞 #%d" % shape_index)
	if not shapes.is_empty():
		picker.select(clampi(int(item.get("sort_collider", 0)), 0, shapes.size() - 1))
	picker.item_selected.connect(func(value: int) -> void:
		model.set_actor_field(index, "sort_collider", value)
		edited.emit())
	reference.add_child(picker)
	add_child(reference)
	var actor := MapDef._actor_from(item)
	var local_reach: Array = item.get("reach_local", [
		actor.reach.position.x - actor.rect.position.x,
		actor.reach.position.y - actor.rect.position.y,
		actor.reach.size.x,
		actor.reach.size.y])
	add_child(_rect_fields("交互区", local_reach, func(values: Array) -> void:
		model.set_actor_field(index, "reach_local", values)
		edited.emit()))
	var offset_row := HBoxContainer.new()
	var offset_label := Label.new()
	offset_label.text = "手动排序偏移 Y（0 = 自动）"
	offset_row.add_child(offset_label)
	var offset := _spin(float(item.get("sort_offset", 0)), false)
	offset.value_changed.connect(func(value: float) -> void:
		model.erase_actor_field(index, "cover_y")
		model.set_actor_field(index, "sort_offset", value)
		edited.emit())
	offset_row.add_child(offset)
	add_child(offset_row)
	if item.has("cover_y"):
		var legacy := Label.new()
		legacy.text = "当前保留旧绝对基线；点上方「恢复自动」后使用碰撞上边缘。"
		add_child(legacy)


func _rect_fields(title: String, values: Array, changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	row.add_child(label)
	var fields: Array[SpinBox] = []
	for component: int in 4:
		var field := _spin(float(values[component]), component >= 2)
		field.prefix = ["x ", "y ", "宽 ", "高 "][component]
		fields.append(field)
		row.add_child(field)
	for field: SpinBox in fields:
		field.value_changed.connect(func(_value: float) -> void:
			var updated: Array = []
			for input: SpinBox in fields:
				updated.append(input.value)
			changed.call(updated))
	return row


func _spin(value: float, dimension: bool) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = 1 if dimension else -10000
	field.max_value = 10000
	field.value = value
	field.step = 1
	field.custom_minimum_size.x = 94
	return field
