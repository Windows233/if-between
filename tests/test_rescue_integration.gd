extends RefCounted


static func run(h: TestHarness) -> void:
	h.section("第二章秋千救援整合")
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/events/ch2_swing.json"))
	var event := StoryEvent.from_dictionary(raw)
	h.check("秋千救援剧情校验", event.validate(), [])

	var intro := _node(event, &"cutscene")
	h.check("开场先自动存档", intro.stage[0].kind, &"save")
	h.check("C 在秋千处登场", intro.stage[2].kind, &"npc")
	h.check("C 的脚底位置", intro.stage[2].point("at"), Vector2(186, 88))
	h.check("救援前 C 使用受困朝向", intro.stage[2].text("pose"), "side")
	h.check("开场由 C 提醒别碰线",
		intro.stage[3].dialogue().lines[0].text, "别碰线。碰了会——")

	var challenge := _node(event, &"challenge")
	h.check("小游戏是剧情演出步骤", challenge.stage[1].kind, &"rescue")
	var flags := WorldState.new()
	flags.set_value(&"ch2/rescue_success", true)
	h.check("成功进入获救段落", challenge.resolved_next(flags), &"rescued")
	flags.set_value(&"ch2/rescue_success", false)
	h.check("失败进入结局演出", challenge.resolved_next(flags), &"failed")

	var failed := _node(event, &"failed")
	h.check("失败后不提前解锁结局", failed.effects.has(&"ending/end4_arrogant"), false)
	h.check("失败提供重试和退出", _choice_ids(failed), [&"retry", &"finish"])
	h.check("重试回到同一场小游戏", _node(event, &"retry").next_id, &"challenge")
	h.check("退出选项進入新結局节点", _node(event, &"ending").ending, &"end4_arrogant")
	h.check("旧铁律结局仍保留",
		DataLoader.load_endings().ids().has(&"end4_iron"), true)

	var rescued := _node(event, &"rescued")
	h.check("成功后标记 C 已获救", rescued.effects.get(&"ch2/rescued_c"), true)
	h.check("成功段落包含后续会面", rescued.next_id, &"gift")
	var gift := _node(event, &"gift")
	h.check("成功后获得御守", gift.effects.get(&"item/charm"), 1)
	h.check("C 留在秋千旁等待交谈",
		gift.stage[1].text("talk"), "ch2_c_wait")
	h.check("C 立绘文件存在", FileAccess.file_exists("res://art/portrait/c_base.png"), true)
	h.check("旧的未生成立绘引用已清除",
		FileAccess.get_file_as_string("res://data/events/ch2_swing.json")
			.contains("c_rescue_v1"), false)

	var main := h.new_main()
	main._on_rescue_feedback(&"success")
	h.check("成功判定播放对应音效", main.last_sound,
		"res://audio/sfx/rescue_success.wav")
	main._on_rescue_feedback(&"mistake")
	h.check("失误判定播放对应音效", main.last_sound,
		"res://audio/sfx/rescue_mistake.wav")
	main._on_rescue_feedback(&"complete")
	h.check("救援完成播放对应音效", main.last_sound,
		"res://audio/sfx/rescue_complete.wav")
	main.enter_map(&"school_yard", &"from_gate")
	main.rescue_panel.allow_background_process = true
	main.rescue_panel.open()
	var input := InputEventKey.new()
	input.physical_keycode = KEY_SPACE
	input.pressed = true
	main._unhandled_input(input)
	h.check("主入口把空格交给救援面板",
		main.rescue_panel.model.state, RescueTiming.State.PRACTICE_FEEDBACK)
	input.physical_keycode = KEY_F5
	main._unhandled_input(input)
	h.check("小游戏期间快捷键不打开存档菜单",
		main.save_menu.is_open(), false)
	main.rescue_panel.close()

	var rescue_step := StageStep.from_dictionary({
		"do": "rescue", "flag": "ch2/rescue_success",
	})
	var success_finished: Array[bool] = [false]
	_finish_rescue(main.cutscene, rescue_step, success_finished)
	await h.root.get_tree().process_frame
	h.check("演出协程等待救援完成", main.rescue_panel.is_open(), true)
	main.rescue_panel.model.submit()
	main.rescue_panel.model.submit()
	for line: int in RescueTiming.LINE_COUNT:
		main.rescue_panel.model.phase = 0.25
		main.rescue_panel.submit()
	for frame: int in 3:
		if success_finished[0]:
			break
		await h.root.get_tree().process_frame
	h.check("救援成功后演出继续", success_finished[0], true)
	h.check("成功结果写入剧情状态",
		main.flags.get_value(&"ch2/rescue_success"), true)

	main.flags.unset_value(&"ch2/rescue_success")
	var cancelled_finished: Array[bool] = [false]
	_finish_rescue(main.cutscene, rescue_step, cancelled_finished)
	await h.root.get_tree().process_frame
	main.cutscene.cancel()
	for frame: int in 3:
		if cancelled_finished[0]:
			break
		await h.root.get_tree().process_frame
	h.check("取消剧情关闭小游戏面板", main.rescue_panel.is_open(), false)
	h.check("取消期间不写入救援结果",
		main.flags.has_value(&"ch2/rescue_success"), false)
	main.queue_free()


static func _finish_rescue(
		cutscene: Cutscene, step: StageStep, finished: Array[bool]) -> void:
	await cutscene._perform(step)
	finished[0] = true


static func _node(event: StoryEvent, id: StringName) -> StoryNode:
	for node: StoryNode in event.nodes:
		if node.id == id:
			return node
	return StoryNode.new()


static func _choice_ids(node: StoryNode) -> Array[StringName]:
	var ids: Array[StringName] = []
	for choice: StoryChoice in node.choices:
		ids.append(choice.id)
	return ids
