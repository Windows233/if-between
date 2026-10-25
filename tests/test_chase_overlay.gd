extends SceneTree

const CHASE_OVERLAY_SCRIPT = preload("res://ui/chase_overlay.gd")

class FakeClockOverlay:
	extends "res://ui/chase_overlay.gd"

	var clock_usec: int = 0

	func _now_usec() -> int:
		return clock_usec

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_focus_routing()
	_test_warning_gate()
	_test_deadlines()
	_test_wrong_key()
	_test_freeze_resume()
	print("ChaseOverlay: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(1 if _failures > 0 else 0)


func _test_focus_routing() -> void:
	var overlay := _new_overlay()
	var results: Array[bool] = []
	overlay.qte_finished.connect(
		func(_key: StringName, success: bool) -> void: results.append(success)
	)
	overlay.clock_usec = 1_000_000
	overlay.start_qte(&"q")
	_activate_after_warning(overlay)
	var root_control: Control = overlay.get_node("ChaseRoot") as Control
	_check("覆盖层不申请 GUI 焦点", root_control.focus_mode, Control.FOCUS_NONE)
	_check("无控件焦点仍可接收转发输入", get_root().gui_get_focus_owner(), null)

	var deadline: int = overlay._active_until_usec
	overlay._on_window_focus_exited()
	_check("失焦期间忽略按键", overlay.handle_input(_key(KEY_Q)), false)
	overlay.clock_usec += 500_000
	overlay._on_window_focus_entered()
	_check("失焦冻结不扣 QTE 时限", overlay._active_until_usec, deadline + 500_000)
	_check("恢复焦点后仍可完成判定", overlay.handle_input(_key(KEY_Q)), true)
	_check("失焦前后仅产生一次成功", results, [true])
	overlay.free()


func _test_warning_gate() -> void:
	var overlay := _new_overlay()
	var results: Array[bool] = []
	overlay.qte_finished.connect(
		func(_key: StringName, success: bool) -> void: results.append(success)
	)
	overlay.clock_usec = 2_000_000
	overlay.start_qte(&"q")
	_check("预警期 Q 不计成功", overlay.handle_input(_key(KEY_Q)), false)
	_check("预警期仍未进入判定", overlay._phase, CHASE_OVERLAY_SCRIPT.Phase.WARNING)
	_check("预警期没有完成信号", results.size(), 0)
	overlay.clock_usec += CHASE_OVERLAY_SCRIPT.WARNING_DURATION_USEC
	overlay._process(0.0)
	_check("预警结束后显示正式判定", overlay._phase, CHASE_OVERLAY_SCRIPT.Phase.ACTIVE)
	_check("正式提示出现后 Q 生效", overlay.handle_input(_key(KEY_Q)), true)
	_check("预警期按键没有提前消费判定", results, [true])
	overlay.free()


func _test_deadlines() -> void:
	_test_deadline(&"q", CHASE_OVERLAY_SCRIPT.Q_DURATION_USEC)
	_test_deadline(&"e", CHASE_OVERLAY_SCRIPT.E_DURATION_USEC)


func _test_deadline(key: StringName, expected_duration: int) -> void:
	var overlay := _new_overlay()
	var results: Array[bool] = []
	overlay.qte_finished.connect(
		func(_finished_key: StringName, success: bool) -> void: results.append(success)
	)
	overlay.clock_usec = 3_000_000
	overlay.start_qte(key)
	_activate_after_warning(overlay)
	var active_start: int = overlay.clock_usec
	_check("%s 时限符合剧本秒数" % key, overlay._active_until_usec - active_start, expected_duration)
	overlay.clock_usec = overlay._active_until_usec - 1
	overlay._process(0.0)
	_check("%s 截止前仍可判定" % key, overlay.is_running(), true)
	overlay.clock_usec = overlay._active_until_usec
	overlay._process(0.0)
	_check("%s 到期判为失败" % key, results, [false])
	_check("%s 超时结束 QTE" % key, overlay.is_running(), false)
	overlay.free()


func _test_wrong_key() -> void:
	var overlay := _new_overlay()
	var results: Array[bool] = []
	var wrong_keys: Array[StringName] = []
	overlay.qte_finished.connect(
		func(_key: StringName, success: bool) -> void: results.append(success)
	)
	overlay.wrong_key_pressed.connect(
		func(key: StringName) -> void: wrong_keys.append(key)
	)
	overlay.clock_usec = 4_000_000
	overlay.start_qte(&"q")
	_activate_after_warning(overlay)
	var original_deadline: int = overlay._active_until_usec
	_check("错键被消费", overlay.handle_input(_key(KEY_E)), true)
	_check("错键仍处于判定期", overlay.is_running(), true)
	_check("错键不延长 Q 截止时间", overlay._active_until_usec, original_deadline)
	_check("错键产生提示事件", wrong_keys, [&"e"])
	overlay.clock_usec = original_deadline - 1
	overlay._process(0.0)
	_check("错键后正确 Q 仍成功", overlay.handle_input(_key(KEY_Q)), true)
	_check("错键后只产生最终成功", results, [true])
	overlay.free()


func _test_freeze_resume() -> void:
	var overlay := _new_overlay()
	var results: Array[bool] = []
	overlay.qte_finished.connect(
		func(_key: StringName, success: bool) -> void: results.append(success)
	)
	overlay.clock_usec = 5_000_000
	overlay.start_qte(&"e")
	_activate_after_warning(overlay)
	var original_deadline: int = overlay._active_until_usec
	overlay.set_frozen(true)
	_check("冻结时忽略按键", overlay.handle_input(_key(KEY_E)), false)
	overlay.clock_usec += 2_000_000
	overlay._process(0.0)
	_check("冻结时不产生超时", overlay.is_running(), true)
	overlay.set_frozen(false)
	_check("恢复时补回冻结时长", overlay._active_until_usec, original_deadline + 2_000_000)
	overlay._process(0.0)
	_check("恢复后继续判定", overlay.is_running(), true)
	_check("恢复后 E 可成功", overlay.handle_input(_key(KEY_E)), true)
	_check("恢复仅产生一次成功", results, [true])
	overlay.free()


func _activate_after_warning(overlay: FakeClockOverlay) -> void:
	overlay.clock_usec += CHASE_OVERLAY_SCRIPT.WARNING_DURATION_USEC
	overlay._process(0.0)


func _new_overlay() -> FakeClockOverlay:
	var overlay := FakeClockOverlay.new()
	get_root().add_child(overlay)
	return overlay


func _key(physical_key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_key
	event.pressed = true
	return event


func _check(label: String, actual: Variant, expected: Variant) -> void:
	_checks += 1
	if actual == expected:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: %s | actual=%s | expected=%s" % [label, actual, expected])
