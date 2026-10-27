class_name Ch2ChaseSession
extends Node

signal trigger_reached
signal door_reached
signal qte_resolved(key: StringName, success: bool)
signal door_confirmed

const MIST_PATH := "res://art/npc/shadow_cat/chase_mist_right.png"
const MIST_CHASE_SPEED := 144.0
const INITIAL_GAP := 48.0
const QTE_CATCH_GAP := 26.0
const RESCUE_BURST_LIMIT := 118.0
const PURSUER_STEP := 2.0

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
var _door_confirmed := false
var _rescue_pending := false
var _catch_count := 0
var _expected_key: StringName = &""
var _base_time_scale := 1.0
var _base_zoom := Vector2.ONE
var _trail: Array[Vector2] = []
var _trail_total_distance := 0.0
var _trail_start_distance := 0.0
var _mist_trail_distance := 0.0
var _mist: CharacterBody2D
var _mist_sprite: Sprite2D


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
	if main.object_preview != null:
		main.object_preview.clear()

	_cancelled = false
	active = true
	qte_pending = false
	_qte_started = false
	_waiting_for_trigger = false
	_awaiting_door = false
	_arrived = false
	_door_confirmed = false
	_rescue_pending = false
	_catch_count = 0
	_door_area = _library_door_area()
	main.player.chase_input_locked = false
	_base_time_scale = Engine.time_scale
	_base_zoom = main.camera.zoom if main.camera != null else Vector2.ONE
	_trail.clear()
	main.walk_and_use = false
	main.player.walk_path.clear()
	_trail.append(main.player.global_position)
	_trail_total_distance = 0.0
	_trail_start_distance = 0.0
	_mist_trail_distance = -INITIAL_GAP
	main.flags.set_value(&"ch2/chase_q1", false)
	main.flags.set_value(&"ch2/chase_q2", false)
	main.flags.set_value(&"ch2/chase_arrived", false)
	main.flags.set_value(&"ch2/chase_rescued", false)
	_create_mist()
	main.update_player_control()
	return true


func run_qte(key: StringName) -> bool:
	if _arrived:
		main.flags.set_value(&"ch2/chase_q1" if key == &"q" else &"ch2/chase_q2", true)
		return true
	if _rescue_pending:
		return true
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
	qte_pending = true
	if not _arrived and _catch_count < 3 and _mist_gap() > QTE_CATCH_GAP:
		_waiting_for_trigger = true
		await trigger_reached
		_waiting_for_trigger = false
	if _arrived:
		main.flags.set_value(&"ch2/chase_q1" if key == &"q" else &"ch2/chase_q2", true)
		qte_pending = false
		return true
	if _cancelled:
		qte_pending = false
		return false

	if overlay == null:
		qte_pending = false
		_rescue_pending = true
		_rescue_cat()
		return true

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
		_rescue_pending = true
		_rescue_cat()
		return true
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
				_qte_started = false
				Engine.time_scale = _base_time_scale
				if main.camera != null:
					main.camera.clear_shake()
					main.update_camera()
				success = main.player.start_chase_burst(
					_direction_vector(StringName(direction_result[0])))
				if success:
					await _wait_for_burst()
	qte_pending = false
	_qte_started = false
	main.player.chase_input_locked = false
	main.flags.set_value(result_flag, success)
	Engine.time_scale = _base_time_scale
	if main.camera != null:
		main.camera.clear_shake()
		main.update_camera()
	_catch_count += 1
	if not success:
		_rescue_pending = true
		_rescue_cat()
		return true
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
	if _rescue_pending:
		main.flags.set_value(&"ch2/chase_rescued", true)
		_restore_world()
		main.update_player_control()
		return false
	if not _arrived and _door_area.has_point(main.player.global_position):
		_arrived = true
	elif not _arrived:
		await door_reached
	if _cancelled:
		_awaiting_door = false
		return false
	if _rescue_pending:
		_awaiting_door = false
		main.flags.set_value(&"ch2/chase_rescued", true)
		_restore_world()
		main.update_player_control()
		return false
	if not _arrived:
		_awaiting_door = false
		return false
	if not _door_confirmed:
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
	return active and not _cancelled and not _rescue_pending \
		and (not qte_pending or _waiting_for_trigger) \
		and _door_area.has_point(main.player.global_position)


func confirm_door_interaction() -> bool:
	if not awaiting_door_interaction():
		return false
	_arrived = true
	_door_confirmed = true
	main.flags.set_value(&"ch2/chase_arrived", true)
	if _waiting_for_trigger:
		_waiting_for_trigger = false
		trigger_reached.emit()
	if _awaiting_door:
		door_reached.emit()
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
	if _rescue_pending:
		await _push_player_clear_of_mist()
		active = false
		_restore_world()
		main.update_player_control()
	if _mist == null or not is_instance_valid(_mist):
		return
	var target: Vector2 = _point_on_trail_distance(_mist_trail_distance)
	var tween := create_tween()
	tween.tween_property(_mist, "global_position", target, duration)
	tween.parallel().tween_property(_mist, "modulate:a", 0.0, duration)
	await tween.finished
	_remove_mist()


func _process(_delta: float) -> void:
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
		_trail_total_distance += _trail[-1].distance_to(position) if not _trail.is_empty() else 0.0
		_trail.append(position)
		if _trail.size() > 4096:
			_trail_start_distance += _trail[0].distance_to(_trail[1])
			_trail.pop_front()

	if _waiting_for_trigger and _mist_gap() <= QTE_CATCH_GAP:
		_waiting_for_trigger = false
		trigger_reached.emit()
	if _awaiting_door and _door_area.has_point(position) and not _arrived:
		_arrived = true
		door_reached.emit()

	if _awaiting_door and _catch_count >= 2 and _mist_gap() <= QTE_CATCH_GAP:
		_rescue_pending = true
		_awaiting_door = false
		_rescue_cat()
		door_reached.emit()

	if main.camera != null:
		main.camera.zoom = _base_zoom * (1.15 if _qte_started else 1.05)
		if _qte_started:
			Engine.time_scale = 0.2
		elif not is_equal_approx(Engine.time_scale, _base_time_scale):
			Engine.time_scale = _base_time_scale


func _physics_process(delta: float) -> void:
	if not active or _rescue_pending or _mist == null or not is_instance_valid(_mist):
		return
	if overlay != null and overlay.is_frozen():
		return
	if delta <= 0.0:
		_mist.velocity = Vector2.ZERO
		return

	var budget: float = MIST_CHASE_SPEED * main.player.scale.x * minf(delta, 0.1)
	while budget > 0.001:
		var available: float = _trail_total_distance - _mist_trail_distance
		if available <= 0.001:
			break
		var step: float = minf(minf(budget, available), PURSUER_STEP)
		var target: Vector2 = _point_on_trail_distance(_mist_trail_distance + step)
		var gap: Vector2 = target - _mist.global_position
		if gap.length() <= 0.01:
			_mist_trail_distance += step
			budget -= step
			continue
		var motion: Vector2 = gap.limit_length(step)
		_mist.velocity = motion / maxf(minf(delta, 0.1), 0.001)
		var before: Vector2 = _mist.global_position
		var collision := _mist.move_and_collide(motion)
		var moved: float = before.distance_to(_mist.global_position)
		_mist_trail_distance += moved
		budget -= moved
		_mist_sprite.flip_h = _mist.velocity.x > 0.0 if absf(_mist.velocity.x) > 0.2 else _mist_sprite.flip_h
		if collision != null or moved <= 0.001:
			_mist.velocity = Vector2.ZERO
			break
	_mist.velocity = Vector2.ZERO


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
	_mist = CharacterBody2D.new()
	_mist.name = "ch2_chase_mist"
	_mist.collision_layer = 0
	_mist.collision_mask = 1
	_mist.scale = main.player.scale
	_mist.add_collision_exception_with(main.player)
	var collision := CollisionShape2D.new()
	var foot := CircleShape2D.new()
	foot.radius = 4.0
	collision.shape = foot
	_mist.add_child(collision)
	_mist_sprite = Sprite2D.new()
	_mist_sprite.name = "Visual"
	_mist_sprite.texture = texture
	# 素材是高清原图；沿用人物/地图标尺，限制在主角约1.5倍高度内。
	var height: float = Player.DISPLAY_HEIGHT * 1.5
	var ratio := height / maxf(texture.get_height(), 1.0)
	_mist_sprite.scale = Vector2.ONE * ratio
	_mist_sprite.offset.y = -texture.get_height() * 0.5
	_mist_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mist.z_index = 30
	main.stage_view.add_child(_mist)
	_mist.add_child(_mist_sprite)
	var spawn: Vector2 = main.player.global_position - Vector2(INITIAL_GAP, 0.0)
	while not WalkGrid.is_free(main.current_map, spawn) \
			and spawn.distance_to(main.player.global_position) > 12.0:
		spawn += Vector2(2.0, 0.0)
	_mist.global_position = spawn
	_mist_trail_distance = -spawn.distance_to(main.player.global_position)


func _mist_gap() -> float:
	if _mist == null or not is_instance_valid(_mist) or main == null or main.player == null:
		return INF
	return _mist.global_position.distance_to(main.player.global_position)


func _rescue_cat() -> void:
	if _mist_sprite != null and is_instance_valid(_mist_sprite):
		_mist_sprite.modulate = Color(0.7, 0.7, 0.7, 1.0)


func _push_player_clear_of_mist() -> void:
	if _mist == null or not is_instance_valid(_mist) or main == null or main.player == null:
		return
	var away: Vector2 = (main.player.global_position - _mist.global_position).normalized()
	if away.is_zero_approx():
		away = Vector2.RIGHT
	var perpendicular := Vector2(-away.y, away.x)
	var positive: float = main.player.burst_clearance(perpendicular, RESCUE_BURST_LIMIT)
	var negative: float = main.player.burst_clearance(-perpendicular, RESCUE_BURST_LIMIT)
	var direction := perpendicular if positive >= negative else -perpendicular
	var distance := maxf(positive, negative)
	if distance <= 0.0:
		return
	if main.player.start_chase_burst(direction, distance):
		main.update_player_control()
		await _wait_for_burst()


func _point_on_trail_distance(distance: float) -> Vector2:
	if _trail.is_empty():
		return main.player.global_position
	if distance < _trail_start_distance:
		var first_direction := Vector2.RIGHT
		if _trail.size() > 1:
			var first_segment: Vector2 = _trail[1] - _trail[0]
			if not first_segment.is_zero_approx():
				first_direction = first_segment.normalized()
		return _trail[0] - first_direction * (_trail_start_distance - distance)
	var remaining := clampf(distance - _trail_start_distance, 0.0,
		_trail_total_distance - _trail_start_distance)
	for index in range(1, _trail.size()):
		var start: Vector2 = _trail[index - 1]
		var end: Vector2 = _trail[index]
		var segment_length := start.distance_to(end)
		if remaining <= segment_length and segment_length > 0.0:
			return start.lerp(end, remaining / segment_length)
		remaining -= segment_length
	return _trail[-1]


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
	_mist_sprite = null
