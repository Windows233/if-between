## 编辑器试走状态、出生点和地图比较选项；configure(model) 只读取模型。
##
## preview_requested(options) / compare_requested(map_id, options) 交给 dock 集成。
##
## ShortcutsPanel 可独立挂载；所有按键捕获都来自当前 GUI 的输入事件。
@tool
extends VBoxContainer

signal preview_requested(options: Dictionary)
signal compare_requested(map_id: String, options: Dictionary)

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Preview := preload("res://addons/if_map_editor/map_object_preview.gd")
const Shortcuts := preload("res://addons/if_map_editor/map_shortcuts.gd")


class ShortcutsPanel:
	extends VBoxContainer

	var shortcuts: RefCounted
	var _message: Label
	var _buttons: Dictionary = {}

	func configure(module: RefCounted = null) -> void:
		if shortcuts != null and shortcuts.changed.is_connected(_refresh):
			shortcuts.changed.disconnect(_refresh)
		shortcuts = module if module != null else Shortcuts.new()
		var error: int = shortcuts.load_settings() if module == null else OK
		for child: Node in get_children():
			remove_child(child)
			child.queue_free()
		_buttons.clear()
		var title := Label.new()
		title.text = "画布快捷键（仅本编辑器）"
		add_child(title)
		_message = Label.new()
		_message.name = "ShortcutMessage"
		_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_message.text = "点按键按钮后直接输入组合键；Esc 取消。配置保存在 user://。"
		add_child(_message)
		if error != OK and error != ERR_FILE_NOT_FOUND:
			_message.text = "快捷键配置读取失败，保留默认值：" + error_string(error)
		for action: String in shortcuts.actions():
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = Shortcuts.LABELS[action]
			label.custom_minimum_size.x = 88
			row.add_child(label)
			var buttons: Array[Button] = []
			for slot: int in maxi(shortcuts.get_bindings(action).size(), 2):
				var button := Button.new()
				button.name = "%s_%d" % [action, slot]
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.pressed.connect(_begin_capture.bind(action, slot))
				row.add_child(button)
				buttons.append(button)
			_buttons[action] = buttons
			add_child(row)
		var reset := Button.new()
		reset.name = "RestoreShortcuts"
		reset.text = "恢复全部默认快捷键"
		reset.pressed.connect(_restore)
		add_child(reset)
		shortcuts.changed.connect(_refresh)
		_refresh()

	func _begin_capture(action: String, slot: int) -> void:
		if shortcuts.begin_capture(action, slot):
			_message.text = "正在设置「%s」：按组合键，Esc 取消。" % Shortcuts.LABELS[action]
			_refresh()

	func _input(event: InputEvent) -> void:
		if shortcuts == null or not is_visible_in_tree() or not get_window().has_focus():
			return
		if shortcuts.capture_event(event):
			get_viewport().set_input_as_handled()
			_message.text = shortcuts.last_error if not shortcuts.last_error.is_empty() else "快捷键已更新；Esc 可取消正在进行的捕获。"
			_refresh()

	func _restore() -> void:
		var error: int = shortcuts.restore_defaults()
		_message.text = "已恢复默认快捷键。" if error == OK else "恢复失败：" + error_string(error)
		_refresh()

	func _refresh() -> void:
		for action: String in _buttons:
			var bindings: Array = shortcuts.get_bindings(action)
			var buttons: Array = _buttons[action]
			for slot: int in buttons.size():
				var button: Button = buttons[slot]
				button.text = bindings[slot].as_text_keycode() if slot < bindings.size() else "添加按键"
				button.disabled = slot > bindings.size()
				if shortcuts.capture_action == action and shortcuts.capture_slot == slot:
					button.text = "请按键…"


var _model: RefCounted
var _flags: Dictionary = {}
var _hints: Dictionary = {}
var flag_rows: Dictionary = {}
var _flag_list: VBoxContainer
var _spawn: OptionButton
var _compare_map: OptionButton
var _compare_spawn: OptionButton
var _show_ranges: CheckBox
var _message: Label
var _flag_name: LineEdit


func configure(model: RefCounted) -> void:
	_model = model
	_flags = {}
	_hints = existing_flags(model.data)
	flag_rows.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "状态试走与地图比较"
	add_child(title)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.text = "勾选变量名才向预览设置状态；未勾选表示变量不存在。条件、碰撞与交互使用游戏原判定。"
	add_child(_message)
	_spawn = _picker("Spawn", "试走出生点")
	_fill_spawns(_spawn, model.data)
	_show_ranges = CheckBox.new()
	_show_ranges.name = "ShowRanges"
	_show_ranges.text = "显示碰撞与交互区"
	add_child(_show_ranges)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 160
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_flag_list = VBoxContainer.new()
	_flag_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_flag_list)
	for key: String in _hints:
		_add_flag_row(key, _hints[key])
	var custom_row := HBoxContainer.new()
	_flag_name = LineEdit.new()
	_flag_name.name = "CustomFlagName"
	_flag_name.placeholder_text = "新增状态变量名"
	_flag_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_row.add_child(_flag_name)
	var add := Button.new()
	add.text = "添加状态"
	add.name = "AddFlag"
	add.pressed.connect(_add_custom_flag)
	custom_row.add_child(add)
	add_child(custom_row)
	var preview := Button.new()
	preview.name = "RequestPreview"
	preview.text = "用当前未保存布局试走"
	preview.pressed.connect(func() -> void: preview_requested.emit(get_options()))
	add_child(preview)
	_compare_map = _picker("CompareMap", "只读比较地图（含昼夜版本）")
	var maps := Model.list_maps()
	if not maps.has(str(model.data.get("id", model.map_id))):
		maps.append(str(model.data.get("id", model.map_id)))
	for map_id: String in maps:
		var suffix := "（夜）" if map_id.ends_with("_night") else ""
		_compare_map.add_item(map_id + suffix)
		_compare_map.set_item_metadata(_compare_map.item_count - 1, map_id)
	_compare_spawn = _picker("CompareSpawn", "比较侧出生点")
	_compare_map.item_selected.connect(_comparison_selected)
	var current_id: String = str(model.data.get("id", model.map_id))
	var counterpart := current_id.trim_suffix("_night") if current_id.ends_with("_night") else current_id + "_night"
	var preferred := maps.find(counterpart)
	_compare_map.select(preferred if preferred >= 0 else maxi(maps.find(current_id), 0))
	_comparison_selected(_compare_map.selected)
	var compare := Button.new()
	compare.name = "RequestCompare"
	compare.text = "与当前布局并列比较（只读）"
	compare.pressed.connect(_request_compare)
	add_child(compare)


func _picker(node_name: String, caption: String) -> OptionButton:
	var label := Label.new()
	label.text = caption
	add_child(label)
	var picker := OptionButton.new()
	picker.name = node_name
	picker.fit_to_longest_item = false
	add_child(picker)
	return picker


static func _fill_spawns(picker: OptionButton, data: Dictionary) -> void:
	picker.clear()
	picker.add_item("默认出生点")
	picker.set_item_metadata(0, "")
	var spawns: Variant = data.get("spawns", {})
	if spawns is Dictionary:
		for key: Variant in spawns:
			picker.add_item(str(key))
			picker.set_item_metadata(picker.item_count - 1, str(key))


static func existing_flags(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	_collect_flags(data, result)
	return result


static func _collect_flags(value: Variant, result: Dictionary) -> void:
	if value is Dictionary:
		if value.has("if"):
			var condition := Condition.from_dictionary(value["if"])
			if condition != null:
				_collect_condition(condition, result)
		if not str(value.get("blocked_by", "")).is_empty():
			result[str(value.blocked_by)] = true
		for child: Variant in value.values():
			_collect_flags(child, result)
	elif value is Array:
		for child: Variant in value:
			_collect_flags(child, result)


static func _collect_condition(condition: Condition, result: Dictionary) -> void:
	for key: StringName in condition.referenced_variables():
		if not result.has(str(key)):
			result[str(key)] = true
	if condition.kind == Condition.Kind.COMPARE:
		result[str(condition.variable)] = condition.value
	for child: Condition in condition.children:
		_collect_condition(child, result)


func _add_flag_row(key: String, initial: Variant) -> void:
	var row := VBoxContainer.new()
	var enabled := CheckBox.new()
	enabled.text = key
	enabled.tooltip_text = key + "：勾选后设置；取消勾选表示不存在。"
	row.add_child(enabled)
	var fields := HBoxContainer.new()
	row.add_child(fields)
	var type := OptionButton.new()
	for label: String in ["布尔", "数字", "文本", "null"]:
		type.add_item(label)
	type.select(_type_index(initial))
	fields.add_child(type)
	var boolean := CheckBox.new()
	boolean.text = "为真"
	boolean.set_pressed_no_signal(bool(initial) if initial is bool else true)
	fields.add_child(boolean)
	var number := SpinBox.new()
	number.min_value = -1000000000
	number.max_value = 1000000000
	number.step = 0.1
	number.allow_greater = true
	number.allow_lesser = true
	number.value = float(initial) if initial is int or initial is float else 0.0
	fields.add_child(number)
	var text := LineEdit.new()
	text.placeholder_text = "状态值"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = str(initial) if initial is String else ""
	fields.add_child(text)
	flag_rows[key] = {"enabled": enabled, "type": type, "boolean": boolean, "number": number, "text": text}
	_flag_list.add_child(row)
	enabled.toggled.connect(func(_value: bool) -> void: _read_flag(key))
	type.item_selected.connect(func(_index: int) -> void: _read_flag(key))
	boolean.toggled.connect(func(_value: bool) -> void: _read_flag(key))
	number.value_changed.connect(func(_value: float) -> void: _read_flag(key))
	text.text_changed.connect(func(_value: String) -> void: _read_flag(key))
	_read_flag(key)


static func _type_index(value: Variant) -> int:
	if value is bool:
		return 0
	if value is int or value is float:
		return 1
	return 3 if value == null else 2


func _read_flag(key: String) -> void:
	var row: Dictionary = flag_rows[key]
	row.boolean.visible = row.type.selected == 0
	row.number.visible = row.type.selected == 1
	row.text.visible = row.type.selected == 2
	if not row.enabled.button_pressed:
		_flags.erase(key)
		return
	match row.type.selected:
		0: _flags[key] = row.boolean.button_pressed
		1: _flags[key] = row.number.value
		2: _flags[key] = row.text.text
		3: _flags[key] = null


func set_flag(key: String, value: Variant, enabled := true) -> void:
	if not flag_rows.has(key):
		_add_flag_row(key, value)
	var row: Dictionary = flag_rows[key]
	row.type.select(_type_index(value))
	row.enabled.set_pressed_no_signal(enabled)
	match _type_index(value):
		0: row.boolean.set_pressed_no_signal(value)
		1: row.number.set_value_no_signal(value)
		2: row.text.text = value
	_read_flag(key)


func _add_custom_flag() -> void:
	var key := _flag_name.text.strip_edges()
	if key.is_empty():
		_message.text = "请先填写状态变量名。"
		return
	if not flag_rows.has(key):
		set_flag(key, true)
	_flag_name.clear()


func get_options() -> Dictionary:
	return {"flags": _flags.duplicate(true), "spawn": str(_spawn.get_selected_metadata()),
		"show_ranges": _show_ranges.button_pressed}


func comparison_data(map_id: String) -> Dictionary:
	if map_id == str(_model.data.get("id", _model.map_id)):
		return _model.data.duplicate(true)
	if not Model.list_maps().has(map_id):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % map_id))
	return value.duplicate(true) if value is Dictionary else {}


func _comparison_selected(index: int) -> void:
	var data := comparison_data(str(_compare_map.get_item_metadata(index)))
	_fill_spawns(_compare_spawn, data)
	var hints := existing_flags(data)
	for key: String in hints:
		if not flag_rows.has(key):
			_add_flag_row(key, hints[key])


func _request_compare() -> void:
	var map_id := str(_compare_map.get_selected_metadata())
	if comparison_data(map_id).is_empty():
		_message.text = "比较地图读取失败：" + map_id
		return
	var settings := get_options()
	settings["read_only"] = true
	settings["spawn"] = str(_compare_spawn.get_selected_metadata())
	compare_requested.emit(map_id, settings)


func create_comparison(map_id: String, settings: Dictionary = {}) -> HSplitContainer:
	var other := comparison_data(map_id)
	if other.is_empty():
		return null
	return Preview.create_comparison(_model.data, other, get_options(), settings)
