## 贴图属性卡与异步请求回归：只在内存地图上操作，不加载或保存正式地图。
## SubViewport 验证真实按钮点击；外部扫描由信号推进，不依赖编辑器导入时序。
## 可独立 --script 运行，也可由插件入口 await run(harness)。
extends SceneTree

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const Shortcuts := preload("res://addons/if_map_editor/map_shortcuts.gd")


class MemoryShortcuts extends Shortcuts:
	func load_settings() -> Error:
		return ERR_FILE_NOT_FOUND


class FixtureDock extends Dock:
	signal fixture_scan_completed
	var waiting_paths: Dictionary = {}
	var scan_requests := 0

	func _ready() -> void:
		_shortcuts = MemoryShortcuts.new()
		_build()

	func _load_imported_asset(path: String) -> Texture2D:
		if waiting_paths.has(path):
			return null
		var image := Image.load_from_file(path)
		return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null

	func _refresh_assets_after_scan() -> void:
		scan_requests += 1
		await fixture_scan_completed

	func _save_actor_editor_state() -> Error:
		return OK


func _initialize() -> void:
	call_deferred("_standalone")


func _standalone() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	await run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("贴图属性卡按钮与异步请求")
	var folder := "user://__map_texture_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var created := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	h.check("贴图 UI 临时目录可创建", created, OK)
	if created != OK:
		return
	var ready := _create_images(h, folder)
	if ready:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1600, 1000)
		viewport.gui_disable_input = false
		viewport.gui_embed_subwindows = true
		viewport.handle_input_locally = true
		h.root.add_child(viewport)
		var dock := FixtureDock.new()
		viewport.add_child(dock)
		dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dock.model.data = _fixture(folder)
		dock.model.map_id = "texture_ui_fixture"
		dock.model.draft_dir = folder.path_join("unused_drafts")
		dock.model.reset_history()
		dock.canvas.load_map(dock.model, "", "", dock.model.map_size())
		_select(dock, [0])
		await _frames(h.root)
		dock._set_initial_panel_layout()
		await _frames(h.root)
		_test_texture_assignment(h, dock, folder)
		await _test_buttons(h, dock, viewport, folder)
		_test_protected_selection(h, dock)
		await _test_async_requests(h, dock, folder)
		viewport.queue_free()
		await _frames(h.root)
	var directory := DirAccess.open(folder)
	if directory != null:
		for filename: String in directory.get_files():
			h.check("清理贴图 UI 图片 " + filename,
				DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(filename))), OK)
	h.check("清理贴图 UI 临时目录", DirAccess.remove_absolute(ProjectSettings.globalize_path(folder)), OK)


static func _create_images(h: TestHarness, folder: String) -> bool:
	var ready := true
	var dimensions := {"background.png": Vector2i(128, 96), "original.png": Vector2i(32, 16),
		"oversized.png": Vector2i(256, 128), "replacement.png": Vector2i(48, 24)}
	for filename: String in dimensions:
		var image_size: Vector2i = dimensions[filename]
		var image := Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.3, 0.5, 0.7, 0.8))
		var error := image.save_png(folder.path_join(filename))
		h.check("贴图 UI 图片可保存 " + filename, error, OK)
		ready = ready and error == OK
	return ready


static func _fixture(folder: String) -> Dictionary:
	return {"id": "texture_ui_fixture", "name": "贴图 UI 内存夹具", "size": [640, 480],
		"background": folder.path_join("background.png"), "walls": [], "portals": [],
		"spawns": {"start": [20, 20]}, "actors": [
			{"id": "desk", "label": "夹具书桌", "rect": [100, 80, 120, 100], "decor": true,
				"sprite": folder.path_join("original.png"), "cover": true,
				"collision": [[10, 60, 100, 35]], "reach_local": [-5, 50, 130, 55]},
			{"id": "peer", "label": "另一个物件", "rect": [350, 80, 80, 60], "decor": true}]}


static func _test_texture_assignment(h: TestHarness, dock, folder: String) -> void:
	var expected: Dictionary = dock.model.data.duplicate(true)
	var oversized := folder.path_join("oversized.png")
	expected["actors"][0]["sprite"] = oversized
	h.check("属性卡设置大图成功", dock._set_actor_texture(0, oversized), true)
	h.check("属性卡换图只改路径，保留框与局部几何", dock.model.data, expected)
	_check_sprite_edit(h, dock, oversized, "同步换图")
	var replacement := folder.path_join("replacement.png")
	expected["actors"][0]["sprite"] = replacement
	h.check("贴图应用入口可更新现有物件", dock._apply_actor_texture(0, replacement), true)
	h.check("应用入口同样保留已框位置和尺寸", dock.model.data, expected)
	_check_sprite_edit(h, dock, replacement, "直接应用贴图")


static func _test_buttons(h: TestHarness, dock, viewport: SubViewport, folder: String) -> void:
	var fit: Button = dock._texture_rect_button
	h.check("单选独立物件可使用框选按钮", fit.disabled, false)
	await _visible_click(viewport, dock, fit)
	h.check("真实点击框选按钮切换画布工具", dock.canvas.tool, Dock.Canvas.Tool.TEXTURE_RECT)
	h.check("真实点击框选按钮同步按下状态", fit.button_pressed, true)
	await _visible_click(viewport, dock, fit)
	h.check("再次点击框选按钮回到选择工具", dock.canvas.tool, Dock.Canvas.Tool.SELECT)
	h.check("再次点击框选按钮清除按下状态", fit.button_pressed, false)
	var native := _button(dock._actor_panel, "恢复原图尺寸")
	h.check("属性卡提供恢复原图按钮", native != null, true)
	if native == null:
		return
	var before: Rect2 = dock.model.rect_of(Dock.Kind.ACTOR, 0)
	await _visible_click(viewport, dock, native)
	var expected: Vector2 = dock.model.world_size_for_image(Vector2(48, 24))
	h.check("恢复原图按钮使用背景像素比例", dock.model.rect_of(Dock.Kind.ACTOR, 0), Rect2(before.position, expected))
	h.check("恢复原图按钮确实改变已框尺寸", dock.model.rect_of(Dock.Kind.ACTOR, 0).size != before.size, true)
	_check_sprite_edit(h, dock, folder.path_join("replacement.png"), "恢复原图尺寸")


static func _test_protected_selection(h: TestHarness, dock) -> void:
	var before: Dictionary = dock.model.data.duplicate(true)
	dock.canvas.set_actor_editor_state({}, {"desk": true})
	dock.canvas.selection_changed.emit()
	h.check("锁定物件禁用框选按钮", dock._texture_rect_button.disabled, true)
	dock._on_tool(Dock.Canvas.Tool.TEXTURE_RECT)
	h.check("锁定物件不能进入框选工具", dock.canvas.tool, Dock.Canvas.Tool.SELECT)
	dock.canvas.set_actor_editor_state({}, {})
	dock.canvas.selection_changed.emit()
	_select(dock, [0, 1])
	h.check("多选物件禁用框选按钮", dock._texture_rect_button.disabled, true)
	dock._on_tool(Dock.Canvas.Tool.TEXTURE_RECT)
	h.check("多选物件不能进入框选工具", dock.canvas.tool, Dock.Canvas.Tool.SELECT)
	h.check("锁定与多选拦截不改地图", dock.model.data, before)
	_select(dock, [0])


static func _test_async_requests(h: TestHarness, dock, folder: String) -> void:
	var oversized := folder.path_join("oversized.png")
	var original := folder.path_join("original.png")
	var before: Dictionary = dock.model.data.duplicate(true)
	dock.waiting_paths[oversized] = true
	var previous_scans: int = dock.scan_requests
	h.check("等待导入的贴图先返回未应用", dock._set_actor_texture(0, oversized), false)
	h.check("等待贴图请求确实进入扫描等待", dock.scan_requests, previous_scans + 1)
	h.check("扫描完成前地图保持原样", dock.model.data, before)
	dock.waiting_paths.erase(oversized)
	dock.fixture_scan_completed.emit()
	await _frames(dock)
	before["actors"][0]["sprite"] = oversized
	h.check("扫描完成后为原选中物件应用贴图", dock.model.data, before)
	_check_sprite_edit(h, dock, oversized, "异步扫描完成")
	dock.waiting_paths[oversized] = true
	dock._set_actor_texture(0, oversized)
	h.check("新同步贴图请求成功", dock._set_actor_texture(0, original), true)
	before = dock.model.data.duplicate(true)
	dock.waiting_paths.erase(oversized)
	dock.fixture_scan_completed.emit()
	await _frames(dock)
	h.check("较早的扫描请求不能覆盖较新的贴图", dock.model.data, before)
	_check_sprite_edit(h, dock, original, "较新请求完成")
	dock.waiting_paths[oversized] = true
	dock._set_actor_texture(0, oversized)
	_select(dock, [1])
	_select(dock, [0])
	dock.waiting_paths.erase(oversized)
	dock.fixture_scan_completed.emit()
	await _frames(dock)
	h.check("画布选中离开再返回不能复活旧贴图请求", dock.model.data, before)
	_check_sprite_edit(h, dock, original, "重新选回原物件")
	dock.waiting_paths[oversized] = true
	dock._set_actor_texture(0, oversized)
	_tree_select(dock, 1)
	_tree_select(dock, 0)
	dock.waiting_paths.erase(oversized)
	dock.fixture_scan_completed.emit()
	await _frames(dock)
	h.check("场景树选中离开再返回不能复活旧贴图请求", dock.model.data, before)
	_check_sprite_edit(h, dock, original, "场景树重新选回原物件")


static func _check_sprite_edit(h: TestHarness, dock, expected: String, context: String) -> void:
	var edit: LineEdit = dock.get("_sprite_path_edit") as LineEdit
	h.check(context + "属性卡贴图输入框存在", is_instance_valid(edit), true)
	if is_instance_valid(edit):
		h.check(context + "输入框与实际贴图路径同步", edit.text, expected)


static func _select(dock, indices: Array[int]) -> void:
	dock.canvas.select_actors(indices)
	dock.canvas.selection_changed.emit()


static func _tree_select(dock, index: int) -> void:
	for item: TreeItem in dock._hierarchy_actor_items.values():
		item.deselect(0)
	var target: TreeItem = dock._hierarchy_actor_items[index]
	target.select(0)
	dock._on_hierarchy_item_selected()


static func _frames(node: Node) -> void:
	await node.get_tree().process_frame
	await node.get_tree().process_frame


static func _visible_click(viewport: SubViewport, dock, control: Control) -> void:
	dock._panel_scroll.ensure_control_visible(control)
	await _frames(dock)
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
	await _frames(dock)


static func _button(node: Node, caption: String) -> Button:
	for child: Node in node.get_children():
		if child is Button and child.text == caption:
			return child
		var found := _button(child, caption)
		if found != null:
			return found
	return null
