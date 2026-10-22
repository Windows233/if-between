## 旧墙迁移助手：手动勾选旧墙，向纯逻辑模块请求来源快照的迁移预览。
##
## 打开、切换选项与取消不改模型；确认前重新核对目标、地图来源及隐藏锁定状态。
##
## 独立窗口滚动展示旧墙与预览；成功通知 dock 统一记撤销并刷新，不自动保存。
@tool
extends ConfirmationDialog

const Transfer := preload("res://addons/if_map_editor/map_geometry_transfer.gd")

signal applied(actor_index: int)

var _model
var _source: Dictionary = {}
var _map_id := ""
var _actor_index := -1
var _actor_id := ""
var _validate_target: Callable
var _plan: Dictionary = {}
var _target_label: Label
var _wall_list: Tree
var _preserve_sort: CheckBox
var _preview: RichTextLabel
var _content: VBoxContainer
var _syncing := false


func configure(model, actor_index: int, validate_target: Callable) -> void:
	if _content == null:
		_build()
	_model = model
	_source = model.data.duplicate(true)
	_map_id = model.map_id
	_actor_index = actor_index
	_actor_id = str(model.actor_field(actor_index, "id", ""))
	_validate_target = validate_target
	_syncing = true
	_preserve_sort.button_pressed = true
	_target_label.text = "归入物件：%s（%s）" % [str(model.actor_field(actor_index, "label", "")), _actor_id]
	_wall_list.clear()
	var root := _wall_list.create_item()
	var target_rect: Rect2 = model.rect_of(model.Kind.ACTOR, actor_index)
	for wall_index: int in model.walls().size():
		var wall_rect: Rect2 = model.rect_of(model.Kind.WALL, wall_index)
		var item := _wall_list.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, false)
		item.set_metadata(0, wall_index)
		var description := "#%d  世界 (%s, %s)  %s × %s" % [wall_index,
			wall_rect.position.x, wall_rect.position.y, wall_rect.size.x, wall_rect.size.y]
		if wall_rect.intersects(target_rect):
			description += "  [与贴图重叠]"
		item.set_text(0, description)
		item.set_tooltip_text(0, description)
		item.set_text_overrun_behavior(0, TextServer.OVERRUN_TRIM_ELLIPSIS)
	_syncing = false
	_refresh_preview()


func _build() -> void:
	title = "归入地图墙"
	ok_button_text = "确认归入"
	cancel_button_text = "取消"
	dialog_hide_on_ok = false
	min_size = Vector2i(300, 320)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	add_child(_content)
	_target_label = _label("")
	_content.add_child(_target_label)
	_content.add_child(_label("手动勾选需要归入的旧墙。重叠只作提示，不会自动选择。"))
	_wall_list = Tree.new()
	_wall_list.hide_root = true
	_wall_list.columns = 1
	_wall_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wall_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wall_list.custom_minimum_size = Vector2(0, 80)
	_wall_list.item_edited.connect(_refresh_preview)
	_content.add_child(_wall_list)
	_preserve_sort = CheckBox.new()
	_preserve_sort.text = "保持当前遮挡基线"
	_preserve_sort.button_pressed = true
	_preserve_sort.tooltip_text = "默认用排序偏移保持原基线；取消勾选后采用碰撞箱上边缘的自动基线。"
	_preserve_sort.toggled.connect(func(_enabled: bool) -> void: _refresh_preview())
	_content.add_child(_preserve_sort)
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = false
	_preview.scroll_active = true
	_preview.fit_content = false
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0, 64)
	_content.add_child(_preview)
	_content.add_child(_label("仅修改未保存布局；确认后可撤销。"))
	confirmed.connect(_confirm_transfer)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func open_for_viewport() -> void:
	var available := Vector2i(get_parent().get_viewport().get_visible_rect().size) - Vector2i(32, 32)
	var target := Vector2i(maxi(min_size.x, mini(620, available.x)), maxi(min_size.y, mini(560, available.y)))
	_prepare_popup_layout(target)
	max_size = target
	popup_centered(target)


func _prepare_popup_layout(target: Vector2i) -> void:
	var width := maxf(1.0, float(target.x) - 32.0)
	for child: Node in _content.get_children():
		if child is Label:
			(child as Label).size = Vector2(width, 0)
			(child as Label).update_minimum_size()
	_content.size = Vector2(width, maxf(1.0, float(target.y) - 80.0))


func selected_wall_indices() -> Array[int]:
	var selected: Array[int] = []
	if _wall_list == null or _wall_list.get_root() == null:
		return selected
	var item := _wall_list.get_root().get_first_child()
	while item != null:
		if item.is_checked(0):
			selected.append(int(item.get_metadata(0)))
		item = item.get_next()
	return selected


func _context_error() -> String:
	if _model == null or _model.map_id != _map_id:
		return "地图已改变，请关闭助手后重新打开。"
	if _validate_target.is_valid():
		var reason: String = _validate_target.call()
		if not reason.is_empty():
			return reason
	if _actor_index < 0 or _actor_index >= _model.actors().size() \
			or str(_model.actor_field(_actor_index, "id", "")) != _actor_id:
		return "目标 ID 已改变，请关闭助手后重新打开。"
	if _model.data != _source:
		return "地图或来源数据已变化，预览已失效；请关闭助手后重新打开。"
	return ""


func _refresh_preview() -> void:
	if _syncing or _model == null:
		return
	var selected := selected_wall_indices()
	_plan = Transfer.preview(_source, _actor_index, selected, _preserve_sort.button_pressed)
	var lines := PackedStringArray(["已选旧墙：%d / %d；新增碰撞：%d" % [selected.size(),
		_wall_list.get_root().get_child_count(), int(_plan.get("added_shapes", 0))],
		"遮挡基线：%s → %s" % [float(_plan.get("before_baseline", 0.0)), float(_plan.get("after_baseline", 0.0))]])
	if bool(_plan.get("ok", false)):
		var shapes: Array = _plan["data"]["actors"][_actor_index].get("collision", [])
		var before := MapDef._actor_from(_source["actors"][_actor_index]).collision_rects().size()
		var added := int(_plan.get("added_shapes", 0))
		lines.append("将移除旧墙：%d；目标有效碰撞：%d → %d" % [added, before, shapes.size()])
		var indices: Array = _plan.get("wall_indices", [])
		for offset: int in added:
			lines.append("墙 #%d → 局部矩形 %s" % [int(indices[offset]), str(shapes[shapes.size() - added + offset])])
	for warning: String in _plan.get("warnings", []):
		lines.append("警告：" + warning)
	for error: String in _plan.get("errors", []):
		lines.append("错误：" + error)
	var reason := _context_error()
	if selected.is_empty():
		lines.append("请选择至少一面旧墙。")
	if not reason.is_empty():
		lines.append("错误：" + reason)
	_preview.text = "\n".join(lines)
	get_ok_button().disabled = selected.is_empty() or not bool(_plan.get("ok", false)) or not reason.is_empty()


func _confirm_transfer() -> void:
	_refresh_preview()
	if get_ok_button().disabled:
		return
	if not Transfer.apply(_model, _plan):
		_preview.text += "\n错误：来源已失效或重新校验未通过，请关闭助手后重新打开。"
		get_ok_button().disabled = true
		return
	applied.emit(_actor_index)
	hide()
