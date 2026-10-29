## 按实际交互跑完无血迹前置的图书馆前后两轮，并验证逃跑输入。
## 使用正式事件和地图触发器，不伪造完成标记来跳过开箱、回溯。
extends RefCounted

static func run(h: TestHarness) -> void:
	var main := h.new_main()
	main.cutscene.instant = true
	ItemTable.add(main.flags, &"diary")
	ItemTable.add(main.flags, &"key")
	main.start_story(&"ch2_diary", &"library_enter")
	_drain(main, h)
	var entry: Vector2 = main.current_map.spawn_point(&"from_school_gate")
	var c_entry := preload("res://scenes/library_staging.gd").point(main.current_map, "entry_c")
	h.check("首次入馆C位于门口并面朝左", main.cutscene._actor("c").flip_h, false)
	var shelf := _actor(main.current_map, &"shelf_a")
	var front := false
	for p: Vector2 in WalkGrid.reachable(main.current_map, entry):
		if shelf.reach.has_point(p) and WalkGrid.has_landing_room(main.current_map, p) \
				and p.y >= shelf.collision_rects()[0].end.y:
			front = true
			break
	h.check("用户书架交互区在前方有可达脚点", front, true)
	main.begin_interaction(shelf)
	h.check("书架对话不放大书架", main.object_preview.content, null)
	_drain(main, h)
	h.check("读书完成且没有调查血迹", main.flags.get_value(&"ch2/library/shelf_seen"), true)
	h.check("血迹不是首次猫事件前置", main.flags.get_value(&"ch2/library/blood_seen"), null)
	var cat := _actor(main.current_map, &"cat_monster")
	main.player.global_position = Vector2(cat.reach.position.x + 4, cat.reach.end.y - 4)
	var stopped: Vector2 = main.player.global_position
	main.player.walk_path.assign([stopped, entry])
	h.check("走入猫区域自动触发", main.map_triggers.update(stopped), true)
	h.check("触发后主角原地停住", main.player.global_position, stopped)
	h.check("触发后清除原行走路径", main.player.walk_path.is_empty(), true)
	var carpet := preload("res://scenes/library_staging.gd").point(main.current_map, "carpet_c")
	h.check("C从入口走到地毯", main.cutscene._actor("c").position, carpet)
	_drain(main, h)
	h.check("首次猫对话进入日记媒介选择", main.cutscene.is_inventory_select_active(), true)
	h.check("日记可供选择", main.cutscene.choose_inventory_selection(&"diary"), true)
	_drain(main, h)
	h.check("背叛后完成时间回溯", main.flags.get_value(&"ch2/library/rewound"), true)
	h.check("回溯后主角在馆门入口", main.player.global_position, entry)
	h.check("回溯后C也在原入口", main.cutscene._actor("c").position, c_entry)
	h.check("回溯后C面朝左", main.cutscene._actor("c").flip_h, false)
	main.begin_interaction(shelf)
	_drain(main, h)
	h.check("再次读书看到新一页", main.flags.get_value(&"ch2/library/fairy_tale_second"), true)
	main.begin_interaction(_actor(main.current_map, &"box"))
	_drain(main, h)
	h.check("无二次血迹调查也能打开宝箱", main.flags.get_value(&"ch2/library/box_opened"), true)
	h.check("合照进入背包", ItemTable.has(main.flags, &"group_photo"), true)
	main.cutscene.instant = false
	h.check("开箱后自动进入猫对话", main.map_triggers.update(main.player.global_position), true)
	h.check("二次猫对话C仍留在门口", main.cutscene._actor("c").position, c_entry)
	h.check("猫在对话框右侧有立绘", main.dialogue.slot_portrait(DialogueLine.Side.RIGHT) != null, true)
	var panel := Rect2(Vector2(0,main.dialogue.hold_top()),Vector2(main.get_viewport_rect().size.x,main.get_viewport_rect().size.y-main.dialogue.hold_top()))
	for slot: DialoguePortrait in main.dialogue._slots:
		if slot.side == DialogueLine.Side.RIGHT:
			h.check("猫立绘完整放在对话框内",panel.encloses(Rect2(slot.sprite.position,slot.sprite.size)),true)
	var cat_scene := DataLoader.load_event(&"ch2_library_cat").node(&"second_scene")
	var portraits_ok := true
	for step: StageStep in cat_scene.stage:
		for line: Dictionary in step.data.get("lines",[]):
			if line.get("speaker","") == "猫":
				portraits_ok = portraits_ok and line.get("portrait","") == "res://art/props/library_cat_cover.png" and line.get("side","") == "right"
	h.check("回溯后的猫台词复用现有立绘",portraits_ok,true)
	h.check("猫对话不会残留宝箱近景", main.object_preview.content, null)
	main.cutscene.instant = true
	_drain(main, h)
	h.check("猫说完后C走回第一次地毯位置", main.cutscene._actor("c").position, carpet)
	main.chase_overlay.cancel_qte()
	main.story.cancel()
	# 不携带撬棍仍会进入要求的倒架段。
	var success := DataLoader.load_event(&"ch2_library_cat").node(&"dodge_success")
	h.check("QTE成功无需撬棍条件即可倒架", success.next_id, &"crowbar_used")
	h.check("QTE成功不再被道具分支跳过倒架", success.next_when.is_empty(), true)
	main.enter_map(&"library", &"from_school_gate", true)
	for code: int in [KEY_E, KEY_SPACE]:
		main.player.global_position = entry
		h.check("双交互键专项追逐启动", main.escape_session.begin("library"), true)
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = code
		main._unhandled_input(key)
		h.check("E和空格均可从馆门逃出：%s" % code, main.escape_session.active, false)
	main.queue_free()
	await h.root.get_tree().process_frame

static func _drain(main: Node2D, h: TestHarness) -> void:
	for i: int in 8:
		if not main.dialogue.is_open():
			break
		h.drain_dialogue(main.dialogue)

static func _actor(def: MapDef, id: StringName) -> MapDef.Actor:
	for actor: MapDef.Actor in def.actors:
		if actor.id == id:
			return actor
	return null
