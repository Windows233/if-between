extends SceneTree

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const Shortcuts := preload("res://addons/if_map_editor/map_shortcuts.gd")
const Harness := preload("res://tests/test_harness.gd")
const TemplateList := preload("res://addons/if_map_editor/map_template_list.gd")


class MemoryShortcuts extends Shortcuts:
	func load_settings() -> Error:
		return ERR_FILE_NOT_FOUND


class FixtureDock extends Dock:
	var save_requests := 0

	func _ready() -> void:
		_shortcuts = MemoryShortcuts.new()
		_editor_state_path = "user://scene_tools_gui_unused.cfg"
		_build()
		_map_picker.add_item("内存场景工具夹具")

	func _on_save() -> void:
		save_requests += 1


func _initialize() -> void:
	call_deferred("_standalone")


func _standalone() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var harness := Harness.new()
	harness.setup(root)
	await run(harness)
	quit(0 if harness.report() else 1)


static func fixture() -> Dictionary:
	return {"id": "scene_tools_gui_memory", "name": "场景工具 GUI 内存夹具",
		"size": [400, 300], "walls": [[240, 180, 30, 20]], "portals": [],
		"spawns": {"start": [200, 150]}, "actors": [
			{"id": "desk", "label": "夹具书桌", "rect": [80, 60, 70, 45],
				"decor": true, "collision": [[0, 30, 70, 15]]}],
		"triggers": [{"id": "zone", "rect": [0, 0, 40, 40],
			"event": "ch2_library_locked", "mode": "enter", "enabled": true, "once": false}]}


static func _frames(node: Node) -> void:
	var tree := node.get_tree()
	await tree.process_frame
	await tree.process_frame


static func _click(viewport: Viewport, point: Vector2) -> void:
	while viewport is Window and viewport.is_embedded():
		point += Vector2(viewport.position)
		viewport = viewport.get_parent().get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.position = point
		button.global_position = point
		button.button_index = MOUSE_BUTTON_LEFT
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		button.pressed = pressed
		viewport.push_input(button, true)


static func _reachable(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree() or not control.get_global_rect().has_area():
		return false
	var bounds := control.get_global_rect()
	if not control.get_viewport().get_visible_rect().encloses(bounds):
		return false
	var ancestor := control.get_parent()
	while ancestor is Control:
		if ancestor.clip_contents and not ancestor.get_global_rect().encloses(bounds):
			return false
		ancestor = ancestor.get_parent()
	var viewport := control.get_viewport()
	while viewport is Window and viewport.is_embedded():
		bounds.position += Vector2(viewport.position)
		viewport = viewport.get_parent().get_viewport()
		if not viewport.get_visible_rect().encloses(bounds):
			return false
	return not (control is BaseButton and control.disabled)


static func _tap(control: Control, scroll: ScrollContainer = null) -> bool:
	if control == null:
		return false
	if scroll != null:
		scroll.ensure_control_visible(control)
	await _frames(control)
	if not _reachable(control):
		return false
	var viewport := control.get_viewport()
	_click(viewport, control.get_global_rect().get_center())
	await _frames(viewport)
	return true


static func _button(parent: Node, caption: String) -> Button:
	for child: Node in parent.get_children():
		if child is Button and child.text == caption:
			return child
		var found := _button(child, caption)
		if found != null:
			return found
	return null


static func _window(parent: Node, title_prefix: String) -> Window:
	for child: Node in parent.get_children():
		if child is Window and child.title.begins_with(title_prefix):
			return child
	return null


static func _tab(tabs: TabContainer, index: int) -> void:
	var bar := tabs.get_tab_bar()
	_click(bar.get_viewport(), bar.get_global_rect().position + bar.get_tab_rect(index).get_center())
	await _frames(tabs)


static func _shot(harness: TestHarness, viewport: SubViewport, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scene-tools-shot-dir="):
			var directory := argument.trim_prefix("--scene-tools-shot-dir=")
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var error := ERR_CANT_CREATE
			if not image.is_empty():
				error = image.save_png(directory.path_join(name + ".png"))
			harness.check("真实渲染截图 " + name, error, OK)


static func _config_snapshot() -> Dictionary:
	var result := {}
	for path: String in [Shortcuts.DEFAULT_PATH, Dock.EDITOR_STATE_PATH, "user://scene_tools_gui_unused.cfg"]:
		result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result


static func run(harness: TestHarness) -> void:
	harness.section("场景工具主界面真实 GUI 入口集成")
	var original_configs := _config_snapshot()
	var display := TextureRect.new()
	display.size = Vector2(1600, 900)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	harness.root.add_child(display)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.gui_disable_input = false
	viewport.gui_embed_subwindows = true
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	display.add_child(viewport)
	display.texture = viewport.get_texture()
	viewport.handle_input_locally = true
	var template_preview := TemplateList.TemplatePreview.new()
	template_preview.actor = MapDef._actor_from({"id": "preview", "rect": [0, 0, 80, 60],
		"sprite": "res://art/props/gatehouse_desk.png", "quarter_turns": 1, "flip_h": true})
	template_preview.position = Vector2(100, 100)
	template_preview.zoom = 0.5
	viewport.add_child(template_preview)
	await _frames(display)
	harness.check("模板拖动预览在真实画布中保持缩放", template_preview.zoom, 0.5)
	harness.check("模板拖动预览使用运行时视觉路径", template_preview.actor.visual_sprites(), PackedStringArray(["res://art/props/gatehouse_desk.png"]))
	template_preview.queue_free()
	var dock := FixtureDock.new()
	viewport.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.model.map_id = "scene_tools_gui_memory"
	dock.model.data = fixture()
	dock.model.reset_history()
	dock.canvas.load_map(dock.model, "", "", dock.model.map_size())
	await _frames(dock)
	dock._set_initial_panel_layout()
	await _frames(dock)
	for index: int in dock._asset_tabs.get_tab_count():
		if dock._asset_tabs.get_tab_title(index) == "工具":
			await _tab(dock._asset_tabs, index)
			break
	harness.check("主界面工具页可通过 GUI 切换", dock._asset_tabs.get_current_tab_control().name, &"工具")
	await _tap(_button(dock._asset_tabs, "显示吸附网格"))
	harness.check("网格开关真实点击连接画布", dock.canvas.show_grid, true)
	await _tap(_button(dock._asset_tabs, "锁定墙"))
	harness.check("图层锁真实点击连接画布", dock.canvas.locked_layers.get("walls", false), true)
	harness.check("显示与图层锁不改地图数据", dock.model.data, fixture())
	var selected: Array[int] = [0]
	dock.canvas.select_actors(selected)
	dock._on_selection_changed()
	await _frames(dock)
	var visual: Control
	var template: Control
	for child: Node in dock._actor_panel.get_children():
		if child.get_script() == Dock.VisualInspector:
			visual = child
		if child.get_script() == Dock.TemplateInspector:
			template = child
	harness.check("选中物件挂载视觉与模板属性卡", visual != null and template != null, true)
	if visual != null:
		await _tap(visual.find_child("AdvancedAppearanceToggle", true, false), dock._panel_scroll)
		await _tap(_button(visual, "添加视觉部件"), dock._panel_scroll)
		harness.check("视觉部件按钮真实点击修改内存模型", dock.model.actor_field(0, "visual_parts", []).size(), 1)
		dock.model.undo()
		dock._on_selection_changed()
		await _frames(dock)
	await _shot(harness, viewport, "01-main")
	var opened := await _tap(_button(dock._asset_tabs, "场景检查 / 触发 / 试走设置…"))
	var dialog := _window(dock, "场景工具 · ") as AcceptDialog
	harness.check("主界面按钮真实点击打开场景工具", opened and dialog != null and dialog.visible, true)
	if dialog == null:
		display.free()
		return
	var tabs: TabContainer
	for child: Node in dialog.get_children():
		if child is TabContainer:
			tabs = child
	var titles: Array[String] = []
	if tabs != null:
		for index: int in tabs.get_tab_count():
			titles.append(tabs.get_tab_title(index))
	harness.check("四页标题与顺序", titles, ["校验与迁移", "事件触发区域", "试走状态与地图比较", "快捷键"])
	if tabs == null or tabs.get_tab_count() != 4:
		display.free()
		return
	var review_scroll := tabs.get_tab_control(0) as ScrollContainer
	var review = review_scroll.get_child(0)
	await _tap(_button(review, "一键校验"), review_scroll)
	harness.check("校验按钮真实点击产出报告", not review._report.is_empty(), true)
	var before_migration: Dictionary = dock.model.data.duplicate(true)
	var migration_requests: Array = []
	review.review_requested.connect(func(report: Dictionary) -> void: migration_requests.append(report))
	review._walls.get_root().get_first_child().set_checked(0, true)
	await _tap(_button(review, "加入 / 更新此物件"), review_scroll)
	await _tap(_button(review, "预览整批迁移"), review_scroll)
	harness.check("迁移预览按钮真实点击生成候选", review._preview.get("ok", false), true)
	harness.check("迁移预览不发保存请求且不改模型", migration_requests.is_empty() and dock.save_requests == 0 and dock.model.data == before_migration, true)
	await _shot(harness, viewport, "02-review")
	await _tab(tabs, 1)
	harness.check("真实点击切换事件触发页", tabs.current_tab, 1)
	var trigger_scroll := tabs.get_tab_control(1) as ScrollContainer
	var triggers = trigger_scroll.get_child(0)
	var list: ItemList = triggers._list
	_click(list.get_viewport(), list.get_global_rect().position + list.get_item_rect(0).get_center())
	await _frames(dock)
	harness.check("真实点击触发列表选择区域", triggers.selected_index, 0)
	harness.check("触发选择连接画布定位", dock.canvas.selected_trigger, 0)
	harness.check("触发区域定位到画布中心", (dock.canvas.pan + Vector2(20, 20) * dock.canvas.zoom).distance_to(dock.canvas.size * 0.5) < 1.0, true)
	var took_bounds := await _tap(triggers.find_child("UseSelectionBounds", true, false), trigger_scroll)
	harness.check("从选区取矩形按钮可达", took_bounds, true)
	harness.check("真实点击将物件选区写入触发矩形", triggers.trigger_rect(0), dock.model.rect_of(Dock.Kind.ACTOR, 0))
	await _tap(triggers.find_child("TriggerOnce", true, false), trigger_scroll)
	harness.check("触发 once 勾选真实写入模型", dock.model.data.triggers[0].once, true)
	var applied := await _tap(triggers.find_child("ApplyCondition", true, false), trigger_scroll)
	harness.check("条件按钮可滚动到可点击区域", applied, true)
	await _shot(harness, viewport, "03-triggers")
	await _tab(tabs, 2)
	harness.check("真实点击切换试走与比较页", tabs.current_tab, 2)
	var options_scroll := tabs.get_tab_control(2) as ScrollContainer
	var options = options_scroll.get_child(0)
	await _tap(options.find_child("ShowRanges", true, false), options_scroll)
	harness.check("预览范围选项真实点击生效", options.get_options().show_ranges, true)
	var before_preview: Dictionary = dock.model.data.duplicate(true)
	await _tap(options.find_child("RequestPreview", true, false), options_scroll)
	var preview := _window(dock, "场景试走：")
	harness.check("试走按钮真实点击创建预览窗口", preview != null and preview.visible, true)
	if preview != null:
		harness.check("试走复制当前未保存模型", preview.get("panel").definition.id, dock.model.map_id)
		await _shot(harness, viewport, "04a-preview-window")
		preview.queue_free()
		await _frames(dock)
	for index: int in options._compare_map.item_count:
		if str(options._compare_map.get_item_metadata(index)) == dock.model.map_id:
			options._compare_map.select(index)
			options._comparison_selected(index)
	await _tap(options.find_child("RequestCompare", true, false), options_scroll)
	var comparison := _window(dock, "地图并排比较 · ")
	harness.check("比较按钮真实点击创建窗口", comparison != null and comparison.visible, true)
	if comparison != null:
		var split: HSplitContainer
		for child: Node in comparison.get_children():
			if child is HSplitContainer:
				split = child
		harness.check("比较窗口显示两个独立面板", split.get_child_count() if split != null else 0, 2)
		if split != null and split.get_child_count() == 2:
			harness.check("比较双方均为只读", split.get_child(0).options.read_only and split.get_child(1).options.read_only, true)
		harness.check("比较窗口关闭按钮在父视口内完整可达", _reachable((comparison as AcceptDialog).get_ok_button()), true)
		print("Comparison geometry: position=", comparison.position, " size=", comparison.size,
			" close=", (comparison as AcceptDialog).get_ok_button().get_global_rect())
		await _shot(harness, viewport, "04b-comparison-window")
		comparison.queue_free()
		await _frames(dock)
	harness.check("试走和比较不修改地图模型", dock.model.data, before_preview)
	await _shot(harness, viewport, "04-preview-options")
	await _tab(tabs, 3)
	harness.check("真实点击切换快捷键页", tabs.current_tab, 3)
	var shortcut_scroll := tabs.get_tab_control(3) as ScrollContainer
	var shortcuts = shortcut_scroll.get_child(0)
	await _tap(shortcuts._buttons["copy"][0], shortcut_scroll)
	harness.check("快捷键按钮真实点击开始捕获", dock._shortcuts.capture_action, "copy")
	harness.check("捕获按钮提供明确反馈", shortcuts._buttons["copy"][0].text, "请按键…")
	dock._shortcuts.cancel_capture()
	var copy_key := Shortcuts.key_event(KEY_C | KEY_MASK_CTRL)
	copy_key.pressed = true
	harness.check("取消捕获不改变原绑定", dock._shortcuts.action_for(copy_key), "copy")
	await _shot(harness, viewport, "05-shortcuts")
	harness.check("用户配置未写入且夹具无地图写入路径", _config_snapshot() == original_configs and dock.model.path.is_empty(), true)
	display.free()
	await _frames(harness.root)
