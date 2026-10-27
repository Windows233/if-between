class_name Ch2ChaseSession
extends Node

signal trigger_reached
signal door_reached
signal qte_resolved(key: StringName, success: bool)
signal door_confirmed

const MIST_PATH := "res://art/npc/shadow_cat/chase_mist_right.png"

var main: Variant
var overlay: ChaseOverlay
var active := false
var qte_pending := false
var _qte_started := false
var _cancelled := false
var _waiting_for_trigger := false
var _awaiting_door := false
var _arrived := false
var _door_area := Rect2()
var _expected_key: StringName = &""
var _trigger_x := 0.0
var _base_time_scale := 1.0
var _base_zoom := Vector2.ONE
var _trail: Array[Vector2] = []
var _mist: Sprite2D
var _mist_lag := 32.0
var _mist_hold_until_msec := 0


func setup(host: Variant, qte_overlay: ChaseOverlay) -> void:
	main = host
	overlay = qte_overlay
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 100
	if overlay != null and not overlay.qte_finished.is_connected(_on_overlay_qte_finished):
		overlay.qte_finished.connect(_on_overlay_qte_finished)


func can_start() -> bool:
	return main != null and main.flags.get_value(&"ch2/diary_read") == true \
		and main.flags.get_value(&"ch2/teamed_c") == true \
		and ItemTable.has(main.flags, &"charm")


func begin() -> bool:
	if main == null or main.player == null or main.current_map == null:
		return false
	if main.current_map.id != &"school_gate" or active or not can_start():
		return active

	_cancelled = false
	active = true
	qte_pending = false
	_qte_started = false
	_waiting_for_trigger = false
	_awaiting_door = false
	_arrived = false
	_door_area = _library_door_area()
	main.player.chase_input_locked = false
	_base_time_scale = Engine.time_scale
	_base_zoom = main.camera.zoom if main.camera != null else Vector2.ONE
	_mist_lag = 32.0
	_mist_hold_until_msec = 0
	_trail.clear()
	main.walk_and_use = false
	main.player.walk_path.clear()
	_trail.append(main.player.global_position)
	main.flags.set_value(&"ch2/chase_q1", false)
	main.flags.set_value(&"ch2/chase_q2", false)
	main.flags.set_value(&"ch2/chase_arrived", false)
	_create_mist()
	main.update_player_control()
	return true


func run_qte(key: StringName, trigger_x: float) -> bool:
	if qte_pending and _cancelled:
		while qte_pending:
			if not is_inside_tree():
				return false
			await get_tree().process_frame
	if not active and not begin():
		return false
	if _cancelled or qte_pending or (key != &"q" and key != &"e"):
		return false

	_expected_key = key
	_trigger_x = trigger_x
	qte_pending = true
	if main.player.global_position.x < trigger_x:
		_waiting_for_trigger = true
		await trigger_reached
		_waiting_for_trigger = false
	if _cancelled:
		qte_pending = false
		return false

	if overlay == null:
		qte_pending = false
		_finish_run(true)
		return false

	_qte_started = true
	main.player.chase_input_locked = true
	Engine.time_scale = 0.2
	if main.camera != null:
		main.camera.zoom = _base_zoom * 1.15
		main.camera.shake(2.4, 0.22)
	if not overlay.start_qte(key, false, true):
		qte_pending = false
		_qte_started = false
		main.player.chase_input_locked = false
		_finish_run(true)
		return false
	main.update_player_control()

	var result: Array = await qte_resolved
	if _cancelled:
		qte_pending = false
		_qte_started = false
		main.player.chase_input_locked = false
		return false
	var success: bool = bool(result[1])
	var result_flag: StringName = &"ch2/chase_q1" if key == &"q" else &"ch2/chase_q2"
	if success:
		main.player.chase_input_locked = true
		if not overlay.start_direction_qte():
			success = false
		else:
			var direction_result: Array = await qte_resolved
			success = not _cancelled and bool(direction_result[1])
			if success:
				main.player.start_chase_burst(_direction_vector(StringName(direction_result[0])))
				main.player.chase_input_locked = false
				await _wait_for_burst()
	qte_pending = false
	_qte_started = false
	main.player.chase_input_locked = false
	main.flags.set_value(result_flag, success)
	Engine.time_scale = _base_time_scale
	if main.camera != null:
		main.camera.clear_shake()
		main.update_camera()
	if not success:
		_finish_run(true)
		return false

	_mist_lag = 48.0
	_mist_hold_until_msec = Time.get_ticks_msec() + 350
	return true


func run_dodge_qte(key: StringName) -> bool:
	if main == null or main.player == null or main.current_map == null:
		return false
	if qte_pending and _cancelled:
		while qte_pending:
			if not is_inside_tree():
				return false
			await get_tree().process_frame
	if qte_pending or active or (key != &"q" and key != &"e"):
		return false
	if overlay == null:
		return false

	_cancelled = false
	_expected_key = key
	qte_pending = true
	_qte_started = true
	_base_time_scale = Engine.time_scale
	_base_zoom = main.camera.zoom if main.camera != null else Vector2.ONE
	main.walk_and_use = false
	main.player.walk_path.clear()
	Engine.time_scale = 0.2
	if main.camera != null:
		main.camera.zoom = _base_zoom * 1.3
		main.camera.shake(2.4, 0.22)
	if not overlay.start_qte(key, true):
		qte_pending = false
		_qte_started = false
		_restore_world()
		return false
	main.update_player_control()

	var result: Array = await qte_resolved
	_qte_started = false
	var success := false if _cancelled else bool(result[1])
	_restore_world()
	main.update_player_control()
	qte_pending = false
	return success


func wait_for_arrival() -> bool:
	if not active or _cancelled:
		return false
	_awaiting_door = true
	if _door_area.has_point(main.player.global_position):
		_arrived = true
	else:
		await door_reached
	if _cancelled or not _arrived:
		_awaiting_door = false
		return false
	main.player.chase_input_locked = true
	if main.toast != null:
		main.toast.show_text("到图书馆门口了，按空格进门")
	await door_confirmed
	_awaiting_door = false
	if _cancelled:
		main.player.chase_input_locked = false
		return false
	active = false
	main.flags.set_value(&"ch2/chase_arrived", true)
	main.player.chase_input_locked = false
	_restore_world()
	main.update_player_control()
	return true


func can_move_player() -> bool:
	return active and not _cancelled and not _arrived \
		and (overlay == null or not overlay.is_frozen())


func awaiting_door_interaction() -> bool:
	return _awaiting_door and _arrived and not _cancelled


func confirm_door_interaction() -> bool:
	if not awaiting_door_interaction():
		return false
	door_confirmed.emit()
	return true


func cancel() -> void:
	_cancelled = true
	if _waiting_for_trigger:
		_waiting_for_trigger = false
		trigger_reached.emit()
	if _awaiting_door:
		_awaiting_door = false
		door_reached.emit()
		if _arrived:
			door_confirmed.emit()
	if overlay != null:
		overlay.cancel_qte()
	active = false
	_qte_started = false
	if main != null and main.player != null:
		main.player.chase_input_locked = false
		main.walk_and_use = false
		main.player.walk_path.clear()
	_restore_world()
	_remove_mist()
	if main != null:
		main.update_player_control()


func retreat_mist(duration: float = 0.3) -> void:
	if _mist == null or not is_instance_valid(_mist):
		return
	var target: Vector2 = _point_on_trail(48.0)
	var tween := create_tween()
	tween.tween_property(_mist, "global_position", target, duration)
	tween.parallel().tween_property(_mist, "modulate:a", 0.0, duration)
	await tween.finished
	_remove_mist()


func _process(delta: float) -> void:
	# Main restores the map camera each frame; retain duel framing while its QTE is active.
	if qte_pending and _qte_started and not active:
		if main != null and main.camera != null:
			main.camera.zoom = _base_zoom * 1.3
		return
	if not active or main == null or main.player == null:
		return
	if overlay != null and overlay.is_frozen():
		return

	var position: Vector2 = main.player.global_position
	if _trail.is_empty() or _trail[-1].distance_to(position) >= 1.0:
		_trail.append(position)
		if _trail.size() > 4096:
			_trail.pop_front()

	if _waiting_for_trigger and position.x >= _trigger_x:
		_waiting_for_trigger = false
		trigger_reached.emit()
	if _awaiting_door and _door_area.has_point(position):
		_arrived = true
		door_reached.emit()

	if _mist != null and is_instance_valid(_mist):
		if Time.get_ticks_msec() >= _mist_hold_until_msec:
			_mist_lag = move_toward(_mist_lag, 32.0, delta * 64.0)
		_mist.global_position = _point_on_trail(_mist_lag)
		_mist.flip_h = _mist.global_position.x > position.x

	if main.camera != null:
		main.camera.zoom = _base_zoom * (1.15 if _qte_started else 1.05)
		if _qte_started:
			Engine.time_scale = 0.2
		elif not is_equal_approx(Engine.time_scale, _base_time_scale):
			Engine.time_scale = _base_time_scale


func _on_overlay_qte_finished(key: StringName, success: bool) -> void:
	if qte_pending and (key == _expected_key or key == &"direction" \
			or key in [&"up", &"down", &"left", &"right"]):
		qte_resolved.emit(key, success)


func _library_door_area() -> Rect2:
	if main == null or main.current_map == null or main.current_map.id != &"school_gate":
		return Rect2()
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.id in [&"to_library", &"to_library_locked"]:
			return portal.rect
	return Rect2()


func _direction_vector(direction: StringName) -> Vector2:
	match direction:
		&"up": return Vector2.UP
		&"left": return Vector2.LEFT
		&"down": return Vector2.DOWN
		&"right": return Vector2.RIGHT
		_: return Vector2.ZERO


func _wait_for_burst() -> void:
	while main.player.is_chase_bursting() and not _cancelled:
		await get_tree().physics_frame


func _create_mist() -> void:
	_remove_mist()
	if not ResourceLoader.exists(MIST_PATH) or main.stage_view == null:
		return
	var texture := load(MIST_PATH) as Texture2D
	if texture == null:
		return
	_mist = Sprite2D.new()
	_mist.name = "ch2_chase_mist"
	_mist.texture = texture
	# 素材是高清原图；沿用人物/地图标尺，限制在主角约1.5倍高度内。
	var height: float = Player.DISPLAY_HEIGHT * main.current_map.player_scale * 1.5
	var ratio := height / maxf(texture.get_height(), 1.0)
	_mist.scale = Vector2.ONE * ratio
	_mist.offset.y = -texture.get_height() * 0.5
	_mist.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mist.z_index = 30
	_mist.global_position = main.player.global_position
	main.stage_view.add_child(_mist)


func _point_on_trail(distance_back: float) -> Vector2:
	if _trail.is_empty():
		return main.player.global_position
	var remaining := distance_back
	for index in range(_trail.size() - 1, 0, -1):
		var end: Vector2 = _trail[index]
		var start: Vector2 = _trail[index - 1]
		var segment: Vector2 = end - start
		var length: float = segment.length()
		if length >= remaining and length > 0.0:
			return end - segment / length * remaining
		remaining -= length
	return _trail[0]


func _finish_run(remove_mist: bool) -> void:
	active = false
	_qte_started = false
	_waiting_for_trigger = false
	_awaiting_door = false
	if main != null and main.player != null:
		main.player.chase_input_locked = false
	_restore_world()
	if remove_mist:
		_remove_mist()
	if main != null:
		main.update_player_control()


func _restore_world() -> void:
	Engine.time_scale = _base_time_scale
	if overlay != null:
		overlay.cancel_qte()
	if main != null and main.camera != null:
		main.camera.clear_shake()
		main.camera.zoom = _base_zoom
		main.update_camera()


func _remove_mist() -> void:
	if _mist != null and is_instance_valid(_mist):
		_mist.queue_free()
	_mist = null
