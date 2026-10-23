## 地图画布快捷键：只匹配传入事件，配置保存在 user://。
##
## 不注册 InputMap，不发送系统按键；冲突和写入失败均保留原配置。
##
## 设置面板在 map_preview_options.gd 的 ShortcutsPanel，由 dock 按需挂载。
@tool
extends RefCounted

signal changed

const DEFAULT_PATH := "user://if_map_editor_shortcuts.cfg"
const DEFAULTS := {
	"undo": [KEY_Z | KEY_MASK_CTRL],
	"redo": [KEY_Y | KEY_MASK_CTRL, KEY_Z | KEY_MASK_CTRL | KEY_MASK_SHIFT],
	"copy": [KEY_C | KEY_MASK_CTRL],
	"paste": [KEY_V | KEY_MASK_CTRL],
	"duplicate": [KEY_D | KEY_MASK_CTRL],
	"delete": [KEY_DELETE],
	"frame_selection": [KEY_F],
	"cancel": [KEY_ESCAPE],
}
const LABELS := {"undo": "撤销", "redo": "重做", "copy": "复制", "paste": "粘贴",
	"duplicate": "复制副本", "delete": "删除", "frame_selection": "聚焦选中", "cancel": "取消操作"}

var config_path := DEFAULT_PATH
var capture_action := ""
var capture_slot := 0
var last_error := ""
var _bindings: Dictionary = DEFAULTS.duplicate(true)


func _init(path: String = DEFAULT_PATH) -> void:
	config_path = path


static func key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code & KEY_CODE_MASK
	event.ctrl_pressed = (code & KEY_MASK_CTRL) != 0
	event.shift_pressed = (code & KEY_MASK_SHIFT) != 0
	event.alt_pressed = (code & KEY_MASK_ALT) != 0
	event.meta_pressed = (code & KEY_MASK_META) != 0
	return event


static func event_code(event: InputEventKey) -> int:
	var code: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	if code == KEY_NONE or code in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		return 0
	if event.ctrl_pressed:
		code |= KEY_MASK_CTRL
	if event.shift_pressed:
		code |= KEY_MASK_SHIFT
	if event.alt_pressed:
		code |= KEY_MASK_ALT
	if event.meta_pressed:
		code |= KEY_MASK_META
	return code


func actions() -> Array:
	return DEFAULTS.keys()


func get_bindings(action: String) -> Array[InputEventKey]:
	var result: Array[InputEventKey] = []
	for code: int in _bindings.get(action, []):
		result.append(key_event(code))
	return result


func get_shortcut(action: String) -> Shortcut:
	var shortcut := Shortcut.new()
	for event: InputEventKey in get_bindings(action):
		shortcut.events.append(event)
	return shortcut


func action_for(event: InputEvent) -> String:
	if not event is InputEventKey or not event.pressed or event.echo:
		return ""
	var code := event_code(event)
	for action: String in _bindings:
		if code != 0 and code in _bindings[action]:
			return action
	return ""


func conflict_for(event: InputEventKey, except_action := "") -> String:
	var code := event_code(event)
	for action: String in _bindings:
		if action != except_action and code in _bindings[action]:
			return action
	return ""


func set_binding(action: String, events: Array, persist := true) -> String:
	if not DEFAULTS.has(action):
		return "未知动作：" + action
	var codes: Array[int] = []
	for event: Variant in events:
		if not event is InputEventKey or event_code(event) == 0:
			return "请按一个普通按键，可组合 Ctrl / Shift / Alt / Meta。"
		var conflict := conflict_for(event, action)
		if not conflict.is_empty():
			return "快捷键冲突：%s 已用于「%s」。" % [event.as_text_keycode(), LABELS[conflict]]
		var code := event_code(event)
		if codes.has(code):
			return "同一动作的快捷键不能重复。"
		codes.append(code)
	var previous: Array = _bindings[action]
	_bindings[action] = codes
	if persist:
		var error := save_settings()
		if error != OK:
			_bindings[action] = previous
			return "快捷键保存失败：%s" % error_string(error)
	changed.emit()
	return ""


func save_settings() -> Error:
	var config := ConfigFile.new()
	for action: String in _bindings:
		config.set_value("shortcuts", action, _bindings[action])
	return config.save(config_path)


func load_settings() -> Error:
	var config := ConfigFile.new()
	var error := config.load(config_path)
	if error != OK:
		return error
	var candidate := DEFAULTS.duplicate(true)
	var seen: Dictionary = {}
	for action: String in candidate:
		var values: Variant = config.get_value("shortcuts", action, candidate[action])
		if not values is Array:
			return ERR_INVALID_DATA
		candidate[action] = []
		for code: Variant in values:
			if not code is int or code == 0 or event_code(key_event(code)) != code or seen.has(code):
				return ERR_INVALID_DATA
			candidate[action].append(code)
			seen[code] = action
	_bindings = candidate
	changed.emit()
	return OK


func restore_defaults(persist := true) -> Error:
	var previous := _bindings
	_bindings = DEFAULTS.duplicate(true)
	var error := save_settings() if persist else OK
	if error != OK:
		_bindings = previous
		return error
	cancel_capture()
	changed.emit()
	return OK


func begin_capture(action: String, slot := 0) -> bool:
	if not DEFAULTS.has(action) or slot < 0 or slot > _bindings[action].size():
		return false
	capture_action = action
	capture_slot = slot
	last_error = ""
	return true


func cancel_capture() -> void:
	capture_action = ""
	last_error = ""


func capture_event(event: InputEvent, persist := true) -> bool:
	if capture_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return false
	if event_code(event) == KEY_ESCAPE:
		cancel_capture()
		return true
	if event_code(event) == 0:
		return false
	var events := get_bindings(capture_action)
	if capture_slot == events.size():
		events.append(event)
	else:
		events[capture_slot] = event
	last_error = set_binding(capture_action, events, persist)
	if last_error.is_empty():
		capture_action = ""
	return true
