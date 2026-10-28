## 回归探针：剧情真实流程里，两次 QTE 后在图书馆门口窄道被第三次追上，
## C 救援必须出场、推开主角并接着进图书馆，不能卡住。
## godot --headless --path . --script res://tests/probe_chase_door_rescue.gd
extends SceneTree

var main: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	root.add_child(main)
	main.boot()
	main.debug_start_map = ""
	main.enter_map(&"school_gate", &"near_classroom")
	main.flags.set_value(&"ch2/diary_read", true)
	main.flags.set_value(&"ch2/teamed_c", true)
	main.flags.set_value(&"ch2/gate_entry_seen", true)
	ItemTable.add(main.flags, &"charm")
	main.cutscene.instant = true
	main.start_story(&"ch2_diary", &"chase_checkpoint")
	var session: Ch2ChaseSession = main.chase_session
	var overlay: ChaseOverlay = main.chase_overlay
	var door_spot := Vector2.ZERO
	var placed_at_door := false
	var rescue_seen := false
	var pushed_from := Vector2.ZERO
	var c_seen_at_gate := false
	var elapsed := 0.0
	while elapsed < 20.0:
		await physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
		overlay._set_freeze_reason(ChaseOverlay.FREEZE_FOCUS, false)
		if main.current_map.id == &"library":
			break
		if main.dialogue != null and main.dialogue.visible and main.dialogue.has_method("advance"):
			main.dialogue.advance()
		if overlay.is_running():
			if overlay._phase == ChaseOverlay.Phase.WARNING:
				overlay._warning_until_usec = Time.get_ticks_usec() - 1
				overlay._process(0.0)
			if overlay._phase == ChaseOverlay.Phase.ACTIVE:
				var key := InputEventKey.new()
				key.pressed = true
				key.physical_keycode = KEY_D if overlay._direction_mode \
					else (KEY_Q if overlay._expected_key == &"q" else KEY_E)
				overlay.handle_input(key)
			continue
		if session._rescue_pending:
			rescue_seen = true
			c_seen_at_gate = c_seen_at_gate or main.cutscene._actor("c") != null
			continue
		if not session.active or session._mist == null:
			continue
		session._elapsed = maxf(session._elapsed, session._catch_ready_at + 0.01)
		if session._catch_count < 2 and session._waiting_for_trigger:
			session._mist.global_position = main.player.global_position + Vector2(-10, 0)
		elif session._catch_count >= 2 and session._awaiting_door and not placed_at_door:
			placed_at_door = true
			var door: Rect2 = session._door_area
			door_spot = Vector2(door.get_center().x, door.end.y - 4.0)
			main.player.global_position = door_spot
			session._mist.global_position = door_spot + Vector2(0, 17)
			pushed_from = door_spot
	var ok: bool = main.current_map.id == &"library" and rescue_seen and c_seen_at_gate \
		and main.flags.get_value(&"ch2/chase_rescued") == true
	print("[门口救援] 到门口=%s 救援=%s 校门C出场=%s 已救援旗标=%s 进入=%s 用时 %.1fs" % [
		placed_at_door, rescue_seen, c_seen_at_gate,
		main.flags.get_value(&"ch2/chase_rescued"), main.current_map.id, elapsed])
	print("=== %s ===" % ("通过" if ok else "失败"))
	quit(0 if ok else 1)
