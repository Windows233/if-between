## 2026-10-28 标定结果（速度 128）：理想最短/熟练/一般 2 次入馆，绕宽 1 次，冲刺朝侧面 3 次转救援。
## 校门追逐节奏标定探针：用真实物理帧驱动主角走几条八方向路线，统计黑猫追上次数。
## godot --headless --path . --script res://tests/probe_chase_pacing.gd [-- --speed=150]
## 只是模拟：脚本操控主角（八方向键盘移动、路线经过喷泉绕行），QTE 立即按对，
## 冲刺方向按路线朝前（或指定）。冲刺后玩家重新朝门口走最短路。不代表人工实玩手感。
extends SceneTree

const DOOR := Vector2(353, 120)
## 每条路线：起步反应、先走的折线（之后接最短路到门）、到门后按空格的反应、冲刺键（0=朝前）。
const ROUTES := [
	{"name": "理想最短", "start_delay": 0.0, "door_delay": 0.1, "burst": 0, "points": []},
	{"name": "熟练", "start_delay": 0.2, "door_delay": 0.25, "burst": 0,
		"points": [Vector2(108, 170)]},
	{"name": "一般·先右再下", "start_delay": 0.35, "door_delay": 0.3, "burst": 0,
		"points": [Vector2(130, 126), Vector2(166, 168)]},
	{"name": "一般·绕得较宽", "start_delay": 0.4, "door_delay": 0.35, "burst": 0,
		"points": [Vector2(110, 126), Vector2(160, 180), Vector2(268, 180)]},
	{"name": "一般·冲刺朝下", "start_delay": 0.35, "door_delay": 0.3, "burst": KEY_S,
		"points": [Vector2(130, 126), Vector2(166, 168)]},
	{"name": "一般·冲刺朝上", "start_delay": 0.35, "door_delay": 0.3, "burst": KEY_W,
		"points": [Vector2(130, 126), Vector2(166, 168)]},
	{"name": "绕远·喷泉上方", "start_delay": 0.4, "door_delay": 0.35, "burst": 0,
		"points": [Vector2(150, 126), Vector2(150, 70), Vector2(264, 70)]},
]

var main: Node2D
var _planner: Ch2ChasePursuer
var _catches: Array[String] = []
var _story_done := false
var _story_result := ""
var _elapsed := 0.0
var _walked := 0.0
var _stuck_logged := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	root.add_child(main)
	main.boot()
	main.debug_start_map = ""
	main.enter_map(&"school_gate", &"near_classroom")
	_planner = Ch2ChasePursuer.new()
	_planner.setup(main.current_map, null, null, main.player.scale)
	var start_at: Vector2 = main.player.global_position
	var ideal := _planner.find_path(start_at, DOOR)
	var report: Array[String] = []
	for route: Dictionary in ROUTES:
		report.append(await _simulate(route))
	print("\n[追逐节奏] 猫速 %.0f（地图 %.1f/秒），主角 %.0f/秒，出场 %.1f 秒，开跑保护 %.1f 秒，最短路 %.0f" % [
		_speed(), _speed() * main.player.scale.x, main.player.movement_speed(),
		Ch2ChasePursuer.EMERGE_TIME, Ch2ChaseSession.CATCH_GRACE, _length(start_at, ideal)])
	for line in report:
		print(line)
	_planner.free()
	quit(0)


func _simulate(route: Dictionary) -> String:
	main.chase_session.cancel()
	main.enter_map(&"school_gate", &"near_classroom")
	main.flags.set_value(&"ch2/diary_read", true)
	main.flags.set_value(&"ch2/teamed_c", true)
	main.flags.set_value(&"ch2/gate_entry_seen", true)
	if not ItemTable.has(main.flags, &"charm"):
		ItemTable.add(main.flags, &"charm")
	var overlay: ChaseOverlay = main.chase_overlay
	overlay._set_freeze_reason(ChaseOverlay.FREEZE_FOCUS, false)
	_catches.clear()
	_story_done = false
	_story_result = ""
	_elapsed = 0.0
	_walked = 0.0
	_stuck_logged = false
	var session: Ch2ChaseSession = main.chase_session
	if not session.begin():
		return "%s：追逐无法启动" % route.name
	session._mist.speed_value = _speed()
	var spawn: Vector2 = session._mist.global_position
	var start_gap: float = session._mist_gap()
	_story(session)
	var player: Player = main.player
	var points: Array = route.points.duplicate()
	var planned := false
	var was_bursting := false
	var door_wait := 0.0
	while not _story_done and _elapsed < 30.0:
		await physics_frame
		var delta: float = Engine.time_scale / float(Engine.physics_ticks_per_second)
		_elapsed += delta
		overlay._set_freeze_reason(ChaseOverlay.FREEZE_FOCUS, false)
		if overlay.is_running():
			var key: Key = route.burst if route.burst != 0 else _toward(player.global_position, points)
			_answer_qte(overlay, key)
			continue
		if player.is_chase_bursting():
			was_bursting = true
			continue
		if was_bursting:
			# 冲刺后重新看路：直接朝门口走最短路。
			was_bursting = false
			points.clear()
			planned = false
		if session.qte_pending and not session._waiting_for_trigger:
			continue
		# 与 main.gd 一致：门口确认不受输入锁影响。
		if session.awaiting_door_interaction():
			door_wait += delta
			if door_wait >= route.door_delay:
				session.confirm_door_interaction()
			continue
		if player.chase_input_locked:
			continue
		if _elapsed < route.start_delay:
			continue
		if points.is_empty() and not planned:
			planned = true
			points.append_array(_planner.find_path(player.global_position, DOOR))
		if points.is_empty():
			if not _stuck_logged:
				_stuck_logged = true
				print("  [无路可走] %s" % player.global_position)
			continue
		var gap: Vector2 = points[0] - player.global_position
		var direction := Vector2(
			signf(gap.x) if absf(gap.x) > 0.75 else 0.0,
			signf(gap.y) if absf(gap.y) > 0.75 else 0.0)
		if direction == Vector2.ZERO:
			points.pop_front()
			continue
		var before := player.global_position
		player.velocity = direction.normalized() * player.movement_speed()
		player.move_and_slide()
		var moved := before.distance_to(player.global_position)
		_walked += moved
		if moved < 0.05:
			print("  [路线受阻] %s 前往 %s" % [player.global_position, points[0]])
			points.pop_front()
	if not _story_done:
		print("  [超时] 主角%s 锁=%s qte=%s 等触发=%s 等门=%s 到门=%s 门区=%s 路点=%d" % [player.global_position, player.chase_input_locked, session.qte_pending, session._waiting_for_trigger, session._awaiting_door, session._arrived, session._door_area, points.size()])
	return "%s：出生 %s 路程差 %.0f｜走 %.0f 用时 %.2fs｜被追上 %d 次 %s｜%s" % [
		route.name, spawn, start_gap, _walked, _elapsed, _catches.size(),
		", ".join(_catches), _story_result]


func _story(session: Ch2ChaseSession) -> void:
	var on_trigger := func() -> void:
		if not session._arrived:
			_catches.append("%.1fs@%.0f" % [_elapsed, _walked])
			print("  追上 主角%s 猫%s" % [main.player.global_position, session._mist.global_position])
	session.trigger_reached.connect(on_trigger)
	await session.run_qte(&"q")
	print("  Q后 主角%s 猫%s" % [main.player.global_position, session._mist.global_position])
	await session.run_qte(&"e")
	session.trigger_reached.disconnect(on_trigger)
	var arrived: bool = await session.wait_for_arrival()
	if session._rescue_pending:
		_catches.append("%.1fs@%.0f" % [_elapsed, _walked])
		_story_result = "第三次被追上→C救援"
	else:
		_story_result = "到门入馆" if arrived else "未到门"
	session.cancel()
	_story_done = true


func _answer_qte(overlay: ChaseOverlay, burst_key: Key) -> void:
	if overlay._phase == ChaseOverlay.Phase.WARNING:
		overlay._warning_until_usec = Time.get_ticks_usec() - 1
		overlay._process(0.0)
	if overlay._phase != ChaseOverlay.Phase.ACTIVE:
		return
	var key := InputEventKey.new()
	key.pressed = true
	if overlay._direction_mode:
		key.physical_keycode = burst_key
	else:
		key.physical_keycode = KEY_Q if overlay._expected_key == &"q" else KEY_E
	overlay.handle_input(key)


## 朝前冲刺：取几格之后路线点的主轴方向。
func _toward(from: Vector2, points: Array) -> Key:
	var aim := DOOR
	if not points.is_empty():
		aim = points[mini(points.size() - 1, 12)]
	var gap: Vector2 = aim - from
	if absf(gap.x) >= absf(gap.y):
		return KEY_D if gap.x > 0.0 else KEY_A
	return KEY_S if gap.y > 0.0 else KEY_W


func _length(from: Vector2, route: Array[Vector2]) -> float:
	var total := 0.0
	var at := from
	for point in route:
		total += at.distance_to(point)
		at = point
	return total


func _speed() -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="):
			return float(arg.trim_prefix("--speed="))
	return Ch2ChasePursuer.SPEED
