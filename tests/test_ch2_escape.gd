## 后段逃跑验证：障碍、可达路径、自动隐蔽、暂停与状态清理。
extends RefCounted


static func run(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	main.flags.set_value(&"item/key", 1)
	var barrier_at := Vector2(233, 238)
	h.check("书架未倒时原通道可行走", WalkGrid.is_free(main.current_map, barrier_at), true)
	main.flags.set_value(&"ch2/library/shelf_fallen", true)
	main.refresh_scene()
	barrier_at = _barrier_center(main.current_map)
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
	key.keycode = KEY_F
	key.pressed = true
	main._unhandled_input(key)
	h.check("图书馆逃跑中F不会提前解锁校门隐蔽",
		main.flags.get_value(&"ch2/personal/stealth_started") == true, false)
	main.player.global_position = main.current_map.spawn_point(&"from_school_gate")
	h.check("馆门必须由交互确认后退出", main.escape_session.active, true)
	h.check("靠近馆门可退出第一段", main.escape_session.try_exit(), true)
	h.check("退出恢复角色透明度", main.player.modulate.a, 1.0)
	main.enter_map(&"school_gate", &"from_library", true)
	h.check("校门逃跑能够启动", main.escape_session.begin("gate"), true)
	var classroom_portal: MapDef.Portal = null
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.id == &"to_classroom":
			classroom_portal = portal
			break
	h.check("校门地图有教学楼门区", classroom_portal != null, true)
	if classroom_portal == null:
		main.queue_free()
		return
	var gate_stands := WalkGrid.reachable(main.current_map,
		main.current_map.spawn_point(&"from_library"))
	var gate_reachable := false
	for stand: Vector2 in gate_stands:
		if classroom_portal.rect.grow(Ch2EscapeSession.EXIT_MARGIN \
				* main.current_map.player_scale).has_point(stand):
			gate_reachable = true
			break
	h.check("从图书馆出口能走进教学楼门区", gate_reachable, true)
	var gate_stand := _reachable_portal_stand(main.current_map,
		classroom_portal, main.current_map.spawn_point(&"from_library"))
	if gate_stand == Vector2.INF:
		main.queue_free()
		return
	main.player.global_position = gate_stand
	main.flags.set_value(&"ch2/personal/stealth_started", false)
	var gate_path := WalkGrid.path_to(main.current_map,
		main.current_map.spawn_point(&"from_library"), gate_stand)
	h.check("从图书馆出口到教学楼门区有完整可走路径",
		not gate_path.is_empty() and gate_path[-1].distance_to(gate_stand) < 3.0, true)
	h.check("实际教学楼门区可触发离开检查", main.escape_session._at_escape_exit(), true)
	h.check("有钥匙时不使用夜幕之泪也能进教室", main.escape_session.try_exit(), true)
	h.check("进门后可重新启动隐蔽专项", main.escape_session.begin("gate"), true)
	var gate_key := InputEventKey.new()
	gate_key.physical_keycode = KEY_F
	gate_key.keycode = KEY_F
	gate_key.pressed = true
	main._unhandled_input(gate_key)
	h.check("驱动想法解锁前F不能提前开启隐蔽",
		main.flags.get_value(&"ch2/personal/stealth_started") == true, false)
	main.flags.set_value(&"ch2/personal/stealth_available", true)
	h.check("校门段允许主动启动隐蔽", main.escape_session.activate_stealth(), true)
	main._unhandled_input(gate_key)
	h.check("读完驱动想法后F主动开启隐蔽",
		main.flags.get_value(&"ch2/personal/stealth_started") == true, true)
	h.check("隐蔽有角色半透明反馈", main.player.modulate.a < 0.6, true)
	main.flags.set_value(&"item/key", 0)
	h.check("逃跑不跳过教学楼钥匙检查", main.escape_session.try_exit(), false)
	main.flags.set_value(&"item/key", 1)
	h.check("隐蔽加钥匙同样能进教室", main.escape_session.try_exit(), true)
	h.check("进入教室前追逐会话已结束", main.escape_session.active, false)
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
		if actor.id in [&"classroom_window", &"window"]:
			window = actor
	var window_landing := Vector2.ZERO
	var window_distance := INF
	if window != null:
		for point: Vector2 in WalkGrid.reachable(main.current_map, main.player.global_position):
			if not WalkGrid.has_landing_room(main.current_map, point) \
					or main.current_map.actor_near(point, 24.0) != window:
				continue
			var distance: float = main.player.global_position.distance_to(point)
			if distance < window_distance:
				window_landing = point
				window_distance = distance
	if window == null:
		h.check("未放置的窗户不绑定交互", window, null)
	else:
		h.check("窗边交互区有可站立落点", window_distance < INF, true)
		var window_path := WalkGrid.path_to(main.current_map, main.player.global_position, window_landing)
		h.check("教室门口可走到窗边交互区", window_distance < INF and not window_path.is_empty() \
			and window_path[-1].distance_to(window_landing) < 3, true)
	var cat_map := DataLoader.load_map(&"library")
	var cat_flags := WorldState.new()
	var cat_path := WalkGrid.path_to(cat_map, cat_map.spawn_point(&"from_school_gate"), Vector2(251, 296))
	h.check("猫事件预定脚点由WalkGrid可达", not cat_path.is_empty() and cat_path[-1].distance_to(Vector2(251, 296)) < 3, true)
	var cat_landing := Vector2.ZERO
	var landing_distance := INF
	for point: Vector2 in WalkGrid.reachable(cat_map, Vector2(251, 296)):
		if not WalkGrid.has_landing_room(cat_map, point):
			continue
		if MapDef.rect_distance(Rect2(Vector2(158, 136), Vector2(150, 110)), point) > 8.0:
			continue
		var distance := Vector2(251, 296).distance_to(point)
		if distance < landing_distance:
			cat_landing = point
			landing_distance = distance
	h.check("贴近猫的安全落点真实存在", landing_distance < INF, true)
	var map_view := MapView.new()
	map_view.build(cat_map, cat_flags)
	h.check("猫图层产生独立Sprite供Alpha指令使用",
		map_view._actor_variant_nodes.has(&"library_cat_visual"), true)
	h.check("地图猫可淡至50%", map_view.set_actor_alpha(&"library_cat_visual", 0.5), true)
	var cat_sprite := map_view._actor_variant_nodes.get(&"library_cat_visual") as Sprite2D
	h.check("猫Alpha反馈达到0.5", cat_sprite != null and is_equal_approx(cat_sprite.modulate.a, 0.5), true)
	h.check("取消或回溯复位猫Alpha", map_view.set_actor_alpha(&"library_cat_visual", 1.0), true)
	h.check("猫Alpha复位为1", cat_sprite != null and is_equal_approx(cat_sprite.modulate.a, 1.0), true)
	main.flags.set_value(&"ch2/personal/stealth_started", false)
	h.check("逃跑指令拒绝未知路段", StageStep.from_dictionary({"do":"ch2_escape_run", "phase":"unknown"}).validate().is_empty(), false)
	main.queue_free()
	await _test_escape_save_retry(h)
	await _test_escape_gate_unlock(h)
	await test_auto_stealth_reaction(h)


## 从正式校门追逐节点启动，不按 F：内心话期间双方停住，读完继续追逐。
static func test_auto_stealth_reaction(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"school_gate", &"from_library", true)
	main.flags.set_value(&"ch2/personal/stealth_available", true)
	main.flags.set_value(&"item/key", 1)
	main.cutscene.instant = false
	main.start_story(&"ch2_library_cat", &"escape_gate_run")
	for _frame: int in 60:
		if main.escape_session.active:
			break
		await h.root.get_tree().process_frame
	var session: Ch2EscapeSession = main.escape_session
	h.check("正式追逐节点启动校门会话", session.active and session.phase == "gate", true)
	if not session.active:
		main.queue_free()
		return
	session.set_process(false)
	session._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	session._hold = 0.0
	var chaser := session._chaser as AnimatedSprite2D
	chaser.play(&"walk_side")
	main.player.play_animation(true)
	session._process(0.016)
	h.check("追逐中无需F自动触发夜幕之泪", main.flags.get_value(&"ch2/personal/stealth_started"), true)
	h.check("自动触发后主角获得隐蔽外观", main.player.modulate.a < 0.6, true)
	h.check("内心话使用下方对话框", main.dialogue.is_open(), true)
	h.check("内心话文字符合用户要求", main.dialogue._dialogue.lines[0].text,
		"（居然夜幕之泪\n还有这种效果。）")
	h.check("内心话说话人为主角", main.dialogue._dialogue.lines[0].speaker, "我")
	h.check("内心话期间暂停主角控制", main.player.is_physics_processing(), false)
	h.check("内心话期间停止追兵走路动画", chaser.is_playing(), false)
	h.check("内心话期间隐藏追逐提示", session._hud.visible, false)
	var hero_at: Vector2 = main.player.global_position
	var c_at := chaser.global_position
	var c_frame := chaser.frame
	var hold := session._hold
	session._process(1.0)
	await h.root.get_tree().create_timer(0.12).timeout
	h.check("内心话期间主角不移动", main.player.global_position, hero_at)
	h.check("内心话期间C不移动", chaser.global_position, c_at)
	h.check("内心话期间C动作帧停住", chaser.frame, c_frame)
	h.check("内心话不消耗追逐计时", session._hold, hold)
	h.check("内心话期间不能绕过对话进门", session.try_exit(), false)
	h.drain_dialogue(main.dialogue)
	h.check("读完内心话恢复主角控制", main.player.is_physics_processing(), true)
	h.check("读完内心话追逐仍在运行", session.active and main.story.is_active(), true)
	h.check("读完内心话恢复追兵动画", chaser.is_playing(), true)
	h.check("读完内心话恢复路线提示", session._hud.visible, true)
	session._process(0.1)
	h.check("读完内心话C继续沿原路线追赶", chaser.global_position.distance_to(c_at) > 0.0, true)
	session._process(0.1)
	h.check("同次追逐不重复弹内心话", main.dialogue.is_open(), false)
	# 返回标题/切图可能在内心话中发生：取消必须断开旧回调、清理暂停态。
	session._begin_stealth_reaction()
	h.check("取消专项已打开内心话", main.dialogue.is_open(), true)
	main.story.cancel()
	session.cancel()
	h.check("取消清掉专用内心话框", main.dialogue.is_open(), false)
	h.check("取消断开恢复追逐回调",
		main.dialogue.finished.is_connected(session._end_stealth_reaction), false)
	h.check("取消恢复主角透明度", main.player.modulate.a, 1.0)
	h.check("取消不残留暂停标记", session._stealth_dialogue_open, false)
	main.queue_free()


static func _test_escape_save_retry(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	main.player.global_position = Vector2(233, 258)
	main.flags.set_value(&"item/key", 1)
	main.flags.set_value(&"item/charm", 1)
	main.flags.set_value(&"item/night_tear", 1)
	main.flags.set_value(&"ch2/library/shelf_fallen", true)
	main.refresh_scene()
	h.check("逃跑检查点可以保存", main.capture_ch2_checkpoint("escape"), true)
	h.check("逃跑检查点记录图书馆开跑场景",
		String(main.ch2_checkpoints.get("escape", {}).get("map_id", "")), "library")
	var library_event := DataLoader.load_event(&"ch2_library_cat")
	var caught_node := library_event.node(&"escape_caught")
	var caught_image: StageStep = null
	if caught_node != null:
		for step: StageStep in caught_node.stage:
			if step.kind == &"image":
				caught_image = step
				break
	h.check("被C追上时显示全屏CG",
		caught_image != null and caught_image.flag("fill"), true)
	var rug_preview := MapDef.Actor.new()
	rug_preview.rect = Rect2(10.0, 10.0, 20.0, 20.0)
	rug_preview.sprite = "res://art/props/ch2_box_closed_2.png"
	main.object_preview.show_actor(rug_preview, main.current_map)
	h.check("开始追逐前地毯近景确实显示", main.object_preview.content != null, true)
	main.start_story(&"ch2_library_cat", &"escape_library_run")
	h.check("C追逐启动时清理地毯近景", main.object_preview.content, null)
	h.check("剧情写倒架标记后开跑立即生成碰撞", WalkGrid.is_free(main.current_map, _barrier_center(main.current_map)), false)
	h.check("首次逃跑开场不能提前F隐蔽", main.escape_session.activate_stealth(), false)
	main.flags.set_value(&"ch2/personal/stealth_available", true)
	h.check("图书馆段F不会提前启动校门隐蔽", main.escape_session.activate_stealth(), false)
	h.check("逃跑中允许存档", main.save_game(2), true)
	h.check("逃跑中读档成功", main.load_game(2), true)
	await h.root.get_tree().create_timer(0.8).timeout
	h.check("读档从逃跑检查点重新开始", main.story.current_node_id(), &"escape_library_run")
	h.check("读档恢复实际追逐", main.escape_session.active, true)
	h.check("重开检查点需重新主动开启隐蔽", main.flags.get_value(&"ch2/personal/stealth_started"), false)
	h.check("读档不会丢失夜幕之泪", main.flags.get_value(&"item/night_tear"), 1)
	h.check("读档保留地图血迹", main.flags.get_value(&"map_blood/library/entrance"), true)
	var retry_player_start: Vector2 = main.player.global_position
	var retry_chaser_start: Vector2 = main.escape_session._chaser.global_position
	main.player.global_position = retry_player_start + Vector2(18.0, 12.0)
	main.escape_session._chaser.global_position = main.player.global_position
	main.escape_session._finish(false)
	# 失败 CG 淡入后才会打开重试选项。
	await h.root.get_tree().create_timer(0.3).timeout
	h.drain_dialogue(main.dialogue)
	h.check("被追上后进入重试分支", main.story.current_node_id(), &"escape_caught")
	h.check("可以选择仅重试这一段", h.pick(main, &"retry_escape"), true)
	await h.root.get_tree().create_timer(0.8).timeout
	h.check("重试没有跳过追逐", main.escape_session.active, true)
	h.check("重试返回图书馆开跑点", main.current_map.id, &"library")
	h.check("逃跑重试把玩家送回开场位置",
		main.player.global_position.distance_to(retry_player_start) < 0.1, true)
	h.check("逃跑重试把C送回开场位置",
		main.escape_session._chaser.global_position.distance_to(retry_chaser_start) < 0.1, true)
	h.check("重试不复制决策币", main.flags.get_value(&"item/charm"), 1)
	main.show_title()
	h.check("回标题会清理追逐和 HUD", main.escape_session.active, false)
	h.check("回标题恢复角色透明度", main.player.modulate.a, 1.0)
	main.delete_save(2)
	main.queue_free()


static func _test_escape_gate_unlock(h: TestHarness) -> void:
	var main := h.new_main()
	main.flags.set_value(&"ch2/c_at_school_gate", true)
	main.enter_map(&"school_gate", &"near_classroom", true)
	var c_wait: Node2D = main.cutscene._actors.get("c") as Node2D
	var c_shape: CollisionShape2D = null
	if c_wait != null:
		var c_shapes := c_wait.find_children("*", "CollisionShape2D", true, false)
		if not c_shapes.is_empty():
			c_shape = c_shapes[0] as CollisionShape2D
	var player_shapes: Array[Node] = main.player.find_children("*", "CollisionShape2D", true, false)
	var player_shape := player_shapes[0] as CollisionShape2D if not player_shapes.is_empty() else null
	if player_shape == null:
		h.check("追逐主角有实体碰撞框", false, true)
		main.queue_free()
		return
	var player_size: Vector2 = player_shape.shape.size * player_shape.global_scale.abs()
	var player_rect := Rect2(player_shape.global_position - player_size * 0.5, player_size)
	var c_size: Vector2 = c_shape.shape.size * c_shape.global_scale.abs() if c_shape != null else Vector2.ZERO
	var c_rect := Rect2(c_shape.global_position - c_size * 0.5, c_size) if c_shape != null else Rect2()
	h.check("校门等待C不占追逐出生点", c_wait != null and not c_rect.intersects(player_rect), true)
	var gate_plan := DataLoader.load_map(&"school_gate")
	if c_shape != null:
		gate_plan.walls.append(c_rect)
	var qte_path := WalkGrid.path_to(gate_plan, main.player.global_position, Vector2(148, 126))
	h.check("校门等待C不堵住QTE起跑路", not qte_path.is_empty() \
		and qte_path[-1].distance_to(Vector2(148, 126)) < 3, true)
	main.flags.set_value(&"item/key", 1)
	main.flags.set_value(&"ch2/personal/stealth_started", false)
	main.flags.set_value(&"ch2/personal/stealth_available", false)
	var classroom_portal: MapDef.Portal = null
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.id == &"to_classroom":
			classroom_portal = portal
			break
	if classroom_portal == null:
		h.check("校门地图有教学楼门区", false, true)
		main.queue_free()
		return
	var classroom_stand := _reachable_portal_stand(main.current_map,
		classroom_portal, main.current_map.spawn_point(&"near_classroom"))
	if classroom_stand == Vector2.INF:
		h.check("教学楼门区附近存在可走落点", false, true)
		main.queue_free()
		return
	main.player.global_position = classroom_stand
	h.check("技能未解锁也可启动校门追逐", main.escape_session.begin("gate"), true)
	h.check("技能未解锁也可直接进教学楼", main.escape_session.try_exit(), true)
	h.check("直接进门结束本段追逐", main.escape_session.active, false)
	main.escape_session._finish(false)
	main.flags.set_value(&"ch2/personal/stealth_available", true)
	main.flags.set_value(&"ch2/personal/stealth_started", false)
	h.check("技能解锁后可选择是否隐蔽", main.escape_session.begin("gate"), true)
	h.check("F测试时校门追逐仍激活", main.escape_session.active, true)
	h.check("F测试时阶段为校门", main.escape_session.phase, "gate")
	h.check("F测试时隐蔽能力已解锁",
		main.flags.get_value(&"ch2/personal/stealth_available"), true)
	h.check("解锁后未按F也可进门", main.escape_session.try_exit(), true)
	h.check("重新启动后仍能选择F隐蔽", main.escape_session.begin("gate"), true)
	h.check("手动会话只返回离开结果，由剧情登记成功", main.flags.get_value(&"ch2/escape_succeeded"), null)
	h.check("解锁后逃跑中可主动F隐蔽", main.escape_session.activate_stealth(), true)
	h.check("按F后角色获得隐蔽透明度", main.player.modulate.a < 0.6, true)
	h.check("主动F后同样成功离开校门追逐", main.escape_session.try_exit(), true)
	main.escape_session._finish(false)
	main.queue_free()


static func _reachable_portal_stand(map: MapDef, portal: MapDef.Portal,
		origin: Vector2) -> Vector2:
	var margin := Ch2EscapeSession.EXIT_MARGIN * map.player_scale
	var target_area := portal.rect.grow(margin)
	for stand: Vector2 in WalkGrid.reachable(map, origin):
		if target_area.has_point(stand):
			return stand
	return Vector2.INF


static func _barrier_center(def: MapDef) -> Vector2:
	for actor: MapDef.Actor in def.actors:
		if actor.id == &"escape_shelf_barrier" and not actor.collision_rects().is_empty():
			return actor.collision_rects()[0].get_center()
	return Vector2.INF
