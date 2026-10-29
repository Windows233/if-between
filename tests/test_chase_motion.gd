## 校门追逐的冲刺时长、距离、碰撞及C救援后的真实异步衔接。
## 使用实际Player移动与正式剧情节点，避免即时演出跳过卡住的等待。
extends RefCounted


static func run(h: TestHarness) -> void:
	h.section("追逐冲刺与C救场衔接")
	await _test_departure_and_retries(h)
	_test_burst(h)
	await _test_clearance(h)
	await _test_rescue_story(h,false)
	await _test_rescue_story(h,true)
	_test_cancel_and_door_rescue(h)
	for node: StringName in [&"run_q1",&"run_q2",&"arrive"]:
		await _test_door_catch(h,node)
	await _test_burst_into_door(h)
	await _test_interaction_idle(h)


static func _test_burst(h: TestHarness) -> void:
	var player := Player.new()
	h.root.add_child(player)
	player.set_physics_process(false)
	for rate: int in [30,60,144]:
		for distance: float in [18.0,110.0,118.0]:
			player.position = Vector2.ZERO
			player.scale = Vector2.ONE * 0.5
			player.start_chase_burst(Vector2.RIGHT,distance)
			for frame: int in rate * 2:
				if not player.is_chase_bursting():
					break
				player._physics_process(1.0 / rate)
			h.check("%dFPS距离%.0f冲刺按时结束" % [rate,distance],player.is_chase_bursting(),false)
			h.check_float("%dFPS冲刺使用指定距离%.0f" % [rate,distance],player.position.x,distance*0.5,0.01)
			h.check("冲刺结束恢复输入",player.chase_input_locked,false)
	player.queue_free()


static func _test_door_catch(h: TestHarness, node: StringName) -> void:
	var main := h.new_main()
	main.enter_map(&"school_gate",&"from_library")
	await h.root.get_tree().physics_frame
	await h.root.get_tree().physics_frame
	main.flags.set_value(&"ch2/diary_read",true)
	main.flags.set_value(&"ch2/teamed_c",true)
	ItemTable.add(main.flags,&"charm")
	main.chase_session.begin()
	main.chase_session._catch_count = 2 if node == &"arrive" else (1 if node == &"run_q2" else 0)
	main.start_story(&"ch2_diary",node)
	var foot := Vector2(353,120)
	h.check(str(node)+"门区脚点合法",WalkGrid.is_free(main.current_map,foot),true)
	main.player.position = foot
	main.chase_session._mist.global_position = foot+Vector2.DOWN*8
	h.check(str(node)+"门口猫确实追上主角",main.chase_session._mist_caught_player(),true)
	# 同一帧到门区与猫追上，不能从等待进门切换到另一个永远等不到的信号。
	main.chase_session._process(0)
	h.check(str(node)+"门口接触优先进门",main.chase_session._rescue_pending,false)
	h.check(str(node)+"门口接触仍能确认进门",main.chase_session.awaiting_door_interaction(),true)
	var input := InputEventKey.new()
	input.pressed = true
	input.physical_keycode = KEY_SPACE
	main._unhandled_input(input)
	var deadline := Time.get_ticks_msec()+3500
	while Time.get_ticks_msec() < deadline:
		await h.root.get_tree().process_frame
		if main.dialogue.is_open():
			main.dialogue.advance()
			main.dialogue.advance()
		if main.current_map.id == &"library" and not main.story.is_active():
			break
	h.check(str(node)+"被追上同时按进门进入图书馆",main.current_map.id,&"library")
	h.check(str(node)+"直接入馆有C", main.cutscene.actor_ids().has("c"), true)
	h.check(str(node)+"直接入馆C使用正式站位",main.cutscene._actor("c").position,preload("res://scenes/library_staging.gd").point(main.current_map,"entry_c"))
	h.check(str(node)+"门口冲突后剧情不挂起",main.story.is_active(),false)
	h.check(str(node)+"门口冲突后时速恢复",Engine.time_scale,1.0)
	main.story.cancel()
	main.chase_session.cancel()
	main.queue_free()
	await h.root.get_tree().process_frame


static func _test_interaction_idle(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"school_yard",&"from_gate")
	await h.root.get_tree().physics_frame
	await h.root.get_tree().physics_frame
	var actor: MapDef.Actor
	for candidate: MapDef.Actor in main.current_map.actors:
		if candidate.id == &"sandbox":
			actor = candidate
	h.check("步行互动测试有沙坑物件",actor != null,true)
	if actor == null:
		main.queue_free()
		return
	var start: Vector2 = main.player.position
	main.player.facing = Vector2.RIGHT
	main.player.velocity = Vector2.RIGHT*main.player.movement_speed()
	main.player.walk_path.append(start+Vector2.RIGHT*20)
	main.player.play_animation(true)
	main.begin_interaction(actor)
	main.update_player_control()
	await h.root.get_tree().physics_frame
	var sprite: AnimatedSprite2D = main.player.get_node("Body")
	h.check("移动中互动已打开对白",main.dialogue.is_open(),true)
	h.check("对白期间切为站立姿态",sprite.animation,&"idle_side")
	h.check("对白期间保持朝向",main.player.facing,Vector2.RIGHT)
	h.check("对白期间清零移动速度",main.player.velocity,Vector2.ZERO)
	h.check("对白期间停止步行路径",main.player.walk_path.is_empty(),true)
	h.check("对白期间原地停下",main.player.position,start)
	main.story.cancel()
	main.update_player_control()
	await h.root.get_tree().physics_frame
	h.check("对白结束不沿旧路径继续走",main.player.position,start)
	main.queue_free()
	await h.root.get_tree().process_frame


static func _test_burst_into_door(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"school_gate",&"from_library")
	await h.root.get_tree().physics_frame
	await h.root.get_tree().physics_frame
	main.flags.set_value(&"ch2/diary_read",true)
	main.flags.set_value(&"ch2/teamed_c",true)
	ItemTable.add(main.flags,&"charm")
	main.chase_session.begin()
	main.chase_session._mist.global_position = main.player.position+Vector2.DOWN*8
	main.start_story(&"ch2_diary",&"run_q1")
	var entered := false
	var deadline := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec() < deadline:
		await h.root.get_tree().process_frame
		var overlay: ChaseOverlay = main.chase_overlay
		if overlay._phase == ChaseOverlay.Phase.ACTIVE:
			var input := InputEventKey.new()
			input.pressed = true
			input.physical_keycode = KEY_W if overlay._direction_mode else KEY_Q
			main._unhandled_input(input)
		if main.chase_session._arrived and main.chase_session.active:
			entered = true
			var confirm := InputEventKey.new()
			confirm.pressed = true
			confirm.physical_keycode = KEY_E
			main._unhandled_input(confirm)
		if main.dialogue.is_open():
			main.dialogue.advance()
			main.dialogue.advance()
		if main.current_map.id == &"library" and not main.story.is_active():
			break
	h.check("QTE冲刺抵达门区",entered,true)
	h.check("冲刺进门可用E确认",main.current_map.id,&"library")
	h.check("抵达门区后不挂起冲刺",main.player.is_chase_bursting(),false)
	h.check("冲刺进门后剧情正常结束",main.story.is_active(),false)
	h.check("冲刺进门后不遗留慢动作",Engine.time_scale,1.0)
	main.story.cancel()
	main.chase_session.cancel()
	main.queue_free()
	await h.root.get_tree().process_frame


static func _test_cancel_and_door_rescue(h: TestHarness) -> void:
	var main := h.new_main()
	var session: Ch2ChaseSession = main.chase_session
	# 同一帧踏入门区又被猫追上时，救援推开动作优先于已到门口的普通移动锁。
	session._cancelled = false
	session._rescue_pending = true
	session._arrived = true
	main.player.start_chase_burst(Vector2.RIGHT)
	h.check("门区救援仍允许受控冲刺更新",session.can_move_player(),true)
	session.cancel()
	h.check("取消追逐清除未完成冲刺",main.player.is_chase_bursting(),false)
	h.check("取消追逐清除输入锁",main.player.chase_input_locked,false)
	main.queue_free()


static func _test_clearance(h: TestHarness) -> void:
	var player := Player.create()
	h.root.add_child(player)
	player.set_physics_process(false)
	var wall := StaticBody2D.new()
	wall.position = Vector2(50,-8)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10,16)
	collision.shape = shape
	wall.add_child(collision)
	h.root.add_child(wall)
	await h.root.get_tree().physics_frame
	var clearance := player.burst_clearance(Vector2.RIGHT,118)
	h.check("冲刺净空累计检测到前方墙体",clearance > 0 and clearance <= 37,true)
	player.start_chase_burst(Vector2.RIGHT)
	for frame: int in 100:
		if not player.is_chase_bursting():
			break
		player._physics_process(1.0/60)
	h.check("撞墙立即结束冲刺",player.is_chase_bursting(),false)
	h.check("冲刺不穿过墙体",player.position.x <= 37.01,true)
	player.queue_free()
	wall.queue_free()
	await h.root.get_tree().physics_frame


static func _test_rescue_story(h: TestHarness, third_catch: bool) -> void:
	var main := h.new_main()
	main.enter_map(&"school_gate",&"near_classroom")
	await h.root.get_tree().physics_frame
	await h.root.get_tree().physics_frame
	main.flags.set_value(&"ch2/diary_read",true)
	main.flags.set_value(&"ch2/teamed_c",true)
	ItemTable.add(main.flags,&"charm")
	main.flags.set_value(&"ch2/chase_failures",2)
	h.check("救场回归启动真实追逐",main.chase_session.begin(),true)
	# 只加快猫接近；QTE输入、冲刺、剧情分流和救援均走正式流程。
	main.start_story(&"ch2_diary",&"run_q1")
	var saw_push := false
	var push_enabled := false
	var saw_after := false
	var saw_dash := false
	var dash_start := Vector2.ZERO
	var dash_distance := 0.0
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec() < deadline:
		await h.root.get_tree().process_frame
		var session: Ch2ChaseSession = main.chase_session
		if is_instance_valid(session._mist) and (session._waiting_for_trigger or session._awaiting_door):
			session._mist.global_position = main.player.global_position + Vector2.RIGHT * 10
		var overlay: ChaseOverlay = main.chase_overlay
		if overlay._phase == ChaseOverlay.Phase.ACTIVE:
			var input := InputEventKey.new()
			input.pressed = true
			input.physical_keycode = KEY_Q if overlay._expected_key == &"q" else (KEY_E if third_catch else KEY_Q)
			if overlay._direction_mode:
				var best := -1.0
				for key: int in Player.MOVE_KEYS:
					var available: float = main.player.burst_clearance(Player.MOVE_KEYS[key],Player.CHASE_BURST_DISTANCE)
					if available > best:
						best = available
						input.physical_keycode = key
				if not saw_dash:
					dash_start = main.player.position
			main._unhandled_input(input)
		if main.player.is_chase_bursting():
			if session.active:
				saw_dash = true
			else:
				saw_push = true
				push_enabled = push_enabled or main.player.is_physics_processing()
		if main.flags.get_value(&"ch2/chase_q1") == true and dash_distance == 0.0:
			dash_distance = main.player.position.distance_to(dash_start)
		if main.dialogue.is_open():
			saw_after = saw_after or main.dialogue._dialogue.lines[main.dialogue._index].text == "你没受伤吧"
			main.dialogue.advance()
			main.dialogue.advance()
		if main.current_map.id == &"library" and not main.story.is_active():
			break
	h.check("真实QTE方向输入执行冲刺",saw_dash,true)
	h.check("成功冲刺确实拉开距离",dash_distance > 10,true)
	h.check("首轮冲刺后正确推进QTE状态",main.flags.get_value(&"ch2/chase_q1"),true)
	h.check("第二轮按结果进入救援",main.flags.get_value(&"ch2/chase_q2"),third_catch)
	h.check("C救场执行推开动作",saw_push,true)
	h.check("追逐结束后推开主角仍有物理更新",push_enabled,true)
	h.check("推开后接上C询问伤势对白",saw_after,true)
	h.check("救场对白后进入图书馆",main.current_map.id,&"library")
	h.check("救场入馆后正确结束剧情",main.story.is_active(),false)
	h.check("救场入馆写入首次进入标记",main.flags.get_value(&"ch2/first_library_entry"),true)
	h.check("救场结束没有遗留冲刺锁",main.player.is_chase_bursting() or main.player.chase_input_locked,false)
	main.story.cancel()
	main.queue_free()
	await h.root.get_tree().process_frame


## 跨End5重试走真实错键输入；第三次失败救场，累计数不被检查点覆盖。
static func _test_departure_and_retries(h: TestHarness) -> void:
	var main := h.new_main()
	main.cutscene.instant = true
	main.flags.set_value(&"ch2/rescued_c", true)
	main.flags.set_value(&"ch2/teamed_c", true)
	main.flags.set_value(&"ch2/yard_entry_seen", true)
	main.enter_map(&"school_yard", &"from_gate")
	main.start_story(&"ch2_c_wait")
	main._on_choice_chosen(&"ready")
	h.check("与C准备后主角直接进入教室", main.current_map.id, &"classroom")
	h.check("教学楼内不显示C模型", main.cutscene.actor_ids().has("c"), false)
	main.enter_map(&"school_yard", &"from_gate")
	h.check("离场后操场不重新生成C", main.cutscene.actor_ids().has("c"), false)
	main.enter_map(&"school_gate", &"near_classroom")
	h.check("教学楼外不重新生成C", main.cutscene.actor_ids().has("c"), false)
	main.flags.set_value(&"ch2/diary_read", true)
	ItemTable.add(main.flags, &"charm")
	main.capture_ch2_checkpoint("chase")
	main.chase_session.begin()
	main.start_story(&"ch2_diary", &"run_q1")
	for attempt: int in range(1,4):
		var deadline := Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < deadline:
			await h.root.get_tree().process_frame
			var session: Ch2ChaseSession = main.chase_session
			if is_instance_valid(session._mist) and session._waiting_for_trigger:
				session._mist.global_position = main.player.global_position + Vector2.RIGHT * 10
			if main.chase_overlay._phase == ChaseOverlay.Phase.ACTIVE:
				var key := InputEventKey.new()
				key.pressed = true
				key.physical_keycode = KEY_X
				main._unhandled_input(key)
			if attempt < 3 and main.choice_menu.is_open():
				break
			if main.current_map.id == &"library" and not main.story.is_active():
				break
		h.check("失败累计第%d次" % attempt, main.flags.get_value(&"ch2/chase_failures"), attempt)
		if attempt < 3:
			h.check("前两次失败进入End5重试页", main.story.runtime.current_node().id, &"end5_chase_outcome")
			h.check("前两次不触发C救场", main.flags.get_value(&"ch2/chase_rescued"), false)
			main._on_choice_chosen(&"retry_chase")
			h.check("重试保留累计失败数", main.flags.get_value(&"ch2/chase_failures"), attempt)
		else:
			h.check("第三次失败C救场进入图书馆", main.current_map.id, &"library")
			h.check("救场后图书馆有C", main.cutscene.actor_ids().has("c"), true)
			h.check("救场后可推进图书馆后续剧情", main.flags.get_value(&"ch2/first_library_entry"), true)
	main.queue_free()
	await h.root.get_tree().process_frame
