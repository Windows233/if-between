## 物件的真实绘制层与同层顺序，独立于场景树的编组整理顺序。
## 只改所选物件的draw_layer/draw_order，不移动几何或改其它物件。
## edited交给主面板记录撤销；sync_fields仅刷新界面，不回写地图。
@tool
extends VBoxContainer

signal edited
signal overlay_selected

const LAYERS := ["", "back", "auto", "front", "above_overlay"]
const CAPTIONS := ["沿用原设置（含视觉部件）", "地面／人物后方", "自动遮挡（随人物站位）", "人物之上／整张前景之下", "整张前景之上"]

var model
var actor_index := -1
var selection: Array[int] = []
var _layer_picker: OptionButton
var _order: SpinBox
var _overlay_path: Label
var _select_overlay: Button
var _mutating_controls: Array[Control] = []


func configure(source, index: int, selected: Array[int] = []) -> void:
	model = source
	actor_index = index
	selection.assign(selected if not selected.is_empty() else [index])
	name = "DrawLayerInspector"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label("图层上下关系（会保存到地图）"))
	_layer_picker = OptionButton.new()
	_layer_picker.name = "DrawLayerPicker"
	_layer_picker.fit_to_longest_item = false
	_layer_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for caption: String in CAPTIONS:
		_layer_picker.add_item(caption)
	_layer_picker.item_selected.connect(_on_layer_selected)
	add_child(_layer_picker)
	_mutating_controls.append(_layer_picker)
	var row := HFlowContainer.new()
	var order_label := _label("同层顺序")
	order_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(order_label)
	_order = SpinBox.new()
	_order.name = "DrawOrder"
	_order.min_value = -2147483648
	_order.max_value = 2147483647
	_order.step = 1
	_order.update_on_text_changed = false
	_order.custom_minimum_size.x = 110
	_order.value_changed.connect(_on_order_changed)
	row.add_child(_order)
	_mutating_controls.append(_order)
	add_child(row)
	var buttons := HFlowContainer.new()
	for entry: Array in [["顺序 +1", "LayerBringForward", 1], ["顺序 −1", "LayerSendBackward", -1],
			["同层置顶", "LayerToFront", 2], ["同层置底", "LayerToBack", -2]]:
		var button := Button.new()
		button.name = entry[1]
		button.text = entry[0]
		button.pressed.connect(_change_order.bind(int(entry[2])))
		buttons.add_child(button)
		_mutating_controls.append(button)
	add_child(buttons)
	var above := Button.new()
	above.name = "AboveOverlay"
	above.text = "放到整张前景之上"
	above.pressed.connect(_set_layer.bind("above_overlay"))
	add_child(above)
	_mutating_controls.append(above)
	add_child(_label("同一绘制层内，顺序越大越靠前。自动遮挡仍会随人物站位改变；这与场景树中的编组排序不同。"))
	_overlay_path = _label("")
	_overlay_path.name = "OverlayPath"
	add_child(_overlay_path)
	_select_overlay = Button.new()
	_select_overlay.name = "SelectOverlay"
	_select_overlay.text = "查看整张前景层"
	_select_overlay.pressed.connect(func() -> void: overlay_selected.emit())
	add_child(_select_overlay)
	sync_fields()


func sync_fields() -> void:
	if model == null or _layer_picker == null or not _valid_index():
		return
	var value := str(model.actor_field(actor_index, "draw_layer", ""))
	_layer_picker.select(maxi(LAYERS.find(value), 0))
	_order.set_value_no_signal(float(model.actor_field(actor_index, "draw_order", 0)))
	var overlay := str(model.data.get("overlay", ""))
	_overlay_path.text = "整张前景：" + (overlay.get_file() if not overlay.is_empty() else "无")
	_overlay_path.tooltip_text = overlay
	_select_overlay.disabled = overlay.is_empty()
	var readonly := selection.size() != 1
	for control: Control in _mutating_controls:
		# 主面板可能因锁定把控件设为只读，刷新不能把这层保护重新打开。
		if readonly and control is SpinBox:
			(control as SpinBox).editable = false
		elif readonly and control is BaseButton:
			(control as BaseButton).disabled = true


func _valid_index() -> bool:
	return actor_index >= 0 and actor_index < model.count(model.Kind.ACTOR)


func _can_edit() -> bool:
	return model != null and selection.size() == 1 and selection[0] == actor_index and _valid_index()


func _on_layer_selected(index: int) -> void:
	if index >= 0 and index < LAYERS.size():
		_set_layer(LAYERS[index])


func _set_layer(value: String) -> void:
	if not _can_edit() or value not in LAYERS:
		return
	var previous := str(model.actor_field(actor_index, "draw_layer", ""))
	if previous == value:
		return
	if value.is_empty():
		model.erase_actor_field(actor_index, "draw_layer")
	else:
		model.set_actor_field(actor_index, "draw_layer", value)
	sync_fields()
	edited.emit()


func _on_order_changed(value: float) -> void:
	_set_order(int(value))


func _set_order(value: int) -> void:
	if not _can_edit() or int(model.actor_field(actor_index, "draw_order", 0)) == value:
		return
	model.set_actor_field(actor_index, "draw_order", value)
	sync_fields()
	edited.emit()


func _change_order(operation: int) -> void:
	if not _can_edit():
		return
	var current := int(model.actor_field(actor_index, "draw_order", 0))
	var target := current + operation
	if absi(operation) == 2:
		var edge := current
		for index: int in model.count(model.Kind.ACTOR):
			var value := int(model.actor_field(index, "draw_order", 0))
			edge = maxi(edge, value) if operation > 0 else mini(edge, value)
		target = edge + (1 if operation > 0 else -1)
	_set_order(target)


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
