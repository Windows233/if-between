## 状态试走、并列比较和快捷键设置的独立定向入口。
##
## 使用真实 MapView / Player、隔离视口及 Viewport.push_input 验证 GUI。
##
## 父入口可 await run(harness)；不导入资源，不修改正式地图或编辑器模型。
extends SceneTree

const Preview := preload("res://addons/if_map_editor/map_object_preview.gd")
const Options := preload("res://addons/if_map_editor/map_preview_options.gd")
const Shortcuts := preload("res://addons/if_map_editor/map_shortcuts.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


func _initialize() -> void:
	call_deferred("_standalone")


func _standalone() -> void:
	root.size = Vector2i(1180, 900)
	root.gui_embed_subwindows = true
	var harness := TestHarness.new()
	harness.setup(root)
	await run(harness)
	quit(0 if harness.report() else 1)


static func fixture() -> Dictionary:
	return {"id": "unsaved_flags", "name": "未保存状态地图", "size": [360, 240],
		"spawns": {"start": [48, 112], "side": [40, 200]}, "walls": [],
		"actors": [
			{"id": "gate", "label": "状态门", "rect": [128, 64, 48, 100], "hidden": true,
				"collision": [[0, 0, 48, 100]], "reach_local": [-20, -10, 88, 120],
				"if": {"var": "gate_closed", "value": true}, "event": "must_not_run"},
			{"id": "visitor", "label": "访客", "rect": [240, 140, 32, 40], "person": true,
				"if": {"exists": "visitor"}},
			{"id": "score_prop", "rect": [288, 160, 32, 32], "solid": true,
				"if": {"all": [{"var": "score", "op": ">=", "value": 2},
					{"any": [{"var": "mood", "value": "night"}, {"exists": "badge"}]}]}}
		], "portals": [{"id": "exit", "label": "出口", "rect": [12, 150, 32, 36],
			"if": {"not": {"var": "gate_closed", "value": true}},
			"blocked_by": "sealed", "blocked_text": "门暂时锁住了", "event": "must_not_run"}]}


static func run(harness: TestHarness) -> void:
	harness.section("状态试走 / 只读比较 / 快捷键设置")
	_test_shortcuts(harness)
	_test_options(harness)
	await _test_preview(harness)
	await _test_gui(harness)
	await _test_comparison_gui(harness)


static func _key(code: int, pressed := true) -> InputEventKey:
	var event := Shortcuts.key_event(code)
	event.pressed = pressed
	return event


static func _test_shortcuts(harness: TestHarness) -> void:
	var path := "user://test_map_preview_shortcuts_%s.cfg" % Time.get_ticks_usec()
	var shortcuts := Shortcuts.new(path)
	for action: String in Shortcuts.DEFAULTS:
		for code: int in Shortcuts.DEFAULTS[action]:
			harness.check("保留默认快捷键 " + action, shortcuts.action_for(_key(code)), action)
	harness.check("松开按键不执行动作", shortcuts.action_for(_key(KEY_Z | KEY_MASK_CTRL, false)), "")
	var echo := _key(KEY_Z | KEY_MASK_CTRL)
	echo.echo = true
	harness.check("按键重复不执行动作", shortcuts.action_for(echo), "")
	harness.check("鼠标事件不执行动作", shortcuts.action_for(InputEventMouseButton.new()), "")
	harness.check("额外修饰键不误触聚焦", shortcuts.action_for(_key(KEY_F | KEY_MASK_ALT)), "")
	var physical := InputEventKey.new()
	physical.physical_keycode = KEY_C
	physical.ctrl_pressed = true
	physical.pressed = true
	harness.check("物理键事件也能匹配", shortcuts.action_for(physical), "copy")
	harness.check("Shortcut 可直接注入按钮", shortcuts.get_shortcut("copy").matches_event(_key(KEY_C | KEY_MASK_CTRL)), true)
	var conflict := shortcuts.set_binding("paste", [_key(KEY_C | KEY_MASK_CTRL)], false)
	harness.check("拒绝占用别的动作按键", conflict.is_empty(), false)
	harness.check("拒绝冲突不覆盖原配置", shortcuts.action_for(_key(KEY_V | KEY_MASK_CTRL)), "paste")
	harness.check("重复按键也拒绝", shortcuts.set_binding("copy", [physical, physical], false).is_empty(), false)
	harness.check("未知动作拒绝", shortcuts.set_binding("unknown", [], false).is_empty(), false)
	harness.check("仅修饰键拒绝", shortcuts.set_binding("copy", [_key(KEY_CTRL)], false).is_empty(), false)
	harness.check("按键修改并持久化", shortcuts.set_binding("copy", [_key(KEY_K | KEY_MASK_CTRL)]), "")
	var loaded := Shortcuts.new(path)
	harness.check("ConfigFile 重载成功", loaded.load_settings(), OK)
	harness.check("重载使用自定义按键", loaded.action_for(_key(KEY_K | KEY_MASK_CTRL)), "copy")
	harness.check("重载后原绑定释放", loaded.action_for(_key(KEY_C | KEY_MASK_CTRL)), "")
	harness.check("Shortcut 保留重做两个入口", loaded.get_shortcut("redo").events.size(), 2)
	harness.check("开始捕获", loaded.begin_capture("paste"), true)
	harness.check("忽略修饰键但保留捕获", loaded.capture_event(_key(KEY_SHIFT), false), false)
	harness.check("冲突事件被处理", loaded.capture_event(_key(KEY_K | KEY_MASK_CTRL), false), true)
	harness.check("冲突后允许继续输入", loaded.capture_action, "paste")
	harness.check("捕获反馈冲突", loaded.last_error.is_empty(), false)
	harness.check("无冲突捕获成功", loaded.capture_event(_key(KEY_J | KEY_MASK_CTRL), false), true)
	harness.check("成功后退出捕获", loaded.capture_action, "")
	harness.check("捕获后的按键执行正确动作", loaded.action_for(_key(KEY_J | KEY_MASK_CTRL)), "paste")
	loaded.begin_capture("copy")
	loaded.capture_event(_key(KEY_ESCAPE), false)
	harness.check("Esc 取消捕获", loaded.capture_action, "")
	var invalid := ConfigFile.new()
	invalid.set_value("shortcuts", "copy", [KEY_V | KEY_MASK_CTRL])
	harness.check("写入损坏配置夹具", invalid.save(path), OK)
	harness.check("加载跨动作冲突配置失败", loaded.load_settings(), ERR_INVALID_DATA)
	harness.check("失败加载保持当前配置", loaded.action_for(_key(KEY_J | KEY_MASK_CTRL)), "paste")
	harness.check("恢复默认且保存", loaded.restore_defaults(), OK)
	harness.check("恢复后重做备用键仍在", loaded.action_for(_key(KEY_Z | KEY_MASK_CTRL | KEY_MASK_SHIFT)), "redo")
	harness.check("恢复后自定义键释放", loaded.action_for(_key(KEY_J | KEY_MASK_CTRL)), "")
	var failing := Shortcuts.new("user://missing_preview_options_dir/shortcuts.cfg")
	harness.check("保存失败明确拒绝", failing.set_binding("copy", [_key(KEY_K | KEY_MASK_CTRL)]).is_empty(), false)
	harness.check("保存失败回滚按键", failing.action_for(_key(KEY_C | KEY_MASK_CTRL)), "copy")
	harness.check("删除测试配置", DirAccess.remove_absolute(ProjectSettings.globalize_path(path)), OK)


static func _test_options(harness: TestHarness) -> void:
	var model := Model.new()
	model.data = fixture()
	model.map_id = "unsaved_flags"
	model.reset_history()
	model.dirty = true
	var original := JSON.stringify(model.data)
	var history: Array = model._history.duplicate(true)
	var options := Options.new()
	options.configure(model)
	for key: String in ["gate_closed", "visitor", "score", "mood", "badge", "sealed"]:
		harness.check("识别嵌套条件或门禁变量 " + key, options.flag_rows.has(key), true)
	harness.check("初始状态保持变量不存在", options.get_options().flags, {})
	options.set_flag("gate_closed", false)
	options.set_flag("score", 3.5)
	options.set_flag("mood", "night")
	options.set_flag("badge", null)
	var settings := options.get_options()
	harness.check("布尔 false 与未设置区分", settings.flags.get("gate_closed"), false)
	harness.check("数字字段保留小数", settings.flags.get("score"), 3.5)
	harness.check("文本状态不变成 JSON 字符串", settings.flags.get("mood"), "night")
	harness.check("null 状态保留键", settings.flags.has("badge"), true)
	options.set_flag("badge", true, false)
	harness.check("取消勾选移除变量", options.get_options().flags.has("badge"), false)
	settings.flags["score"] = 99
	harness.check("返回选项与界面状态隔离", options.get_options().flags.score, 3.5)
	harness.check("当前地图比较取未保存数据", options.comparison_data("unsaved_flags"), model.data)
	harness.check("不存在的比较图不加载", options.comparison_data("../../project"), {})
	var comparison := options.create_comparison("unsaved_flags", {"flags": {"gate_closed": true}})
	harness.root.add_child(comparison)
	harness.check("并列比较真实创建两块面板", comparison.get_child_count(), 2)
	var left: Control = comparison.get_child(0)
	var right: Control = comparison.get_child(1)
	harness.check("左侧强制只读", left.options.read_only, true)
	harness.check("右侧强制只读", right.options.read_only, true)
	harness.check("比较两侧状态独立", left.flags.get_value(&"gate_closed"), false)
	harness.check("比较另一侧状态", right.flags.get_value(&"gate_closed"), true)
	harness.check("比较两侧物理世界独立", left.view.get_viewport().world_2d == right.view.get_viewport().world_2d, false)
	model.data.actors[0].rect[0] = 180
	harness.check("比较图保留创建时快照", left.definition.actors[0].rect.position.x, 128.0)
	model.data.actors[0].rect[0] = 128
	harness.check("选项和比较不改变源布局", JSON.stringify(model.data), original)
	harness.check("选项和比较不改变历史", model._history, history)
	harness.check("选项和比较不改变脏状态", model.dirty, true)
	harness.check("选项和比较不改变地图路径", model.path, "")
	comparison.free()
	options.free()


static func _test_preview(harness: TestHarness) -> void:
	var preview := Preview.new()
	harness.root.add_child(preview)
	preview.configure(fixture(), {"flags": {"gate_closed": false}, "spawn": "side", "show_ranges": true})
	preview.set_physics_process(false)
	preview.show()
	harness.check("选中出生点用于未保存预览", preview.player.position, Vector2(40, 200))
	harness.check("初始范围选项生效", preview._range_toggle.button_pressed, true)
	harness.check("地图与覆盖层共享 WorldState", preview._ranges.flags, preview.flags)
	harness.check("条件不满足的物件无实体", _actor_shapes(preview).size(), 0)
	harness.check("条件不满足的物件不可交互", preview.definition.actor_near(Vector2(148, 112), 48, preview.flags), null)
	preview.player.position = Vector2(148, 112)
	preview.player.facing = Vector2.RIGHT
	var before := preview.player.position
	preview.set_options({"flags": {"gate_closed": true}})
	harness.check("flag 切换重建真实物件实体", _actor_shapes(preview).size(), 1)
	harness.check("隐藏编辑器物件仍参与 runtime 碰撞", _actor_shapes(preview)[0].disabled, false)
	harness.check("切换状态不强挪角色", preview.player.position, before)
	harness.check("被新碰撞阻挡给出警告", preview.panel._warning.visible, true)
	harness.check("警告说明保留原位置", preview.panel._warning.text.contains("保留原位置"), true)
	var flags_before := preview.flags.snapshot()
	harness.check("交互检查命中真实条件物件", preview.panel.inspect_interaction().contains("状态门"), true)
	harness.check("交互检查不执行演出或修改状态", preview.flags.snapshot(), flags_before)
	preview.set_options({"flags": {"gate_closed": false, "visitor": null}})
	harness.check("移除条件实体后警告解除", preview.panel._warning.visible, false)
	harness.check("存在性条件遵循 null 语义", _actor_shapes(preview).size(), 0)
	preview.set_options({"flags": {"gate_closed": false, "visitor": true, "score": 3, "mood": "night"}})
	harness.check("存在性与嵌套条件构造真实碰撞", _actor_shapes(preview).size(), 2)
	preview.set_options({"flags": {"gate_closed": false, "sealed": true}})
	preview.player.position = Vector2(24, 170)
	harness.check("门禁检查反馈但不运行事件", preview.panel.inspect_interaction().contains("门暂时锁住了"), true)
	preview.set_options({"flags": {"gate_closed": true}, "spawn": "start"})
	await harness.root.get_tree().physics_frame
	await harness.root.get_tree().physics_frame
	preview.player.walk_path = [Vector2(220, 112)]
	for frame: int in 100:
		await harness.root.get_tree().physics_frame
		preview.player._physics_process(1.0 / Engine.physics_ticks_per_second)
	harness.check("开启条件后真实物理阻挡行走", preview.player.position.x <= 128.0 - Player.FOOT_SIZE.x * 0.5 + 0.1, true)
	preview.set_options({"flags": {"gate_closed": false}})
	await harness.root.get_tree().physics_frame
	await harness.root.get_tree().physics_frame
	preview.player.walk_path = [Vector2(220, 112)]
	for frame: int in 70:
		await harness.root.get_tree().physics_frame
		preview.player._physics_process(1.0 / Engine.physics_ticks_per_second)
	harness.check("关闭条件后真实物理通路恢复", preview.player.position.x > 184.0, true)
	harness.check("多次重建只保留一套地图节点", preview.view.get_child_count(), 1)
	preview.free()


static func _actor_shapes(preview: Window) -> Array[CollisionShape2D]:
	var shapes: Array[CollisionShape2D] = []
	for collision: CollisionShape2D in preview._ranges.collision_shapes:
		if collision.get_parent().name == "Actors":
			shapes.append(collision)
	return shapes


static func _frames(node: Node) -> void:
	await node.get_tree().process_frame
	await node.get_tree().process_frame


static func _click(viewport: Viewport, position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		viewport.push_input(event, true)


static func _choose(viewport: Viewport, picker: OptionButton, selected: int) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = picker.get_global_rect().get_center()
	press.global_position = press.position
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(press, true)
	await _frames(picker)
	var popup := picker.get_popup()
	var row_height := float(popup.get_contents_minimum_size().y) / float(popup.item_count)
	var position := Vector2(popup.position) + Vector2(popup.size.x * 0.5, row_height * (selected + 0.5))
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	await _frames(picker)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = position
	release.global_position = position
	viewport.push_input(release, true)
	if popup.visible:
		_click(viewport, position)
	await _frames(picker)


static func _type_text(viewport: Viewport, field: LineEdit, text: String) -> void:
	_click(viewport, field.get_global_rect().get_center())
	viewport.push_input(_key(KEY_A | KEY_MASK_CTRL), true)
	viewport.push_input(_key(KEY_BACKSPACE), true)
	for character: String in text:
		var event := InputEventKey.new()
		event.pressed = true
		event.unicode = character.unicode_at(0)
		viewport.push_input(event, true)
	viewport.push_input(_key(KEY_ENTER), true)
	await _frames(field)


static func _test_gui(harness: TestHarness) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1180, 900)
	viewport.world_2d = World2D.new()
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	harness.root.add_child(viewport)
	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(split)
	var model := Model.new()
	model.data = fixture()
	model.map_id = "unsaved_flags"
	model.reset_history()
	var options := Options.new()
	split.add_child(options)
	options.configure(model)
	var received: Array[Dictionary] = []
	var comparisons: Array[Dictionary] = []
	options.preview_requested.connect(func(settings: Dictionary) -> void: received.append(settings))
	options.compare_requested.connect(func(map_id: String, settings: Dictionary) -> void:
		comparisons.append({"map_id": map_id, "options": settings}))
	var settings_panel := Options.ShortcutsPanel.new()
	var path := "user://test_map_shortcuts_gui_%s.cfg" % Time.get_ticks_usec()
	var shortcuts := Shortcuts.new(path)
	split.add_child(settings_panel)
	settings_panel.configure(shortcuts)
	await _frames(split)
	var gate: Dictionary = options.flag_rows["gate_closed"]
	_click(viewport, gate.enabled.get_global_rect().get_center())
	await _frames(split)
	harness.check("GUI 勾选已有状态变量", options.get_options().flags.gate_closed, true)
	_click(viewport, gate.boolean.get_global_rect().get_center())
	await _frames(split)
	harness.check("GUI 可设置 false", options.get_options().flags.gate_closed, false)
	await _choose(viewport, options._spawn, 2)
	harness.check("GUI 下拉选择出生点", options.get_options().spawn, "side")
	var score: Dictionary = options.flag_rows.score
	var scroll: ScrollContainer = options._flag_list.get_parent()
	scroll.ensure_control_visible(score.number)
	await _frames(split)
	_click(viewport, score.enabled.get_global_rect().get_center())
	await _type_text(viewport, score.number.get_line_edit(), "4.5")
	harness.check("GUI 数字状态字段真实输入", options.get_options().flags.get("score"), 4.5)
	var mood: Dictionary = options.flag_rows.mood
	scroll.ensure_control_visible(mood.text)
	await _frames(split)
	_click(viewport, mood.enabled.get_global_rect().get_center())
	await _type_text(viewport, mood.text, "night")
	harness.check("GUI 文本状态字段真实输入", options.get_options().flags.get("mood"), "night")
	var ranges: CheckBox = options.get_node("ShowRanges")
	_click(viewport, ranges.get_global_rect().get_center())
	var preview_button: Button = options.get_node("RequestPreview")
	_click(viewport, preview_button.get_global_rect().get_center())
	await _frames(split)
	harness.check("明确试走按钮真实点击发出信号", received.size(), 1)
	if not received.is_empty():
		harness.check("试走信号携带 UI 设置", received[0].show_ranges, true)
		harness.check("试走信号携带选中出生点", received[0].spawn, "side")
	var compare_index := -1
	for index: int in options._compare_map.item_count:
		if str(options._compare_map.get_item_metadata(index)).ends_with("_night"):
			compare_index = index
			break
	harness.check("比较入口提供真实昼夜地图", compare_index >= 0, true)
	var expected_map := "unsaved_flags"
	if compare_index >= 0:
		expected_map = str(options._compare_map.get_item_metadata(compare_index))
		await _choose(viewport, options._compare_map, compare_index)
		harness.check("GUI 比较下拉真实选择夜间地图", options._compare_map.selected, compare_index)
	var compare_button: Button = options.get_node("RequestCompare")
	_click(viewport, compare_button.get_global_rect().get_center())
	await _frames(split)
	harness.check("明确比较按钮真实点击发出信号", comparisons.size(), 1)
	if not comparisons.is_empty():
		harness.check("比较按钮使用选中的只读地图", comparisons[0].map_id, expected_map)
		harness.check("比较信号强制只读", comparisons[0].options.read_only, true)
		harness.check("比较不切正式模型地图", model.map_id, "unsaved_flags")
	var copy_button: Button = settings_panel._buttons.copy[0]
	_click(viewport, copy_button.get_global_rect().get_center())
	await _frames(split)
	harness.check("GUI 点击开始捕获", shortcuts.capture_action, "copy")
	viewport.push_input(_key(KEY_V | KEY_MASK_CTRL), true)
	await _frames(split)
	harness.check("GUI 按键捕获拒绝冲突", settings_panel._message.text.contains("冲突"), true)
	viewport.push_input(_key(KEY_K | KEY_MASK_CTRL), true)
	await _frames(split)
	harness.check("GUI 捕获成功且应用", shortcuts.action_for(_key(KEY_K | KEY_MASK_CTRL)), "copy")
	var reload := Shortcuts.new(path)
	harness.check("GUI 捕获结果持久化", reload.load_settings(), OK)
	harness.check("GUI 保存结果可重载", reload.action_for(_key(KEY_K | KEY_MASK_CTRL)), "copy")
	var reset: Button = settings_panel.get_node("RestoreShortcuts")
	_click(viewport, reset.get_global_rect().get_center())
	await _frames(split)
	harness.check("GUI 恢复默认真实点击", shortcuts.action_for(_key(KEY_C | KEY_MASK_CTRL)), "copy")
	harness.check("GUI 不改变正式模型历史", model._history.size(), 1)
	harness.check("GUI 不保存正式模型", model.dirty, false)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		harness.check("GUI 渲染产生图像", image != null and not image.is_empty(), true)
		if image != null and not image.is_empty():
			harness.check("保存 GUI 验证截图", image.save_png("res://.godot/preview-options-validation/options-gui.png"), OK)
	harness.check("清理 GUI 测试配置", DirAccess.remove_absolute(ProjectSettings.globalize_path(path)), OK)
	viewport.free()


static func _test_comparison_gui(harness: TestHarness) -> void:
	var left_data := fixture()
	left_data["background"] = "res://art/props/gatehouse_desk.png"
	var right_data := left_data.duplicate(true)
	right_data["id"] = "comparison_night"
	right_data["name"] = "另一个只读状态"
	var comparison := Preview.create_comparison(left_data, right_data,
		{"flags": {"gate_closed": false}, "show_ranges": true},
		{"flags": {"gate_closed": true}, "show_ranges": true})
	var window := AcceptDialog.new()
	window.title = "只读比较 GUI 验证"
	window.add_child(comparison)
	harness.root.add_child(window)
	window.popup_centered(Vector2i(1120, 650))
	if DisplayServer.get_name() == "headless":
		window.size = Vector2i(1120, 650)
	await _frames(window)
	var left: Control = comparison.get_child(0)
	var right: Control = comparison.get_child(1)
	harness.check("AcceptDialog 中比较面板撑满内容区", comparison.size.x >= 1080, true)
	harness.check("比较左侧有实际可见画布", left._display.size.x > 300 and left._display.size.y > 300, true)
	harness.check("比较右侧有实际可见画布", right._display.size.x > 300 and right._display.size.y > 300, true)
	harness.check("两侧画布按水平并列显示", right.position.x >= left.position.x + left.size.x, true)
	var position: Vector2 = left.player.position
	left.player.walk_path.append(position + Vector2(80, 0))
	left.advance(1.0 / Engine.physics_ticks_per_second)
	harness.check("只读比较不会执行角色移动", left.player.position, position)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var left_image: Image = left.view.get_viewport().get_texture().get_image()
		var right_image: Image = right.view.get_viewport().get_texture().get_image()
		harness.check("两侧视口都产生真实图像", not left_image.is_empty() and not right_image.is_empty(), true)
		harness.check("不同状态产生不同渲染结果", left_image.get_data() != right_image.get_data(), true)
		harness.check("保存左侧比较截图", left_image.save_png("res://.godot/preview-options-validation/compare-left.png"), OK)
		harness.check("保存右侧比较截图", right_image.save_png("res://.godot/preview-options-validation/compare-right.png"), OK)
		var window_image: Image = window.get_texture().get_image()
		harness.check("保存 AcceptDialog 并列比较截图", window_image.save_png("res://.godot/preview-options-validation/compare-gui.png"), OK)
	window.free()
