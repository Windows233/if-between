## 地图编辑器主界面：物件列表、中央画布、右侧检查器与地图工具。
##
## 数值框和画布是**双向同步**的：拖了矩形，数值跟着变；敲了数字，画面跟着动。
## 同步时用一个 `_syncing` 旗子挡住回写，免得程序设值又被当成玩家改动（会把
## 「未保存」的星号无缘无故点亮）。
@tool
extends VBoxContainer

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const Kind := Model.Kind
const ObjectInspector := preload("res://addons/if_map_editor/map_object_inspector.gd")
const ObjectLibrary := preload("res://addons/if_map_editor/map_object_library.gd")
const ObjectPreview := preload("res://addons/if_map_editor/map_object_preview.gd")
const AssetList := preload("res://addons/if_map_editor/map_asset_list.gd")

const EDITOR_STATE_PATH := "user://if_map_editor_scene_state.cfg"

enum LayoutAction { ALIGN_LEFT, ALIGN_CENTER_X, ALIGN_RIGHT, ALIGN_TOP, ALIGN_CENTER_Y, ALIGN_BOTTOM,
	DISTRIBUTE_HORIZONTAL, DISTRIBUTE_VERTICAL }

var model = Model.new()
var canvas: Control = null

var _map_picker: OptionButton
var _save_button: Button
var _drop_draft_button: Button
var _tool_buttons: Array[Button] = []
var _sel_label: Label
var _spins: Array[SpinBox] = []
var _base_row: HBoxContainer
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
var _object_list: ItemList
var _hidden_actor_ids: Dictionary = {}
var _locked_actor_ids: Dictionary = {}
var _editor_state_path := EDITOR_STATE_PATH
var _hide_selected_button: Button
var _lock_selected_button: Button
var _show_all_button: Button
var _asset_tabs: TabContainer
var _asset_filter: LineEdit
var _asset_list: ItemList
var _asset_empty: Label
var _group_button: Button
var _ungroup_button: Button
var _template_picker: OptionButton
var _layout_popup: PopupMenu
var _library = ObjectLibrary.new()
var _body_split: HSplitContainer
var _workspace_split: HSplitContainer


func _ready() -> void:
	_build()
	refresh_map_list(true)
	await get_tree().process_frame
	_set_initial_panel_layout()


# ---------------------------------------------------------------- 界面

func _build() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_row_title())

	var tools := HFlowContainer.new()
	tools.add_child(_text("工具："))
	for item in [["选择 / 拖动 / 改尺寸", Canvas.Tool.SELECT],
			["画墙", Canvas.Tool.WALL],
			["画传送区", Canvas.Tool.PORTAL],
			["拉遮挡基线", Canvas.Tool.BASELINE],
			["画物件碰撞", Canvas.Tool.COLLISION]]:
		var b := Button.new()
		b.text = str(item[0])
		b.toggle_mode = true
		b.pressed.connect(_on_tool.bind(int(item[1])))
		tools.add_child(b)
		_tool_buttons.append(b)
	_tool_buttons[0].button_pressed = true
	add_child(tools)

	add_child(_row_layers())

	add_child(_row_selection())
	add_child(_object_actions())
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
	scene_page.add_child(_text("场景物件（Ctrl / Shift 多选）"))
	_object_list = ItemList.new()
	_object_list.select_mode = ItemList.SELECT_MULTI
	_object_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_object_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_object_list.multi_selected.connect(_objects_selected)
	scene_page.add_child(_object_list)
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
	refresh_assets.pressed.connect(_refresh_assets)
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
	canvas = Canvas.new()
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
	_refresh_assets()


func _set_initial_panel_layout() -> void:
	_body_split.split_offset = 220
	var inspector_width := clampi(roundi(_workspace_split.size.x * 0.28), 300, 380)
	_workspace_split.split_offset = maxi(300, int(_workspace_split.size.x) - inspector_width)


func _object_actions() -> HFlowContainer:
	var row := HFlowContainer.new()
	for action: Array in [["撤销", "undo"], ["重做", "redo"], ["复制物件", "copy"],
			["粘贴", "paste"], ["复制并偏移", "duplicate"], ["存为物件模板…", "template"], ["当前布局试走", "preview"]]:
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


func _refresh_assets() -> void:
	if _asset_list == null:
		return
	_asset_list.clear()
	var query := _asset_filter.text.strip_edges().to_lower() if _asset_filter != null else ""
	for path: String in model.prop_files():
		var filename := path.get_file().get_basename()
		if not query.is_empty() and not filename.to_lower().contains(query):
			continue
		var texture := load(path) as Texture2D
		_asset_list.add_item(filename, texture)
		var index := _asset_list.item_count - 1
		_asset_list.set_item_metadata(index, path)
		_asset_list.set_item_tooltip(index, path)
	_asset_list.visible = _asset_list.item_count > 0
	_asset_empty.visible = _asset_list.item_count == 0
	_asset_empty.text = "没有匹配的素材" if not query.is_empty() else "素材目录为空"


func _refresh_objects() -> void:
	if _object_list == null:
		return
	_object_list.clear()
	for index: int in model.count(Kind.ACTOR):
		var group_name := model.group_name_for_actor(index)
		var label := model.label_of(Kind.ACTOR, index)
		if not group_name.is_empty():
			label = "%s / %s" % [group_name, label]
		var actor_id := str(model.actor_field(index, "id", ""))
		var state_tags: Array[String] = []
		if _hidden_actor_ids.has(actor_id):
			state_tags.append("隐藏")
		if _locked_actor_ids.has(actor_id):
			state_tags.append("锁定")
		if not state_tags.is_empty():
			label += "  [%s]" % " / ".join(state_tags)
		_object_list.add_item("%s  [%s]" % [label, actor_id])
		if canvas.sel_kind == Kind.ACTOR and canvas.selected_actors().has(index):
			_object_list.select(index, false)
	_refresh_object_state_buttons()
	_refresh_group_buttons()


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
	if not _selection_has_locked_actor():
		return true
	_status.text = "选区包含锁定物件，请先在场景列表中解锁。"
	return false


func _objects_selected(_index: int, _selected: bool) -> void:
	var selected: Array[int] = []
	for index: int in _object_list.get_selected_items():
		selected.append(index)
	canvas.select_actors(selected)
	_refresh_selection()


func _selected_actor_indices() -> Array[int]:
	var selected: Array[int] = []
	for index: int in _object_list.get_selected_items():
		selected.append(index)
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
		var preview := ObjectPreview.new()
		add_child(preview)
		preview.configure(model.data.duplicate(true))
		preview.popup_centered()
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


func _row_title() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_text("地图："))
	_map_picker = OptionButton.new()
	_map_picker.custom_minimum_size = Vector2(200, 0)
	_map_picker.item_selected.connect(_on_map_selected)
	row.add_child(_map_picker)
	var reload := Button.new()
	reload.text = "重新载入（丢弃改动）"
	reload.tooltip_text = "从磁盘重读这张图，丢掉这次没保存的改动"
	reload.pressed.connect(_on_reload)
	row.add_child(reload)
	var fit := Button.new()
	fit.text = "适应画布"
	fit.tooltip_text = "把整张地图缩放并居中到当前画布区域"
	fit.pressed.connect(func() -> void: canvas.fit_to_view())
	row.add_child(fit)
	_drop_draft_button = Button.new()
	_drop_draft_button.text = "丢弃草稿"
	_drop_draft_button.tooltip_text = "把这张图的未保存草稿删掉（改动就此消失）"
	_drop_draft_button.pressed.connect(_on_drop_draft)
	row.add_child(_drop_draft_button)
	_save_button = Button.new()
	_save_button.text = "保存到 JSON"
	_save_button.pressed.connect(_on_save)
	row.add_child(_save_button)
	var backup_history := Button.new()
	backup_history.text = "备份历史…"
	backup_history.tooltip_text = "载入一份旧地图快照到编辑器；确认后仍需手动保存才会覆盖地图。"
	backup_history.pressed.connect(_open_backup_dialog)
	row.add_child(backup_history)
	var copy := Button.new()
	copy.text = "复制布局到…"
	copy.tooltip_text = "把这张图的碰撞箱/传送区/物件覆盖到另一张图上（白天版↔夜间版）"
	copy.pressed.connect(_open_copy_dialog)
	row.add_child(copy)
	return row


func _row_layers() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_text("显示："))
	for item in [["背景", "show_bg"], ["前景层", "show_overlay"], ["墙", "show_walls"],
			["传送区", "show_portals"], ["物件", "show_actors"], ["出生点", "show_spawns"],
			["可走格", "show_walk"], ["脚底框（跟鼠标）", "show_foot"]]:
		var cb := CheckBox.new()
		cb.text = str(item[0])
		cb.button_pressed = true
		cb.tooltip_text = "取消勾选：这一类既不显示，也点不中（底下压着的东西就能选中了）"
		cb.toggled.connect(_on_layer.bind(str(item[1])))
		row.add_child(cb)
	var refresh := Button.new()
	refresh.text = "重算可走格"
	refresh.tooltip_text = "改完墙之后点它，重新跑一遍游戏那份 WalkGrid"
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


func _row_selection() -> HBoxContainer:
	var row := HBoxContainer.new()
	_sel_label = _text("未选中")
	_sel_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(_sel_label)
	for name in ["x", "y", "宽", "高"]:
		row.add_child(_text(name))
		var spin := SpinBox.new()
		spin.min_value = -4096
		spin.max_value = 4096
		spin.step = 1
		spin.custom_minimum_size = Vector2(78, 0)
		spin.value_changed.connect(_on_spin_changed)
		row.add_child(spin)
		_spins.append(spin)

	_base_row = HBoxContainer.new()
	_base_row.add_child(_text("遮挡基线 Y"))
	_base_spin = SpinBox.new()
	_base_spin.min_value = -4096
	_base_spin.max_value = 4096
	_base_spin.step = 1
	_base_spin.custom_minimum_size = Vector2(78, 0)
	_base_spin.value_changed.connect(_on_base_spin)
	_base_row.add_child(_base_spin)
	_base_auto_button = Button.new()
	_base_auto_button.text = "恢复自动"
	_base_auto_button.pressed.connect(_on_base_auto)
	_base_row.add_child(_base_auto_button)
	_base_row.visible = false
	row.add_child(_base_row)

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
	if not problems.is_empty():
		_status.text = "保存前请修正：\n" + "\n".join(problems)
		return
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
	canvas.tool = which
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = i == which
	match which:
		Canvas.Tool.SELECT:
			_status.text = "选择：点中矩形拖走；八个白点改尺寸；Delete 删掉；数值框可精确改。"
		Canvas.Tool.WALL:
			_status.text = "画墙：在图上按住左键拖出一个框，松手就加进 walls。"
		Canvas.Tool.PORTAL:
			_status.text = "画传送区：同上，落进 portals（默认 locked，不通往任何地方）。"
		Canvas.Tool.BASELINE:
			_status.text = "拉基线：点一件遮挡物（身上有黄线），上下拖，松手写进它的 cover_y。"
		Canvas.Tool.COLLISION:
			_status.text = "左侧先选物件，再拖出局部碰撞箱；自动排序取参考碰撞箱上边缘。旧地图墙不自动删除。"


func _on_layer(on: bool, prop: String) -> void:
	canvas.set_layer_visible(prop, on)
	if prop == "show_walk":
		if on:
			_status.text = "正在算可走格……（用的是游戏同一份 WalkGrid）"
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
		refs = model.actor_references(canvas.sel_index)
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
	dialog.confirmed.connect(func() -> void:
		_do_delete(what, was)
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(470, 220))


func _do_delete(what: String, was: String) -> void:
	if not _allow_selection_edit():
		return
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
	var r: Rect2 = canvas.model.rect_of(canvas.sel_kind, canvas.sel_index)
	var next := Rect2(
		Vector2(_spins[0].value, _spins[1].value),
		Vector2(maxf(1.0, _spins[2].value), maxf(1.0, _spins[3].value)))
	if next != r:
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
	_refresh_selection()


func _refresh_selection() -> void:
	_refresh_objects()
	var kind: int = canvas.sel_kind
	var index: int = canvas.sel_index
	_syncing = true
	if kind < 0:
		_sel_label.text = "未选中"
		for spin in _spins:
			spin.editable = false
		_base_row.visible = false
	else:
		var names := ["墙", "传送区", "物件", "出生点", "前景层"]
		var r: Rect2 = model.rect_of(kind, index)
		_sel_label.text = "%s #%d %s" % [names[kind], index, model.label_of(kind, index)]
		_spins[0].value = r.position.x
		_spins[1].value = r.position.y
		_spins[2].value = r.size.x
		_spins[3].value = r.size.y
		var is_spawn: bool = kind == Kind.SPAWN
		var is_overlay: bool = kind == Kind.OVERLAY
		var is_locked: bool = _selection_has_locked_actor()
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
		var is_cover: bool = kind == Kind.ACTOR and model.is_cover_actor(index)
		_base_row.visible = is_cover
		if is_cover:
			_base_spin.editable = not is_locked
			_base_auto_button.disabled = is_locked
			_base_spin.value = model.actor_cover_y(index)
			_base_spin.tooltip_text = "独立物件：碰撞箱上边缘；旧物件：贴图底边。橙线表示手动调整。"
	_syncing = false
	_sync_actor_panel()


func _on_edited() -> void:
	model.record_history()
	_prune_actor_editor_state()
	canvas.invalidate_def()      # 数据改了，脚底框/可走格那边的 MapDef 要重建
	_refresh_dirty()
	_refresh_objects()
	if canvas.sel_kind == Kind.ACTOR and _base_row.visible:
		_syncing = true
		_base_spin.value = model.actor_cover_y(canvas.sel_index)
		_syncing = false
	canvas.queue_redraw()


func _on_canvas_edited() -> void:
	_on_edited()
	if canvas.tool == Canvas.Tool.COLLISION and canvas.sel_kind == Kind.ACTOR:
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
		child.queue_free()
	_panel_scroll.visible = true

	_actor_panel.add_child(_text("物件属性（id 与名字改完，记得点上面的「保存到 JSON」）"))

	var row1 := HBoxContainer.new()
	row1.add_child(_text("id"))
	row1.add_child(_field("id", 110.0))
	row1.add_child(_text("  名字"))
	row1.add_child(_field("label", 130.0))
	_actor_panel.add_child(row1)

	var row2 := HBoxContainer.new()
	row2.add_child(_text("贴图"))
	var sprite_line := _field("sprite", 320.0)
	row2.add_child(sprite_line)
	var picker := OptionButton.new()
	picker.add_item("（从 art/props 选）")
	var props := model.prop_files()
	for path in props:
		picker.add_item(path.get_file())
	picker.item_selected.connect(func(i: int) -> void:
		if i <= 0:
			return
		var path: String = props[i - 1]
		model.set_actor_field(_panel_index, "sprite", path)
		sprite_line.text = path
		_on_edited()
		canvas.queue_redraw())
	row2.add_child(picker)
	_actor_panel.add_child(row2)

	var row3 := HBoxContainer.new()
	row3.add_child(_text("属性："))
	row3.add_child(_bool_field("decor", "只装饰（不参与交互）"))
	row3.add_child(_bool_field("cover", "会挡人（按站位分前后）"))
	row3.add_child(_bool_field("over", "永远画在角色之上"))
	_actor_panel.add_child(row3)
	var geometry := ObjectInspector.new()
	geometry.configure(model, _panel_index)
	geometry.edited.connect(_on_edited)
	geometry.rebuild_requested.connect(_rebuild_object_inspector)
	_actor_panel.add_child(geometry)

	_build_interaction_section()
	_actor_panel.add_child(_switch_row())
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
			_actor_panel.add_child(_text_area("line", 520.0, 44.0))
		"talk":
			_build_talk_list()
		"event":
			_actor_panel.add_child(_text("  → data/events/%s.json（正文在那个文件里，编辑器不编剧情）"
				% str(model.actor_field(_panel_index, "event", ""))))
		"actions":
			_actor_panel.add_child(_text("  → 写在 data/maps 里的多动作菜单，编辑器暂不编辑"))
		_:
			_actor_panel.add_child(_text("  想让它能说话，就点右边的按钮换成旁白或对话。"))


func _switch_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var to_line := Button.new()
	to_line.text = "换成单句旁白"
	to_line.pressed.connect(func() -> void: _switch_form("line"))
	row.add_child(to_line)
	var to_talk := Button.new()
	to_talk.text = "换成多句对话"
	to_talk.pressed.connect(func() -> void: _switch_form("talk"))
	row.add_child(to_talk)
	row.add_child(_text("（原来的内容会搬过去；挂了剧情事件的件不动）"))
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
		var row := HBoxContainer.new()

		var who := LineEdit.new()
		who.text = str(line.get("speaker", ""))
		who.placeholder_text = "说话人（空=旁白）"
		who.custom_minimum_size = Vector2(96, 0)
		who.text_changed.connect(func(t: String) -> void: _set_talk(i, "speaker", t))
		row.add_child(who)

		var side := OptionButton.new()
		side.add_item("左")
		side.add_item("右")
		side.selected = 1 if str(line.get("side", "left")) == "right" else 0
		side.item_selected.connect(func(k: int) -> void:
			_set_talk(i, "side", "right" if k == 1 else "left"))
		row.add_child(side)

		var port := OptionButton.new()
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
		body.custom_minimum_size = Vector2(300, 38)
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
	var res_path := model.import_image(source_path, "res://art/map", model.map_id + "_wall")
	if res_path == "":
		_status.text = "导入失败：得是能读的 .png。"
		return
	model.set_overlay_path(res_path)
	canvas.set_overlay_texture(res_path)
	canvas.clear_texture_cache()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	canvas.sel_kind = Kind.OVERLAY
	canvas.sel_index = 0
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_status.text = "前景层换成 %s（整张拉伸到地图大小，图的尺寸不用管）" % res_path
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		canvas.clear_texture_cache()
		canvas.set_overlay_texture(res_path))


func _import_and_create(source_path: String) -> void:
	var res_path := model.import_image(source_path, "res://art/props")
	if res_path == "":
		_status.text = "导入失败：得是能读的 .png。别的格式先在画图工具里另存成 png。"
		return
	var index := model.add_actor_with_sprite(res_path, true)
	canvas.sel_kind = Kind.ACTOR
	canvas.sel_index = index
	canvas.clear_texture_cache()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_status.text = "导入成 %s，并建了一件遮挡物件。拖到位置上、拉它的黄线；名字在下面改。" % res_path
	# 新文件被 Godot 导成纹理要一两秒，等一下再清缓存重画一次，图才出得来
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		canvas.clear_texture_cache()
		canvas.queue_redraw()
		_refresh_assets())
