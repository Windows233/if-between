class_name Ch2ChaseSession
extends Node

signal trigger_reached
signal door_reached
signal qte_resolved(key: StringName, success: bool)
signal door_confirmed

const MIST_PATH := "res://art/npc/shadow_cat/chase_mist_right.png"
## 追兵本体的移动/寻路/接触判定全在 `Ch2ChasePursuer`；这里只管剧情节奏。
const MIST_CHASE_SPEED := Ch2ChasePursuer.SPEED
## 开跑后这段时间内即使贴上也不算追上（主角刚出教学楼时不被抓）。
const CATCH_GRACE := 2.0
## 每次 QTE 结束后这段时间内不再算追上：冲刺撞墙没拉开距离时，不会立刻连着弹下一个 QTE。
const RECATCH_GRACE := 1.0
const RESCUE_BURST_LIMIT := 118.0
## 垂直方向能冲的距离低于这个值（未缩放单位），视为被堵，改选任意空旷方向。
const RESCUE_MIN_BURST := 24.0
const RESCUE_C_SPACING := 12.0

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
var _elapsed := 0.0
var _catch_ready_at := 0.0
var _mist: Ch2ChasePursuer
var _mist_sprite: Sprite2D
var _rescue_c: Node2D
var _rescue_direction := Vector2.ZERO
var _rescue_distance := 0.0
## 救援冲刺进行中：门口已到达时主角本不可移动，这段要单独放行物理。
var _rescue_bursting := false


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
	main.walk_and_use = false
	main.player.walk_path.clear()
	_rescue_c = null
	_rescue_direction = Vector2.ZERO
	_rescue_distance = 0.0
	_elapsed = 0.0
	_catch_ready_at = CATCH_GRACE
	main.flags.set_value(&"ch2/chase_q1", false)
	main.flags.set_value(&"ch2/chase_q2", false)
	main.flags.set_value(&"ch2/chase_arrived", false)
	main.flags.set_value(&"ch2/chase_rescued", false)
	_create_mist()
	if _mist == null:
		active = false
		_restore_world()
		return false
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
	if not _arrived and _catch_count < 3 and not _mist_caught_player():
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
	_catch_ready_at = _elapsed + RECATCH_GRACE
	if success and _mist != null and is_instance_valid(_mist):
		_mist.stagger()
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
	if _rescue_pending:
		# 在门口按空格前被第三次追上：走 C 救援，不算直接进门。
		_arrived = false
		main.player.chase_input_locked = false
		main.flags.set_value(&"ch2/chase_arrived", false)
		main.flags.set_value(&"ch2/chase_rescued", true)
		_restore_world()
		main.update_player_control()
		return false
	active = false
	main.flags.set_value(&"ch2/chase_arrived", true)
	main.player.chase_input_locked = false
	_restore_world()
	main.update_player_control()
	return true


func can_move_player() -> bool:
	if _rescue_bursting and not _cancelled:
		return true
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
	var tween := create_tween()
	tween.tween_property(_mist, "modulate:a", 0.0, duration)
	await tween.finished
	_remove_mist()


func prepare_rescue_c() -> void:
	if main == null or main.player == null or main.cutscene == null:
		return
	var rescue := _rescue_burst()
	_rescue_direction = rescue.direction
	_rescue_distance = rescue.distance
	# 无论能否冲刺 C 都必须出场，否则后面的救援对白没人说。四面堵死时挡在主角与猫之间。
	var side: Vector2 = _rescue_direction
	if side.is_zero_approx():
		side = Vector2.RIGHT
		if _mist != null and is_instance_valid(_mist):
			var away: Vector2 = main.player.global_position - _mist.global_position
			side = Vector2(signf(away.x) if absf(away.x) > 0.01 else 1.0, 0.0)
	var scale_factor: float = main.current_map.player_scale if main.current_map != null else 1.0
	var at: Vector2 = main.player.global_position - side * RESCUE_C_SPACING * scale_factor
	_rescue_c = main.cutscene.add_actor("c", "res://art/npc/c", at,
		Player.DISPLAY_HEIGHT, 12, "walk_" + _facing_name(_rescue_direction))
	if _rescue_c == null:
		return
	# 救援演出里的 C 不占碰撞：演员默认挂的脚底 StaticBody2D 会紧贴主角，
	# 挡住冲刺或让净空检测误判（门口窄道里尤其明显）。
	var body := _rescue_c.get_node_or_null("Body")
	if body != null:
		_rescue_c.remove_child(body)
		body.free()
	# 往下推时 C 在主角身后（画面偏上），要画在主角下面，否则会把主角整个盖住。
	_rescue_c.z_index = main.player.z_index - 1 if side.y > 0.5 else main.player.z_index + 2
	if main.toast != null and main.toast.is_open() \
			and main.toast.current_text() == "到图书馆门口了，按空格进门":
		main.toast.hide_now()
	_set_rescue_c_pose(true)
	_rescue_c.modulate.a = 0.0
	if not main.cutscene.instant:
		var fade := create_tween()
		fade.tween_property(_rescue_c, "modulate:a", 1.0, 0.14)
		await fade.finished
	else:
		_rescue_c.modulate.a = 1.0


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
	_elapsed += _delta
	_update_mist_hold()

	if _waiting_for_trigger and _mist_caught_player():
		_waiting_for_trigger = false
		trigger_reached.emit()
	if _awaiting_door and _door_area.has_point(position) and not _arrived:
		_arrived = true
		door_reached.emit()

	# 第三次追上 → C 救援。门口等确认（按空格）时被追上也一样；
	# wait_for_arrival 可能停在 door_reached 或 door_confirmed 任一处，两个都要放行。
	if _awaiting_door and not _door_confirmed and _catch_count >= 2 and _mist_caught_player():
		_rescue_pending = true
		_awaiting_door = false
		_rescue_cat()
		door_reached.emit()
		door_confirmed.emit()

	if main.camera != null:
		main.camera.zoom = _base_zoom * (1.15 if _qte_started else 1.05)
		if _qte_started:
			Engine.time_scale = 0.2
		elif not is_equal_approx(Engine.time_scale, _base_time_scale):
			Engine.time_scale = _base_time_scale


func _physics_process(_delta: float) -> void:
	# 追兵在自己的物理帧里移动；这里只保证它在该停的时候停住（物理帧先于下一次 _process）。
	_update_mist_hold()


## QTE/冲刺进行中、救援中、已进门或窗口失焦时，追兵原地不动。
func _update_mist_hold() -> void:
	if _mist == null or not is_instance_valid(_mist):
		return
	# 走进门区但还没按空格时猫照样追，门口也可能被追上。
	_mist.holding = not active or _rescue_pending or _door_confirmed \
		or (qte_pending and not _waiting_for_trigger) \
		or (overlay != null and overlay.is_frozen())


## 追兵脚底与主角相贴，并且已过开跑保护期。
func _mist_caught_player() -> bool:
	if _mist == null or not is_instance_valid(_mist) or main == null or main.player == null:
		return false
	if _elapsed < _catch_ready_at or _mist.is_emerging():
		return false
	return _mist.is_touching(main.player)


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
	# 出生点：教学楼门口左侧的地图边缘，与主角出教学楼的位置同一高度，从左边追过来。
	var spawn := Ch2ChasePursuer.edge_spawn(main.current_map, main.player.global_position, -1)
	if spawn.is_equal_approx(main.player.global_position):
		push_warning("[追逐] 校门左侧地图边缘找不到可走的追兵出生点")
		return
	_mist = Ch2ChasePursuer.new()
	_mist.setup(main.current_map, main.player, texture, main.player.scale)
	_mist.global_position = spawn
	main.stage_view.add_child(_mist)
	_mist_sprite = _mist.get_node_or_null("Visual") as Sprite2D
	_mist.emerge()
	_update_mist_hold()


## 追兵到主角的实际可走路程（绕障）。
func _mist_gap() -> float:
	if _mist == null or not is_instance_valid(_mist) or main == null or main.player == null:
		return INF
	return _mist.path_gap()


func _rescue_cat() -> void:
	if _mist_sprite != null and is_instance_valid(_mist_sprite):
		_mist_sprite.modulate = Color(0.7, 0.7, 0.7, 1.0)


## C 推着主角同步冲刺；主角撞墙即停，C 跟着停。C 只是演出节点，没有碰撞体。
func _push_player_clear_of_mist() -> void:
	if main == null or main.player == null:
		return
	if _rescue_direction.is_zero_approx():
		var rescue := _rescue_burst()
		_rescue_direction = rescue.direction
		_rescue_distance = rescue.distance
	var direction: Vector2 = _rescue_direction
	if _rescue_distance <= 0.0 or direction.is_zero_approx():
		# 四面都贴墙：不冲刺，C 已在身边，直接进对话。
		_set_rescue_c_pose(false)
		return
	if not main.player.start_chase_burst(direction, _rescue_distance):
		return
	_rescue_bursting = true
	_set_rescue_c_pose(true)
	main.update_player_control()
	# 保险：冲刺本身最多 CHASE_BURST_DURATION；多给一倍余量，绝不让剧情卡在这里。
	var deadline := Time.get_ticks_msec() + int(Player.CHASE_BURST_DURATION * 2000.0) + 500
	while main.player.is_chase_bursting() and not _cancelled:
		_follow_player_with_rescue_c(direction)
		if Time.get_ticks_msec() > deadline:
			main.player.stop_chase_burst()
			break
		# process_frame 在本帧物理之后：C 贴的是主角这一帧移动后的位置，不会落后半拍。
		await get_tree().process_frame
	_follow_player_with_rescue_c(direction)
	_rescue_bursting = false
	main.update_player_control()
	_set_rescue_c_pose(false)


func _follow_player_with_rescue_c(direction: Vector2) -> void:
	if _rescue_c == null or not is_instance_valid(_rescue_c):
		return
	var scale_factor: float = main.current_map.player_scale if main.current_map != null else 1.0
	_rescue_c.global_position = main.player.global_position \
		- direction * RESCUE_C_SPACING * scale_factor


## 救援冲刺方向（只取东南西北）：
## 1. 先看垂直于「猫→主角」连线的两个方向，取一路无障碍的；都有障碍取能冲得最远的。
## 2. 两个垂直方向都几乎冲不动（如图书馆门口窄道），改为四个方向里最空旷的。
## 返回 {"direction", "distance"}，distance 为未缩放的主角单位；四面都堵死时为 0。
func _rescue_burst() -> Dictionary:
	if main == null or main.player == null:
		return {"direction": Vector2.ZERO, "distance": 0.0}
	var away := Vector2.RIGHT
	if _mist != null and is_instance_valid(_mist):
		away = main.player.global_position - _mist.global_position
	if away.is_zero_approx():
		away = Vector2.RIGHT
	var sides: Array[Vector2] = []
	if absf(away.x) >= absf(away.y):
		sides.append_array([Vector2.UP, Vector2.DOWN])
	else:
		sides.append_array([Vector2.LEFT, Vector2.RIGHT])
	var best := _longest_burst(sides)
	if best.distance >= RESCUE_MIN_BURST:
		return best
	# 极端情况：不再拘泥垂直方向，任选最空旷的一边；平手时优先背离猫的方向。
	var away_axis := Vector2(signf(away.x), 0.0) if absf(away.x) >= absf(away.y) \
		else Vector2(0.0, signf(away.y))
	var all: Array[Vector2] = [away_axis, sides[0], sides[1], -away_axis]
	return _longest_burst(all)


func _longest_burst(directions: Array[Vector2]) -> Dictionary:
	var best := {"direction": Vector2.ZERO, "distance": 0.0}
	for direction: Vector2 in directions:
		var clearance: float = main.player.burst_clearance(direction, RESCUE_BURST_LIMIT)
		if clearance > best.distance + 0.01:
			best = {"direction": direction, "distance": clearance}
	return best


func _set_rescue_c_pose(moving: bool) -> void:
	if _rescue_c == null or not is_instance_valid(_rescue_c):
		return
	var sprite := _rescue_c as AnimatedSprite2D
	if sprite == null:
		return
	var side := _facing_name(_rescue_direction)
	var pose := ("walk_" if moving else "idle_") + side
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(pose):
		sprite.play(pose)
	if side == "side":
		sprite.flip_h = _rescue_direction.x > 0.0


func _facing_name(direction: Vector2) -> String:
	if absf(direction.x) >= absf(direction.y):
		return "side"
	return "up" if direction.y < 0.0 else "down"


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
