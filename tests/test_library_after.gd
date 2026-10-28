## 图书馆后段：数据绑定、分支契约与个人锚点回溯。
class_name TestLibraryAfter
extends RefCounted


static func run(h: TestHarness) -> void:
	test_events_and_endings(h)
	await test_market_ending_contract(h)
	test_map_bindings(h)
	test_anchor_personal_flags(h)
	test_checkpoint_keeps_persistent_state(h)
	test_new_stage_steps(h)
	await test_dynamic_inventory_selection(h)
	await test_approach_actor_completes(h)
	await test_chase_burst_animation_and_collision(h)
	test_window_marker_and_delivery_timing(h)
	test_library_art_restoration(h)
	await test_cancelled_dodge_qte_can_restart(h)
	await test_duel_qte_input_and_cleanup(h)


static func test_approach_actor_completes(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	main.cutscene.instant = false
	main.player.global_position = Vector2(251, 296)
	await main.cutscene._approach_map_actor(&"library_cat_visual", 8.0)
	var cat := _actor(main.current_map, &"library_cat_visual")
	h.check("接近黑猫剧情可在对话后继续",
		cat != null and MapDef.rect_distance(cat.reach, main.player.global_position) <= 8.0, true)
	main.queue_free()


static func test_chase_burst_animation_and_collision(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	var player: Player = main.player
	player.global_position = Vector2(233.0, 190.0)
	var start := player.global_position
	var base_time_scale := Engine.time_scale
	Engine.time_scale = 1.0
	h.check("冲刺侧向动画有四帧", player._sprite.sprite_frames.get_frame_count(&"burst_side"), 4)
	h.check("四帧动画贯穿冲刺时长",
		player._sprite.sprite_frames.get_animation_speed(&"burst_side"), Player.CHASE_BURST_FPS)
	player.start_chase_burst(Vector2.RIGHT)
	h.check("冲刺立即切换四帧动作", player._sprite.animation, &"burst_side")
	await h.root.get_tree().physics_frame
	var initial_speed := player._chase_burst_velocity.length()
	h.check("冲刺起始锁住常规移动输入", player.chase_input_locked, true)
	for _frame: int in 7:
		await h.root.get_tree().physics_frame
	var early_speed := player._chase_burst_velocity.length()
	for _frame: int in 9:
		await h.root.get_tree().physics_frame
	var peak_speed := player._chase_burst_velocity.length()
	for _frame: int in 9:
		await h.root.get_tree().physics_frame
	var decelerating_speed := player._chase_burst_velocity.length()
	h.check("冲刺速度先从静止平滑上升", early_speed > initial_speed, true)
	h.check("冲刺速度先增至峰值", peak_speed > early_speed, true)
	h.check("冲刺经过峰值后平滑减速", decelerating_speed < peak_speed, true)
	h.check("冲刺平均速度快于常规行走",
		Player.CHASE_BURST_DISTANCE / Player.CHASE_BURST_DURATION > player.movement_speed(), true)
	for _frame: int in 10:
		await h.root.get_tree().physics_frame
	var displacement := player.global_position.x - start.x
	h.check("冲刺确实沿选定方向移动", displacement > 0.0, true)
	h.check("冲刺距离不会过度拉开",
		displacement < Player.CHASE_BURST_DISTANCE * player.scale.x + 1.0, true)
	h.check("四帧动作结束后冲刺停止", player.is_chase_bursting(), false)
	h.check("冲刺结束立即释放移动输入", player.chase_input_locked, false)

	player.global_position = start
	var wall := StaticBody2D.new()
	wall.position = start + Vector2(22.0, 0.0)
	var collision := CollisionShape2D.new()
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(10.0, 48.0)
	collision.shape = wall_shape
	wall.add_child(collision)
	main.add_child(wall)
	await h.root.get_tree().physics_frame
	player.start_chase_burst(Vector2.RIGHT)
	for _frame: int in 40:
		await h.root.get_tree().physics_frame
		if not player.is_chase_bursting():
			break
	var blocked_displacement := player.global_position.x - start.x
	h.check("平滑冲刺仍受障碍碰撞拦截", blocked_displacement < 22.0, true)
	h.check("碰撞后输入锁立即释放", player.chase_input_locked, false)
	Engine.time_scale = base_time_scale
	main.queue_free()


static func test_duel_qte_input_and_cleanup(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	var base_zoom: Vector2 = main.camera.zoom
	var base_speed := Engine.time_scale
	var result: Array[bool] = []
	_collect_dodge(main, result)
	var overlay: ChaseOverlay = main.chase_overlay
	overlay._set_freeze_reason(ChaseOverlay.FREEZE_FOCUS, false)
	h.check("C对抗进入真实慢动作", Engine.time_scale, 0.2)
	h.check("C对抗拉近镜头", main.camera.zoom.is_equal_approx(base_zoom * 1.3), true)
	h.check("C对抗不是黑雾提示", overlay._caption.text, "C 正在逼近")
	h.check("C对抗按键面板居中", absf(overlay._panel_rect.get_center().x - 160.0) < 1, true)
	overlay._warning_until_usec = Time.get_ticks_usec() - 1
	overlay._process(0)
	h.check("预警后显示指定按键", overlay._key_label.text, "Q")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_E
	overlay.handle_input(key)
	h.check("错键保留剩余反应机会", overlay.is_running(), true)
	key.physical_keycode = KEY_Q
	overlay.handle_input(key)
	h.check("正确按键真正成功", result, [true])
	h.check("成功后时间恢复", Engine.time_scale, base_speed)
	h.check("成功后镜头恢复", main.camera.zoom.is_equal_approx(base_zoom), true)
	h.check("成功后输入锁释放", main.chase_session.qte_pending, false)
	var timeout_result: Array[bool] = []
	_collect_dodge(main, timeout_result)
	overlay._warning_until_usec = Time.get_ticks_usec() - 1
	overlay._process(0)
	overlay._active_until_usec = Time.get_ticks_usec() - 1
	overlay._process(0)
	h.check("超时走真实失败出口", timeout_result, [false])
	h.check("失败后时间恢复", Engine.time_scale, base_speed)
	h.check("失败后镜头恢复", main.camera.zoom.is_equal_approx(base_zoom), true)
	h.check("后续黑雾QTE仍可启动", overlay.start_qte(&"e"), true)
	h.check("黑雾追逐没有沿用C提示", overlay._caption.text, "黑雾逼近")
	overlay.cancel_qte()
	main.queue_free()


static func test_library_art_restoration(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	var cat := _actor(main.current_map, &"library_cat_visual")
	var blood := _actor(main.current_map, &"library_blood_visual")
	h.check("独立猫图层存在且不抢交互", cat != null and cat.decor, true)
	h.check("独立血迹图层存在且不挡路", blood != null and blood.decor and not blood.solid, true)
	if cat == null or blood == null:
		main.queue_free()
		return
	h.check("首次入馆猫可见", cat.sprite_variant, "visible")
	h.check("首次调查前旧血迹已可见", blood.sprite_variant, "visible")
	h.check("图书馆个人锚点捕获", main.capture_personal_anchor(), true)
	main.flags.set_value(&"ch2/personal/library_cat_hidden", true)
	main.refresh_scene()
	h.check("净化后恢复正确隐藏图层", _actor(main.current_map, &"library_cat_visual").sprite_variant, "hidden")
	h.check("个人回溯成功", main.restore_personal_anchor(), true)
	h.check("回溯后猫回到锚点外观", _actor(main.current_map, &"library_cat_visual").sprite_variant, "visible")
	h.check("地图血迹标记未随个人回溯消失", main.flags.get_value(&"map_blood/library/entrance"), true)
	h.check("回溯后地图血迹仍可见", _actor(main.current_map, &"library_blood_visual").sprite_variant, "visible")
	main.queue_free()


static func test_events_and_endings(h: TestHarness) -> void:
	var endings := DataLoader.load_endings()
	var event_ids: Array[StringName] = [
		&"ch2_library_blood",
		&"ch2_library_shelf",
		&"ch2_library_box",
		&"ch2_library_cat",
		&"ch2_classroom_window",
		&"ch2_market_b_end",
	]
	for event_id: StringName in event_ids:
		var event := DataLoader.load_event(event_id, endings.ids())
		h.check("后段事件可载入：%s" % event_id, event != null, true)
		if event != null:
			h.check("后段事件合法：%s" % event_id, event.validate(endings.ids()), [])
	h.check("End6 已登记", endings.get_ending(&"end6_sin") != null, true)
	h.check("End7 已登记", endings.get_ending(&"end7_rewritten") != null, true)


static func test_dynamic_inventory_selection(h: TestHarness) -> void:
	var main := h.new_main()
	main.cutscene.instant = true
	ItemTable.add(main.flags, &"diary")
	ItemTable.add(main.flags, &"key")
	var event := DataLoader.load_event(&"ch2_library_cat", DataLoader.load_endings().ids())
	var selection: Array[StageStep] = [StageStep.from_dictionary({
		"do": "inventory_select",
		"result": "test/selected_mediator",
	})]
	main.flags.set_value(&"test/selected_mediator", "")
	main.cutscene.run(selection)
	await h.root.get_tree().process_frame
	h.check("道具选择菜单列出背包中真实物品",
		main.choice_menu._options.size(), 2)
	h.check("动态选择菜单有日记项", main.choice_menu._options.any(
		func(option: ChoiceOption) -> bool: return option.id == &"diary"), true)
	h.check("动态选择菜单不列出未持有的吊坠", main.choice_menu._options.any(
		func(option: ChoiceOption) -> bool: return option.id == &"pendant"), false)
	h.check("显示菜单期间不会预扣日记", ItemTable.count_of(main.flags, &"diary"), 1)
	main.choice_menu.select_id(&"key")
	main.choice_menu.confirm()
	await h.root.get_tree().process_frame
	h.check("选择结果记录玩家实际选中的道具",
		main.flags.get_value(&"test/selected_mediator"), "key")
	h.check("选择错误道具不扣日记", ItemTable.count_of(main.flags, &"diary"), 1)

	main.flags.set_value(&"test/selected_mediator", "")
	main.cutscene.run(selection)
	await h.root.get_tree().process_frame
	main.choice_menu.select_id(&"diary")
	main.choice_menu.confirm()
	await h.root.get_tree().process_frame
	h.check("选择日记后才进入确认节点",
		main.flags.get_value(&"test/selected_mediator"), "diary")
	h.check("玩家选择日记时仍未提前扣物", ItemTable.count_of(main.flags, &"diary"), 1)
	var with_diary := event.node(&"diary_consume")
	h.check("媒介确认节点独立执行扣物",
		with_diary != null and float(with_diary.effects.get(&"item/diary", -1)) == 0.0, true)
	h.check("选择完成后菜单关闭", main.choice_menu.is_open(), false)
	main.queue_free()


static func test_window_marker_and_delivery_timing(h: TestHarness) -> void:
	var classroom := DataLoader.load_map(&"classroom")
	var window := _actor(classroom, &"classroom_window")
	var view := MapView.new()
	view.build(classroom, WorldState.new())
	if window != null:
		h.check("窗边持续标记绑定当前交互区", view.set_actor_marker(
			&"classroom_window", "走到标记的窗边，把决策币抛出去。"), true)
		var marker := view._actor_markers.get(&"classroom_window") as Node2D
		var label := marker.get_child(1) as Label if marker != null and marker.get_child_count() > 1 else null
		h.check("窗边目标文字可见", label != null and label.text.contains("决策币"), true)
		var frame := marker.get_child(0) as Line2D if marker != null and marker.get_child_count() > 0 else null
		h.check("窗边目标框覆盖窗actor实际reach", frame != null \
				and frame.points[0].distance_to(window.reach.position) < 0.01, true)
	else:
		h.check("未放置窗户时不生成窗边标记", view.set_actor_marker(
			&"classroom_window", "走到标记的窗边，把决策币抛出去。"), false)
	h.check("交互后可清除窗边目标", view.set_actor_marker(&"", ""), true)
	h.check("清除后不遗留目标框", view._actor_markers.is_empty(), true)

	var main := h.new_main()
	main.enter_map(&"classroom", &"from_gate", true)
	main.flags.set_value(&"ch2/window_marker_active", true)
	main.refresh_scene()
	h.check("保存状态不为未放置窗户恢复标记",
		main.map_view._actor_markers.has(&"classroom_window"), window != null)
	main.queue_free()

	var market := DataLoader.load_map(&"market_night")
	var b_anchor := _actor(market, &"b_end_anchor")
	var meet_action: Dictionary = b_anchor.raw.get("actions", [])[0] if b_anchor != null else {}
	h.check("接近B不提前标记玩偶交付", not meet_action.has("set"), true)
	var ending := DataLoader.load_event(&"ch2_market_b_end", DataLoader.load_endings().ids())
	var delivery := ending.node(&"doll_transfer_apply") if ending != null else null
	h.check("实际玩偶交付节点登记完成", delivery != null \
			and delivery.effects.get(&"ch2/cat_delivered") == true, true)


static func test_market_ending_contract(h: TestHarness) -> void:
	var event := DataLoader.load_event(&"ch2_market_b_end", DataLoader.load_endings().ids())
	h.check("夜市收尾事件可载入供合约测试", event != null, true)
	if event == null:
		return
	var b_arrives := event.node(&"b_arrives")
	var b_spawned_in_event := false
	for step: StageStep in b_arrives.stage:
		if step.kind == &"npc" and step.text("id") == "b":
			b_spawned_in_event = true
	h.check("B 不在玩家交互后才生成", b_spawned_in_event, false)
	var delivery := event.node(&"doll_transfer_apply")
	h.check("玩偶实际交付节点才登记B接应完成", delivery != null \
			and delivery.effects.get(&"ch2/cat_delivered") == true, true)
	var elder_leaves := event.node(&"elder_leaves")
	var ending_results := event.node(&"ending_results")
	h.check("老人离场前不提前写最终世界状态",
		elder_leaves != null and elder_leaves.effects.is_empty(), true)
	var result_caption: StageStep = ending_results.stage[0] if ending_results != null \
			and not ending_results.stage.is_empty() else StageStep.new()
	h.check("结果屏状态在结果屏节点提交",
		ending_results != null and ending_results.effects.get(&"ch2/school_closed") == true \
			and ending_results.effects.get(&"ch2/night_tear_absorbed") == true, true)
	h.check("三条结果等待玩家确认", result_caption.kind == &"caption" \
			and result_caption.flag("wait_click"), true)
	var ending_question := event.node(&"ending_question")
	h.check("结果确认后进入独立疑问屏", ending_question != null, true)
	var reward_check := event.node(&"silver_reward_check")
	var reward := event.node(&"silver_reward")
	h.check("银币奖励节点存在", reward != null, true)
	if reward_check == null or reward == null:
		return
	h.check("银币已领取时跳过重复奖励", reward_check.resolved_next(_flags_with_reward()), &"elder_leaves")
	h.check("银币未领取时进入奖励", reward_check.resolved_next(WorldState.new()), &"silver_reward")
	var add_once: StageStep = reward.stage[0] if not reward.stage.is_empty() else StageStep.new()
	h.check("银币采用幂等增加指令", add_once.kind, &"item_add_once")
	h.check("银币奖励数量为十", add_once.number("amount"), 10.0)
	h.check("银币幂等标记", add_once.text("flag"), "ch2/silver_rewarded")
	var main: Variant = h.new_main()
	main.cutscene.instant = true
	ItemTable.add(main.flags, &"silver_coin", 7)
	var add_steps: Array[StageStep] = [add_once]
	await main.cutscene.run(add_steps)
	h.check("银币奖励保留已有库存并增加十枚",
		ItemTable.count_of(main.flags, &"silver_coin"), 17)
	await main.cutscene.run(add_steps)
	h.check("重播银币奖励不重复增加",
		ItemTable.count_of(main.flags, &"silver_coin"), 17)
	main.queue_free()


static func _flags_with_reward() -> WorldState:
	var flags := WorldState.new()
	flags.set_value(&"ch2/silver_rewarded", true)
	return flags


static func test_map_bindings(h: TestHarness) -> void:
	var library := DataLoader.load_map(&"library")
	var classroom := DataLoader.load_map(&"classroom")
	var market := DataLoader.load_map(&"market_night")
	h.check("图书馆后段地图可载入", library != null, true)
	h.check("教室窗边地图可载入", classroom != null, true)
	h.check("夜市地图可载入", market != null, true)
	if library != null:
		var cat := _actor(library, &"cat_monster")
		var box := _actor(library, &"box")
		var blood := _actor(library, &"library_blood")
		var shelf := _actor(library, &"shelf_a")
		h.check("中央猫绑定调查事件", _has_event(cat, &"ch2_library_cat"), true)
		h.check("盒子绑定调查事件", _has_event(box, &"ch2_library_box"), true)
		h.check("血迹绑定调查事件", _has_event(blood, &"ch2_library_blood"), true)
		h.check("童话书绑定书架事件", _has_event(shelf, &"ch2_library_shelf"), true)
		h.check("盒子有开关贴图", box != null and box.sprite_variants.has("open"), true)
		var flags := WorldState.new()
		var spawn := library.spawn_point(&"from_school_gate")
		var reachable := WalkGrid.reachable(library, spawn)
		var box_reachable := false
		for point: Vector2 in reachable:
			if WalkGrid.has_landing_room(library, point) \
					and library.actor_near(point, 28.0, flags) == box:
				box_reachable = true
				break
		h.check("从图书馆入口可达且能选中盒子的站位", box_reachable, true)
		h.check("首遍线索未调查时猫事件锁定", cat.is_active(flags), false)
		flags.set_value(&"ch2/library/blood_seen", true)
		flags.set_value(&"ch2/library/shelf_seen", true)
		h.check("首遍血迹和书架调查后开放猫事件", cat.is_active(flags), true)
		var cat_event := DataLoader.load_event(&"ch2_library_cat", DataLoader.load_endings().ids())
		var cat_select := cat_event.node(&"first_item_select")
		h.check("媒介选择不提前扣日记", ItemTable.count_of(flags, &"diary"), 0)
		var selection_step := cat_select.stage[0] if not cat_select.stage.is_empty() else StageStep.new()
		h.check("媒介选择使用动态背包菜单", selection_step.kind, &"inventory_select")
		h.check("确认媒介前不会扣除日记", cat_select.effects.is_empty(), true)
		var wrong_item := cat_event.node(&"wrong_item")
		h.check("错选道具不扣物且重新打开选择", \
			wrong_item != null and wrong_item.effects.is_empty() \
				and wrong_item.next_id == &"first_item_select", true)
		var diary_consume := cat_event.node(&"diary_consume")
		var with_diary := cat_event.node(&"with_diary")
		h.check("确认日记的独立节点才扣物，之后才介入", diary_consume != null \
				and float(diary_consume.effects.get(&"item/diary", -1)) == 0.0 \
				and diary_consume.next_id == &"with_diary" \
				and with_diary != null and not with_diary.effects.has(&"item/diary"), true)
		var library_view := MapView.new()
		library_view.build(library, flags)
		var cat_sprite: Sprite2D = library_view._actor_variant_nodes.get(&"library_cat_visual") as Sprite2D
		h.check("图书馆猫贴图可做透明度过渡", cat_sprite != null, true)
		h.check("地图猫淡到50%", library_view.set_actor_alpha(&"library_cat_visual", 0.5), true)
		h.check("猫透明反馈为0.5", cat_sprite != null and is_equal_approx(cat_sprite.modulate.a, 0.5), true)
		h.check("图层复位到不透明", library_view.set_actor_alpha(&"library_cat_visual", 1.0), true)
		h.check("猫透明度复位为1", cat_sprite != null and is_equal_approx(cat_sprite.modulate.a, 1.0), true)
		var approach_event := cat_event.node(&"approach")
		var approach_uses_alpha := false
		for step: StageStep in approach_event.stage:
			if step.kind == &"map_actor_alpha" and is_equal_approx(step.number("alpha"), 0.5):
				approach_uses_alpha = true
		h.check("C穿猫虚影演出触发50%图层Alpha", approach_uses_alpha, true)
		flags.set_value(&"ch2/library/first_betrayal", true)
		flags.set_value(&"ch2/library/rewound", true)
		h.check("回溯后盒子未开时锁定猫事件", cat.is_active(flags), false)
		flags.set_value(&"ch2/library/blood_second_seen", true)
		flags.set_value(&"ch2/library/fairy_tale_second", true)
		flags.set_value(&"ch2/library/box_opened", true)
		h.check("回溯后线索与盒子完成才开放猫事件", cat.is_active(flags), true)
		var box_selectable_with_cat := false
		for point: Vector2 in reachable:
			if WalkGrid.has_landing_room(library, point) \
					and library.actor_near(point, 24.0, flags) == box:
				box_selectable_with_cat = true
				break
		h.check("猫激活后盒子仍有独立可选站位", box_selectable_with_cat, true)
	if classroom != null:
		var classroom_overlay := _actor(classroom, &"new_actor_3")
		h.check("教室全屏遮挡物不截获交互", classroom_overlay != null and classroom_overlay.decor, true)
		var window := _actor(classroom, &"classroom_window")
		h.check("窗边绑定抛币事件",
			_has_event(window, &"ch2_classroom_window"), window != null)
		var classroom_window_reachable := false
		var classroom_flags := WorldState.new()
		if window != null:
			for point: Vector2 in WalkGrid.reachable(classroom, classroom.spawn_point(&"from_gate")):
				if WalkGrid.has_landing_room(classroom, point) \
						and classroom.actor_near(point, 24.0, classroom_flags) == window:
					classroom_window_reachable = true
					break
		h.check("教室窗边可达状态符合对象放置状态", classroom_window_reachable, window != null)
		var marker_view := MapView.new()
		marker_view.build(classroom, classroom_flags)
		h.check("窗边标记可绑定地图reach", marker_view.set_actor_marker(
			&"classroom_window", "走到标记的窗边，把决策币抛出去。"), window != null)
		var marker := marker_view._actor_markers.get(&"classroom_window") as Node2D
		var frame := marker.get_node_or_null("Frame") as Line2D if marker != null else null
		h.check("窗边框覆盖真实交互区", frame != null and window != null \
				and frame.points[0].distance_to(window.reach.position) < 0.01, window != null)
		h.check("窗边标记支持清除", marker_view.set_actor_marker(&"", "") \
				and marker_view._actor_markers.is_empty(), true)
		marker_view.clear()
		var back_gate := _portal(classroom, &"back_gate")
		h.check("隐蔽路线后门受阻", back_gate != null and back_gate.blocked_by == "ch2/personal/stealth_started", true)
	if market != null:
		var market_flags := WorldState.new()
		var b_anchor := _actor(market, &"b_end_anchor")
		h.check("夜市 B 前置未满足时隐藏", b_anchor != null and b_anchor.is_active(market_flags), false)
		market_flags.set_value(&"ch2/left_veil_realm", true)
		h.check("夜市 B 离界后显示", b_anchor != null and b_anchor.is_active(market_flags), true)
		h.check("夜市 B 可见贴图", b_anchor != null and b_anchor.sprite == "res://art/npc/b/down1.png", true)
		h.check("夜市 B 使用下半身显示框", b_anchor != null and b_anchor.rect.size.y == 45.0, true)
		h.check("夜市 B 逻辑脚点在可站位置", b_anchor != null and WalkGrid.is_free(market, Vector2(b_anchor.rect.position.x + b_anchor.rect.size.x * 0.5, b_anchor.rect.end.y)), true)
		market_flags.set_value(&"ch2/cat_delivered", true)
		h.check("完成交接后地图隐藏 B 演员", b_anchor != null and b_anchor.is_active(market_flags), false)
		h.check("完成接应后地图隐藏 B 演员", b_anchor != null and b_anchor.is_active(market_flags), false)
		var south_gate := _portal(market, &"south_gate")
		if south_gate == null and not market.portals.is_empty():
			south_gate = market.portals[0]
		h.check("夜市 B 物件不与南门本体重叠",
			b_anchor != null and south_gate != null and not b_anchor.rect.intersects(south_gate.rect), true)
		h.check("夜市接应点绑定 B 事件",
			_has_event(b_anchor, &"ch2_market_b_end"), true)
	var cat_event := DataLoader.load_event(&"ch2_library_cat", DataLoader.load_endings().ids())
	var diary_consume := cat_event.node(&"diary_consume")
	h.check("确认日记后才扣除一份日记", diary_consume.effects.get(&"item/diary", 1), 0)


static func test_anchor_personal_flags(h: TestHarness) -> void:
	var data := SaveData.new()
	data.map_id = &"library"
	data.spawn = &"from_school_gate"
	data.player_position = Vector2(233, 296)
	var flags := WorldState.new()
	ItemTable.add(flags, &"diary")
	flags.set_value(&"ch2/personal/first_betrayal", false)
	flags.set_value(&"memory/library", "kept")

	var anchor := PersonalAnchor.new()
	h.check("后段个人状态锚点捕获", anchor.capture_once(data, flags), true)
	flags.set_value(&"ch2/personal/first_betrayal", true)
	flags.set_value(&"ch2/personal/new_state", true)
	flags.set_value(&"memory/library", "changed")
	h.check("后段个人状态锚点恢复", anchor.restore(data, flags), true)
	h.check("恢复首次个人状态", flags.get_value(&"ch2/personal/first_betrayal"), false)
	h.check("移除锚点后新增个人状态", flags.has_value(&"ch2/personal/new_state"), false)
	h.check("不回滚记忆状态", flags.get_value(&"memory/library"), "changed")

	var round_trip := PersonalAnchor.new()
	h.check("个人状态随锚点序列化", round_trip.load_dictionary(anchor.to_dictionary()), true)
	h.check("序列化后仍有个人状态", round_trip.to_dictionary().get("personal_flags", {}).has("ch2/personal/first_betrayal"), true)


static func test_checkpoint_keeps_persistent_state(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	h.check("图书馆检查点可捕获", main.capture_ch2_checkpoint("route"), true)
	main.flags.set_value(&"memory/library_after_checkpoint", "remembered")
	main.flags.set_value(&"map_blood/library/entrance", true)
	main.flags.set_value(&"ch2/personal/first_betrayal", true)
	main.flags.set_value(&"ch2/chase_q1", true)
	h.check("追逐检查点恢复成功", main.restore_ch2_checkpoint("route"), true)
	h.check("檢查点恢复保留新记忆",
		main.flags.get_value(&"memory/library_after_checkpoint"), "remembered")
	h.check("检查点恢复保留地图血迹",
		main.flags.get_value(&"map_blood/library/entrance"), true)
	h.check("检查点恢复保留个人事件状态",
		main.flags.get_value(&"ch2/personal/first_betrayal"), true)
	h.check("检查点恢复回滚追逐临时状态",
		main.flags.get_value(&"ch2/chase_q1") != true, true)
	main.queue_free()


static func test_cancelled_dodge_qte_can_restart(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	var first_result: Array[bool] = []
	var second_result: Array[bool] = []
	_collect_dodge(main, first_result)
	main.chase_session.cancel()
	_collect_dodge(main, second_result)
	var restarted := false
	for _frame: int in 20:
		await h.root.get_tree().process_frame
		if main.chase_overlay.is_running():
			restarted = true
			break
	h.check("取消后的独立闪避 QTE 可以重启", restarted, true)
	main.chase_session.cancel()
	h.check("取消后的旧 QTE 正常结束", first_result, [false])
	h.check("取消后的新 QTE 正常结束", second_result, [false])
	h.check("取消后的 QTE 状态已清理", main.chase_session.qte_pending, false)
	main.queue_free()


static func _collect_dodge(main: Variant, result: Array[bool]) -> void:
	result.append(await main.chase_session.run_dodge_qte(&"q"))


static func test_new_stage_steps(h: TestHarness) -> void:
	var restore := StageStep.from_dictionary({"do": "personal_anchor_restore"})
	var dodge := StageStep.from_dictionary({"do": "ch2_dodge_qte", "key": "q"})
	var variant := StageStep.from_dictionary({
		"do": "map_actor_variant",
		"actor": "box",
		"variant": "open",
	})
	var alpha := StageStep.from_dictionary({
		"do": "map_actor_alpha",
		"actor": "library_cat_visual",
		"alpha": 0.5,
		"time": 0.2,
	})
	var invalid_alpha := StageStep.from_dictionary({
		"do": "map_actor_alpha",
		"actor": "library_cat_visual",
		"alpha": 1.5,
	})
	var marker := StageStep.from_dictionary({
		"do": "map_actor_marker",
		"actor": "classroom_window",
		"text": "走到标记的窗边，把决策币抛出去。",
	})
	h.check("个人锚点恢复指令合法", restore.validate(), [])
	h.check("独立闪避 QTE 指令合法", dodge.validate(), [])
	h.check("地图贴图变体指令合法", variant.validate(), [])
	h.check("地图角色透明度指令合法", alpha.validate(), [])
	h.check("地图角色透明度拒绝越界值", invalid_alpha.validate().is_empty(), false)
	h.check("动态地图目标标记指令合法", marker.validate(), [])


static func _actor(definition: MapDef, actor_id: StringName) -> MapDef.Actor:
	for actor: MapDef.Actor in definition.actors:
		if actor.id == actor_id:
			return actor
	return null


static func _flags_with_diary() -> WorldState:
	var flags := WorldState.new()
	ItemTable.add(flags, &"diary")
	return flags


static func _portal(definition: MapDef, portal_id: StringName) -> MapDef.Portal:
	for portal: MapDef.Portal in definition.portals:
		if portal.id == portal_id:
			return portal
	return null


static func _has_event(actor: MapDef.Actor, event_id: StringName) -> bool:
	if actor == null:
		return false
	for interaction: MapDef.Interaction in actor.interactions:
		if interaction.event_id == event_id:
			return true
	return false
