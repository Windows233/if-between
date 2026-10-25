## 地图编辑器主界面：物件列表、中央画布、右侧检查器与地图工具。
##
## 数值框和画布是**双向同步**的：拖了矩形，数值跟着变；敲了数字，画面跟着动。
## 同步时用一个 `_syncing` 旗子挡住回写，免得程序设值又被当成玩家改动（会把
## 「未保存」的星号无缘无故点亮）。
@tool
extends VBoxContainer

signal asset_scan_finished

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const Kind := Model.Kind
const ObjectInspector := preload("res://addons/if_map_editor/map_object_inspector.gd")
const ObjectLibrary := preload("res://addons/if_map_editor/map_object_library.gd")
const ObjectPreview := preload("res://addons/if_map_editor/map_object_preview.gd")
const AssetList := preload("res://addons/if_map_editor/map_asset_list.gd")
const GeometryTransferDialog := preload("res://addons/if_map_editor/map_geometry_transfer_dialog.gd")
const MapCreationDialog := preload("res://addons/if_map_editor/map_creation_dialog.gd")
const SceneHierarchy := preload("res://addons/if_map_editor/map_scene_hierarchy.gd")
const SceneTreeControl := preload("res://addons/if_map_editor/map_scene_tree.gd")
const VisualInspector := preload("res://addons/if_map_editor/map_visual_inspector.gd")
const TemplateInspector := preload("res://addons/if_map_editor/map_template_inspector.gd")
const PreviewOptions := preload("res://addons/if_map_editor/map_preview_options.gd")
const Shortcuts := preload("res://addons/if_map_editor/map_shortcuts.gd")
const ReviewPanel := preload("res://addons/if_map_editor/map_review_panel.gd")
const Validation := preload("res://addons/if_map_editor/map_validation.gd")
const TriggerEditor := preload("res://addons/if_map_editor/map_trigger_editor.gd")
const TemplateList := preload("res://addons/if_map_editor/map_template_list.gd")

const EDITOR_STATE_PATH := "user://if_map_editor_scene_state.cfg"

enum LayoutAction { ALIGN_LEFT, ALIGN_CENTER_X, ALIGN_RIGHT, ALIGN_TOP, ALIGN_CENTER_Y, ALIGN_BOTTOM,
	DISTRIBUTE_HORIZONTAL, DISTRIBUTE_VERTICAL }

var model = Model.new()
var canvas: Control = null

var _map_picker: OptionButton
var _zoom_spin: SpinBox
var _save_button: Button
var _drop_draft_button: Button
var _tool_buttons: Array[Button] = []
var _sel_label: Label
var _spins: Array[SpinBox] = []
var _base_row: HFlowContainer
var _base_spin: SpinBox
var _base_auto_button: Button
var _status: Label
var _syncing := false
## 「物件属性」面板：只在选中物件时出现。**每次换选中项才重建** ——
## 每敲一个字都重建会把光标弄丢。
var _actor_panel: VBoxContainer
var _panel_scroll: ScrollContainer
var _panel_kind := -1
var _panel_index := -1
var _panel_locked := false
var _panel_id_readonly := false
var _object_tree: Tree
var _hierarchy_actor_items: Dictionary = {}
var _hierarchy_group_items: Array[TreeItem] = []
var _hierarchy_structure: Array = []
var _hierarchy_map_id := ""
var _hierarchy_syncing := false
var _hierarchy_selection_queued := false
var _hierarchy_selecting := false
var _hidden_actor_ids: Dictionary = {}
var _locked_actor_ids: Dictionary = {}
var _editor_state_path := EDITOR_STATE_PATH
var _hide_selected_button: Button
var _lock_selected_button: Button
var _show_all_button: Button
var _frame_selected_button: Button
var _asset_tabs: TabContainer
var _asset_filter: LineEdit
var _asset_list: ItemList
var _asset_empty: Label
var _asset_scan_in_progress := false
var _asset_scan_requested := false
var _asset_import_pending: Dictionary = {}
var _group_button: Button
var _ungroup_button: Button
var _template_picker: OptionButton
var _template_list: ItemList
var _template_filter: LineEdit
var _layout_popup: PopupMenu
var _library = ObjectLibrary.new()
var _shortcuts = Shortcuts.new()
var _body_split: HSplitContainer
var _workspace_split: HSplitContainer
var _transfer_button: Button
var _transfer_dialog: GeometryTransferDialog
var _map_management: HFlowContainer
var _toolbar_drawers: Array[Control] = []
var _drawer_buttons: Array[Button] = []
var _object_inspector: Control
var _texture_request_serial := 0
var _texture_selection_key: Array = []
var _sprite_path_edit: LineEdit
var _visibility_icons: Array[Texture2D] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		var filesystem := EditorInterface.get_resource_filesystem()
		if not filesystem.filesystem_changed.is_connected(_on_asset_filesystem_changed):
			filesystem.filesystem_changed.connect(_on_asset_filesystem_changed)
	_build()
	refresh_map_list(true)
	await get_tree().process_frame
	_refresh_assets_after_scan()
	_set_initial_panel_layout()


# ---------------------------------------------------------------- 界面

func _build() -> void:
	canvas = Canvas.new()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_management = HFlowContainer.new()
	add_child(_row_title())

	var tools := HFlowContainer.new()
	tools.add_child(_text("工具："))
	for item in [["选择 / 移动", Canvas.Tool.SELECT],
			["画墙", Canvas.Tool.WALL],
			["画传送区", Canvas.Tool.PORTAL]]:
		var b := Button.new()
		b.text = str(item[0])
		b.toggle_mode = true
		b.set_meta("map_tool", int(item[1]))
		b.pressed.connect(_on_tool.bind(int(item[1])))
		tools.add_child(b)
		_tool_buttons.append(b)
	_tool_buttons[0].button_pressed = true
	tools.add_child(VSeparator.new())
	var drawer_controls: Array[Control] = [_map_management, _row_layers(), _row_selection(), _object_actions()]
	var drawer_names := ["地图管理", "显示设置", "选择与尺寸", "排布与模板"]
	for index in drawer_controls.size():
		var button := Button.new()
		button.text = drawer_names[index] + " ▾"
		button.toggle_mode = true
		button.toggled.connect(_toggle_toolbar_drawer.bind(index))
		tools.add_child(button)
		_drawer_buttons.append(button)
		_toolbar_drawers.append(drawer_controls[index])
	add_child(tools)
	for drawer in _toolbar_drawers:
		drawer.visible = false
		add_child(drawer)
	_body_split = HSplitContainer.new()
	_body_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body_split)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 210
	_body_split.add_child(sidebar)
	_asset_tabs = TabContainer.new()
	_asset_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(_asset_tabs)
	var scene_page := VBoxContainer.new()
	scene_page.name = "场景"
	scene_page.add_child(_text("场景层级（Ctrl / Shift 多选）"))
	_object_tree = SceneTreeControl.new()
	_object_tree.hierarchy_drop.connect(_on_hierarchy_drop)
	_object_tree.hide_root = true
	_object_tree.columns = 2
	_object_tree.set_column_expand(0, true)
	_object_tree.set_column_expand(1, false)
	_object_tree.set_column_custom_minimum_width(1, 24)
	_object_tree.select_mode = Tree.SELECT_MULTI
	_object_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_object_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_object_tree.multi_selected.connect(_on_hierarchy_multi_selected)
	_object_tree.button_clicked.connect(_on_hierarchy_button_clicked)
	_object_tree.item_edited.connect(_on_hierarchy_item_edited)
	_object_tree.item_activated.connect(_on_hierarchy_item_activated)
	scene_page.add_child(_object_tree)
	var object_tools := HFlowContainer.new()
	_hide_selected_button = Button.new()
	_hide_selected_button.text = "隐藏所选"
	_hide_selected_button.tooltip_text = "隐藏所选物件；隐藏只影响编辑器视图和画布拾取。"
	_hide_selected_button.pressed.connect(_toggle_selected_actor_visibility)
	object_tools.add_child(_hide_selected_button)
	_lock_selected_button = Button.new()
	_lock_selected_button.text = "锁定所选"
	_lock_selected_button.tooltip_text = "锁定所选物件，阻止移动、改属性、删除和编组；复制仍可使用。"
	_lock_selected_button.pressed.connect(_toggle_selected_actor_lock)
	object_tools.add_child(_lock_selected_button)
	_show_all_button = Button.new()
	_show_all_button.text = "全部显示"
	_show_all_button.tooltip_text = "显示这张地图中的所有隐藏物件。"
	_show_all_button.pressed.connect(_show_all_actors)
	object_tools.add_child(_show_all_button)
	_frame_selected_button = Button.new()
	_frame_selected_button.text = "定位所选"
	_frame_selected_button.tooltip_text = "将画布对准所选对象；也可双击物件，或在画布中按 F。"
	_frame_selected_button.pressed.connect(_frame_selection)
	object_tools.add_child(_frame_selected_button)
	scene_page.add_child(object_tools)
	_asset_tabs.add_child(scene_page)
	var asset_page := VBoxContainer.new()
	asset_page.name = "素材"
	var asset_toolbar := HBoxContainer.new()
	_asset_filter = LineEdit.new()
	_asset_filter.placeholder_text = "筛选素材"
	_asset_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_filter.text_changed.connect(func(_text: String) -> void: _refresh_assets())
	asset_toolbar.add_child(_asset_filter)
	var refresh_assets := Button.new()
	refresh_assets.text = "刷新"
	refresh_assets.pressed.connect(_refresh_assets_after_scan)
	asset_toolbar.add_child(refresh_assets)
	asset_page.add_child(asset_toolbar)
	_asset_list = AssetList.new()
	_asset_list.select_mode = ItemList.SELECT_SINGLE
	_asset_list.icon_mode = ItemList.ICON_MODE_TOP
	_asset_list.fixed_icon_size = Vector2i(64, 64)
	_asset_list.fixed_column_width = 98
	_asset_list.max_columns = 2
	_asset_list.max_text_lines = 2
	_asset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_list.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_asset_list.item_clicked.connect(_on_asset_item_clicked)
	_asset_list.gui_input.connect(_on_asset_list_gui_input)
	asset_page.add_child(_asset_list)
	_asset_empty = _text("")
	_asset_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_asset_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_empty.visible = false
	asset_page.add_child(_asset_empty)
	_asset_tabs.add_child(asset_page)
	_workspace_split = HSplitContainer.new()
	_workspace_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_split.add_child(_workspace_split)
	_shortcuts.load_settings()
	canvas.shortcuts = _shortcuts
	canvas.template_library = _library
	_asset_list.canvas = canvas
	canvas.custom_minimum_size = Vector2(300, 240)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.selection_changed.connect(_on_selection_changed)
	canvas.edited.connect(_on_canvas_edited)
	canvas.status.connect(func(text: String) -> void: _status.text = text)
	canvas.command_requested.connect(_object_command)
	_workspace_split.add_child(canvas)

	# 属性面板放进**定高滚动区**：对话一行一句，行数一多面板会很长，
	# 不挡住下面的画布（也不把下面的东西挤出屏幕）。
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.custom_minimum_size = Vector2(300, 0)
	_panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel_scroll.visible = false
	_workspace_split.add_child(_panel_scroll)
	_actor_panel = VBoxContainer.new()
	_actor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_scroll.add_child(_actor_panel)

	_status = _text("选一张地图开始。滚轮缩放，中键/右键拖动平移。")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_refresh_templates()
	_build_scene_tools()
	_build_template_browser()


func _build_template_browser() -> void:
	var page := VBoxContainer.new()
	page.name = "模板"
	_template_filter = LineEdit.new()
	_template_filter.placeholder_text = "名称 / 分类 / 标签"
	_template_filter.text_changed.connect(func(_query: String) -> void: _refresh_templates())
	page.add_child(_template_filter)
	_template_list = TemplateList.new()
	_template_list.library = _library
	_template_list.canvas = canvas
	_template_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_template_list.item_activated.connect(func(index: int) -> void:
		if not canvas.is_kind_editable(Kind.ACTOR):
			return
		var selected: Array[int] = _library.instantiate(str(_template_list.get_item_metadata(index)), model, model.map_size() * 0.5)
		canvas.select_actors(selected)
		_on_edited()
		_refresh_selection())
	page.add_child(_template_list)
	var note := _text("拖到画布放置；双击放到地图中央。")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)
	_asset_tabs.add_child(page)
	_refresh_templates()


func _build_scene_tools() -> void:
	var page := VBoxContainer.new()
	page.name = "工具"
	_asset_tabs.add_child(page)
	var open := Button.new()
	open.text = "场景检查 / 触发 / 试走设置…"
	open.pressed.connect(_open_scene_tools)
	page.add_child(open)
	var grid := CheckBox.new()
	grid.text = "显示吸附网格"
	grid.toggled.connect(func(value: bool) -> void: canvas.show_grid = value)
	page.add_child(grid)
	var step := SpinBox.new()
	step.prefix = "吸附步长 "
	step.min_value = 0.1
	step.max_value = 1024
	step.step = 0.1
	step.value = 1
	step.value_changed.connect(func(value: float) -> void: canvas.snap_step = value)
	page.add_child(step)
	var isolation := OptionButton.new()
	isolation.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for caption: String in ["显示全部层", "仅墙", "仅传送区", "仅物件", "仅出生点", "仅前景"]:
		isolation.add_item(caption)
	isolation.item_selected.connect(func(index: int) -> void:
		canvas.configure_edit_layers(canvas.locked_layers, ["", "walls", "portals", "actors", "spawns", "overlay"][index]))
	page.add_child(isolation)
	for entry: Array in [["墙", "walls"], ["传送区", "portals"], ["物件", "actors"], ["出生点", "spawns"], ["前景", "overlay"]]:
		var lock := CheckBox.new()
		lock.text = "锁定" + str(entry[0])
		lock.toggled.connect(func(value: bool) -> void:
			var locks: Dictionary = canvas.locked_layers.duplicate()
			locks[str(entry[1])] = value
			canvas.configure_edit_layers(locks, canvas.isolated_layer)
			_refresh_selection())
		page.add_child(lock)


func _open_preview(options: Dictionary) -> void:
	var preview := ObjectPreview.new()
	add_child(preview)
	preview.configure(model.data.duplicate(true), options)
	preview.popup_centered()


func _open_scene_tools() -> void:
	if model.map_id.is_empty():
		return
	var dialog := AcceptDialog.new()
	dialog.title = "场景工具 · " + model.map_id
	dialog.exclusive = false
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(720, 500)
	dialog.add_child(tabs)
	var review := ReviewPanel.new()
	_add_tool_tab(tabs, "校验与迁移", review)
	review.configure(model, _library)
	review.edited.connect(_on_edited)
	review.issue_selected.connect(_locate_issue)
	review.review_requested.connect(func(report: Dictionary) -> void:
		if report.get("action", "") == "save":
			_on_save())
	var triggers := TriggerEditor.new()
	_add_tool_tab(tabs, "事件触发区域", triggers)
	triggers.configure(model)
	triggers.edited.connect(_on_edited)
	triggers.selection_changed.connect(func(index: int) -> void: canvas.set_trigger_selection(index))
	triggers.bounds_requested.connect(func(index: int) -> void:
		if canvas.sel_kind < 0 or canvas.sel_index < 0:
			_status.text = "先在画布选择一个矩形物件、墙或传送区，再取它的矩形。"
			return
		triggers.set_trigger_rect(index, model.rect_of(canvas.sel_kind, canvas.sel_index))
		canvas.set_trigger_selection(index))
	var options := PreviewOptions.new()
	_add_tool_tab(tabs, "试走状态与地图比较", options)
	options.configure(model)
	options.preview_requested.connect(_open_preview)
	options.compare_requested.connect(func(map_id: String, settings: Dictionary) -> void:
		var comparison: HSplitContainer = options.create_comparison(map_id, settings)
		if comparison == null:
			return
		var window := AcceptDialog.new()
		window.title = "地图并排比较 · " + map_id
		window.add_child(comparison)
		window.confirmed.connect(window.queue_free)
		window.canceled.connect(window.queue_free)
		add_child(window)
		window.popup_centered(Vector2i(1120, 650)))
	var shortcuts := PreviewOptions.ShortcutsPanel.new()
	_add_tool_tab(tabs, "快捷键", shortcuts)
	shortcuts.configure(_shortcuts)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(820, 620))


func _add_tool_tab(tabs: TabContainer, title: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	tabs.add_child(scroll)


func _locate_issue(issue: Dictionary) -> void:
	var kind: int = {"actor": Kind.ACTOR, "wall": Kind.WALL, "portal": Kind.PORTAL,
		"spawn": Kind.SPAWN}.get(str(issue.get("kind", "")), -1)
	var index := int(issue.get("index", -1))
	if kind == Kind.ACTOR:
		var selected: Array[int] = [index]
		canvas.select_actors(selected)
	elif kind >= 0:
		canvas.sel_kind = kind
		canvas.sel_index = index
	elif str(issue.get("kind", "")) == "trigger":
		canvas.set_trigger_selection(index)
	canvas.frame_selection()
	_refresh_selection()
	_status.text = str(issue.get("message", ""))


func _set_initial_panel_layout() -> void:
	_body_split.split_offset = 220
	var inspector_width := clampi(roundi(_workspace_split.size.x * 0.28), 300, 380)
	_workspace_split.split_offset = maxi(300, int(_workspace_split.size.x) - inspector_width)


func _object_actions() -> HFlowContainer:
	var row := HFlowContainer.new()
	for action: Array in [["撤销", "undo"], ["重做", "redo"], ["复制物件", "copy"],
			["粘贴", "paste"], ["复制并偏移", "duplicate"], ["存为物件模板…", "template"]]:
		var button := Button.new()
		button.text = str(action[0])
		button.pressed.connect(_object_command.bind(str(action[1])))
		row.add_child(button)
	_group_button = Button.new()
	_group_button.text = "编组"
	_group_button.tooltip_text = "将至少两件物件编为一组；选中组内任一物件会整体选择、移动和复制。"
	_group_button.pressed.connect(_object_command.bind("group"))
	row.add_child(_group_button)
	_ungroup_button = Button.new()
	_ungroup_button.text = "解组"
	_ungroup_button.tooltip_text = "移除所选物件所属的组，不删除物件。"
	_ungroup_button.pressed.connect(_object_command.bind("ungroup"))
	row.add_child(_ungroup_button)
	var layout_button := MenuButton.new()
	layout_button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	layout_button.text = "对齐 / 分布"
	layout_button.tooltip_text = "对齐至少选择两件物件；等间距至少选择三件。"
	_layout_popup = layout_button.get_popup()
	for action: Array in [["左对齐", LayoutAction.ALIGN_LEFT], ["水平居中", LayoutAction.ALIGN_CENTER_X],
			["右对齐", LayoutAction.ALIGN_RIGHT], ["顶对齐", LayoutAction.ALIGN_TOP],
			["垂直居中", LayoutAction.ALIGN_CENTER_Y], ["底对齐", LayoutAction.ALIGN_BOTTOM]]:
		_layout_popup.add_item(str(action[0]), int(action[1]))
	_layout_popup.add_separator()
	_layout_popup.add_item("水平等间距", LayoutAction.DISTRIBUTE_HORIZONTAL)
	_layout_popup.add_item("垂直等间距", LayoutAction.DISTRIBUTE_VERTICAL)
	_layout_popup.about_to_popup.connect(_refresh_layout_menu)
	_layout_popup.id_pressed.connect(_on_layout_action)
	row.add_child(layout_button)
	_template_picker = OptionButton.new()
	_template_picker.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	_template_picker.custom_minimum_size.x = 180
	row.add_child(_template_picker)
	var place := Button.new()
	place.text = "从模板放置"
	place.pressed.connect(func() -> void:
		if _template_picker.item_count == 0:
			return
		var selected: Array[int] = _library.instantiate(_template_picker.get_item_text(_template_picker.selected),
			model, model.map_size() * 0.5)
		canvas.select_actors(selected)
		_on_edited()
		_refresh_selection())
	row.add_child(place)
	return row


func _refresh_layout_menu() -> void:
	var count: int = canvas.selected_actors().size()
	for index: int in _layout_popup.item_count:
		var minimum := 2 if index < 6 else 3
		_layout_popup.set_item_disabled(index, count < minimum or _selection_has_locked_actor())


func _refresh_templates() -> void:
	_template_picker.clear()
	for name: String in _library.list_templates():
		_template_picker.add_item(name)
	if _template_list != null:
		_template_list.clear()
		for name: String in _library.list_templates("", [], _template_filter.text.strip_edges()):
			_template_list.add_item(name)
			_template_list.set_item_metadata(_template_list.item_count - 1, name)


func _refresh_assets() -> void:
	if _asset_list == null:
		return
	_asset_list.clear()
	_asset_import_pending.clear()
	var query := _asset_filter.text.strip_edges().to_lower() if _asset_filter != null else ""
	for path: String in _list_png_files("res://art/props"):
		var filename := path.get_file().get_basename()
		if not query.is_empty() and not filename.to_lower().contains(query):
			continue
		var texture := _load_imported_asset(path)
		var item_text := filename if texture != null else "%s（等待导入）" % filename
		_asset_list.add_item(item_text, texture)
		var index := _asset_list.item_count - 1
		_asset_list.set_item_metadata(index, path)
		if texture == null:
			_asset_import_pending[path] = true
			_asset_list.set_item_tooltip(index, "%s\nGodot 尚未完成此 PNG 的纹理导入。点击或拖动会请求扫描。" % path)
		else:
			_asset_list.set_item_tooltip(index, path)
	_asset_list.visible = _asset_list.item_count > 0
	_asset_empty.visible = _asset_list.item_count == 0
	if not query.is_empty() and _asset_list.item_count == 0:
		_asset_empty.text = "没有匹配的素材"
	else:
		_asset_empty.text = "素材目录为空"


static func _list_png_files(directory_path: String) -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open(ProjectSettings.globalize_path(directory_path))
	if directory == null:
		return paths
	for filename: String in directory.get_files():
		if filename.get_extension().to_lower() == "png":
			paths.append(directory_path.trim_suffix("/") + "/" + filename)
	paths.sort()
	return paths


func _load_imported_asset(path: String) -> Texture2D:
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(path + ".import"):
		return null
	# 源 PNG 已复制并不等于纹理已导入；提前 load 会在正常等待期间刷红报错。
	var imported := ConfigFile.new()
	if imported.load(path + ".import") != OK or not bool(imported.get_value("remap", "valid", true)):
		return null
	var remapped := str(imported.get_value("remap", "path", ""))
	if remapped.is_empty() or not FileAccess.file_exists(remapped):
		return null
	return ResourceLoader.load(path, "Texture2D") as Texture2D


func _asset_import_timeout_msec() -> int:
	return 10000


## scan 的忙碌标记可能先于新纹理可载入清零；以目标资源真正就绪为准。
func _wait_for_imported_asset(path: String) -> Texture2D:
	var deadline := Time.get_ticks_msec() + _asset_import_timeout_msec()
	await _refresh_assets_after_scan()
	if not is_inside_tree():
		return null
	var texture := _load_imported_asset(path)
	if texture != null:
		return texture
	await _retry_asset_import(path, deadline)
	while is_inside_tree():
		texture = _load_imported_asset(path)
		if texture != null:
			return texture
		if Time.get_ticks_msec() >= deadline:
			break
		await get_tree().process_frame
	return null


func _retry_asset_import(path: String, deadline: int) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var filesystem := EditorInterface.get_resource_filesystem()
	while is_inside_tree() and (filesystem.is_scanning() or filesystem.is_importing()):
		if Time.get_ticks_msec() >= deadline:
			return
		await get_tree().process_frame
	if not is_inside_tree() or Time.get_ticks_msec() >= deadline or not FileAccess.file_exists(path):
		return
	# 新文件先登记到编辑器文件系统，再显式导入一次。reimport_files 返回时导入已完成；
	# 它内部会推进主循环，所以调用方仍须在等待结束后核对地图、选区与请求序号。
	filesystem.update_file(path)
	filesystem.reimport_files(PackedStringArray([path]))
	await get_tree().process_frame


func _refresh_assets_after_scan() -> void:
	if not Engine.is_editor_hint():
		_refresh_assets()
		return
	if _asset_scan_in_progress:
		_asset_scan_requested = true
		var wait_deadline := Time.get_ticks_msec() + _asset_import_timeout_msec()
		while is_inside_tree() and _asset_scan_in_progress and Time.get_ticks_msec() < wait_deadline:
			await get_tree().process_frame
		return
	_asset_scan_in_progress = true
	var deadline := Time.get_ticks_msec() + _asset_import_timeout_msec()
	var filesystem := EditorInterface.get_resource_filesystem()
	while is_inside_tree() and (filesystem.is_scanning() or filesystem.is_importing()) \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	while is_inside_tree() and Time.get_ticks_msec() < deadline:
		_asset_scan_requested = false
		filesystem.scan()
		await get_tree().process_frame
		while is_inside_tree() and (filesystem.is_scanning() or filesystem.is_importing()) \
				and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if not is_inside_tree():
			break
		_refresh_assets()
		if not _asset_scan_requested:
			break
	_asset_scan_in_progress = false
	asset_scan_finished.emit()


func _on_asset_filesystem_changed() -> void:
	_refresh_assets()


func _request_asset_import(path: String) -> void:
	if not _asset_import_pending.has(path):
		return
	_status.text = "已发现 %s，正在请求 Godot 扫描并导入；完成后素材列表会自动更新。" % path.get_file()
	_refresh_assets_after_scan()


func _on_asset_item_clicked(index: int, _position: Vector2, _mouse_button_index: int) -> void:
	if index < 0 or index >= _asset_list.item_count:
		return
	_request_asset_import(str(_asset_list.get_item_metadata(index)))


func _on_asset_list_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	var index := _asset_list.get_item_at_position(event.position, true)
	if index >= 0 and index < _asset_list.item_count:
		_request_asset_import(str(_asset_list.get_item_metadata(index)))


func _refresh_objects() -> void:
	if _object_tree == null:
		return
	var actor_ids := PackedStringArray()
	for index: int in model.count(Kind.ACTOR):
		actor_ids.append(str(model.actor_field(index, "id", "")))
	var groups: Array[Dictionary] = []
	var group_structure: Array = []
	for raw_group: Variant in model.editor_groups():
		if not raw_group is Dictionary:
			continue
		var group: Dictionary = raw_group
		groups.append(group)
		group_structure.append({"id": str(group.get("id", "")),
			"members": group.get("members", []), "parent": group.get("parent", "")})
	var structure: Array = [model.map_id, actor_ids, group_structure, model.data.get("editor_tree_order", [])]
	_hierarchy_syncing = true
	if structure != _hierarchy_structure or _object_tree.get_root() == null:
		var collapsed: Dictionary = {}
		if _hierarchy_map_id == model.map_id:
			for item: TreeItem in _hierarchy_group_items:
				collapsed[str(item.get_metadata(0).get("id", ""))] = item.collapsed
		_object_tree.clear()
		_hierarchy_actor_items.clear()
		_hierarchy_group_items.clear()
		var root := _object_tree.create_item()
		root.set_selectable(0, false)
		var group_items := {}
		for group: Dictionary in groups:
			var item := _create_group_item(group, root, group_items, {})
			var group_id := str(group.get("id", ""))
			item.set_metadata(0, {"kind": "group", "id": group_id,
				"name": str(group.get("name", "组"))})
			item.collapsed = bool(collapsed.get(group_id, false))
			_hierarchy_group_items.append(item)
		for index: int in model.count(Kind.ACTOR):
			var parent := root
			var actor_id := str(model.actor_field(index, "id", ""))
			if not actor_id.is_empty():
				for group_index: int in groups.size():
					if groups[group_index].get("members", []).has(actor_id):
						parent = _hierarchy_group_items[group_index]
						break
			var item := _object_tree.create_item(parent)
			item.set_metadata(0, {"kind": "actor", "index": index, "id": actor_id})
			_hierarchy_actor_items[index] = item
		_order_hierarchy_children(root)
		_hierarchy_structure = structure.duplicate(true)
		_hierarchy_map_id = model.map_id
	var group_id_counts: Dictionary = {}
	for group: Dictionary in groups:
		var group_id := str(group.get("id", ""))
		group_id_counts[group_id] = int(group_id_counts.get(group_id, 0)) + 1
	for group_index: int in groups.size():
		var item := _hierarchy_group_items[group_index]
		var group: Dictionary = groups[group_index]
		var group_id := str(group.get("id", ""))
		var group_name := str(group.get("name", "组"))
		item.set_text(0, group_name)
		item.set_metadata(0, {"kind": "group", "id": group_id, "name": group_name})
		var editable := not group_id.is_empty() and int(group_id_counts.get(group_id, 0)) == 1
		for index: int in _hierarchy_item_actor_indices(item):
			editable = editable and not canvas.actor_is_locked(index)
		item.set_editable(0, editable)
		item.set_tooltip_text(0, "双击编组名称可改名；选中编组会整体选择成员。" if editable
			else "编组包含锁定物件或组 ID 无效，暂时不能改名。")
	var actor_id_counts := _actor_id_counts()
	for index: int in model.count(Kind.ACTOR):
		var item: TreeItem = _hierarchy_actor_items[index]
		var label := model.label_of(Kind.ACTOR, index)
		var actor_id := str(model.actor_field(index, "id", ""))
		var hidden := _hidden_actor_ids.has(actor_id)
		var state_tags: Array[String] = []
		if hidden:
			state_tags.append("隐藏")
		if _locked_actor_ids.has(actor_id):
			state_tags.append("锁定")
		if not state_tags.is_empty():
			label += "  [%s]" % " / ".join(state_tags)
		item.set_text(0, "%s  [%s]" % [label, actor_id])
		item.set_tooltip_text(0, "双击定位物件；隐藏与锁定状态仅影响编辑器。")
		item.clear_buttons()
		var valid_id := not actor_id.is_empty() and int(actor_id_counts.get(actor_id, 0)) == 1
		item.add_button(1, _visibility_icon(hidden), 1, not valid_id,
			"切换编辑器画布可见性" if valid_id else "请先为物件设置唯一 ID，才能保存可见性状态。")
	_sync_hierarchy_selection()
	_hierarchy_syncing = false
	_refresh_object_state_buttons()
	_refresh_group_buttons()


func _visibility_icon(hidden: bool) -> Texture2D:
	if not hidden and _object_tree.has_theme_icon("GuiVisibilityVisible", "EditorIcons"):
		return _object_tree.get_theme_icon("GuiVisibilityVisible", "EditorIcons")
	if _visibility_icons.is_empty():
		_visibility_icons = [_make_visibility_icon(false), _make_visibility_icon(true)]
	return _visibility_icons[1 if hidden else 0]


func _make_visibility_icon(hidden: bool) -> Texture2D:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var ink := Color(0.82, 0.86, 0.9, 1.0)
	for x in range(2, 14):
		var rise := sin(PI * float(x - 2) / 11.0) * 4.5
		var upper := roundi(7.5 - rise)
		var lower := roundi(7.5 + rise)
		image.set_pixel(x, upper, ink)
		image.set_pixel(x, lower, ink)
	for y in range(5, 11):
		for x in range(5, 11):
			if Vector2(x - 7.5, y - 7.5).length_squared() <= 5.0:
				image.set_pixel(x, y, ink)
	for y in range(6, 10):
		for x in range(6, 10):
			if Vector2(x - 7.5, y - 7.5).length_squared() <= 2.0:
				image.set_pixel(x, y, Color(0.22, 0.26, 0.3, 1.0))
	if hidden:
		var cross := Color(1.0, 0.42, 0.36, 1.0)
		for step in range(3, 13):
			image.set_pixel(step, step, cross)
			image.set_pixel(step, 15 - step, cross)
	return ImageTexture.create_from_image(image)


func _on_hierarchy_button_clicked(item: TreeItem, column: int, button_id: int,
		_mouse_button: int) -> void:
	if column != 1 or button_id != 1 or item == null:
		return
	var metadata: Dictionary = item.get_metadata(0)
	if metadata.get("kind", "") != "actor":
		return
	var index := int(metadata.get("index", -1))
	if index < 0 or index >= model.count(Kind.ACTOR):
		return
	var actor_id := str(model.actor_field(index, "id", ""))
	if actor_id.is_empty() or int(_actor_id_counts().get(actor_id, 0)) != 1:
		_status.text = "请先为物件设置唯一 ID，才能保存可见性状态。"
		return
	var hidden := not _hidden_actor_ids.has(actor_id)
	if hidden:
		_hidden_actor_ids[actor_id] = true
	else:
		_hidden_actor_ids.erase(actor_id)
	var save_error := _save_actor_editor_state()
	canvas.set_actor_editor_state(_hidden_actor_ids, _locked_actor_ids)
	_refresh_selection()
	if save_error == OK:
		_status.text = "物件已从编辑器画布隐藏。" if hidden else "物件已在编辑器画布显示。"
	else:
		_status.text = "状态已临时应用，但未能写入编辑器状态文件：%d" % save_error


func _create_group_item(group: Dictionary, root: TreeItem, items: Dictionary, visiting: Dictionary) -> TreeItem:
	var identity := str(group.get("id", ""))
	if items.has(identity):
		return items[identity]
	visiting[identity] = true
	var parent := root
	var parent_id := str(group.get("parent", ""))
	var parent_group := SceneHierarchy.find_group(model.data, parent_id)
	if not parent_group.is_empty() and not visiting.has(parent_id):
		parent = _create_group_item(parent_group, root, items, visiting)
	var item := _object_tree.create_item(parent)
	item.set_metadata(0, {"kind": "group", "id": identity})
	items[identity] = item
	return item


func _order_hierarchy_children(parent: TreeItem) -> void:
	var children: Array[TreeItem] = []
	var child := parent.get_first_child()
	while child != null:
		children.append(child)
		_order_hierarchy_children(child)
		child = child.get_next()
	var order: Array = model.data.get("editor_tree_order", [])
	children.sort_custom(func(first: TreeItem, second: TreeItem) -> bool:
		var first_index := order.find(_hierarchy_key(first.get_metadata(0)))
		var second_index := order.find(_hierarchy_key(second.get_metadata(0)))
		return (first_index if first_index >= 0 else 100000) < (second_index if second_index >= 0 else 100000))
	for index: int in range(1, children.size()):
		children[index].move_after(children[index - 1])


func _hierarchy_key(metadata: Dictionary) -> String:
	return str(metadata.get("kind", "")) + ":" + str(metadata.get("id", ""))


func _on_hierarchy_drop(source: Dictionary, target: Dictionary, section: int) -> void:
	var before: Dictionary = model.data.duplicate(true)
	var identity := str(source.get("id", ""))
	var kind := str(source.get("kind", ""))
	var members: Array[String] = []
	members.assign(SceneHierarchy.descendants(model.data, identity) if kind == "group" else [identity])
	for index: int in model.count(Kind.ACTOR):
		if members.has(str(model.actor_field(index, "id", ""))) and canvas.actor_is_locked(index):
			_status.text = "请先解锁编组内的物件。"
			return
	var target_id := str(target.get("id", ""))
	var target_kind := str(target.get("kind", ""))
	var parent_id := target_id if target_kind == "group" and section == 0 else \
		str(SceneHierarchy.find_group(model.data, target_id).get("parent", "")) if target_kind == "group" else \
		SceneHierarchy.parent_of_actor(model.data, target_id)
	if not SceneHierarchy.reparent(model.data, kind, identity, parent_id):
		_status.text = "层级移动被拒绝：不能把编组放入自身或后代。"
		return
	SceneHierarchy.reorder(model.data, _hierarchy_key(source), _hierarchy_key(target) if section != 0 else "", section > 0)
	if not SceneHierarchy.errors(model.data).is_empty():
		model.data = before
		return
	model.dirty = true
	_on_edited()
	_status.text = "层级已调整；物件位置、碰撞和遮挡顺序保持原值。"


func _sync_hierarchy_selection() -> void:
	var selected: Array[int] = canvas.selected_actors()
	var primary: TreeItem = null
	if _hierarchy_selecting:
		primary = _object_tree.get_selected()
	elif canvas.sel_kind == Kind.ACTOR:
		primary = _hierarchy_actor_items.get(canvas.sel_index)
	for index: int in _hierarchy_actor_items:
		var item: TreeItem = _hierarchy_actor_items[index]
		if item.is_selected(0) != selected.has(index):
			if selected.has(index):
				item.select(0, false)
			else:
				item.deselect(0)
	for item: TreeItem in _hierarchy_group_items:
		var members := _hierarchy_item_actor_indices(item)
		var all_selected := not members.is_empty()
		for index: int in members:
			all_selected = all_selected and selected.has(index)
		if all_selected:
			item.select(0, false)
		else:
			item.deselect(0)
	if primary != null and primary.is_selected(0) and _object_tree.get_selected() != primary:
		primary.select(0)


func _hierarchy_item_actor_indices(item: TreeItem) -> Array[int]:
	var indices: Array[int] = []
	var metadata: Dictionary = item.get_metadata(0)
	if metadata.get("kind", "") == "actor":
		var index := int(metadata.get("index", -1))
		if index >= 0 and index < model.count(Kind.ACTOR):
			indices.append(index)
	else:
		var child := item.get_first_child()
		while child != null:
			indices.append_array(_hierarchy_item_actor_indices(child))
			child = child.get_next()
	return indices


func _on_hierarchy_multi_selected(item: TreeItem, _column: int, selected: bool) -> void:
	if _hierarchy_syncing:
		return
	if not selected:
		var target := item
		if item.get_metadata(0).get("kind", "") == "actor" \
				and item.get_parent() != _object_tree.get_root():
			target = item.get_parent()
		_hierarchy_syncing = true
		target.deselect(0)
		for index: int in _hierarchy_item_actor_indices(target):
			(_hierarchy_actor_items[index] as TreeItem).deselect(0)
		_hierarchy_syncing = false
	if not _hierarchy_selection_queued:
		_hierarchy_selection_queued = true
		_on_hierarchy_item_selected.call_deferred()


func _on_hierarchy_item_selected() -> void:
	_hierarchy_selection_queued = false
	if _hierarchy_syncing:
		return
	var selected := _selected_actor_indices()
	var primary := _object_tree.get_selected()
	canvas.select_actors(selected)
	if primary != null and primary.is_selected(0) \
			and primary.get_metadata(0).get("kind", "") == "group":
		primary.collapsed = false
	if primary != null and primary.get_metadata(0).get("kind", "") == "actor":
		var index := int(primary.get_metadata(0).get("index", -1))
		if canvas.selected_actors().has(index):
			canvas.sel_index = index
	_hierarchy_selecting = true
	_refresh_selection()
	_hierarchy_selecting = false


func _on_hierarchy_item_edited(item: TreeItem = null) -> void:
	if _hierarchy_syncing:
		return
	if item == null:
		item = _object_tree.get_edited()
	if item == null:
		return
	var metadata: Dictionary = item.get_metadata(0)
	if metadata.get("kind", "") != "group":
		return
	for index: int in _hierarchy_item_actor_indices(item):
		if canvas.actor_is_locked(index):
			item.set_text(0, str(metadata.get("name", "组")))
			_status.text = "编组包含锁定物件，请先解锁后再改名。"
			return
	var old_name := str(metadata.get("name", "组"))
	var requested_name := item.get_text(0).strip_edges()
	if not model.rename_group(str(metadata.get("id", "")), requested_name):
		item.set_text(0, old_name)
		_status.text = "编组改名失败：名称不能为空或重名，且编组必须有唯一有效的 ID。"
		return
	item.set_text(0, requested_name)
	if requested_name == old_name:
		return
	_on_edited()
	_status.text = "编组已改名为「%s」，可撤销或重做。" % requested_name


func _on_hierarchy_item_activated() -> void:
	var item := _object_tree.get_selected()
	if item == null or item.get_metadata(0).get("kind", "") != "actor":
		return
	_on_hierarchy_item_selected()
	_frame_selection()


func _frame_selection() -> void:
	_status.text = "画布已定位到所选对象。" if canvas.frame_selection() \
		else "没有可定位的选区；隐藏物件需要先显示。"


func _refresh_group_buttons() -> void:
	if _group_button == null or _ungroup_button == null or canvas == null:
		return
	var selected: Array[int] = canvas.selected_actors()
	var selected_groups: Dictionary = {}
	var has_ungrouped := false
	_ungroup_button.disabled = true
	for index: int in selected:
		var group_name := model.group_name_for_actor(index)
		if group_name.is_empty():
			has_ungrouped = true
		else:
			selected_groups[group_name] = true
			_ungroup_button.disabled = false
	_group_button.disabled = selected.size() < 2 or (not has_ungrouped and selected_groups.size() <= 1)
	if _selection_has_locked_actor():
		_group_button.disabled = true
		_ungroup_button.disabled = true


func _selection_has_locked_actor() -> bool:
	for index: int in canvas.selected_actors():
		if canvas.actor_is_locked(index):
			return true
	return false


func _allow_selection_edit() -> bool:
	if canvas.sel_kind >= 0 and not canvas.is_kind_editable(canvas.sel_kind):
		_status.text = "当前图层已锁定或隔离，请先恢复该层编辑。"
		return false
	if not _selection_has_locked_actor():
		return true
	_status.text = "选区包含锁定物件，请先在场景列表中解锁。"
	return false


func _selected_actor_indices() -> Array[int]:
	var selected: Array[int] = []
	var item := _object_tree.get_next_selected(null)
	while item != null:
		for index: int in _hierarchy_item_actor_indices(item):
			if not selected.has(index):
				selected.append(index)
		item = _object_tree.get_next_selected(item)
	return selected


func _refresh_object_state_buttons() -> void:
	if _hide_selected_button == null:
		return
	var selected := _selected_actor_indices()
	var all_hidden := not selected.is_empty()
	var all_locked := not selected.is_empty()
	for index: int in selected:
		var actor_id := str(model.actor_field(index, "id", ""))
		all_hidden = all_hidden and _hidden_actor_ids.has(actor_id)
		all_locked = all_locked and _locked_actor_ids.has(actor_id)
	_hide_selected_button.disabled = selected.is_empty()
	_hide_selected_button.text = "显示所选" if all_hidden else "隐藏所选"
	_lock_selected_button.disabled = selected.is_empty()
	_lock_selected_button.text = "解锁所选" if all_locked else "锁定所选"
	_show_all_button.disabled = _hidden_actor_ids.is_empty()
	_frame_selected_button.disabled = canvas.sel_kind < 0


func _toggle_selected_actor_visibility() -> void:
	var selected_ids := _selected_editor_state_ids()
	if selected_ids.is_empty():
		return
	var should_hide := false
	for actor_id: String in selected_ids:
		if not _hidden_actor_ids.has(actor_id):
			should_hide = true
			break
	for actor_id: String in selected_ids:
		if should_hide:
			_hidden_actor_ids[actor_id] = true
		else:
			_hidden_actor_ids.erase(actor_id)
	var save_error := _save_actor_editor_state()
	canvas.set_actor_editor_state(_hidden_actor_ids, _locked_actor_ids)
	_refresh_selection()
	if save_error == OK:
		_status.text = "所选物件已隐藏。仍可从场景列表选中并显示。" if should_hide else "所选物件已显示。"
	else:
		_status.text = "状态已临时应用，但未能写入编辑器状态文件：%d" % save_error


func _toggle_selected_actor_lock() -> void:
	var selected_ids := _selected_editor_state_ids()
	if selected_ids.is_empty():
		return
	var should_lock := false
	for actor_id: String in selected_ids:
		if not _locked_actor_ids.has(actor_id):
			should_lock = true
			break
	for actor_id: String in selected_ids:
		if should_lock:
			_locked_actor_ids[actor_id] = true
		else:
			_locked_actor_ids.erase(actor_id)
	var save_error := _save_actor_editor_state()
	canvas.set_actor_editor_state(_hidden_actor_ids, _locked_actor_ids)
	_refresh_selection()
	if save_error == OK:
		_status.text = "所选物件已锁定，属性只读；仍可复制或从场景列表解锁。" if should_lock else "所选物件已解锁。"
	else:
		_status.text = "状态已临时应用，但未能写入编辑器状态文件：%d" % save_error


func _show_all_actors() -> void:
	if _hidden_actor_ids.is_empty():
		return
	_hidden_actor_ids.clear()
	var save_error := _save_actor_editor_state()
	canvas.set_actor_editor_state(_hidden_actor_ids, _locked_actor_ids)
	_refresh_selection()
	_status.text = "这张地图中的隐藏物件已全部显示。" if save_error == OK \
		else "状态已临时应用，但未能写入编辑器状态文件：%d" % save_error


func _load_actor_editor_state(map_id: String) -> void:
	_hidden_actor_ids.clear()
	_locked_actor_ids.clear()
	var config := ConfigFile.new()
	if FileAccess.file_exists(_editor_state_path):
		var error := config.load(_editor_state_path)
		if error != OK:
			_status.text = "编辑器隐藏/锁定状态读取失败：%d" % error
		else:
			_hidden_actor_ids = _id_lookup(config.get_value(map_id, "hidden_actor_ids", []))
			_locked_actor_ids = _id_lookup(config.get_value(map_id, "locked_actor_ids", []))
	canvas.set_actor_editor_state(_hidden_actor_ids, _locked_actor_ids)
	_prune_actor_editor_state()
	_refresh_objects()


func _actor_id_counts() -> Dictionary:
	var counts: Dictionary = {}
	for index: int in model.count(Kind.ACTOR):
		var actor_id := str(model.actor_field(index, "id", ""))
		counts[actor_id] = int(counts.get(actor_id, 0)) + 1
	return counts


func _selected_editor_state_ids() -> PackedStringArray:
	var actor_counts := _actor_id_counts()
	var result := PackedStringArray()
	for index: int in _selected_actor_indices():
		var actor_id := str(model.actor_field(index, "id", ""))
		if actor_id.is_empty() or int(actor_counts.get(actor_id, 0)) != 1:
			_status.text = "隐藏/锁定前，请先为所选物件填写非空且唯一的 ID。"
			return PackedStringArray()
		result.append(actor_id)
	return result


func _prune_actor_editor_state() -> void:
	var actor_counts := _actor_id_counts()
	var changed := false
	for lookup: Dictionary in [_hidden_actor_ids, _locked_actor_ids]:
		for actor_id: Variant in lookup.keys():
			if str(actor_id).is_empty() or int(actor_counts.get(actor_id, 0)) != 1:
				lookup.erase(actor_id)
				changed = true
	if changed:
		var save_error := _save_actor_editor_state()
		canvas.set_actor_editor_state(_hidden_actor_ids, _locked_actor_ids)
		if save_error != OK:
			_status.text = "已清理失效物件状态，但写入状态文件失败：%d" % save_error


func _id_lookup(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is Array or value is PackedStringArray:
		for raw_id: Variant in value:
			var actor_id := str(raw_id)
			if not actor_id.is_empty():
				result[actor_id] = true
	return result


func _ids_from_lookup(lookup: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for actor_id: Variant in lookup:
		if bool(lookup[actor_id]):
			result.append(str(actor_id))
	result.sort()
	return result


func _save_actor_editor_state() -> Error:
	var config := ConfigFile.new()
	if FileAccess.file_exists(_editor_state_path):
		var load_error := config.load(_editor_state_path)
		if load_error != OK:
			return load_error
	config.set_value(model.map_id, "hidden_actor_ids", _ids_from_lookup(_hidden_actor_ids))
	config.set_value(model.map_id, "locked_actor_ids", _ids_from_lookup(_locked_actor_ids))
	return config.save(_editor_state_path)


func _object_command(command: String) -> void:
	if command == "cancel":
		canvas.cancel_interaction()
		_on_tool(Canvas.Tool.SELECT)
		return
	if command == "frame_selection":
		_frame_selection()
		return
	if command == "delete":
		_on_delete()
		return
	if (command == "group" or command == "ungroup") and not _allow_selection_edit():
		return
	if command == "group":
		var group_name: String = model.group_actors(canvas.selected_actors())
		if group_name.is_empty():
			_status.text = "编组需要至少两件物件，且每件物件都要有唯一 ID。"
			return
		_on_edited()
		_refresh_selection()
		_status.text = "已将所选物件编为「%s」；选中组内任一件即可整体移动或复制。" % group_name
		return
	if command == "ungroup":
		var removed: int = model.ungroup_actors(canvas.selected_actors())
		if removed == 0:
			_status.text = "所选物件没有所属编组。"
			return
		_on_edited()
		_refresh_selection()
		_status.text = "已解散 %d 个编组；物件保留。" % removed
		return
	if command == "preview":
		var errors: Array[String] = model.validation_errors()
		if not errors.is_empty():
			_status.text = "试走前请修正：\n" + "\n".join(errors)
			return
		_open_preview({})
		return
	if command == "undo" or command == "redo":
		var restored: bool = model.undo() if command == "undo" else model.redo()
		if restored:
			_prune_actor_editor_state()
			var no_selection: Array[int] = []
			canvas.select_actors(no_selection)
			canvas.set_overlay_texture(model.overlay_path())
			canvas.invalidate_def()
			_panel_kind = -1
			_refresh_dirty()
			_refresh_objects()
			_refresh_selection()
		return
	if command == "copy" or command == "duplicate":
		model.copy_actors(canvas.selected_actors())
		_status.text = "已复制 %d 件物件（包含碰撞与交互）" % canvas.selected_actors().size()
	if command == "paste" or command == "duplicate":
		canvas.select_actors(model.paste_actors())
		_on_edited()
		_refresh_selection()
	if command == "template" and canvas.sel_kind == Kind.ACTOR:
		var dialog := ConfirmationDialog.new()
		dialog.title = "存为物件模板（新实例取当前属性快照）"
		var field := LineEdit.new()
		field.text = str(model.actor_field(canvas.sel_index, "id", "object"))
		dialog.add_child(field)
		var source: Dictionary = model.actor_dict(canvas.sel_index).duplicate(true)
		dialog.confirmed.connect(func() -> void:
			var error: Error = _library.save_template(field.text.strip_edges(), source)
			_status.text = "模板已保存；修改模板不会静默改动已有实例。" if error == OK else "模板保存失败（重名不会覆盖）：%d" % error
			_refresh_templates()
			dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered(Vector2i(460, 120))


func _rebuild_object_inspector() -> void:
	_build_actor_panel()
	_refresh_selection()


func _toggle_toolbar_drawer(open: bool, index: int) -> void:
	for drawer_index in _toolbar_drawers.size():
		var visible := open and drawer_index == index
		_toolbar_drawers[drawer_index].visible = visible
		_drawer_buttons[drawer_index].set_pressed_no_signal(visible)


func _row_title() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_child(_text("地图："))
	_map_picker = OptionButton.new()
	_map_picker.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	_map_picker.custom_minimum_size = Vector2(200, 0)
	_map_picker.item_selected.connect(_on_map_selected)
	row.add_child(_map_picker)
	var create := Button.new()
	create.text = "新建地图…"
	create.pressed.connect(_open_create_map)
	row.add_child(create)
	var add_actor := Button.new()
	add_actor.text = "新建物件"
	add_actor.pressed.connect(_on_add_actor)
	row.add_child(add_actor)
	var import_actor := Button.new()
	import_actor.text = "导入物件…"
	import_actor.pressed.connect(_open_import_dialog)
	row.add_child(import_actor)
	var reload := Button.new()
	reload.text = "重新载入（丢弃改动）"
	reload.tooltip_text = "从磁盘重读这张图，丢掉这次没保存的改动"
	reload.pressed.connect(_on_reload)
	_map_management.add_child(reload)
	var fit := Button.new()
	fit.text = "适应画布"
	fit.tooltip_text = "把整张地图缩放并居中到当前画布区域"
	fit.pressed.connect(func() -> void: canvas.fit_to_view())
	row.add_child(fit)
	row.add_child(_text("倍率"))
	_zoom_spin = SpinBox.new()
	_zoom_spin.min_value = 0.01
	_zoom_spin.max_value = 12.0
	_zoom_spin.step = 0.01
	_zoom_spin.value = canvas.zoom
	_zoom_spin.suffix = "×"
	_zoom_spin.custom_minimum_size.x = 92
	_zoom_spin.tooltip_text = "显示当前画布缩放倍率；可直接输入数值调整。"
	_zoom_spin.value_changed.connect(canvas.set_zoom)
	canvas.zoom_changed.connect(func(value: float) -> void: _zoom_spin.set_value_no_signal(value))
	row.add_child(_zoom_spin)
	_drop_draft_button = Button.new()
	_drop_draft_button.text = "丢弃草稿"
	_drop_draft_button.tooltip_text = "把这张图的未保存草稿删掉（改动就此消失）"
	_drop_draft_button.pressed.connect(_on_drop_draft)
	_map_management.add_child(_drop_draft_button)
	_save_button = Button.new()
	_save_button.text = "保存到 JSON"
	_save_button.pressed.connect(_on_save)
	row.add_child(_save_button)
	var preview := Button.new()
	preview.text = "当前布局试走"
	preview.pressed.connect(_object_command.bind("preview"))
	row.add_child(preview)
	var backup_history := Button.new()
	backup_history.text = "备份历史…"
	backup_history.tooltip_text = "载入一份旧地图快照到编辑器；确认后仍需手动保存才会覆盖地图。"
	backup_history.pressed.connect(_open_backup_dialog)
	_map_management.add_child(backup_history)
	var copy := Button.new()
	copy.text = "复制布局到…"
	copy.tooltip_text = "把这张图的碰撞箱/传送区/物件覆盖到另一张图上（白天版↔夜间版）"
	copy.pressed.connect(_open_copy_dialog)
	_map_management.add_child(copy)
	return row


func _row_layers() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_child(_text("显示："))
	for item in [["背景", "show_bg"], ["前景层", "show_overlay"], ["墙", "show_walls"],
			["传送区", "show_portals"], ["物件", "show_actors"], ["出生点", "show_spawns"],
			["可走格", "show_walk"], ["脚底框（跟鼠标）", "show_foot"]]:
		var cb := CheckBox.new()
		cb.text = str(item[0])
		cb.button_pressed = bool(canvas.get(str(item[1])))
		cb.tooltip_text = "取消勾选：这一类既不显示，也点不中（底下压着的东西就能选中了）"
		if str(item[1]) == "show_walk":
			cb.tooltip_text = "显示角色脚底能站稳的位置；会预留角色碰撞体积，编辑碰撞后自动刷新。"
		elif str(item[1]) == "show_foot":
			cb.tooltip_text = "鼠标处显示角色实际脚底框；绿色可站稳，红色表示会碰到实体。"
		cb.toggled.connect(_on_layer.bind(str(item[1])))
		row.add_child(cb)
	var refresh := Button.new()
	refresh.text = "重算可走格"
	refresh.tooltip_text = "编辑碰撞后会自动刷新，也可点击立即按当前布局重算。"
	refresh.pressed.connect(func() -> void:
		_status.text = "正在算可走格……"
		canvas.recompute_walk())
	row.add_child(refresh)

	# 前景层不透明度：它恒在角色之上，会挡住底下正在编辑的东西
	row.add_child(_text("  前景层"))
	var alpha := HSlider.new()
	alpha.min_value = 0
	alpha.max_value = 100
	alpha.step = 5
	alpha.value = 100
	alpha.custom_minimum_size = Vector2(120, 0)
	alpha.tooltip_text = "调淡前景层，看清它底下盖着的碰撞箱/传送区。只影响显示，不改数据。"
	alpha.value_changed.connect(func(v: float) -> void:
		canvas.overlay_alpha = v / 100.0
		canvas.queue_redraw())
	row.add_child(alpha)
	return row


func _row_selection() -> HFlowContainer:
	var row := HFlowContainer.new()
	_sel_label = _text("未选中")
	_sel_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(_sel_label)
	for name in ["x", "y", "宽", "高"]:
		var field := HBoxContainer.new()
		field.add_child(_text(name))
		var spin := SpinBox.new()
		spin.min_value = -1000000
		spin.max_value = 1000000
		spin.step = 1
		spin.custom_minimum_size = Vector2(78, 0)
		spin.value_changed.connect(_on_spin_changed)
		field.add_child(spin)
		row.add_child(field)
		_spins.append(spin)

	_base_row = HFlowContainer.new()
	_base_spin = SpinBox.new()
	_base_spin.min_value = -1000000
	_base_spin.max_value = 1000000
	_base_spin.step = 1
	_base_spin.custom_minimum_size = Vector2(78, 0)
	_base_spin.value_changed.connect(_on_base_spin)
	_base_row.add_child(_base_spin)
	_base_auto_button = Button.new()
	_base_auto_button.text = "恢复自动"
	_base_auto_button.pressed.connect(_on_base_auto)
	_base_row.add_child(_base_auto_button)
	_base_row.visible = false

	var remove := Button.new()
	remove.text = "删除选中"
	remove.tooltip_text = "删掉当前选中的墙 / 传送区 / 出生点（Delete 键同样管用）"
	remove.pressed.connect(_on_delete)
	row.add_child(remove)

	var add_spawn := Button.new()
	add_spawn.text = "加出生点"
	add_spawn.tooltip_text = "加一个出生点（会问你名字，加在地图正中，之后拖到位置）。"
	add_spawn.tooltip_text += "\n注意：至少得留一个 start —— 新游戏和多数传送点都找它。"
	add_spawn.pressed.connect(_open_spawn_dialog)
	row.add_child(add_spawn)

	var import_image := Button.new()
	import_image.text = "导入图像…"
	import_image.tooltip_text = "挑一张 PNG → 拷进 art/props/ → 新建一件遮挡物件（位置和基线之后在画布上调）"
	import_image.pressed.connect(_open_import_dialog)
	row.add_child(import_image)

	var add_actor := Button.new()
	add_actor.text = "加物件"
	add_actor.tooltip_text = "加一件家具/NPC，落在地图正中；下面的「物件属性」里填名字、贴图和互动内容。"
	add_actor.pressed.connect(_on_add_actor)
	row.add_child(add_actor)
	return row


func _text(t: String) -> Label:
	var label := Label.new()
	label.text = t
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# ---------------------------------------------------------------- 载入与保存

## 重建地图下拉。带草稿的标一个 `*`（还没保存的改动）。
## `load_first` 只在最开始那次用 —— 平时重建（比如刚保存完）不该顺手重载，
## 那会把光标和选中弄丢。
func refresh_map_list(load_first := false) -> void:
	var keep := ""
	if _map_picker.item_count > 0 and _map_picker.selected >= 0:
		keep = str(_map_picker.get_item_metadata(_map_picker.selected))
	var drafts := model.draft_ids()
	_map_picker.clear()
	var ids := Model.list_maps()
	for i in ids.size():
		_map_picker.add_item(ids[i] + ("  *" if drafts.has(ids[i]) else ""), i)
		_map_picker.set_item_metadata(i, ids[i])
		if ids[i] == keep:
			_map_picker.select(i)
	if load_first and ids.size() > 0:
		_load_selected()


## 切到下拉里选的那张图。**切之前先把现在这张的改动存成草稿** ——
## 这是这次要解决的问题：改到一半去看另一张图，回来接着改。
func _on_map_selected(_index: int) -> void:
	var target := str(_map_picker.get_item_metadata(_map_picker.selected))
	if model.map_id != "" and target != model.map_id and model.dirty:
		model.stash_draft()
		_status.text = "%s 的改动先存成草稿了（没保存，回来还能接着改）" % model.map_id
	_load_selected()
	refresh_map_list()


func _open_create_map() -> void:
	var dialog := MapCreationDialog.new()
	dialog.map_created.connect(func(result: Dictionary) -> void:
		_on_map_created(result)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.open_creation()


func _on_map_created(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_status.text = str(result.get("error", "新建地图失败。"))
		return
	if model.map_id != "" and model.dirty:
		model.stash_draft()
	refresh_map_list()
	var id := str((result["data"] as Dictionary).get("id", ""))
	for index in _map_picker.item_count:
		if str(_map_picker.get_item_metadata(index)) == id:
			_map_picker.select(index)
			_load_selected()
			break
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_refresh_assets()
	_status.text = "已创建 %s，背景原图 1:1。接下来放置物件、碰撞和传送区。" % id
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if model.map_id == id:
			canvas.load_map(model, model.background_path(), model.overlay_path(), model.map_size()))


func _on_reload() -> void:
	# 「重新载入」= 丢掉改动重读文件，所以连草稿一起丢掉
	if model.map_id != "":
		model.drop_draft(model.map_id)
	_load_selected()
	refresh_map_list()


func _on_drop_draft() -> void:
	if model.map_id == "" or not model.draft_exists(model.map_id):
		_status.text = "这张图没有草稿。"
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "丢掉 %s 的草稿？" % model.map_id
	dialog.ok_button_text = "丢掉"
	var box := VBoxContainer.new()
	var text := _text("草稿里是 %s 存下的未保存改动。丢掉就没了，图会回到仓库里的版本。"
		% model.draft_time(model.map_id))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	dialog.add_child(_scrolled(box, Vector2(420, 90)))
	dialog.confirmed.connect(func() -> void:
		model.drop_draft(model.map_id)
		_load_selected()
		refresh_map_list()
		_status.text = "草稿丢掉了，这张图回到仓库里的版本。"
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _load_selected() -> void:
	var id := str(_map_picker.get_item_metadata(_map_picker.selected))
	if id == "":
		return
	if not model.load_map(id):
		_status.text = "载入失败：%s" % id
		return
	canvas.load_map(model, model.background_path(), model.overlay_path(), model.map_size())
	_refresh_dirty()
	if model.from_draft:
		_status.text = "载入的是 %s 的**草稿**（%s 存下的，还没保存）。想丢掉就点「丢弃草稿」。" % [
			id, model.draft_time(id)]
	else:
		_status.text = "已载入 %s（%d×%d 游戏单位）。滚轮缩放，中键/右键拖动平移。" % [
			id, int(model.map_size().x), int(model.map_size().y)]
	_load_actor_editor_state(id)


func _on_save() -> void:
	var problems: Array[String] = model.validation_errors()
	var review: Dictionary = Validation.validate(model.data, {}, _library)
	for issue: Dictionary in review.get("errors", []):
		if not problems.has(str(issue.get("message", ""))):
			problems.append(str(issue.get("message", "")))
	if not problems.is_empty():
		_status.text = "保存前请修正：\n" + "\n".join(problems)
		return
	if not review.get("warnings", []).is_empty():
		var messages: Array[String] = []
		for issue: Dictionary in review["warnings"]:
			messages.append(str(issue.get("message", "")))
		var confirm := ConfirmationDialog.new()
		confirm.title = "保存前检查提醒"
		confirm.dialog_text = "\n".join(messages) + "\n仍然保存这份地图？"
		var reviewed: Dictionary = model.data.duplicate(true)
		confirm.confirmed.connect(func() -> void:
			if model.data == reviewed:
				_save_validated()
			else:
				_status.text = "地图在确认期间已变化，请重新保存并校验。"
			confirm.queue_free())
		confirm.canceled.connect(confirm.queue_free)
		add_child(confirm)
		confirm.popup_centered(Vector2i(660, 360))
		return
	_save_validated()


func _save_validated() -> void:
	var err := model.save_to()
	if err == OK:
		_refresh_dirty()
		refresh_map_list()
		var backup_note := "；旧版已备份 %s" % model.last_backup_name if model.last_backup_name != "" else ""
		_status.text = "已保存 %s%s（草稿已清掉）" % [model.path, backup_note]
	elif model.last_backup_failed:
		_status.text = "保存已取消：无法创建自动备份，原地图未覆盖；请检查备份目录写入权限。"
	else:
		_status.text = "保存失败，错误码 %d" % err


func _open_backup_dialog() -> void:
	if model.map_id == "":
		return
	var names: Array[String] = model.backup_store.list_snapshots(model.map_id)
	if names.is_empty():
		var empty_dialog := AcceptDialog.new()
		empty_dialog.title = "地图备份历史"
		empty_dialog.dialog_text = "这张地图还没有旧版快照。每次保存覆盖已有地图后，编辑器会自动保留备份。"
		add_child(empty_dialog)
		empty_dialog.confirmed.connect(func() -> void: empty_dialog.queue_free())
		empty_dialog.canceled.connect(func() -> void: empty_dialog.queue_free())
		empty_dialog.popup_centered()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "载入地图备份"
	dialog.ok_button_text = "载入到编辑器"
	var box := VBoxContainer.new()
	var warning := _text("载入会替换当前编辑内容，但不会立刻改磁盘地图；载入后检查无误，再点「保存到 JSON」。")
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(warning)
	var picker := OptionButton.new()
	picker.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for name: String in names:
		picker.add_item(name.trim_suffix(".json"))
	box.add_child(picker)
	dialog.add_child(_scrolled(box, Vector2(520, 120)))
	dialog.confirmed.connect(func() -> void:
		var error := model.restore_backup(names[picker.selected])
		if error == OK:
			var no_selection: Array[int] = []
			canvas.select_actors(no_selection)
			canvas.set_overlay_texture(model.overlay_path())
			canvas.invalidate_def()
			_panel_kind = -1
			_refresh_dirty()
			_refresh_objects()
			_refresh_selection()
			_status.text = "已载入备份 %s；改动尚未写入地图文件。" % names[picker.selected].trim_suffix(".json")
		else:
			_status.text = "备份无法载入，错误码 %d；地图内容未替换。" % error
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(620, 220))


func _refresh_dirty() -> void:
	_save_button.text = "保存到 JSON *" if model.dirty else "保存到 JSON"
	if _drop_draft_button != null:
		_drop_draft_button.disabled = not model.draft_exists(model.map_id)


# ---------------------------------------------------------------- 交互

func _on_tool(which: int) -> void:
	if which in [Canvas.Tool.BASELINE, Canvas.Tool.COLLISION]:
		if canvas.sel_kind != Kind.ACTOR or canvas.selected_actors().size() != 1 \
				or not _allow_selection_edit():
			_status.text = "请先单选一件未锁定物件，再使用属性卡里的工具。"
			return
	canvas.tool = which
	for button: Button in _tool_buttons:
		button.set_pressed_no_signal(int(button.get_meta("map_tool")) == which)
	if is_instance_valid(_object_inspector):
		_object_inspector.set_active_tool(which)
	match which:
		Canvas.Tool.SELECT:
			_status.text = "选择：拖动物件；移动会带动交互区和碰撞。绿色框调整交互区，红色框调整碰撞；贴图尺寸见「视觉部件与变换」。"
		Canvas.Tool.WALL:
			_status.text = "画墙：在图上按住左键拖出一个框，松手就加进 walls。"
		Canvas.Tool.PORTAL:
			_status.text = "画传送区：同上，落进 portals（默认 locked，不通往任何地方）。"
		Canvas.Tool.BASELINE:
			_status.text = "拉基线：点一件遮挡物（身上有黄线），上下拖，松手写进它的 cover_y。"
		Canvas.Tool.COLLISION:
			_status.text = "先单选物件：空白处拖出碰撞，已有红框可移动和八柄缩放，Esc 取消；排序取参考碰撞上边缘。"


func _on_layer(on: bool, prop: String) -> void:
	canvas.set_layer_visible(prop, on)
	if prop == "show_walk":
		if on:
			_status.text = "可走格已开启：绿=脚底能站稳，红=会碰撞；修改碰撞后自动刷新。"
		else:
			_status.text = "可走格已关闭。"
	else:
		_status.text = "「%s」%s —— 显示开关同时管能不能点中" % [prop, "开着" if on else "关掉了"]


## 删东西。**有跨文件关联的先问一句** —— 删掉就断了那条入口，
## 而且数据本身还是合法的，`check_data` 也不会报（它只查「引用存在不存在」，
## 查不出「本来该有个人来触发」）。
func _on_delete() -> void:
	if canvas.sel_kind < 0 or not _allow_selection_edit():
		return
	var names := ["墙", "传送区", "物件", "出生点", "前景层"]
	var what: String = names[canvas.sel_kind]
	var was: String = model.label_of(canvas.sel_kind, canvas.sel_index)
	var refs: Array[String] = []
	if canvas.sel_kind == Kind.ACTOR:
		for index: int in canvas.selected_actors():
			for reference: String in model.actor_references(index):
				refs.append(model.label_of(Kind.ACTOR, index) + "：" + reference)
	elif canvas.sel_kind == Kind.PORTAL:
		refs = model.portal_references(canvas.sel_index)
	if refs.is_empty():
		_do_delete(what, was)
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "删这件「%s」？它身上挂着东西" % was
	dialog.ok_button_text = "照样删掉"
	var box := VBoxContainer.new()
	var head := _text("删掉之后，下面这些就再也触发不到了（文件还在，只是没了入口）：")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	for line in refs:
		var item := _text("· " + line)
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(item)
	dialog.add_child(_scrolled(box, Vector2(420, 180)))
	var reviewed: Dictionary = model.data.duplicate(true)
	var reviewed_selection: Array[int] = canvas.selected_actors()
	var reviewed_kind: int = canvas.sel_kind
	var reviewed_index: int = canvas.sel_index
	dialog.confirmed.connect(func() -> void:
		if model.data == reviewed and canvas.sel_kind == reviewed_kind \
				and canvas.sel_index == reviewed_index and canvas.selected_actors() == reviewed_selection:
			_do_delete(what, was)
		else:
			_status.text = "选区或地图已变化，请重新确认删除。"
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(470, 220))


func _do_delete(what: String, was: String) -> void:
	if not _allow_selection_edit():
		return
	if canvas.sel_kind == Kind.ACTOR:
		var indices: Array[int] = canvas.selected_actors()
		indices.sort()
		indices.reverse()
		for index: int in indices:
			model.remove_at(Kind.ACTOR, index)
		canvas.actor_selection.clear()
	else:
		model.remove_at(canvas.sel_kind, canvas.sel_index)
	canvas.sel_kind = -1
	canvas.sel_index = -1
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_status.text = "删了一个%s%s（还没保存，点「重新载入」就能全部撤回来）" % [
		what, "（%s）" % was if was != "" else ""]


## 加一个出生点：问名字、加在地图正中，之后拖到位置。
func _open_spawn_dialog() -> void:
	if model.map_id == "":
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "加一个出生点"
	dialog.ok_button_text = "加"
	var box := VBoxContainer.new()
	var head := _text("名字（传送点就是这样引用它的，别和现有的重名）：")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	var field := LineEdit.new()
	field.custom_minimum_size = Vector2(200, 0)
	field.text = "from_"
	box.add_child(field)
	var tip := _text("加进来在地图正中，选中之后拖到位置上；x/y 也能敲数字。")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)
	dialog.add_child(_scrolled(box, Vector2(380, 150)))
	dialog.confirmed.connect(func() -> void:
		var index := model.add_spawn(field.text.strip_edges())
		if index < 0:
			_status.text = "这个名字不能用：空的，或者已经有同名的出生点了"
		else:
			model.set_spawn_point(index, model.map_size() * 0.5)
			canvas.sel_kind = Kind.SPAWN
			canvas.sel_index = index
			_on_edited()
			_refresh_selection()
			canvas.queue_redraw()
			_status.text = "加好了出生点「%s」，现在把它拖到位置上" % field.text.strip_edges()
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 190))
	field.grab_focus()


func _on_layout_action(action: int) -> void:
	if not _allow_selection_edit():
		return
	var selected: Array[int] = canvas.selected_actors()
	var changed := false
	var label := ""
	match action:
		LayoutAction.ALIGN_LEFT:
			changed = model.align_actors(selected, Model.ActorAlignment.LEFT)
			label = "左对齐"
		LayoutAction.ALIGN_CENTER_X:
			changed = model.align_actors(selected, Model.ActorAlignment.CENTER_X)
			label = "水平居中"
		LayoutAction.ALIGN_RIGHT:
			changed = model.align_actors(selected, Model.ActorAlignment.RIGHT)
			label = "右对齐"
		LayoutAction.ALIGN_TOP:
			changed = model.align_actors(selected, Model.ActorAlignment.TOP)
			label = "顶对齐"
		LayoutAction.ALIGN_CENTER_Y:
			changed = model.align_actors(selected, Model.ActorAlignment.CENTER_Y)
			label = "垂直居中"
		LayoutAction.ALIGN_BOTTOM:
			changed = model.align_actors(selected, Model.ActorAlignment.BOTTOM)
			label = "底对齐"
		LayoutAction.DISTRIBUTE_HORIZONTAL:
			changed = model.distribute_actors(selected, Model.DistributionAxis.HORIZONTAL)
			label = "水平等间距"
		LayoutAction.DISTRIBUTE_VERTICAL:
			changed = model.distribute_actors(selected, Model.DistributionAxis.VERTICAL)
			label = "垂直等间距"
	if not changed:
		_status.text = "位置无需调整；对齐需两件物件，等间距需三件。"
		return
	_on_edited()
	_refresh_selection()
	_status.text = "已完成物件%s" % label


func _open_copy_dialog() -> void:
	if model.map_id == "":
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "复制布局到另一张地图"
	dialog.ok_button_text = "覆盖过去"
	var box := VBoxContainer.new()
	var head := _text("把 %s 的碰撞箱、传送区、物件，覆盖到：" % model.map_id)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	var picker := OptionButton.new()
	picker.fit_to_longest_item = false
	picker.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for id in Model.list_maps():
		if id != model.map_id:
			picker.add_item(id)
	box.add_child(picker)
	var with_spawns := CheckBox.new()
	with_spawns.text = "连出生点一起复制"
	box.add_child(with_spawns)
	var warn := _text("目标图里这三项会被整个换掉；尺寸、背景、前景层、音乐不动。")
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(warn)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	dialog.add_child(scroll)
	dialog.confirmed.connect(func() -> void:
		var target := picker.get_item_text(picker.selected)
		var counts := "%d 墙 / %d 传送区 / %d 物件" % [
			model.count(Kind.WALL), model.count(Kind.PORTAL), model.count(Kind.ACTOR)]
		var err := model.copy_layout_to(target, with_spawns.button_pressed)
		_status.text = ("已把 %s 覆盖到 %s" % [counts, target]) if err == "" else err
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _on_spin_changed(_v: float) -> void:
	if _syncing or canvas.sel_kind < 0 or not _allow_selection_edit():
		return
	if canvas.sel_kind == Kind.SPAWN:
		# 出生点是坐标，不是矩形 —— 只认 x / y 两个框
		canvas.model.set_spawn_point(canvas.sel_index, Vector2(_spins[0].value, _spins[1].value))
		_on_edited()
		canvas.queue_redraw()
		return
	var r: Rect2 = canvas.model.interaction_rect_of(canvas.sel_index) \
		if canvas.sel_kind == Kind.ACTOR else canvas.model.rect_of(canvas.sel_kind, canvas.sel_index)
	var next := Rect2(
		Vector2(_spins[0].value, _spins[1].value),
		Vector2(maxf(1.0, _spins[2].value), maxf(1.0, _spins[3].value)))
	if next != r:
		if canvas.sel_kind == Kind.ACTOR:
			canvas.model.set_interaction_rect(canvas.sel_index, next)
		else:
			canvas.model.set_rect(canvas.sel_kind, canvas.sel_index, next)
		_on_edited()
		canvas.queue_redraw()


func _on_base_spin(v: float) -> void:
	if _syncing or canvas.sel_kind != Kind.ACTOR or not canvas.model.is_cover_actor(canvas.sel_index):
		return
	if not _allow_selection_edit():
		return
	canvas.model.set_actor_cover_y(canvas.sel_index, v)
	_on_edited()
	canvas.queue_redraw()


func _on_base_auto() -> void:
	if canvas.sel_kind != Kind.ACTOR or not _allow_selection_edit():
		return
	canvas.model.clear_actor_cover_y(canvas.sel_index)
	_on_edited()
	_refresh_selection()


func _on_selection_changed() -> void:
	_texture_request_serial += 1
	if canvas.tool in [Canvas.Tool.BASELINE, Canvas.Tool.COLLISION] \
			and (canvas.sel_kind != Kind.ACTOR or canvas.selected_actors().size() != 1):
		_on_tool(Canvas.Tool.SELECT)
	_refresh_selection()


func _refresh_selection() -> void:
	var selection_key: Array = [model.get_instance_id(), model.map_id, canvas.sel_kind,
		canvas.sel_index, canvas.selected_actors()]
	if selection_key != _texture_selection_key:
		_texture_request_serial += 1
		_texture_selection_key = selection_key
	_refresh_objects()
	var kind: int = canvas.sel_kind
	var index: int = canvas.sel_index
	_syncing = true
	if kind < 0:
		_sel_label.text = "未选中"
		for spin in _spins:
			spin.editable = false
		if is_instance_valid(_base_row):
			_base_row.visible = false
	else:
		var names := ["墙", "传送区", "物件", "出生点", "前景层"]
		var r: Rect2 = model.interaction_rect_of(index) if kind == Kind.ACTOR \
			else model.rect_of(kind, index)
		_sel_label.text = ("物件交互区" if kind == Kind.ACTOR else names[kind]) \
			+ " #%d %s" % [index, model.label_of(kind, index)]
		_spins[0].value = r.position.x
		_spins[1].value = r.position.y
		_spins[2].value = r.size.x
		_spins[3].value = r.size.y
		for spin: SpinBox in _spins:
			spin.tooltip_text = "编辑物件交互区；不会改变贴图或碰撞。" if kind == Kind.ACTOR else "编辑所选矩形。"
		var is_spawn: bool = kind == Kind.SPAWN
		var is_overlay: bool = kind == Kind.OVERLAY
		var is_locked: bool = _selection_has_locked_actor() or not canvas.is_kind_editable(kind)
		# 出生点没有宽高可改（它就是个坐标）；前景层整张拉伸，四个都不给改
		_spins[0].editable = not is_overlay and not is_locked
		_spins[1].editable = not is_overlay and not is_locked
		_spins[2].editable = not is_spawn and not is_overlay and not is_locked
		_spins[3].editable = not is_spawn and not is_overlay and not is_locked
		if is_overlay:
			_spins[0].value = 0
			_spins[1].value = 0
			_spins[2].value = 0
			_spins[3].value = 0
		if is_spawn:
			# 出生点显示的是「点本身」，别把包装用的 6×6 露出来
			var p: Vector2 = model.spawn_point(index)
			_spins[0].value = p.x
			_spins[1].value = p.y
		var is_cover: bool = kind == Kind.ACTOR and canvas.selected_actors().size() == 1 \
			and model.is_cover_actor(index)
		if is_instance_valid(_base_row):
			_base_row.visible = is_cover
		if is_cover and is_instance_valid(_base_spin) and is_instance_valid(_base_auto_button):
			_base_spin.editable = not is_locked
			_base_auto_button.disabled = is_locked
			_base_spin.set_value_no_signal(model.actor_cover_y(index))
			_base_spin.tooltip_text = "独立物件：碰撞箱上边缘；旧物件：贴图底边。橙线表示手动调整。"
	_syncing = false
	_sync_actor_panel()
	if kind == Kind.ACTOR and is_instance_valid(_object_inspector):
		for object_tool: int in _object_inspector._tool_buttons:
			var button: Button = _object_inspector._tool_buttons[object_tool]
			button.disabled = canvas.selected_actors().size() != 1 or _selection_has_locked_actor() \
				or canvas.actor_is_hidden(index) \
				or (object_tool == Canvas.Tool.BASELINE and not model.is_cover_actor(index))
	_refresh_transfer_button()


func _transfer_target_error(expected_model = null, expected_map := "", expected_index := -1,
		expected_id := "") -> String:
	if expected_model != null and (model != expected_model or model.map_id != expected_map):
		return "地图已切换或重新载入，请关闭助手后重新打开。"
	if canvas.sel_kind != Kind.ACTOR or canvas.sel_index < 0:
		return "请先选中单个物件。"
	var selected: Array[int] = canvas.selected_actors()
	if selected.size() != 1 or selected[0] != canvas.sel_index:
		return "归属目标必须是单个物件；请先解除编组或取消多选。"
	if _selected_actor_indices().size() > 1:
		return "场景树仍选中了多个物件；请先取消多选后再归入地图墙。"
	if model.expand_group_selection(selected).size() != 1:
		return "编组包含多个物件，请先解组后指定归属目标。"
	var index: int = canvas.sel_index
	if index >= model.count(Kind.ACTOR):
		return "目标物件已不存在，请重新选择。"
	var actor_id := str(model.actor_field(index, "id", ""))
	if expected_index >= 0 and (index != expected_index or actor_id != expected_id):
		return "当前目标已改变，请关闭助手后重新打开。"
	if canvas.actor_is_hidden(index) or _hidden_actor_ids.has(actor_id):
		return "目标物件已隐藏，请先显示物件再归入地图墙。"
	if canvas.actor_is_locked(index) or _locked_actor_ids.has(actor_id):
		return "目标物件已锁定，请先解锁物件再归入地图墙。"
	return ""


func _refresh_transfer_button() -> void:
	if not is_instance_valid(_transfer_button):
		return
	_transfer_button.visible = canvas.sel_kind == Kind.ACTOR
	var reason := _transfer_target_error()
	_transfer_button.disabled = not reason.is_empty()
	_transfer_button.tooltip_text = reason if not reason.is_empty() else "手动勾选旧地图墙，归入当前物件的局部碰撞；确认前可预览。"


func _open_geometry_transfer() -> void:
	var reason := _transfer_target_error()
	if not reason.is_empty():
		_status.text = reason
		return
	if not is_instance_valid(_transfer_dialog):
		_transfer_dialog = GeometryTransferDialog.new()
		_transfer_dialog.applied.connect(_on_geometry_transferred)
		add_child(_transfer_dialog)
	var index: int = canvas.sel_index
	var actor_id := str(model.actor_field(index, "id", ""))
	_transfer_dialog.configure(model, index,
		_transfer_target_error.bind(model, model.map_id, index, actor_id))
	if is_inside_tree():
		_transfer_dialog.open_for_viewport()


func _on_geometry_transferred(index: int) -> void:
	var selection: Array[int] = [index]
	canvas.select_actors(selection)
	_on_edited()
	if canvas.show_walk:
		canvas.recompute_walk()
	_panel_kind = -1
	_refresh_selection()
	_status.text = "已归入所选地图墙；可撤销，尚未保存到 JSON。"


func _on_edited() -> void:
	model.record_history()
	_prune_actor_editor_state()
	canvas.invalidate_def()      # 数据改了，脚底框/可走格那边的 MapDef 要重建
	_refresh_dirty()
	_refresh_objects()
	if canvas.sel_kind == Kind.ACTOR and is_instance_valid(_base_row) and _base_row.visible:
		_syncing = true
		_base_spin.set_value_no_signal(model.actor_cover_y(canvas.sel_index))
		_syncing = false
		if is_instance_valid(_object_inspector):
			_object_inspector._refresh_baseline()
	canvas.queue_redraw()


func _on_canvas_edited() -> void:
	_on_edited()
	if canvas.sel_kind == Kind.ACTOR and (canvas.tool == Canvas.Tool.COLLISION \
			or canvas._has_collision_selection()):
		_build_actor_panel()
	_refresh_selection()


# ---------------------------------------------------------------- 物件属性面板
#
# 这块只在**选中物件**时出现。能改：id / 名字 / 贴图 / 三个常用开关（装饰、
# 遮挡、恒在上层）、以及互动内容（单句旁白 / 多句对话）。
#
# **不编剧情。** 挂了 `event`（剧情文件）或 `actions`（多动作菜单）的物件，
# 这里只显示「在哪个文件里」，不动它 —— 剧情正文归 `data/events/`。
#
# **认不得的字段一律原样留着**：所有写入都是「就地改那个字典里的某一个键」
# （`set_actor_field` / `_set_talk`），不重建字典。对话行支持的
# `size_delta` / `shake` 编辑器不显示，但也不会被抹掉。

func _on_add_actor() -> void:
	var index := model.add_actor()
	canvas.sel_kind = Kind.ACTOR
	canvas.sel_index = index
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_status.text = "加了一件物件（先落在地图正中）。拖到位置上，再填下面的名字、贴图、互动内容。"


## 只在「换了选中项」时重建面板 —— 每敲一个字都重建会把光标弄丢。
func _sync_actor_panel() -> void:
	var kind: int = canvas.sel_kind
	if kind != Kind.ACTOR and kind != Kind.OVERLAY:
		_panel_scroll.visible = false
		_panel_kind = -1
		_panel_index = -1
		return
	var is_locked := _selection_has_locked_actor()
	var id_readonly: bool = kind == Kind.ACTOR and canvas.actor_is_hidden(canvas.sel_index)
	if _panel_kind == kind and _panel_index == canvas.sel_index \
			and _panel_locked == is_locked and _panel_id_readonly == id_readonly:
		_panel_scroll.visible = true
		return
	if kind == Kind.OVERLAY:
		_build_overlay_panel()
	else:
		_build_actor_panel()


## 前景层只有一条数据（路径），能做的就三件：看它是谁、换一张、清掉。
## **它整张拉伸到地图大小**，所以没有位置/尺寸可调。
func _build_overlay_panel() -> void:
	_panel_kind = Kind.OVERLAY
	_panel_index = 0
	for child in _actor_panel.get_children():
		_actor_panel.remove_child(child)
		child.queue_free()
	_panel_scroll.visible = true

	_actor_panel.add_child(_text("前景层（恒在角色之上，整张拉伸到地图大小）"))
	var row := HBoxContainer.new()
	row.add_child(_text("图片"))
	var path_line := LineEdit.new()
	path_line.text = model.overlay_path()
	path_line.custom_minimum_size = Vector2(380, 0)
	path_line.text_changed.connect(func(t: String) -> void:
		model.set_overlay_path(t)
		canvas.set_overlay_texture(t)
		_on_edited())
	row.add_child(path_line)
	var swap := Button.new()
	swap.text = "导入图像…"
	swap.tooltip_text = "挑一张 PNG 当作这张图的前景层：拷进 art/map/，命名成 <地图名>_wall"
	swap.pressed.connect(_open_overlay_import_dialog)
	row.add_child(swap)
	var clear := Button.new()
	clear.text = "清除"
	clear.tooltip_text = "把前景层去掉（这条数据清空，图还在 art/map 里）"
	clear.pressed.connect(func() -> void:
		model.clear_overlay()
		canvas.set_overlay_texture("")
		_on_edited()
		canvas.sel_kind = -1
		_refresh_selection()
		_status.text = "前景层清掉了（那条数据没了，图还在 art/map 里）")
	row.add_child(clear)
	_actor_panel.add_child(row)
	_actor_panel.add_child(_text("提示：想看它盖住了什么，把「前景层」不透明度滑条拉淡。"))

	if model.overlay_path() == "":
		_actor_panel.add_child(_text("这张图现在没有前景层。点「导入图像…」加一张。"))


func _build_actor_panel() -> void:
	_panel_kind = Kind.ACTOR
	_panel_index = canvas.sel_index
	_panel_locked = _selection_has_locked_actor()
	_panel_id_readonly = canvas.actor_is_hidden(_panel_index)
	for child in _actor_panel.get_children():
		_actor_panel.remove_child(child)
		child.queue_free()
	_panel_scroll.visible = true

	var title := _text("物件属性（改完请保存到 JSON）")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_actor_panel.add_child(title)

	var row1 := HFlowContainer.new()
	row1.add_child(_text("id"))
	row1.add_child(_field("id", 110.0))
	row1.add_child(_text("  名字"))
	row1.add_child(_field("label", 130.0))
	_actor_panel.add_child(row1)

	var row2 := HFlowContainer.new()
	row2.add_child(_text("贴图"))
	var sprite_line := _field("sprite", 220.0)
	row2.add_child(sprite_line)
	var picker := OptionButton.new()
	picker.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	picker.add_item("（从 art/props 选）")
	picker.fit_to_longest_item = false
	picker.custom_minimum_size.x = 220
	var props := _list_png_files("res://art/props")
	for path in props:
		picker.add_item(path.get_file())
	picker.item_selected.connect(func(i: int) -> void:
		if i <= 0:
			return
		var path: String = props[i - 1]
		if _set_actor_texture(_panel_index, path):
			sprite_line.text = path)
	row2.add_child(picker)
	var import_texture := Button.new()
	import_texture.text = "导入贴图…"
	import_texture.pressed.connect(_open_actor_texture_import)
	row2.add_child(import_texture)
	_actor_panel.add_child(row2)

	var row3 := HFlowContainer.new()
	row3.add_child(_text("属性："))
	row3.add_child(_bool_field("decor", "只装饰（不参与交互）"))
	row3.add_child(_bool_field("cover", "会挡人（按站位分前后）"))
	row3.add_child(_bool_field("over", "永远画在角色之上"))
	_actor_panel.add_child(row3)
	var geometry := ObjectInspector.new()
	geometry.configure(model, _panel_index)
	geometry.tool_requested.connect(_on_tool)
	geometry.edited.connect(_on_edited)
	geometry.rebuild_requested.connect(_rebuild_object_inspector)
	geometry.set_active_tool(canvas.tool)
	_object_inspector = geometry
	if is_instance_valid(_base_row) and _base_row.get_parent() == null:
		_base_row.free()
	_base_row = geometry.baseline_row
	_base_spin = geometry.baseline_spin
	_base_auto_button = geometry.baseline_auto
	_actor_panel.add_child(geometry)
	var visuals := VisualInspector.new()
	visuals.configure(model, _panel_index, canvas.selected_actors())
	visuals.edited.connect(_on_edited)
	visuals.rebuild_requested.connect(_rebuild_object_inspector)
	_actor_panel.add_child(visuals)
	var template := TemplateInspector.new()
	template.configure(model, _library, _panel_index)
	template.set_selection(canvas.selected_actors())
	template.edited.connect(_on_edited)
	template.rebuild_requested.connect(_rebuild_object_inspector)
	_actor_panel.add_child(template)
	_transfer_button = Button.new()
	_transfer_button.text = "归入地图墙…"
	_transfer_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_transfer_button.pressed.connect(_open_geometry_transfer)
	_actor_panel.add_child(_transfer_button)
	_refresh_transfer_button()

	_build_interaction_section()
	_actor_panel.add_child(TriggerEditor.create_actor_event_selector(model, _panel_index, func() -> void:
		_on_edited()
		_rebuild_object_inspector()))
	_actor_panel.add_child(_switch_row())
	for child: Node in _actor_panel.get_children():
		if child is Label:
			(child as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _panel_locked:
		_set_controls_readonly(_actor_panel)


func _set_controls_readonly(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).disabled = true
	elif node is LineEdit:
		(node as LineEdit).editable = false
	elif node is TextEdit:
		(node as TextEdit).editable = false
	elif node is SpinBox:
		(node as SpinBox).editable = false
	for child: Node in node.get_children():
		_set_controls_readonly(child)


func _build_interaction_section() -> void:
	var form: String = model.actor_form(_panel_index)
	var names := {
		"line": "单句旁白", "talk": "多句对话", "event": "挂了剧情事件",
		"actions": "多动作菜单", "decor": "纯装饰（不交互）", "none": "还没写",
	}
	var head := HBoxContainer.new()
	head.add_child(_text("互动内容："))
	head.add_child(_text(str(names.get(form, form))))
	_actor_panel.add_child(head)

	match form:
		"line":
			_actor_panel.add_child(_text_area("line", 220.0, 44.0))
		"talk":
			_build_talk_list()
		"event":
			_actor_panel.add_child(_text("  → data/events/%s.json（正文在那个文件里，编辑器不编剧情）"
				% str(model.actor_field(_panel_index, "event", ""))))
		"actions":
			_actor_panel.add_child(_text("  → 写在 data/maps 里的多动作菜单，编辑器暂不编辑"))
		_:
			_actor_panel.add_child(_text("  想让它能说话，就点右边的按钮换成旁白或对话。"))


func _switch_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	var to_line := Button.new()
	to_line.text = "换成单句旁白"
	to_line.pressed.connect(func() -> void: _switch_form("line"))
	row.add_child(to_line)
	var to_talk := Button.new()
	to_talk.text = "换成多句对话"
	to_talk.pressed.connect(func() -> void: _switch_form("talk"))
	row.add_child(to_talk)
	var note := _text("原内容会搬过去；挂剧情事件的物件保留原内容。")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 220
	row.add_child(note)
	return row


func _switch_form(form: String) -> void:
	var d := model.actor_dict(_panel_index)
	if d.has("event") or d.has("actions"):
		_status.text = "这件挂了剧情事件或动作菜单，编辑器不动它 —— 想改成对话，先去那个文件里把它摘掉"
		return
	if form == "line":
		model.erase_actor_field(_panel_index, "talk")
		model.set_actor_field(_panel_index, "line", str(d.get("line", "")))
	else:
		var old := str(d.get("line", ""))
		model.erase_actor_field(_panel_index, "line")
		model.set_actor_field(_panel_index, "talk",
			[{"text": old}] if old != "" else [{"text": ""}])
	_on_edited()
	_build_actor_panel()
	canvas.queue_redraw()
	_status.text = "换成「%s」了（原本那种写法的内容已清掉）" % ("单句旁白" if form == "line" else "多句对话")


func _build_talk_list() -> void:
	var talk := model.actor_talk(_panel_index)
	var portraits := model.portrait_names()
	for i in talk.size():
		var line: Dictionary = talk[i] if talk[i] is Dictionary else {}
		var row := HFlowContainer.new()

		var who := LineEdit.new()
		who.text = str(line.get("speaker", ""))
		who.placeholder_text = "说话人（空=旁白）"
		who.custom_minimum_size = Vector2(96, 0)
		who.text_changed.connect(func(t: String) -> void: _set_talk(i, "speaker", t))
		row.add_child(who)

		var side := OptionButton.new()
		side.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		side.add_item("左")
		side.add_item("右")
		side.selected = 1 if str(line.get("side", "left")) == "right" else 0
		side.item_selected.connect(func(k: int) -> void:
			_set_talk(i, "side", "right" if k == 1 else "left"))
		row.add_child(side)

		var port := OptionButton.new()
		port.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		port.add_item("（无立绘）")
		for name in portraits:
			port.add_item(name)
		var cur := str(line.get("portrait", ""))
		for k in portraits.size():
			if portraits[k] == cur:
				port.selected = k + 1
		port.item_selected.connect(func(k: int) -> void:
			_set_talk(i, "portrait", "" if k == 0 else portraits[k - 1]))
		row.add_child(port)

		var body := TextEdit.new()
		body.text = str(line.get("text", ""))
		body.custom_minimum_size = Vector2(220, 38)
		body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		body.text_changed.connect(func() -> void: _set_talk(i, "text", body.text))
		row.add_child(body)

		row.add_child(_line_button("↑", func() -> void: _move_talk(i, i - 1)))
		row.add_child(_line_button("↓", func() -> void: _move_talk(i, i + 1)))
		row.add_child(_line_button("✕", func() -> void: _remove_talk(i)))
		_actor_panel.add_child(row)

	var add := Button.new()
	add.text = "加一句"
	add.pressed.connect(func() -> void:
		model.actor_talk(_panel_index).append({"text": ""})
		model.mark_dirty()
		_on_edited()
		_build_actor_panel()
		canvas.queue_redraw())
	_actor_panel.add_child(add)


## 把内容塞进一个定高的滚动区 —— 弹窗内容再长也不会把按钮顶出屏幕。
func _scrolled(content: Control, view: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = view
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _line_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(30, 0)
	b.pressed.connect(action)
	return b


func _set_talk(index: int, key: String, value: Variant) -> void:
	var talk := model.actor_talk(_panel_index)
	if index < 0 or index >= talk.size():
		return
	if not (talk[index] is Dictionary):
		talk[index] = {}
	(talk[index] as Dictionary)[key] = value
	model.mark_dirty()
	_on_edited()
	canvas.queue_redraw()


func _remove_talk(index: int) -> void:
	var talk := model.actor_talk(_panel_index)
	if index < 0 or index >= talk.size():
		return
	talk.remove_at(index)
	model.mark_dirty()
	_on_edited()
	_build_actor_panel()
	canvas.queue_redraw()


func _move_talk(from_index: int, to_index: int) -> void:
	var talk := model.actor_talk(_panel_index)
	if from_index < 0 or from_index >= talk.size():
		return
	if to_index < 0 or to_index >= talk.size():
		return
	var item: Variant = talk[from_index]
	talk.remove_at(from_index)
	talk.insert(to_index, item)
	model.mark_dirty()
	_on_edited()
	_build_actor_panel()
	canvas.queue_redraw()


func _field(key: String, width: float) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = str(model.actor_field(_panel_index, key, ""))
	edit.custom_minimum_size = Vector2(width, 0)
	if key == "sprite":
		_sprite_path_edit = edit
		var apply_texture := func() -> void:
			if edit.text != str(model.actor_field(_panel_index, "sprite", "")):
				_set_actor_texture(_panel_index, edit.text.strip_edges())
		edit.text_submitted.connect(func(_text: String) -> void: apply_texture.call())
		edit.tooltip_text = "输入项目内贴图路径后按 Enter；贴图适配当前框，位置和宽高保持不变。"
		return edit
	if key == "id" and canvas.actor_is_hidden(_panel_index):
		edit.editable = false
		edit.tooltip_text = "请先显示并解锁物件，再修改 ID；隐藏/锁定状态按地图与 ID 保存。"
	edit.text_changed.connect(func(t: String) -> void:
		if not _allow_selection_edit():
			return
		if key == "id" and canvas.actor_is_hidden(_panel_index):
			return
		model.set_actor_field(_panel_index, key, t)
		_on_edited())
	return edit


func _set_actor_texture(index: int, path: String, keep_rect := true) -> bool:
	if not _allow_selection_edit():
		return false
	_texture_request_serial += 1
	if path != "" and not FileAccess.file_exists(path):
		_status.text = "贴图文件不存在：%s。请刷新素材列表并重新选择。" % path
		return false
	if path != "" and _load_imported_asset(path) == null:
		_status.text = "贴图 PNG 尚未完成 Godot 导入，正在重新扫描；完成后会尝试应用。"
		_set_actor_texture_after_scan(index, path, model, model.map_id,
			str(model.actor_field(index, "id", "")), keep_rect, _texture_request_serial)
		return false
	return _apply_actor_texture(index, path, keep_rect)


func _apply_actor_texture(index: int, path: String, keep_rect := true) -> bool:
	if not _allow_selection_edit():
		return false
	if not model.assign_actor_sprite(index, path, keep_rect):
		_status.text = "贴图无法读取：%s。请确认文件是有效 PNG，且项目目录可写。" % path
		return false
	if is_instance_valid(_sprite_path_edit) and _panel_index == index:
		_sprite_path_edit.text = path
	_on_edited()
	_refresh_selection()
	_status.text = "贴图已更新，尺寸保持不变；到「视觉部件与变换」调整大小。" if keep_rect \
		else "物件已按背景像素比例恢复原图尺寸。"
	return true


func _set_actor_texture_after_scan(index: int, path: String, target_model, target_map: String,
		target_id: String, keep_rect := true, request_serial := -1) -> void:
	var texture := await _wait_for_imported_asset(path)
	if not is_inside_tree() or model != target_model or model.map_id != target_map \
			or (request_serial >= 0 and request_serial != _texture_request_serial) \
			or canvas.sel_kind != Kind.ACTOR or canvas.sel_index != index \
			or str(model.actor_field(index, "id", "")) != target_id:
		return
	if texture == null:
		_status.text = "贴图尚未就绪，可能仍在导入：%s。地图数据未修改；请稍后刷新素材列表，使用已有文件。仍无法载入时检查 Godot Import/Output。" % path
		return
	_apply_actor_texture(index, path, keep_rect)


func _open_actor_texture_import() -> void:
	if not _allow_selection_edit():
		return
	var target_model = model
	var target_map: String = model.map_id
	var target_index := _panel_index
	var target_id := str(model.actor_field(target_index, "id", ""))
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.add_filter("*.png", "PNG 图片")
	dialog.title = "为当前物件导入贴图（适配当前范围）"
	dialog.file_selected.connect(func(source: String) -> void:
		_import_actor_texture(source, target_model, target_map, target_index, target_id)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(760, 500))


func _import_actor_texture(source: String, target_model, target_map: String,
		target_index: int, target_id: String) -> void:
	if model != target_model or model.map_id != target_map or _panel_index != target_index \
			or canvas.sel_kind != Kind.ACTOR or canvas.sel_index != target_index \
			or str(model.actor_field(target_index, "id", "")) != target_id or not _allow_selection_edit():
		return
	_texture_request_serial += 1
	var request_serial := _texture_request_serial
	var image := Image.load_from_file(source)
	if image == null or image.is_empty():
		_status.text = "导入失败：所选文件无法解码为 PNG。"
		return
	var imported: String = target_model.import_image(source)
	if imported == "":
		_status.text = "导入失败：无法读取源文件或写入 art/props/。请确认 PNG 有效且项目目录可写。"
		return
	_status.text = "PNG 已复制，等待 Godot 完成纹理导入……"
	var texture := await _wait_for_imported_asset(imported)
	if not is_inside_tree() or model != target_model or model.map_id != target_map \
			or request_serial != _texture_request_serial or canvas.sel_kind != Kind.ACTOR \
			or canvas.sel_index != target_index or _panel_index != target_index \
			or str(model.actor_field(target_index, "id", "")) != target_id:
		return
	if texture == null:
		_status.text = "PNG 已复制到 %s，纹理尚未就绪，可能仍在导入；物件未修改。请稍后刷新素材列表，使用已有文件。仍无法载入时检查 Godot Import/Output。" % imported
		return
	_apply_actor_texture(target_index, imported)


func _bool_field(key: String, label: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = label
	box.button_pressed = bool(model.actor_field(_panel_index, key, false))
	box.toggled.connect(func(on: bool) -> void:
		# 勾「只装饰」= 不参与交互 → 挂着的剧情就再也触发不到。
		# 这条**数据合法、check_data 查不出来**，所以在这儿拦一下。
		if key == "decor" and on and model.actor_has_story(_panel_index):
			box.set_pressed_no_signal(false)
			_confirm_decor(_panel_index, box)
			return
		model.set_actor_field(_panel_index, key, on)
		_on_edited()
		canvas.queue_redraw())
	return box


## 勾「只装饰」会把剧情入口堵死 —— 先把挂着的东西列出来问一句。
func _confirm_decor(index: int, box: CheckBox) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "勾「只装饰」？它就不参与交互了"
	dialog.ok_button_text = "知道，勾上"
	var text := "勾上之后玩家没法再跟它互动，下面这些也就触发不到了：\n\n"
	for line in model.actor_references(index):
		text += "· " + line + "\n"
	var label := _text(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(_scrolled(label, Vector2(420, 180)))
	dialog.confirmed.connect(func() -> void:
		model.set_actor_field(index, "decor", true)
		if is_instance_valid(box):
			box.set_pressed_no_signal(true)
		_on_edited()
		canvas.queue_redraw()
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(470, 240))


## 长文本用多行框 —— 对话一句话可能挺长，单行框看半句很难受。
func _text_area(key: String, width: float, height: float) -> TextEdit:
	var area := TextEdit.new()
	area.text = str(model.actor_field(_panel_index, key, ""))
	area.custom_minimum_size = Vector2(width, height)
	area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	area.text_changed.connect(func() -> void:
		model.set_actor_field(_panel_index, key, area.text)
		_on_edited())
	return area


# ---------------------------------------------------------------- 导入图片做遮挡片

## 从文件系统挑一张图 → 拷进 `art/props/` → 新建一件**遮挡物件**。
##
## 为什么默认勾 `cover`：这个入口就是给「从美术给的图里挑一块做遮挡片」用的
## （集市、学校那批白框遮挡片就是这么做的）。位置和基线随后在画布上调。
func _open_import_dialog() -> void:
	if model.map_id == "":
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.add_filter("*.png", "PNG 图片")
	fd.title = "挑一张图（会拷进 art/props/，并新建一件遮挡物件）"
	fd.file_selected.connect(func(path: String) -> void:
		_import_and_create(path)
		fd.queue_free())
	fd.canceled.connect(func() -> void: fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(760, 500))


## 前景层导入：拷进 `art/map/`，按项目习惯命名 `<地图名>_wall`。
##
## 不用管图的尺寸 —— 游戏里它会被**拉伸到整张地图**（`map_view._add_overlay`）。
func _open_overlay_import_dialog() -> void:
	if model.map_id == "":
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.add_filter("*.png", "PNG 图片")
	fd.title = "挑一张图当前景层（会拷进 art/map/）"
	fd.file_selected.connect(func(path: String) -> void:
		_import_overlay(path)
		fd.queue_free())
	fd.canceled.connect(func() -> void: fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(760, 500))


func _import_overlay(source_path: String) -> void:
	var target_model = model
	var target_map: String = model.map_id
	_texture_request_serial += 1
	var request_serial := _texture_request_serial
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty():
		_status.text = "导入失败：图片无法解码，请选择完整的 PNG 文件。"
		return
	var res_path := target_model.import_image(source_path, "res://art/map", target_map + "_wall")
	if res_path == "":
		_status.text = "导入失败：无法读取 PNG 或写入 art/map/。请确认文件有效且项目目录可写。"
		return
	_status.text = "图片已复制，等待 Godot 完成纹理导入……"
	var texture := await _wait_for_imported_asset(res_path)
	if not is_inside_tree() or model != target_model or model.map_id != target_map \
			or request_serial != _texture_request_serial:
		return
	if texture == null:
		_status.text = "PNG 已复制到 %s，纹理尚未就绪，可能仍在导入；前景层未修改。请稍后刷新素材列表，使用已有文件。仍无法载入时检查 Godot Import/Output。" % res_path
		return
	model.set_overlay_path(res_path)
	canvas.set_overlay_texture(res_path)
	canvas.clear_texture_cache()
	canvas.sel_kind = Kind.OVERLAY
	canvas.sel_index = 0
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_status.text = "前景层换成 %s（整张拉伸到地图大小，图的尺寸不用管）" % res_path


func _import_and_create(source_path: String) -> void:
	var target_model = model
	var target_map: String = model.map_id
	_texture_request_serial += 1
	var request_serial := _texture_request_serial
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty():
		_status.text = "导入失败：图片无法解码，请选择完整的 PNG 文件。"
		return
	var res_path := target_model.import_image(source_path, "res://art/props")
	if res_path == "":
		_status.text = "导入失败：无法读取 PNG 或写入 art/props/。请确认文件有效且项目目录可写。"
		return
	_status.text = "PNG 已复制，等待 Godot 完成纹理导入……"
	var texture := await _wait_for_imported_asset(res_path)
	if not is_inside_tree() or model != target_model or model.map_id != target_map \
			or request_serial != _texture_request_serial:
		return
	if texture == null:
		_status.text = "PNG 已复制到 %s，纹理尚未就绪，可能仍在导入；尚未创建物件。请稍后刷新素材列表，使用已有文件。仍无法载入时检查 Godot Import/Output。" % res_path
		return
	var index := target_model.add_actor_with_sprite(res_path, true)
	if index < 0:
		_status.text = "纹理已导入，但未能创建物件；请检查当前地图尺寸与背景图。素材仍保留在 art/props/。"
		return
	var selection: Array[int] = [index]
	canvas.select_actors(selection)
	canvas.clear_texture_cache()
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_on_tool(Canvas.Tool.SELECT)
	_status.text = "已导入 %s；贴图尺寸可在「视觉部件与变换」中调整。" % res_path
