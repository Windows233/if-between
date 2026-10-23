## 地图触发面板：编辑矩形与现有事件绑定，不写剧情或演出数据。
## configure(model) 接统一地图模型；所有改动进入模型的同一份撤销历史。
## selection_changed 交给画布联动，edited 交给宿主更新脏标记与绘制。
@tool
extends VBoxContainer

signal selection_changed(index: int)
signal edited
signal bounds_requested(index: int)

const MODES := ["enter_map", "enter", "interact", "click"]
const MODE_LABELS := ["进入地图", "进入区域", "区域内按交互键", "点击区域"]

var model
var selected_index := -1
var _list: ItemList
var _fields: VBoxContainer
var _id: LineEdit
var _event: OptionButton
var _mode: OptionButton
var _enabled: CheckBox
var _once: CheckBox
var _rect: Array[SpinBox] = []
var _condition: TextEdit
var _status: Label
var _syncing := false


func configure(source) -> void:
	model = source
	selected_index = -1
	if _list == null:
		_build()
	refresh()


static func existing_events() -> Array[String]:
	var events: Array[String] = []
	var directory := DirAccess.open("res://data/events")
	if directory != null:
		for file: String in directory.get_files():
			if file.ends_with(".json"):
				events.append(file.trim_suffix(".json"))
	events.sort()
	return events


func refresh() -> void:
	if _list == null or model == null:
		return
	_syncing = true
	_list.clear()
	var triggers := _triggers()
	for raw: Variant in triggers:
		var item: Dictionary = raw if raw is Dictionary else {}
		_list.add_item("%s · %s" % [item.get("id", "（无 id）"), item.get("event", "（未绑定）")])
	selected_index = mini(selected_index, triggers.size() - 1)
	_fields.visible = selected_index >= 0
	if selected_index >= 0:
		_list.select(selected_index)
		_show_selection()
	_syncing = false


func select_trigger(index: int) -> void:
	selected_index = index if index >= 0 and index < _triggers().size() else -1
	refresh()
	selection_changed.emit(selected_index)


func add_trigger(bounds: Rect2 = Rect2(0, 0, 1, 1)) -> int:
	if model == null or not _valid_rect(bounds):
		return -1
	if not model.data.get("triggers", []) is Array:
		_status.text = "triggers 必须是数组，未覆盖原数据。"
		return -1
	var events := existing_events()
	if events.is_empty():
		_status.text = "没有可绑定的现有事件。"
		return -1
	_begin_edit()
	var triggers := _triggers()
	var serial := 1
	var ids: Array[String] = []
	for raw: Variant in triggers:
		if raw is Dictionary:
			ids.append(str(raw.get("id", "")))
	while "trigger_%d" % serial in ids:
		serial += 1
	triggers.append({"id": "trigger_%d" % serial, "rect": _rect_values(bounds),
		"event": events[0], "mode": "enter", "enabled": true, "once": false})
	model.data["triggers"] = triggers
	selected_index = triggers.size() - 1
	_finish_edit()
	selection_changed.emit(selected_index)
	return selected_index


func delete_trigger(index: int = -1) -> bool:
	var target := selected_index if index < 0 else index
	if target < 0 or target >= _triggers().size():
		return false
	_begin_edit()
	model.data.triggers.remove_at(target)
	selected_index = mini(target, _triggers().size() - 1)
	_finish_edit()
	selection_changed.emit(selected_index)
	return true


func set_trigger_rect(index: int, bounds: Rect2) -> bool:
	if not _valid_rect(bounds):
		return false
	return set_trigger_field(index, "rect", _rect_values(bounds))


func trigger_rect(index: int) -> Rect2:
	var item := _item(index)
	var raw: Variant = item.get("rect", [])
	if raw is Array and raw.size() == 4:
		return Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	return Rect2()


func set_trigger_field(index: int, field: String, value: Variant) -> bool:
	if _syncing or index < 0 or index >= _triggers().size() or not _triggers()[index] is Dictionary:
		return false
	if field == "id":
		if not value is String or value.strip_edges().is_empty():
			return false
		for other: int in range(_triggers().size()):
			if other != index and str(_item(other).get("id", "")) == value:
				return false
	elif field == "event":
		if not value in existing_events():
			return false
	elif field == "mode":
		if not value in MODES:
			return false
	elif field in ["once", "enabled"]:
		if not value is bool:
			return false
	elif field == "rect":
		if not value is Array or value.size() != 4:
			return false
		for coordinate: Variant in value:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
				return false
		if value[2] <= 0 or value[3] <= 0:
			return false
	elif field == "condition":
		if value != null and not _valid_condition(value):
			return false
	else:
		return false
	_begin_edit()
	if field == "condition" and value == null:
		_item(index).erase(field)
	else:
		_item(index)[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	_finish_edit()
	return true


static func create_actor_event_selector(source, actor_index: int,
		on_edited: Callable = Callable()) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = "ActorEvent"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	var actors: Array = source.data.get("actors", [])
	if actor_index < 0 or actor_index >= actors.size() or not actors[actor_index] is Dictionary:
		picker.disabled = true
		return picker
	var actor: Dictionary = actors[actor_index]
	_fill_events(picker, str(actor.get("event", "")), true)
	if not actor.get("actions", []).is_empty():
		picker.disabled = true
		picker.tooltip_text = "该物件使用多动作菜单；请在原事件入口中维护各动作绑定。"
	picker.item_selected.connect(func(selected: int) -> void:
		var binding: String = str(picker.get_item_metadata(selected))
		var current: Array = source.data.get("actors", [])
		if actor_index >= current.size() or current[actor_index] != actor:
			return
		if picker.disabled:
			return
		if binding != "" and not binding in existing_events():
			return
		if source._history_index < 0:
			source.reset_history()
		if binding.is_empty():
			source.erase_actor_field(actor_index, "event")
		else:
			source.set_actor_field(actor_index, "event", binding)
			if actor.get("decor", false):
				source.set_actor_field(actor_index, "decor", false)
		source.record_history()
		if on_edited.is_valid():
			on_edited.call())
	return picker


func _build() -> void:
	var caption := Label.new()
	caption.text = "地图触发区域（点使用 1 × 1 矩形）"
	add_child(caption)
	_list = ItemList.new()
	_list.name = "TriggerList"
	_list.custom_minimum_size.y = 110
	_list.item_selected.connect(select_trigger)
	add_child(_list)
	var buttons := HFlowContainer.new()
	for entry: Array in [["AddTrigger", "添加区域", add_trigger], ["DeleteTrigger", "删除区域", delete_trigger]]:
		var button := Button.new()
		button.name = entry[0]
		button.text = entry[1]
		button.pressed.connect(func() -> void: entry[2].call())
		buttons.add_child(button)
	add_child(buttons)
	_fields = VBoxContainer.new()
	add_child(_fields)
	_id = LineEdit.new()
	_id.name = "TriggerId"
	_id.placeholder_text = "区域唯一 id"
	_id.text_submitted.connect(func(value: String) -> void: _change("id", value))
	_id.focus_exited.connect(func() -> void: _change("id", _id.text))
	_fields.add_child(_id)
	_event = OptionButton.new()
	_event.name = "TriggerEvent"
	_event.fit_to_longest_item = false
	_event.item_selected.connect(func(index: int) -> void: _change("event", _event.get_item_metadata(index)))
	_fields.add_child(_event)
	_mode = OptionButton.new()
	_mode.name = "TriggerMode"
	for label: String in MODE_LABELS:
		_mode.add_item(label)
	_mode.item_selected.connect(func(index: int) -> void: _change("mode", MODES[index]))
	_fields.add_child(_mode)
	_build_rect()
	var bounds := Button.new()
	bounds.name = "UseSelectionBounds"
	bounds.text = "从当前选区取矩形"
	bounds.pressed.connect(func() -> void:
		if selected_index >= 0:
			bounds_requested.emit(selected_index))
	_fields.add_child(bounds)
	_enabled = CheckBox.new()
	_enabled.name = "TriggerEnabled"
	_enabled.text = "启用"
	_enabled.toggled.connect(func(value: bool) -> void: _change("enabled", value))
	_fields.add_child(_enabled)
	_once = CheckBox.new()
	_once.name = "TriggerOnce"
	_once.text = "本存档只触发一次"
	_once.toggled.connect(func(value: bool) -> void: _change("once", value))
	_fields.add_child(_once)
	var label := Label.new()
	label.text = "条件参数（Condition JSON，留空为无条件）"
	_fields.add_child(label)
	_condition = TextEdit.new()
	_condition.name = "TriggerCondition"
	_condition.custom_minimum_size.y = 85
	_condition.placeholder_text = '{"var":"flag/name","op":"==","value":true}'
	_fields.add_child(_condition)
	var apply := Button.new()
	apply.name = "ApplyCondition"
	apply.text = "应用条件"
	apply.pressed.connect(_apply_condition)
	_fields.add_child(apply)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


func _build_rect() -> void:
	var row := HFlowContainer.new()
	for index: int in range(4):
		var label := Label.new()
		label.text = ["X", "Y", "宽", "高"][index]
		row.add_child(label)
		var spin := SpinBox.new()
		spin.name = ["TriggerX", "TriggerY", "TriggerWidth", "TriggerHeight"][index]
		spin.min_value = 1 if index >= 2 else -1000000
		spin.max_value = 1000000
		spin.step = 1
		spin.custom_minimum_size.x = 85
		spin.value_changed.connect(func(_value: float) -> void:
			if not _syncing:
				set_trigger_rect(selected_index, Rect2(_rect[0].value, _rect[1].value, _rect[2].value, _rect[3].value)))
		_rect.append(spin)
		row.add_child(spin)
	_fields.add_child(row)


func _show_selection() -> void:
	var item := _item(selected_index)
	_id.text = str(item.get("id", ""))
	_fill_events(_event, str(item.get("event", "")))
	_mode.select(MODES.find(str(item.get("mode", "enter"))))
	_enabled.set_pressed_no_signal(bool(item.get("enabled", true)))
	_once.set_pressed_no_signal(bool(item.get("once", false)))
	var bounds := trigger_rect(selected_index)
	var coordinates := _rect_values(bounds)
	for index: int in range(4):
		_rect[index].set_value_no_signal(coordinates[index])
	_condition.text = JSON.stringify(item.condition, "  ") if item.has("condition") else ""


static func _fill_events(picker: OptionButton, current: String, allow_empty: bool = false) -> void:
	picker.clear()
	if allow_empty:
		picker.add_item("（不绑定）")
		picker.set_item_metadata(0, "")
	for event_id: String in existing_events():
		picker.add_item(event_id)
		var index := picker.item_count - 1
		picker.set_item_metadata(index, event_id)
		if event_id == current:
			picker.select(index)
	if current == "" and allow_empty:
		picker.select(0)
	elif not current in existing_events():
		picker.add_item("（事件缺失：%s）" % current)
		var missing := picker.item_count - 1
		picker.set_item_metadata(missing, current)
		picker.set_item_disabled(missing, true)
		picker.select(missing)


func _apply_condition() -> void:
	var text := _condition.text.strip_edges()
	if text.is_empty():
		_change("condition", null)
		return
	var parser := JSON.new()
	if parser.parse(text) != OK or not _valid_condition(parser.data):
		_status.text = "条件无效，未改动地图。支持 var/op/value、exists、all、any、not。"
		return
	_change("condition", parser.data)


func _change(field: String, value: Variant) -> void:
	if _syncing:
		return
	if not set_trigger_field(selected_index, field, value):
		_status.text = "未应用：检查 id 唯一性、现有事件和参数格式。"


func _begin_edit() -> void:
	if model._history_index < 0:
		model.reset_history()


func _finish_edit() -> void:
	model.record_history()
	_status.text = ""
	refresh()
	edited.emit()


func _triggers() -> Array:
	if model == null:
		return []
	var raw: Variant = model.data.get("triggers", [])
	return raw if raw is Array else []


func _item(index: int) -> Dictionary:
	var triggers := _triggers()
	if index < 0 or index >= triggers.size() or not triggers[index] is Dictionary:
		return {}
	return triggers[index]


static func _valid_rect(bounds: Rect2) -> bool:
	return bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.x > 0 and bounds.size.y > 0


static func _rect_values(bounds: Rect2) -> Array:
	var values: Array = []
	for coordinate: float in [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]:
		values.append(int(coordinate) if coordinate == round(coordinate) else coordinate)
	return values


static func _valid_condition(raw: Variant, depth: int = 0) -> bool:
	if not raw is Dictionary or depth > 32:
		return false
	var fields := 0
	for field: String in ["all", "any", "not", "exists", "var"]:
		fields += int(raw.has(field))
	if fields != 1:
		return false
	for field: String in ["all", "any"]:
		if raw.has(field):
			if not raw[field] is Array:
				return false
			for child: Variant in raw[field]:
				if not _valid_condition(child, depth + 1):
					return false
			return true
	if raw.has("not"):
		return _valid_condition(raw["not"], depth + 1)
	var key: Variant = raw.get("exists", raw.get("var"))
	return (key is String or key is StringName) and not str(key).strip_edges().is_empty() \
		and (raw.has("exists") or (raw.has("value") and raw.get("op", "==") \
		in ["==", "=", "eq", "!=", "<>", "ne", ">", "gt", ">=", "ge", "<", "lt", "<=", "le"]))
