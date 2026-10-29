class_name ChaseOverlay
extends CanvasLayer

signal qte_finished(key: StringName, success: bool)
signal wrong_key_pressed(key: StringName)
signal feedback(kind: StringName)

enum Phase { IDLE, WARNING, ACTIVE }

const WARNING_DURATION_USEC: int = 300_000
const Q_DURATION_USEC: int = 1_400_000
const E_DURATION_USEC: int = 1_200_000
const WRONG_FLASH_USEC: int = 120_000
const PANEL_SIZE := Vector2(58.0, 62.0)

const PANEL_COLOR := Color(0.035, 0.04, 0.05, 0.84)
const EDGE_COLOR := Color("#596456")
const WARNING_COLOR := Color("#e7bd70")
const ACTIVE_COLOR := Color("#f0e2c0")
const TRACK_COLOR := Color("#454d4b")
const WRONG_COLOR := Color("#ff8f7d")
const MUTED_COLOR := Color("#c8ccd2")

const FREEZE_EXTERNAL: int = 1
const FREEZE_FOCUS: int = 2
const FREEZE_PAUSE: int = 4

var _root: Control
var _caption: Label
var _key_label: Label
var _timer_label: Label

var _phase: Phase = Phase.IDLE
var _expected_key: StringName = &""
var _active_duration_usec: int = 0
var _warning_started_usec: int = 0
var _warning_until_usec: int = 0
var _active_until_usec: int = 0
var _wrong_flash_until_usec: int = 0
var _freeze_reasons: int = 0
var _frozen_at_usec: int = 0
var _panel_rect := Rect2()
var _ring_center := Vector2()
## The C duel shares the countdown while using its own prompt and framing.
var _duel := false
var _strict_input := false
var _direction_mode := false


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	set_process(false)

	if DisplayServer.get_name() != "headless":
		var window: Window = get_window()
		window.focus_exited.connect(_on_window_focus_exited)
		window.focus_entered.connect(_on_window_focus_entered)
		if not window.has_focus():
			_set_freeze_reason(FREEZE_FOCUS, true)


func start_qte(key: StringName, duel := false, strict_input := false) -> bool:
	if not is_inside_tree() or _phase != Phase.IDLE:
		return false
	if key != &"q" and key != &"e":
		return false

	var now_usec: int = _now_usec()
	_duel = duel
	_strict_input = strict_input
	_direction_mode = false
	_expected_key = key
	_active_duration_usec = Q_DURATION_USEC if key == &"q" else E_DURATION_USEC
	_warning_started_usec = now_usec
	_warning_until_usec = now_usec + WARNING_DURATION_USEC
	_active_until_usec = 0
	_wrong_flash_until_usec = 0
	_phase = Phase.WARNING
	if _is_frozen():
		_frozen_at_usec = now_usec

	_layout()
	_refresh_labels()
	_root.show()
	_root.queue_redraw()
	set_process(true)
	feedback.emit(&"prompt")
	return true


func start_direction_qte() -> bool:
	if not is_inside_tree() or _phase != Phase.IDLE:
		return false
	_duel = false
	_strict_input = true
	_direction_mode = true
	_expected_key = &"direction"
	_active_duration_usec = Q_DURATION_USEC
	_warning_started_usec = _now_usec()
	_warning_until_usec = _warning_started_usec + WARNING_DURATION_USEC
	_active_until_usec = 0
	_wrong_flash_until_usec = 0
	_phase = Phase.WARNING
	if _is_frozen():
		_frozen_at_usec = _warning_started_usec
	_layout()
	_refresh_labels()
	_root.show()
	_root.queue_redraw()
	set_process(true)
	feedback.emit(&"prompt")
	return true


func handle_input(event: InputEvent) -> bool:
	if _phase != Phase.ACTIVE or _is_frozen() or not event is InputEventKey:
		return false

	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false

	var physical_key: Key = key_event.physical_keycode
	var actual_key: StringName = _direction_from_key(physical_key) if _direction_mode else \
		(&"q" if physical_key == KEY_Q else (&"e" if physical_key == KEY_E else &""))
	if actual_key == &"":
		if not _strict_input:
			return false
		_finish(false)
		return true

	var now_usec: int = _now_usec()
	if now_usec >= _active_until_usec:
		_finish(false)
		return true

	if (_direction_mode and actual_key in [&"up", &"left", &"down", &"right"]) \
			or (not _direction_mode and actual_key == _expected_key):
		if _direction_mode:
			_expected_key = actual_key
		_finish(true)
	else:
		if _strict_input:
			_finish(false)
			return true
		_wrong_flash_until_usec = now_usec + WRONG_FLASH_USEC
		_caption.text = "错键"
		wrong_key_pressed.emit(actual_key)
		feedback.emit(&"mistake")
		_root.queue_redraw()
	return true


func set_frozen(value: bool) -> void:
	_set_freeze_reason(FREEZE_EXTERNAL, value)


func cancel_qte() -> bool:
	if _phase == Phase.IDLE:
		return false

	var cancelled_key: StringName = _expected_key
	_reset_qte()
	_root.hide()
	qte_finished.emit(cancelled_key, false)
	return true


func is_running() -> bool:
	return _phase != Phase.IDLE


func is_frozen() -> bool:
	return _is_frozen()


func _process(_delta: float) -> void:
	if _is_frozen() or _phase == Phase.IDLE:
		return

	var now_usec: int = _now_usec()
	if _phase == Phase.WARNING:
		if now_usec >= _warning_until_usec:
			_phase = Phase.ACTIVE
			_active_until_usec = now_usec + _active_duration_usec
			_refresh_labels()
	elif now_usec >= _active_until_usec:
		_finish(false)
		return
	elif _wrong_flash_until_usec > 0 and now_usec >= _wrong_flash_until_usec:
		_wrong_flash_until_usec = 0
		_refresh_labels()

	if _phase != Phase.IDLE:
		if _phase == Phase.ACTIVE:
			var remaining_usec: int = maxi(0, _active_until_usec - now_usec)
			_timer_label.text = "%.1f" % (float(remaining_usec) / 1_000_000.0)
		_root.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_set_freeze_reason(FREEZE_PAUSE, true)
	elif what == NOTIFICATION_UNPAUSED:
		_set_freeze_reason(FREEZE_PAUSE, false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_freeze_reason(FREEZE_FOCUS, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_freeze_reason(FREEZE_FOCUS, false)


func _build() -> void:
	_root = Control.new()
	_root.name = "ChaseRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.focus_mode = Control.FOCUS_NONE
	_root.draw.connect(_draw_overlay)
	add_child(_root)

	_caption = _make_label("Caption", 7, MUTED_COLOR)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key_label = _make_label("Key", 14, ACTIVE_COLOR)
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label = _make_label("Timer", 6, MUTED_COLOR)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.hide()


func _make_label(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_root.add_child(label)
	return label


func _layout() -> void:
	if _root == null:
		return

	var view_size: Vector2 = get_viewport().get_visible_rect().size
	_root.position = Vector2.ZERO
	_root.size = view_size
	var x: float = maxf(4.0, view_size.x - PANEL_SIZE.x - 8.0)
	var y: float = maxf(4.0, minf(8.0, view_size.y - PANEL_SIZE.y - 4.0))
	if _duel:
		x = (view_size.x - PANEL_SIZE.x) * 0.5
		y = (view_size.y - PANEL_SIZE.y) * 0.5
	_panel_rect = Rect2(Vector2(floorf(x), floorf(y)), PANEL_SIZE)
	_ring_center = _panel_rect.position + Vector2(PANEL_SIZE.x * 0.5, 32.0)

	_caption.position = _panel_rect.position + Vector2(3.0, 2.0)
	_caption.size = Vector2(PANEL_SIZE.x - 6.0, 10.0)
	_key_label.position = _ring_center - Vector2(14.0, 9.0)
	_key_label.size = Vector2(28.0, 18.0)
	if _direction_mode:
		_key_label.position = _panel_rect.position + Vector2(12.0, 17.0)
		_key_label.size = Vector2(34.0, 31.0)
	_timer_label.position = _panel_rect.position + Vector2(3.0, 52.0)
	_timer_label.size = Vector2(PANEL_SIZE.x - 6.0, 8.0)
	_root.queue_redraw()


func _refresh_labels() -> void:
	if _phase == Phase.WARNING:
		_caption.text = "C 正在逼近" if _duel else "黑雾逼近"
		_caption.add_theme_color_override("font_color", WARNING_COLOR)
		_key_label.text = "!"
		_key_label.add_theme_color_override("font_color", WARNING_COLOR)
		_timer_label.text = "准备"
	elif _phase == Phase.ACTIVE:
		_caption.text = "按键闪避" if _duel else ("选择冲刺方向" if _direction_mode else "闪避")
		_caption.add_theme_color_override("font_color", MUTED_COLOR)
		_key_label.text = "W\nA   D\nS" if _direction_mode else String(_expected_key).to_upper()
		_key_label.add_theme_font_size_override("font_size", 7 if _direction_mode else 14)
		_key_label.add_theme_color_override("font_color", ACTIVE_COLOR)
		_timer_label.text = "1.4" if _expected_key == &"q" else "1.2"
		if _direction_mode:
			_timer_label.text = "1.4"


func _draw_overlay() -> void:
	if _phase == Phase.IDLE:
		return

	var now_usec: int = _now_usec()
	var flashing_wrong: bool = now_usec < _wrong_flash_until_usec
	var edge_color: Color = WRONG_COLOR if flashing_wrong else EDGE_COLOR
	if _phase == Phase.WARNING:
		edge_color = WARNING_COLOR

	_root.draw_rect(_panel_rect, PANEL_COLOR)
	_root.draw_rect(_panel_rect, edge_color, false, 1.0)
	_root.draw_line(
		_panel_rect.position + Vector2(4.0, 13.0),
		_panel_rect.position + Vector2(PANEL_SIZE.x - 4.0, 13.0),
		edge_color,
		1.0
	)

	if _phase == Phase.WARNING:
		var warning_ratio: float = clampf(
			float(now_usec - _warning_started_usec) / float(WARNING_DURATION_USEC),
			0.0,
			1.0
		)
		var pulse_radius: float = 14.0 + 3.0 * sin(PI * warning_ratio)
		_root.draw_circle(_ring_center, pulse_radius, WARNING_COLOR, false, 2.0, true)
		return

	_root.draw_circle(_ring_center, 19.0, TRACK_COLOR, false, 1.0, true)
	var remaining_ratio: float = clampf(
		float(_active_until_usec - now_usec) / float(_active_duration_usec),
		0.0,
		1.0
	)
	var ring_radius: float = lerpf(7.0, 19.0, remaining_ratio)
	var ring_color: Color = WRONG_COLOR if flashing_wrong else ACTIVE_COLOR
	_root.draw_circle(_ring_center, ring_radius, ring_color, false, 2.0, true)


func _finish(success: bool) -> void:
	var finished_key: StringName = _expected_key
	_reset_qte()
	_root.hide()
	feedback.emit(&"success" if success else &"mistake")
	qte_finished.emit(finished_key, success)


func _reset_qte() -> void:
	_phase = Phase.IDLE
	_expected_key = &""
	_active_duration_usec = 0
	_warning_started_usec = 0
	_warning_until_usec = 0
	_active_until_usec = 0
	_wrong_flash_until_usec = 0
	_strict_input = false
	_direction_mode = false
	set_process(false)


func _direction_from_key(key: Key) -> StringName:
	match key:
		KEY_W: return &"up"
		KEY_A: return &"left"
		KEY_S: return &"down"
		KEY_D: return &"right"
		_: return &""


func _is_frozen() -> bool:
	return _freeze_reasons != 0


func _set_freeze_reason(reason: int, value: bool) -> void:
	var was_frozen: bool = _is_frozen()
	if value:
		_freeze_reasons = _freeze_reasons | reason
	else:
		_freeze_reasons = _freeze_reasons & ~reason

	var frozen_now: bool = _is_frozen()
	if was_frozen == frozen_now:
		return

	var now_usec: int = _now_usec()
	if frozen_now:
		_frozen_at_usec = now_usec
		return

	var frozen_duration: int = maxi(0, now_usec - _frozen_at_usec)
	if _phase == Phase.WARNING:
		_warning_started_usec += frozen_duration
		_warning_until_usec += frozen_duration
	elif _phase == Phase.ACTIVE:
		_active_until_usec += frozen_duration
	if _wrong_flash_until_usec > _frozen_at_usec:
		_wrong_flash_until_usec += frozen_duration
	if _root != null:
		_root.queue_redraw()


func _on_window_focus_exited() -> void:
	_set_freeze_reason(FREEZE_FOCUS, true)


func _on_window_focus_entered() -> void:
	_set_freeze_reason(FREEZE_FOCUS, false)


func _now_usec() -> int:
	return Time.get_ticks_usec()
