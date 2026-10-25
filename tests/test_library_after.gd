## 图书馆后段：数据绑定、分支契约与个人锚点回溯。
class_name TestLibraryAfter
extends RefCounted


static func run(h: TestHarness) -> void:
	test_events_and_endings(h)
	test_map_bindings(h)
	test_anchor_personal_flags(h)
	test_checkpoint_keeps_persistent_state(h)
	test_new_stage_steps(h)
	await test_cancelled_dodge_qte_can_restart(h)


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
		h.check("窗边绑定抛币事件",
			_has_event(_actor(classroom, &"classroom_window"), &"ch2_classroom_window"), true)
		var classroom_window_reachable := false
		var classroom_flags := WorldState.new()
		for point: Vector2 in WalkGrid.reachable(classroom, classroom.spawn_point(&"from_gate")):
			if WalkGrid.has_landing_room(classroom, point) \
					and classroom.actor_near(point, 24.0, classroom_flags) == _actor(classroom, &"classroom_window"):
				classroom_window_reachable = true
				break
		h.check("教室窗边有可达交互站位", classroom_window_reachable, true)
		var back_gate := _portal(classroom, &"back_gate")
		h.check("隐蔽路线后门受阻", back_gate != null and back_gate.blocked_by == "ch2/personal/stealth_started", true)
	if market != null:
		var market_flags := WorldState.new()
		var b_anchor := _actor(market, &"b_end_anchor")
		h.check("夜市 B 前置未满足时隐藏", b_anchor != null and b_anchor.is_active(market_flags), false)
		market_flags.set_value(&"ch2/left_veil_realm", true)
		h.check("夜市 B 离界后显示", b_anchor != null and b_anchor.is_active(market_flags), true)
		var south_gate := _portal(market, &"south_gate")
		if south_gate == null and not market.portals.is_empty():
			south_gate = market.portals[0]
		h.check("夜市 B 物件不与南门本体重叠",
			b_anchor != null and south_gate != null and not b_anchor.rect.intersects(south_gate.rect), true)
		h.check("夜市接应点绑定 B 事件",
			_has_event(b_anchor, &"ch2_market_b_end"), true)


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
	var first_task: Variant = main.chase_session.run_dodge_qte(&"q")
	main.chase_session.cancel()
	var second_task: Variant = main.chase_session.run_dodge_qte(&"q")
	var restarted := false
	for _frame: int in 20:
		await h.root.get_tree().process_frame
		if main.chase_overlay.is_running():
			restarted = true
			break
	h.check("取消后的独立闪避 QTE 可以重启", restarted, true)
	main.chase_session.cancel()
	var first_result: bool = await first_task
	var second_result: bool = await second_task
	h.check("取消后的旧 QTE 正常结束", first_result, false)
	h.check("取消后的新 QTE 正常结束", second_result, false)
	h.check("取消后的 QTE 状态已清理", main.chase_session.qte_pending, false)
	main.queue_free()


static func test_new_stage_steps(h: TestHarness) -> void:
	var restore := StageStep.from_dictionary({"do": "personal_anchor_restore"})
	var dodge := StageStep.from_dictionary({"do": "ch2_dodge_qte", "key": "q"})
	var variant := StageStep.from_dictionary({
		"do": "map_actor_variant",
		"actor": "box",
		"variant": "open",
	})
	h.check("个人锚点恢复指令合法", restore.validate(), [])
	h.check("独立闪避 QTE 指令合法", dodge.validate(), [])
	h.check("地图贴图变体指令合法", variant.validate(), [])


static func _actor(definition: MapDef, actor_id: StringName) -> MapDef.Actor:
	for actor: MapDef.Actor in definition.actors:
		if actor.id == actor_id:
			return actor
	return null


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
