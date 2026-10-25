## 后段逃跑验证：障碍、可达路径、主动输入、暂停与状态清理。
extends RefCounted


static func run(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	main.flags.set_value(&"ch2/personal/stealth_available", true)
	main.flags.set_value(&"item/key", 1)
	var barrier_at := Vector2(233, 238)
	h.check("书架未倒时原通道可行走", WalkGrid.is_free(main.current_map, barrier_at), true)
	main.flags.set_value(&"ch2/library/shelf_fallen", true)
	main.refresh_scene()
	h.check("撬棍标记生成实际障碍", WalkGrid.is_free(main.current_map, barrier_at), false)
	var route := WalkGrid.path_to(main.current_map, Vector2(233, 190), Vector2(233, 258))
	h.check("追兵仍可绕过书架", not route.is_empty() and route[-1].distance_to(Vector2(233, 258)) < 3, true)
	var all_free := true
	for point: Vector2 in route:
		all_free = all_free and WalkGrid.is_free(main.current_map, point)
	h.check("绕行没有穿过倒塌书架", all_free, true)
	main.player.global_position = Vector2(233, 258)
	h.check("图书馆逃跑能够启动", main.escape_session.begin("library"), true)
	h.check("逃跑交还移动控制", main.escape_session.can_move_player(), true)
	h.check("未按键时不会自动隐蔽", main.flags.get_value(&"ch2/personal/stealth_started") == true, false)
	var chaser_at: Vector2 = main.escape_session._chaser.global_position
	var hold: float = main.escape_session._hold
	main.escape_session._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	main.escape_session._process(1.0)
	h.check("失焦停止追兵", main.escape_session._chaser.global_position, chaser_at)
	h.check("失焦不消耗书架争取的时间", main.escape_session._hold, hold)
	main.escape_session._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	main._unhandled_input(key)
	h.check("F 键在逃跑中主动开启隐蔽", main.flags.get_value(&"ch2/personal/stealth_started"), true)
	h.check("隐蔽有角色半透明反馈", main.player.modulate.a < 0.6, true)
	main.player.global_position = main.current_map.spawn_point(&"from_school_gate")
	h.check("馆门必须由交互确认后退出", main.escape_session.active, true)
	h.check("靠近馆门可退出第一段", main.escape_session.try_exit(), true)
	h.check("退出恢复角色透明度", main.player.modulate.a, 1.0)
	main.enter_map(&"school_gate", &"from_library", true)
	h.check("校门逃跑能够启动", main.escape_session.begin("gate"), true)
	main.player.global_position = main.current_map.spawn_point(&"near_classroom")
	main.flags.set_value(&"ch2/personal/stealth_started", false)
	h.check("不隐蔽不能甩开 C 进教室", main.escape_session.try_exit(), false)
	main.escape_session.activate_stealth()
	main.flags.set_value(&"item/key", 0)
	h.check("逃跑不跳过教学楼钥匙检查", main.escape_session.try_exit(), false)
	main.flags.set_value(&"item/key", 1)
	h.check("隐蔽且有钥匙才能进入教室", main.escape_session.try_exit(), true)
	main.enter_map(&"library", &"from_school_gate", true)
	main.player.global_position = Vector2(233, 258)
	var results: Array[bool] = []
	main.escape_session.resolved.connect(func(value: bool) -> void: results.append(value))
	main.escape_session.begin("library")
	main.escape_session._hold = 0.0
	for _step: int in 300:
		main.escape_session._process(0.1)
		if not main.escape_session.active:
			break
	h.check("站着不跑会被沿路径追上", results, [false])
	h.check("被追上后不残留 C 追兵", main.cutscene.actor_ids().has("c"), false)
	main.escape_session.begin("library")
	main.open_pause_menu()
	var before: float = main.escape_session._hold
	await h.root.get_tree().process_frame
	await h.root.get_tree().process_frame
	h.check("暂停菜单不会消耗追兵延迟", main.escape_session._hold, before)
	main.pause_menu.close()
	main.escape_session.cancel()
	main.escape_session.cancel()
	h.check("取消只结束一次，不残留运行态", results, [false, false])
	h.check("取消恢复角色外观", main.player.modulate.a, 1.0)
	main.enter_map(&"classroom", &"from_gate", true)
	var window: MapDef.Actor
	for actor: MapDef.Actor in main.current_map.actors:
		if actor.id == &"classroom_window":
			window = actor
	h.check("窗下交互位置可站立", window != null and WalkGrid.has_landing_room(main.current_map, window.reach.get_center()), true)
	if window != null:
		var path := WalkGrid.path_to(main.current_map, main.player.global_position, window.reach.get_center())
		h.check("教室门口可走到窗下", not path.is_empty() and path[-1].distance_to(window.reach.get_center()) < 3, true)
	main.flags.set_value(&"ch2/personal/stealth_started", false)
	h.check("逃跑指令拒绝未知路段", StageStep.from_dictionary({"do":"ch2_escape_run", "phase":"unknown"}).validate().is_empty(), false)
	main.queue_free()
	await _test_escape_save_retry(h)


static func _test_escape_save_retry(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	main.player.global_position = Vector2(233, 258)
	main.flags.set_value(&"item/key", 1)
	main.flags.set_value(&"item/charm", 1)
	main.flags.set_value(&"item/night_tear", 1)
	main.flags.set_value(&"ch2/personal/stealth_available", true)
	main.flags.set_value(&"ch2/library/shelf_fallen", true)
	main.capture_ch2_checkpoint("escape")
	main.start_story(&"ch2_library_cat", &"escape_library_run")
	h.check("剧情写倒架标记后开跑立即生成碰撞", WalkGrid.is_free(main.current_map, Vector2(233, 238)), false)
	main.escape_session.activate_stealth()
	h.check("逃跑中允许存档", main.save_game(2), true)
	h.check("逃跑中读档成功", main.load_game(2), true)
	await h.root.get_tree().create_timer(0.8).timeout
	h.check("读档从逃跑检查点重新开始", main.story.current_node_id(), &"escape_library_run")
	h.check("读档恢复实际追逐", main.escape_session.active, true)
	h.check("重开检查点需重新主动开启隐蔽", main.flags.get_value(&"ch2/personal/stealth_started"), false)
	h.check("读档不会丢失夜幕之泪", main.flags.get_value(&"item/night_tear"), 1)
	h.check("读档保留地图血迹", main.flags.get_value(&"map_blood/library/entrance"), true)
	main.escape_session._finish(false)
	# 失败 CG 淡入后才会打开重试选项。
	await h.root.get_tree().create_timer(0.3).timeout
	h.drain_dialogue(main.dialogue)
	h.check("被追上后进入重试分支", main.story.current_node_id(), &"escape_caught")
	h.check("可以选择仅重试这一段", h.pick(main, &"retry_escape"), true)
	await h.root.get_tree().create_timer(0.8).timeout
	h.check("重试没有跳过追逐", main.escape_session.active, true)
	h.check("重试不复制决策币", main.flags.get_value(&"item/charm"), 1)
	main.show_title()
	h.check("回标题会清理追逐和 HUD", main.escape_session.active, false)
	h.check("回标题恢复角色透明度", main.player.modulate.a, 1.0)
	main.delete_save(2)
	main.queue_free()
