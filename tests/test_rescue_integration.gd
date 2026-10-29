extends RefCounted


static func run(h: TestHarness) -> void:
	h.section("第二章C救援整合")
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/events/ch2_swing.json"))
	var event := StoryEvent.from_dictionary(raw)
	h.check("C救援剧情校验", event.validate(), [])

	var rescue_entry := _node(event, &"rescue_entry")
	h.check("救援剧情入口节点", rescue_entry.id, &"rescue_entry")
	h.check("开场先建立救援专属检查点",
		rescue_entry.stage[0].kind, &"ch2_checkpoint_save")
	h.check("救援检查点使用独立类型",
		rescue_entry.stage[0].text("checkpoint"), "rescue")
	h.check("检查点之后进入正式挑战", rescue_entry.next_id, &"challenge")

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
	var retry := _node(event, &"retry")
	h.check("重试回到同一场小游戏", retry.next_id, &"challenge")
	h.check("重试恢复救援专属检查点", retry.stage[1].kind, &"ch2_checkpoint_restore")
	h.check("重试检查点类型", retry.stage[1].text("checkpoint"), "rescue")
	var ending := _node(event, &"ending")
	h.check("退出节点清理救援专属检查点", ending.stage[0].kind, &"ch2_checkpoint_clear")
	h.check("退出清理的检查点类型", ending.stage[0].text("checkpoint"), "rescue")
	h.check("旧铁律结局仍保留",
		DataLoader.load_endings().ids().has(&"end4_iron"), true)

	var rescued := _node(event, &"rescued")
	h.check("成功后标记 C 已获救", rescued.effects.get(&"ch2/rescued_c"), true)
	h.check("成功后出现组队确认", _choice_ids(rescued), [&"agree"])
	h.check("组队确认进入当前节点", rescued.choices[0].next_id, &"join_c")
	var join_c := _node(event, &"join_c")
	h.check("组队后保留 C 的操场等待交互",
		join_c.stage[0].text("talk"), "ch2_c_wait")
	h.check("组队节点进入当前奖励节点", join_c.next_id, &"grant_coin")
	var grant_coin := _node(event, &"grant_coin")
	h.check("组队后获得决策币", grant_coin.effects.get(&"item/charm"), 1)
	h.check("C 立绘文件存在", FileAccess.file_exists("res://art/portrait/c/neutral.png"), true)
	h.check("旧的未生成立绘引用已清除",
		FileAccess.get_file_as_string("res://data/events/ch2_swing.json")
			.contains("c_rescue_v1"), false)

	var main := h.new_main()
	main.flags.clear_changes()
	main.flags.set_value(&"item/charm", 1)
	main._announce_items()
	h.check("决策币提示按稿件显示名称与数量",
		main.toast.current_text(), "获得 决策币×1")
	main.flags.unset_value(&"item/charm")
	main.flags.clear_changes()
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
	h.check("操场入场立即显示唯一受困C", main.cutscene.actor_ids(), ["c"])
	h.check("救援前未预置获救状态",
		main.flags.has_value(&"ch2/rescued_c"), false)
	var c_actor: Node2D = main.cutscene._actor("c")
	var binding: Sprite2D = c_actor.get_node_or_null("RescueBinding") as Sprite2D
	h.check("救援复用场上唯一的 C", main.cutscene.actor_ids(), ["c"])
	h.check("受困 C 使用正面静止动画", (c_actor as AnimatedSprite2D).animation, &"idle_down")
	var animated_c := c_actor as AnimatedSprite2D
	var c_frame_size := animated_c.sprite_frames.get_frame_texture(
		animated_c.animation, animated_c.frame).get_size()
	h.check("束缚与 C 的源帧画布等大，父节点统一缩放",
		binding.texture.get_size() * binding.scale, c_frame_size)
	h.check("束缚中心按 C 帧画布对齐",
		binding.position, Vector2(0, -c_frame_size.y * 0.5))
	h.check("初始束缚使用完整状态图", binding.texture.resource_path,
		"res://art/fx/rescue_c/rescue_bind_state_01.png")
	var actor_snapshot: Array = main.cutscene.snapshot_actors()
	h.check("存档记录 C 的受困外观", actor_snapshot[0].get("rescue_binding"), true)
	main.flags.set_value(&"ch2/rescued_c", true)
	main.cutscene.clear_actors()
	main.cutscene.restore_actors(actor_snapshot)
	c_actor = main.cutscene._actor("c")
	h.check("已获救状态读档不恢复束缚",
		c_actor.get_node_or_null("RescueBinding"), null)
	main.flags.unset_value(&"ch2/rescued_c")
	main.cutscene.clear_actors()
	main.cutscene.restore_actors(actor_snapshot)
	c_actor = main.cutscene._actor("c")
	binding = c_actor.get_node_or_null("RescueBinding") as Sprite2D
	h.check("救援前检查点读档恢复完整束缚",
		binding.texture.resource_path,
		"res://art/fx/rescue_c/rescue_bind_state_01.png")

	main.rescue_panel.allow_background_process = true
	main.rescue_panel.set_binding_sprite(binding)
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
	main.rescue_panel.model.phase = 0.25
	main.rescue_panel.submit()
	h.check("练习成功不减少束缚", binding.texture.resource_path,
		"res://art/fx/rescue_c/rescue_bind_state_01.png")
	main.rescue_panel.submit()
	main.rescue_panel.model.phase = 0.25
	main.rescue_panel.submit()
	h.check("第一次正式成功切换状态02", binding.texture.resource_path,
		"res://art/fx/rescue_c/rescue_bind_state_02.png")
	main.rescue_panel.model.phase = 0.0
	main.rescue_panel.submit()
	h.check("正式失误保留当前束缚", binding.texture.resource_path,
		"res://art/fx/rescue_c/rescue_bind_state_02.png")
	main.rescue_panel.submit()
	main.rescue_panel.model.phase = 0.25
	main.rescue_panel.submit()
	h.check("第二次正式成功切换状态03", binding.texture.resource_path,
		"res://art/fx/rescue_c/rescue_bind_state_03.png")
	main.rescue_panel.model.phase = 0.25
	main.rescue_panel.submit()
	h.check("第三次正式成功隐藏束缚层", binding.visible, false)
	h.check("救援正式成功需要三条线", RescueTiming.LINE_COUNT, 3)
	for frame: int in 3:
		if success_finished[0]:
			break
		await h.root.get_tree().process_frame
	h.check("救援成功后演出继续", success_finished[0], true)
	h.check("成功结果写入剧情状态",
		main.flags.get_value(&"ch2/rescue_success"), true)

	main.flags.unset_value(&"ch2/rescue_success")
	var failed_finished: Array[bool] = [false]
	_finish_rescue(main.cutscene, rescue_step, failed_finished)
	await h.root.get_tree().process_frame
	h.check("失败重试前再次从完整束缚开始",
		binding.texture.resource_path,
		"res://art/fx/rescue_c/rescue_bind_state_01.png")
	main.rescue_panel.model.phase = 0.25
	main.rescue_panel.submit()
	main.rescue_panel.submit()
	main.rescue_panel.model.phase = 0.25
	main.rescue_panel.submit()
	for mistake: int in RescueTiming.ERROR_LIMIT:
		main.rescue_panel.model.phase = 0.0
		main.rescue_panel.submit()
		if main.rescue_panel.model.state != RescueTiming.State.FAILED:
			main.rescue_panel.submit()
	h.check("失败前已有成功仍显示状态02", binding.texture.resource_path,
		"res://art/fx/rescue_c/rescue_bind_state_02.png")
	for frame: int in 3:
		if failed_finished[0]:
			break
		await h.root.get_tree().process_frame
	h.check("三次正式失误结束本轮救援", failed_finished[0], true)
	h.check("救援正式失败阈值为三次失误", RescueTiming.ERROR_LIMIT, 3)
	h.check("失败结果写入剧情状态为否",
		main.flags.get_value(&"ch2/rescue_success"), false)
	h.check("失败结束后清理束缚显示", binding.visible, false)
	main.flags.unset_value(&"ch2/rescue_success")
	var retry_finished: Array[bool] = [false]
	_finish_rescue(main.cutscene, rescue_step, retry_finished)
	await h.root.get_tree().process_frame
	h.check("失败重试重新显示完整束缚", binding.visible, true)
	h.check("失败重试恢复状态01", binding.texture.resource_path,
		"res://art/fx/rescue_c/rescue_bind_state_01.png")
	main.cutscene.cancel()
	for frame: int in 3:
		if retry_finished[0]:
			break
		await h.root.get_tree().process_frame
	h.check("取消剧情关闭小游戏面板", main.rescue_panel.is_open(), false)
	h.check("取消时隐藏并清理受困 C", main.cutscene.actor_ids(), [])
	h.check("取消期间不写入救援结果",
		main.flags.has_value(&"ch2/rescue_success"), false)
	main.queue_free()
	await _test_yard_c_interaction(h)


## 沙坑大交互框覆盖 C 周围，仍应优先选择近身且面向的 C。
static func _test_yard_c_interaction(h: TestHarness) -> void:
	for offset: Vector2 in [Vector2(-12,16), Vector2(-18,0), Vector2(18,0)]:
		var main := h.new_main()
		main.cutscene.instant = true
		main.flags.set_value(&"ch2/rescued_c", true)
		main.enter_map(&"school_yard", &"from_gate", true)
		var c: Node2D = main.cutscene._actor("c")
		var point: Vector2 = c.position + offset
		main.player.position = point
		main.player.facing = -offset.normalized()
		h.check("C周围对话脚点可站立：%s" % offset, WalkGrid.has_landing_room(main.current_map,point), true)
		main.interact()
		h.check("面向C时沙坑不抢交互：%s" % offset, main.story.event_id, &"ch2_c_wait")
		h.check("和C交谈不误领沙坑道具：%s" % offset, ItemTable.count_of(main.flags,&"student_id"), 0)
		main.queue_free()
		await h.root.get_tree().process_frame
	var main := h.new_main()
	main.cutscene.instant = true
	main.flags.set_value(&"ch2/rescued_c", true)
	main.enter_map(&"school_yard", &"from_gate", true)
	var c: Node2D = main.cutscene._actor("c")
	main.player.position = c.position + Vector2(18,0)
	main.player.facing = Vector2.DOWN
	main.interact()
	h.check("面向沙坑时仍可调查脚边沙坑", main.has_seen(&"ch2_sandbox"), true)
	h.check("未面向C不强制开启C对话", main.has_seen(&"ch2_c_wait"), false)
	main.queue_free()
	await h.root.get_tree().process_frame
	main = h.new_main()
	main.cutscene.instant = true
	main.flags.set_value(&"ch2/rescued_c", true)
	main.enter_map(&"school_yard", &"from_gate", true)
	c = main.cutscene._actor("c")
	main.player.position = c.position + Vector2(-12,32)
	main.player.facing = Vector2.RIGHT
	h.check("沙坑正常调查脚点可站立", WalkGrid.has_landing_room(main.current_map,main.player.position), true)
	main.interact()
	h.check("离开C近身范围可正常调查沙坑", main.has_seen(&"ch2_sandbox"), true)
	h.check("远处调查沙坑不误触C", main.has_seen(&"ch2_c_wait"), false)
	main.queue_free()
	await h.root.get_tree().process_frame


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
