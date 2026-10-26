extends SceneTree

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")


class FixtureDock extends Dock:
	var selected_map := -1

	func _ready() -> void:
		_build()
		_map_picker.add_item("第一张地图")
		_map_picker.add_item("第二张地图")

	func _on_map_selected(selected: int) -> void:
		selected_map = selected


func _initialize() -> void:
	call_deferred("_standalone")


func _standalone() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	await run(harness)
	quit(0 if harness.report() else 1)


static func fixture() -> Dictionary:
	return {"id": "inspector_fixture", "size": [640, 480], "walls": [], "actors": [
		{"id": "desk", "label": "书桌", "rect": [100, 80, 120, 100], "cover": true,
			"collision": [[20, 25, 50, 40], [3, 80, 20, 15]], "sort_collider": 0,
			"reach_local": [-5, 70, 130, 45], "sort_offset": 3, "cover_y": 150},
		{"id": "legacy", "label": "旧书柜", "rect": [300, 80, 60, 100], "cover": true,
			"reach": [290, 140, 80, 60], "cover_y": 160}]}


static func _click(viewport: SubViewport, position: Vector2) -> void:
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


static func _frames(root_node: Node) -> void:
	await root_node.get_tree().process_frame
	await root_node.get_tree().process_frame


static func _visible_click(viewport: SubViewport, dock, control: Control) -> void:
	dock._panel_scroll.ensure_control_visible(control)
	await _frames(dock)
	_click(viewport, control.get_global_rect().get_center())
	await _frames(dock)


static func _choose(viewport: SubViewport, picker: OptionButton, selected: int) -> void:
	_click(viewport, picker.get_global_rect().get_center())
	await _frames(picker)
	var popup := picker.get_popup()
	var row_height := float(popup.size.y) / float(popup.item_count)
	var position := Vector2(popup.position) + Vector2(popup.size.x * 0.5,
		row_height * (selected + 0.5))
	var hover := InputEventMouseMotion.new()
	hover.position = position
	hover.global_position = position
	viewport.push_input(hover, true)
	await _frames(picker)
	_click(viewport, position)
	await _frames(picker)


static func run(harness: TestHarness) -> void:
	harness.section("地图属性卡真实 GUI 点击")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 720)
	viewport.gui_disable_input = false
	viewport.gui_embed_subwindows = true
	viewport.handle_input_locally = true
	harness.root.add_child(viewport)
	var dock := FixtureDock.new()
	viewport.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.model.data = fixture()
	dock.model.reset_history()
	dock.canvas.load_map(dock.model, "", "", dock.model.map_size())
	await _frames(harness.root)
	dock._set_initial_panel_layout()
	await _frames(harness.root)
	for drawer_index: int in dock._drawer_buttons.size():
		var button: Button = dock._drawer_buttons[drawer_index]
		_click(viewport, button.get_global_rect().get_center())
		await _frames(harness.root)
		harness.check(button.text + " 真实点击展开", dock._toolbar_drawers[drawer_index].visible, true)
		harness.check(button.text + " 展开内容不压住主工作区",
			dock._toolbar_drawers[drawer_index].get_global_rect().end.y <=
			dock._body_split.get_global_rect().position.y, true)
		_click(viewport, button.get_global_rect().get_center())
		await _frames(harness.root)
		harness.check(button.text + " 再次点击收起", dock._toolbar_drawers[drawer_index].visible, false)
	await _choose(viewport, dock._map_picker, 1)
	harness.check("地图下拉真实点击选中第二项", dock.selected_map, 1)
	harness.check("地图下拉选择后关闭", dock._map_picker.get_popup().visible, false)
	var selected: Array[int] = [0]
	dock.canvas.select_actors(selected)
	dock._on_selection_changed()
	await _frames(harness.root)
	harness.check("属性卡提供选择、贴图、墙及传送区工具", dock._tool_buttons.size(), 4)
	harness.check("素材预览已连接画布", dock._asset_list.canvas, dock.canvas)
	harness.check("单选属性卡可见", dock._panel_scroll.visible, true)
	var geometry = dock._object_inspector
	harness.check("属性卡没有被固定宽度撑出侧栏",
		geometry.get_combined_minimum_size().x <= dock._panel_scroll.size.x, true)
	for tool: int in [Dock.Canvas.Tool.BASELINE, Dock.Canvas.Tool.COLLISION]:
		var button: Button = geometry._tool_buttons[tool]
		await _visible_click(viewport, dock, button)
		harness.check(button.text + " 真实点击切换画布工具", dock.canvas.tool, tool)
		harness.check(button.text + " 按钮状态同步", button.button_pressed, true)
	var cover_spin: SpinBox = geometry.baseline_spin
	cover_spin.value = 173.25
	harness.check("手动 cover_y 数值可写回", dock.model.actor_field(0, "cover_y"), 173.25)
	var offset: SpinBox = geometry.get_node("SortOffset") if geometry.has_node("SortOffset") else geometry.find_child("SortOffset", true, false)
	offset.value = 7.5
	harness.check("排序偏移保留精度", dock.model.actor_field(0, "sort_offset"), 7.5)
	harness.check("调整排序偏移切回自动排序", dock.model.actor_dict(0).has("cover_y"), false)
	var reference: OptionButton = geometry.find_child("SortCollider", true, false)
	dock._panel_scroll.ensure_control_visible(reference)
	await _frames(dock)
	await _choose(viewport, reference, 1)
	harness.check("排序参考下拉真实点击更新", dock.model.actor_field(0, "sort_collider"), 1)
	var shape_grid: GridContainer = geometry.get_node("Collision0").get_child(1)
	var shapes_before: Array = dock.model.actor_field(0, "collision").duplicate(true)
	for component: int in 4:
		var spin: SpinBox = shape_grid.get_child(component)
		spin.value += 0.25
	var expected: Array = shapes_before.duplicate(true)
	for component: int in 4:
		expected[0][component] += 0.25
	harness.check("局部碰撞 x/y/宽/高均可精确编辑", dock.model.actor_field(0, "collision"), expected)
	var reach_grid: GridContainer = geometry.get_node("Reach").get_child(1)
	(reach_grid.get_child(0) as SpinBox).value = -9.25
	harness.check("交互区仍可精确编辑", dock.model.actor_field(0, "reach_local")[0], -9.25)
	await _visible_click(viewport, dock, geometry.baseline_auto)
	harness.check("恢复自动移除手动 cover_y", dock.model.actor_dict(0).has("cover_y"), false)
	harness.check("恢复自动移除排序偏移", dock.model.actor_dict(0).has("sort_offset"), false)
	var both: Array[int] = [0, 1]
	dock.canvas.select_actors(both)
	dock._on_selection_changed()
	await _frames(dock)
	harness.check("多选保留主选物件属性与参数入口", dock._panel_scroll.visible, true)
	harness.check("多选禁用物件专属画布工具",
		(dock._object_inspector._tool_buttons[Dock.Canvas.Tool.COLLISION] as Button).disabled, true)
	harness.check("多选退出物件专属工具", dock.canvas.tool, Dock.Canvas.Tool.SELECT)
	var legacy: Array[int] = [1]
	dock.canvas.select_actors(legacy)
	dock._on_selection_changed()
	await _frames(dock)
	geometry = dock._object_inspector
	harness.check("旧物件也保留基线数值入口", geometry.baseline_spin.value, 160)
	harness.check("旧物件也保留交互区参数", geometry.has_node("Reach"), true)
	geometry.baseline_spin.value = 162.5
	harness.check("旧物件手动基线可编辑", dock.model.actor_field(1, "cover_y"), 162.5)
	dock.canvas.set_actor_editor_state({}, {"legacy": true})
	dock._on_selection_changed()
	await _frames(dock)
	geometry = dock._object_inspector
	harness.check("锁定物件基线不可写", geometry.baseline_spin.editable, false)
	harness.check("锁定物件恢复自动不可按", geometry.baseline_auto.disabled, true)
	harness.check("锁定物件碰撞工具不可按",
		(geometry._tool_buttons[Dock.Canvas.Tool.COLLISION] as Button).disabled, true)
	for width: int in [900, 1280]:
		viewport.size = Vector2i(width, 720)
		await _frames(dock)
		for drawer_index: int in dock._drawer_buttons.size():
			var button: Button = dock._drawer_buttons[drawer_index]
			_click(viewport, button.get_global_rect().get_center())
			await _frames(dock)
			harness.check("宽度 %d drawer %d 仍可点击" % [width, drawer_index],
				dock._toolbar_drawers[drawer_index].visible, true)
			harness.check("宽度 %d drawer %d 未盖住工具栏" % [width, drawer_index],
				dock._toolbar_drawers[drawer_index].get_global_rect().position.y >=
				button.get_global_rect().end.y, true)
			_click(viewport, button.get_global_rect().get_center())
			await _frames(dock)
		await _choose(viewport, dock._map_picker, 0 if width == 900 else 1)
		harness.check("缩放后地图下拉真实选择 %d" % width,
			dock.selected_map, 0 if width == 900 else 1)
	viewport.free()
	var library_dock := FixtureDock.new()
	var library_viewport := SubViewport.new()
	library_viewport.size = Vector2i(1280, 800)
	harness.root.add_child(library_viewport)
	library_viewport.add_child(library_dock)
	library_dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	library_dock.model.load_map("library")
	library_dock.canvas.load_map(library_dock.model, library_dock.model.background_path(),
		library_dock.model.overlay_path(), library_dock.model.map_size())
	var library_selection: Array[int] = [0]
	library_dock.canvas.select_actors(library_selection)
	library_dock._on_selection_changed()
	await _frames(library_dock)
	library_dock._set_initial_panel_layout()
	await _frames(library_dock)
	harness.check("真实图书馆长素材名不会撑宽物件属性卡",
		library_dock._actor_panel.get_combined_minimum_size().x <= library_dock._panel_scroll.size.x, true)
	library_viewport.free()
