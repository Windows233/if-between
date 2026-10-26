## 交互区域与碰撞的独立属性卡；交互区域优先显示，贴图由视觉属性卡负责。
## 局部坐标保持兼容旧地图，写入通过model清理旧的世界reach表示。
## 数值修改只发edited，不重建面板，避免正在编辑的输入框失去焦点。
@tool
extends VBoxContainer

const MapDef := preload("res://core/map_def.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")

signal edited
signal rebuild_requested
signal tool_requested(which: int)

var model
var index := -1
var baseline_row: HFlowContainer
var baseline_spin: SpinBox
var baseline_auto: Button
var _tool_buttons: Dictionary = {}
var _offset: SpinBox
var _syncing := false
var _reach_fields: Array[SpinBox] = []
var _collision_fields: Dictionary = {}


func configure(source, actor_index: int) -> void:
	model = source
	index = actor_index
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	var caption := Label.new()
	caption.text = "交互区域大小（独立于贴图）"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(caption)
	_build_reach(model.actor_dict(index))
	var tools := HFlowContainer.new()
	for entry: Array in [["拉遮挡基线", Canvas.Tool.BASELINE], ["画物件碰撞", Canvas.Tool.COLLISION]]:
		var button := Button.new()
		button.text = entry[0]
		button.toggle_mode = true
		button.disabled = entry[1] == Canvas.Tool.BASELINE and not model.is_cover_actor(index)
		button.set_meta("object_tool", entry[1])
		button.pressed.connect(func() -> void: tool_requested.emit(entry[1]))
		_tool_buttons[entry[1]] = button
		tools.add_child(button)
	add_child(tools)
	_build_baseline()
	var item: Dictionary = model.actor_dict(index)
	if not item.has("collision"):
		var convert := Button.new()
		convert.text = "启用物件独立碰撞与交互"
		convert.tooltip_text = "保留旧地图墙，并把当前交互区转为物件局部坐标。"
		convert.pressed.connect(func() -> void:
			model.use_local_geometry(index)
			edited.emit()
			rebuild_requested.emit())
		add_child(convert)
	else:
		_build_collisions(item)
	var offset_row := HFlowContainer.new()
	var offset_label := Label.new()
	offset_label.text = "排序偏移 Y（相对自动基线）"
	offset_row.add_child(offset_label)
	_offset = _spin(float(item.get("sort_offset", 0)), false)
	_offset.name = "SortOffset"
	_offset.value_changed.connect(func(value: float) -> void:
		if _syncing:
			return
		model.erase_actor_field(index, "cover_y")
		model.set_actor_field(index, "sort_offset", value)
		_refresh_baseline()
		edited.emit())
	offset_row.add_child(_offset)
	add_child(offset_row)
	_refresh_baseline()


func _build_baseline() -> void:
	baseline_row = HFlowContainer.new()
	var label := Label.new()
	label.text = "手动遮挡基线 Y（地图坐标）"
	baseline_row.add_child(label)
	baseline_spin = _spin(model.actor_cover_y(index), false)
	baseline_spin.name = "CoverY"
	baseline_spin.value_changed.connect(func(value: float) -> void:
		if _syncing:
			return
		model.set_actor_field(index, "cover_y", value)
		edited.emit())
	baseline_row.add_child(baseline_spin)
	baseline_auto = Button.new()
	baseline_auto.text = "恢复自动"
	baseline_auto.pressed.connect(func() -> void:
		model.clear_actor_cover_y(index)
		_refresh_baseline()
		edited.emit())
	baseline_row.add_child(baseline_auto)
	add_child(baseline_row)


func _refresh_baseline() -> void:
	_syncing = true
	baseline_spin.value = model.actor_cover_y(index)
	if _offset != null:
		_offset.value = float(model.actor_field(index, "sort_offset", 0))
	_syncing = false
	sync_geometry_fields()


func sync_geometry_fields() -> void:
	var actor := MapDef._actor_from(model.actor_dict(index))
	var local := Rect2(actor.reach.position - actor.rect.position, actor.reach.size)
	_sync_rect_fields(_reach_fields, [local.position.x, local.position.y, local.size.x, local.size.y])
	var shapes: Array = model.actor_field(index, "collision", [])
	for shape_index: Variant in _collision_fields:
		if int(shape_index) < shapes.size() and shapes[shape_index] is Array:
			_sync_rect_fields(_collision_fields[shape_index], shapes[shape_index])


func _sync_rect_fields(fields: Array, values: Array) -> void:
	for component: int in mini(fields.size(), values.size()):
		(fields[component] as SpinBox).set_value_no_signal(float(values[component]))


func set_active_tool(which: int) -> void:
	for tool: int in _tool_buttons:
		(_tool_buttons[tool] as Button).set_pressed_no_signal(tool == which)


func _build_collisions(item: Dictionary) -> void:
	var shapes: Array = item.get("collision", [])
	for shape_index: int in shapes.size():
		var section := _rect_fields("碰撞 #%d" % shape_index, shapes[shape_index],
			func(values: Array) -> void:
				var updated: Array = model.actor_field(index, "collision", []).duplicate(true)
				if shape_index >= updated.size():
					return
				updated[shape_index] = values
				model.set_actor_field(index, "collision", updated)
				_refresh_baseline()
				edited.emit())
		section.name = "Collision%d" % shape_index
		_collision_fields[shape_index] = _fields_in(section)
		var remove := Button.new()
		remove.text = "删除碰撞 #%d" % shape_index
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
		section.add_child(remove)
		add_child(section)
	var add := Button.new()
	add.text = "添加局部碰撞箱"
	add.pressed.connect(func() -> void:
		var updated: Array = model.actor_field(index, "collision", []).duplicate(true)
		var rect: Rect2 = model.rect_of(model.Kind.ACTOR, index)
		updated.append([0, rect.size.y * 0.65, rect.size.x, maxf(1, rect.size.y * 0.35)])
		model.set_actor_field(index, "collision", updated)
		model.set_actor_field(index, "cover", true)
		edited.emit()
		rebuild_requested.emit())
	add_child(add)
	var reference := HFlowContainer.new()
	var label := Label.new()
	label.text = "排序参考碰撞（取上边缘）"
	reference.add_child(label)
	var picker := OptionButton.new()
	picker.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	picker.name = "SortCollider"
	for shape_index: int in shapes.size():
		picker.add_item("碰撞 #%d" % shape_index)
	picker.disabled = shapes.is_empty()
	if not shapes.is_empty():
		picker.select(clampi(int(item.get("sort_collider", 0)), 0, shapes.size() - 1))
	picker.item_selected.connect(func(value: int) -> void:
		model.set_actor_field(index, "sort_collider", value)
		_refresh_baseline()
		edited.emit())
	reference.add_child(picker)
	add_child(reference)


func _build_reach(item: Dictionary) -> void:
	var edit_on_canvas := Button.new()
	edit_on_canvas.name = "EditReachOnCanvas"
	edit_on_canvas.text = "在画布调整交互区（绿框）"
	edit_on_canvas.toggle_mode = true
	edit_on_canvas.set_meta("object_tool", Canvas.Tool.SELECT)
	edit_on_canvas.pressed.connect(func() -> void: tool_requested.emit(Canvas.Tool.SELECT))
	_tool_buttons[Canvas.Tool.SELECT] = edit_on_canvas
	add_child(edit_on_canvas)
	var actor := MapDef._actor_from(item)
	var local_reach: Array = item.get("reach_local", [
		actor.reach.position.x - actor.rect.position.x,
		actor.reach.position.y - actor.rect.position.y,
		actor.reach.size.x, actor.reach.size.y])
	var reach := _rect_fields("交互区域位置与大小（相对贴图左上角）", local_reach, func(values: Array) -> void:
		var rect: Rect2 = model.rect_of(model.Kind.ACTOR, index)
		model.set_interaction_rect(index, Rect2(rect.position + Vector2(values[0], values[1]),
			Vector2(values[2], values[3])))
		edited.emit())
	reach.name = "Reach"
	_reach_fields.assign(_fields_in(reach))
	add_child(reach)
	var note := Label.new()
	note.text = "绿色框决定在哪里可以调查或交谈。修改这里只改变交互区域，不拉伸贴图，也不改变碰撞。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)


func _fields_in(section: Node) -> Array[SpinBox]:
	var fields: Array[SpinBox] = []
	for field_name: String in ["X", "Y", "Width", "Height"]:
		var field := section.find_child(field_name, true, false) as SpinBox
		if field != null:
			fields.append(field)
	return fields


func _rect_fields(title: String, values: Array, changed: Callable) -> VBoxContainer:
	var section := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 2
	section.add_child(grid)
	var fields: Array[SpinBox] = []
	for component: int in 4:
		var field := _spin(float(values[component]), component >= 2)
		field.name = ["X", "Y", "Width", "Height"][component]
		field.prefix = ["x ", "y ", "宽 ", "高 "][component]
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fields.append(field)
		grid.add_child(field)
	for field: SpinBox in fields:
		field.value_changed.connect(func(_value: float) -> void:
			var updated: Array = []
			for input: SpinBox in fields:
				updated.append(input.value)
			changed.call(updated))
	return section


func _spin(value: float, dimension: bool) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = 0.01 if dimension else -1000000
	field.max_value = 1000000
	field.step = 0.01
	field.update_on_text_changed = false
	field.value = value
	field.custom_minimum_size.x = 110
	return field
