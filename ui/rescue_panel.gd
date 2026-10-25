## 救援小游戏面板：练习一次，再依次解开三根线。
## 键盘由主入口路由，唯一按钮与公开 submit 共用判定；暂停和失焦冻结推进。
## close 取消当前等待；完成后读取 success_result，声音交给 feedback 的接收方。
class_name RescuePanel
extends CanvasLayer

signal completed(success: bool)
signal cancelled
signal feedback(kind: StringName)

const PANEL_SIZE: Vector2 = Vector2(244.0, 74.0)
const TOP_PANEL_SIZE: Vector2 = Vector2(244.0, 26.0)
const DIM_COLOR: Color = Color(0.03, 0.04, 0.07, 0.52)
const PANEL_COLOR: Color = Color(0.06, 0.07, 0.10, 0.98)
const EDGE_COLOR: Color = Color(0.34, 0.46, 0.38)
const TITLE_COLOR: Color = Color("#f0e2c0")
const TEXT_COLOR: Color = Color("#c8ccd2")
const MUTED_COLOR: Color = Color("#969da8")
const GOOD_COLOR: Color = Color("#a5dfac")
const BAD_COLOR: Color = Color("#ffb59f")

var model: RescueTiming = RescueTiming.new()
var success_result: bool = false
var allow_background_process: bool = false

var _root: Control
var _title: Label
var _counter: Label
var _status: Label
var _hint: Label
var _footer: Label
var _lines: Array[Label] = []
var _button: Button
var _box: Rect2
var _top_box: Rect2
var _track: Rect2
var _binding_sprite: Sprite2D
var _open: bool = false
var _focus_paused: bool = false
var _window_focused: bool = true
var _held_keys: Dictionary[int, bool] = {}
var _mouse_held: bool = false
var _generation: int = 0


func _ready() -> void:
	setup()
	var window: Window = get_window()
	if not window.focus_entered.is_connected(_on_focus_entered):
		window.focus_entered.connect(_on_focus_entered)
		window.focus_exited.connect(_on_focus_exited)
		get_viewport().size_changed.connect(_layout)
	_window_focused = window.has_focus() or DisplayServer.get_name() == "headless"
	_layout()


func setup() -> void:
	if _root != null:
		return
	layer = 12
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_root = Control.new()
	_root.name = "RescueRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.draw.connect(_draw_panel)
	_root.gui_input.connect(_on_background_input)
	add_child(_root)
	_title = _make_label("Title", 11, TITLE_COLOR)
	_title.text = "解开束缚"
	_counter = _make_label("Counter", 8, MUTED_COLOR)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for index: int in RescueTiming.LINE_COUNT:
		_lines.append(_make_label("Line%d" % index, 8, MUTED_COLOR))
	_status = _make_label("Status", 9, TEXT_COLOR)
	_hint = _make_label("Hint", 8, TEXT_COLOR)
	_footer = _make_label("Footer", 7, MUTED_COLOR)
	_footer.text = "空格 / ENTER / 点击按钮"
	_button = Button.new()
	_button.name = "Submit"
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.add_theme_font_size_override("font_size", 9)
	_button.add_theme_color_override("font_color", TITLE_COLOR)
	_button.gui_input.connect(_on_button_input)
	for style_name: String in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("#283c32") if style_name == "hover" else PANEL_COLOR
		style.border_color = GOOD_COLOR if style_name == "pressed" else EDGE_COLOR
		style.set_border_width_all(1)
		_button.add_theme_stylebox_override(style_name, style)
	_root.add_child(_button)
	_root.hide()
	set_process(false)
	_layout()


func open() -> void:
	setup()
	_generation += 1
	success_result = false
	model.reset()
	_held_keys.clear()
	_mouse_held = false
	_open = true
	_root.show()
	set_process(true)
	_layout()
	_refresh()


func close() -> void:
	_generation += 1
	if not _open:
		return
	_open = false
	model.close()
	set_process(false)
	_root.hide()
	if is_instance_valid(_binding_sprite):
		_binding_sprite.hide()
	_binding_sprite = null
	cancelled.emit()


func set_binding_sprite(binding: Sprite2D) -> void:
	if is_instance_valid(_binding_sprite) and _binding_sprite != binding:
		_binding_sprite.hide()
	_binding_sprite = binding
	_sync_binding()


func is_open() -> bool:
	return _open


func set_focus_paused(value: bool) -> void:
	_focus_paused = value


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		var keycode: int = InputUtil.keycode_of(key_event)
		if keycode == KEY_ESCAPE or key_event.is_action("ui_cancel"):
			return false
		if not key_event.pressed:
			_held_keys.erase(keycode)
		elif _can_act() and not key_event.echo and not _held_keys.has(keycode):
			_held_keys[keycode] = true
			if keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] \
					or key_event.is_action("ui_accept"):
				submit()
	elif event is InputEventAction and event.is_action("ui_accept"):
		var action_event: InputEventAction = event as InputEventAction
		if not action_event.pressed:
			_held_keys.erase(-1)
		elif not _held_keys.has(-1) and _can_act():
			_held_keys[-1] = true
			submit()
	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		_handle_mouse(mouse_event, _button.get_global_rect().has_point(mouse_event.position))
	return true


func submit() -> void:
	if not _can_act():
		return
	var generation: int = _generation
	var verdict: RescueTiming.Verdict = model.submit()
	_refresh()
	if model.state == RescueTiming.State.SUCCEEDED or model.state == RescueTiming.State.FAILED:
		success_result = model.state == RescueTiming.State.SUCCEEDED
		_open = false
		set_process(false)
		_root.hide()
		feedback.emit(&"complete" if success_result else &"mistake")
		if generation == _generation:
			completed.emit(success_result)
	elif verdict != RescueTiming.Verdict.NONE:
		feedback.emit(&"success" if verdict == RescueTiming.Verdict.HIT else &"mistake")


func _can_act() -> bool:
	if not _open or _focus_paused or (not allow_background_process and not _window_focused):
		return false
	return not is_inside_tree() or (not get_tree().paused and can_process())


func _process(delta: float) -> void:
	if _can_act():
		model.advance(delta)
		_root.queue_redraw()


func _exit_tree() -> void:
	close()


func _on_focus_entered() -> void:
	_window_focused = true


func _on_focus_exited() -> void:
	_window_focused = false


func _handle_mouse(event: InputEventMouseButton, over_button: bool) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		_mouse_held = false
	elif not _mouse_held:
		_mouse_held = true
		if over_button:
			submit()


func _on_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse(event as InputEventMouseButton, true)
	_button.accept_event()


func _on_background_input(event: InputEvent) -> void:
	handle_input(event)
	_root.accept_event()


func _make_label(node_name: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_root.add_child(label)
	return label


func _layout() -> void:
	if _root == null:
		return
	var view_size: Vector2 = Vector2(320.0, 180.0)
	if is_inside_tree():
		view_size = get_viewport().get_visible_rect().size
	_root.size = view_size
	var left: float = floor((view_size.x - PANEL_SIZE.x) * 0.5)
	_top_box = Rect2(Vector2(left, 4.0), TOP_PANEL_SIZE)
	_box = Rect2(Vector2(left, view_size.y - PANEL_SIZE.y - 7.0), PANEL_SIZE)
	_track = Rect2(_box.position + Vector2(12.0, 20.0), Vector2(220.0, 10.0))
	_place(_title, _top_box.position + Vector2(12, 3), Vector2(112, 16))
	_place(_counter, _top_box.position + Vector2(120, 6), Vector2(112, 12))
	for index: int in _lines.size():
		_place(_lines[index], _box.position + Vector2(12 + index * 74, 3), Vector2(72, 12))
	_place(_status, _box.position + Vector2(12, 34), Vector2(220, 13))
	_place(_hint, _box.position + Vector2(12, 47), Vector2(220, 11))
	_place(_footer, _box.position + Vector2(12, 60), Vector2(152, 10))
	_place(_button, _box.position + Vector2(168, 51), Vector2(64, 19))
	_root.queue_redraw()


func _place(control: Control, offset: Vector2, control_size: Vector2) -> void:
	control.position = offset
	control.size = control_size


func _refresh() -> void:
	_counter.text = "失误 %d / %d" % [model.mistakes, RescueTiming.ERROR_LIMIT]
	var practice: bool = model.state in [RescueTiming.State.PRACTICE, RescueTiming.State.PRACTICE_FEEDBACK]
	for index: int in _lines.size():
		var done: bool = index < model.line_index
		_lines[index].text = "%d  %s" % [index + 1, "已解开" if done else "待解开"]
		_lines[index].add_theme_color_override("font_color", GOOD_COLOR if done else TEXT_COLOR)
	_status.add_theme_color_override("font_color", TEXT_COLOR)
	_button.text = "解开"
	_hint.text = "标记进入绿色区时按下，空等不扣错"
	match model.state:
		RescueTiming.State.PRACTICE:
			_status.text = "先练习一次：这次失误不计数"
			_button.text = "试一试"
		RescueTiming.State.PRACTICE_FEEDBACK, RescueTiming.State.MISTAKE:
			var hit: bool = model.last_verdict == RescueTiming.Verdict.HIT
			var timing: String = "成功" if hit else ("偏早" if model.last_verdict == RescueTiming.Verdict.EARLY else "偏晚")
			_status.text = ("练习%s，不计错" if practice else "%s，先停一下") % timing
			_status.add_theme_color_override("font_color", GOOD_COLOR if hit else BAD_COLOR)
			_hint.text = "确认后开始第一根线" if practice else "确认后重试当前这根线"
			_button.text = "开始" if practice else "继续"
		RescueTiming.State.RUNNING:
			_status.text = "第 %d 根线 · 绿色区 %d%%" % [model.line_index + 1, roundi(model.window_ratio() * 100.0)]
	_sync_binding()
	_root.queue_redraw()


func _sync_binding() -> void:
	if not is_instance_valid(_binding_sprite):
		_binding_sprite = null
		return
	_binding_sprite.call("set_state", model.line_index)


func _draw_panel() -> void:
	_root.draw_rect(Rect2(Vector2.ZERO, _root.size), DIM_COLOR)
	_root.draw_rect(_top_box, PANEL_COLOR)
	_root.draw_rect(_top_box, EDGE_COLOR, false, 1.0)
	_root.draw_line(_top_box.position + Vector2(12, 21), _top_box.position + Vector2(232, 21), EDGE_COLOR)
	_root.draw_rect(_box, PANEL_COLOR)
	_root.draw_rect(_box, EDGE_COLOR, false, 1.0)
	_root.draw_line(_box.position + Vector2(12, 17), _box.position + Vector2(232, 17), EDGE_COLOR)
	_root.draw_rect(_track, Color("#31373e"))
	var safe_zone: Rect2 = Rect2(_track.position + Vector2(_track.size.x * model.window_start(), 0), Vector2(_track.size.x * model.window_ratio(), _track.size.y))
	_root.draw_rect(safe_zone, Color("#477d56"))
	_root.draw_rect(safe_zone, GOOD_COLOR, false, 1.0)
	var marker_x: float = _track.position.x + model.marker_position() * _track.size.x
	var marker_center := Vector2(marker_x, _track.get_center().y)
	var marker := PackedVector2Array([
		marker_center + Vector2(0, -6),
		marker_center + Vector2(4, 0),
		marker_center + Vector2(0, 6),
		marker_center + Vector2(-4, 0),
	])
	_root.draw_colored_polygon(marker, TITLE_COLOR)
	for index: int in marker.size():
		_root.draw_line(marker[index], marker[(index + 1) % marker.size()], Color("#171b1c"), 1.0)
