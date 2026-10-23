@tool
extends VBoxContainer

signal edited
signal rebuild_requested

var model
var library
var index := -1
var selection: Array[int] = []
var _fields: Dictionary = {}
var _pending: Dictionary = {}
var _summary: Label
var _confirm: Button
var _template_parent: OptionButton
var _template_category: LineEdit
var _template_tags: LineEdit
var _template_summary: Label
var _template_confirm: Button
var _pending_template: Dictionary = {}


func configure(source, template_library, actor_index: int) -> void:
	model = source
	library = template_library
	index = actor_index
	selection = [index]
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	refresh()


func set_selection(indices: Array[int]) -> void:
	selection = indices.duplicate()
	_pending.clear()
	if _confirm != null:
		_confirm.disabled = true
	if _summary != null:
		_summary.text = "已更改选择，请重新预览；批量更新 %d 件。" % selection.size()


func refresh() -> void:
	for child: Node in get_children():
		remove_child(child)
		if is_inside_tree():
			child.queue_free()
		else:
			child.free()
	_fields.clear()
	_pending.clear()
	_pending_template.clear()
	if model == null or library == null:
		return
	var info: Dictionary = library.inspect_instance(model, index)
	_add_label("模板来源：%s（格式 v%s）\n实例版本：%s　当前模板版本：%s" % [
		info.get("name", "无"), str(info.get("template_format_version", "未知")), str(info.get("instance_version", "未知")),
		str(info.get("template_version", "不可用"))])
	if not str(info.get("message", "")).is_empty():
		_add_label(str(info["message"]))
	var states := {"default": "默认", "overridden": "已覆盖", "preserved": "保留覆盖", "unknown": "未知"}
	var fields: Dictionary = info.get("fields", {})
	for field: String in fields:
		var state: Dictionary = fields[field]
		var check := CheckBox.new()
		check.name = "Field_" + field.validate_node_name()
		check.text = "%s：%s%s" % [field, states.get(state["state"], "未知"),
			"（本地删除）" if not state["present"] else ""]
		check.tooltip_text = "当前：%s\n模板默认：%s" % [str(state.get("value")),
			str(state.get("default")) if state.get("default_present", false) else "无此字段"]
		_fields[field] = check
		add_child(check)
	var available: bool = info.get("ok", false)
	var tracked: bool = info.get("snapshot_valid", false)
	var actions := HFlowContainer.new()
	add_child(actions)
	_button(actions, "预览更新所选实例", "PreviewUpdate", func(): prepare_update(), available and tracked)
	_button(actions, "预览恢复勾选字段", "PreviewRestoreFields", func(): prepare_restore(false), available and tracked)
	_button(actions, "预览恢复全部模板默认", "PreviewRestoreAll", func(): prepare_restore(true), available and tracked)
	_button(actions, "建立安全基线（保留现状）", "PreviewAdopt", func(): prepare_adoption(), available and not tracked)
	_summary = _add_label("更新和恢复均先预览，再按下确认按钮应用。")
	_summary.name = "PreviewSummary"
	_confirm = _button(self, "确认应用此预览", "ConfirmTemplateChanges", func(): confirm_preview(true), false)
	_build_template_editor(info)


func _build_template_editor(info: Dictionary) -> void:
	_add_label("源模板默认属性编辑")
	_add_label("用当前物件属性更新源模板。只修改模板资产；已放置实例需另外预览并确认更新。")
	_add_label("父模板（单继承）")
	_template_parent = OptionButton.new()
	_template_parent.name = "TemplateParent"
	_template_parent.add_item("无父模板")
	_template_parent.set_item_metadata(0, "")
	for template_name: String in library.list_templates():
		if template_name == info.get("name", ""):
			continue
		_template_parent.add_item(template_name)
		_template_parent.set_item_metadata(_template_parent.item_count - 1, template_name)
		if template_name == info.get("parent", ""):
			_template_parent.select(_template_parent.item_count - 1)
	_template_parent.disabled = not info.get("ok", false)
	_template_parent.item_selected.connect(func(_selected): _invalidate_template_preview())
	add_child(_template_parent)
	var metadata: Dictionary = info.get("metadata", {})
	_add_label("分类")
	_template_category = LineEdit.new()
	_template_category.name = "TemplateCategory"
	_template_category.text = str(metadata.get("category", ""))
	_template_category.placeholder_text = "例如：家具 / 装饰"
	_template_category.text_changed.connect(func(_text): _invalidate_template_preview())
	add_child(_template_category)
	_add_label("标签（用逗号分隔）")
	_template_tags = LineEdit.new()
	_template_tags.name = "TemplateTags"
	_template_tags.text = ", ".join(metadata.get("tags", []))
	_template_tags.placeholder_text = "例如：木制, 室内"
	_template_tags.text_changed.connect(func(_text): _invalidate_template_preview())
	add_child(_template_tags)
	_button(self, "预览：用当前属性更新源模板", "PreviewSourceTemplateUpdate",
		func(): prepare_template_update(), info.get("ok", false))
	_template_summary = _add_label("先核对默认属性、继承关系和分类标签的差异，再确认更新源模板。")
	_template_summary.name = "TemplateUpdateSummary"
	_template_confirm = _button(self, "确认更新源模板（不修改实例）", "ConfirmSourceTemplateUpdate",
		func(): confirm_source_template_update(true), false)


func prepare_template_update() -> Dictionary:
	var item: Dictionary = model.actor_dict(index)
	var name := str(item.get("source_template", ""))
	var info: Dictionary = library.inspect_instance(model, index)
	var metadata: Dictionary = info.get("metadata", {}).duplicate(true)
	metadata["category"] = _template_category.text.strip_edges()
	var tags: Array[String] = []
	for raw: String in _template_tags.text.replace("，", ",").split(",", false):
		var tag := raw.strip_edges()
		if not tag.is_empty() and tag not in tags:
			tags.append(tag)
	metadata["tags"] = tags
	var parent := str(_template_parent.get_selected_metadata())
	var preview: Dictionary = library.preview_template_update(name, item, parent, metadata)
	_pending_template = preview.duplicate(true) if preview.get("ok", false) else {}
	_template_confirm.disabled = _pending_template.is_empty()
	if not preview.get("ok", false):
		_template_summary.text = str(preview.get("message", "无法生成模板更新预览。"))
		return preview
	var lines: Array[String] = ["源模板 %s：v%s → v%s" % [name,
		str(preview["expected_version"]), str(preview["target_version"])]]
	for change: Dictionary in preview["changes"]:
		lines.append(_format_template_change(change))
	var affected: Array[String] = []
	for dependent: Dictionary in preview["affected_templates"]:
		affected.append(dependent["name"])
		if dependent["name"] != name:
			lines.append("子模板默认影响：" + dependent["name"])
			for change: Dictionary in dependent["changes"]:
				lines.append(_format_template_change(change))
	var instances := 0
	for actor: Variant in model.actors():
		if actor is Dictionary and str(actor.get("source_template", "")) in affected:
			instances += 1
	lines.append("当前地图关联实例 %d 件，确认后均保持现状；需要另行预览实例更新。" % instances)
	if preview["changes"].is_empty():
		lines.append("默认值没有差异；确认仍会增加模板版本。")
	_template_summary.text = "\n".join(lines)
	return preview


func confirm_source_template_update(confirmed := false) -> Error:
	if not confirmed:
		return ERR_UNAUTHORIZED
	if _pending_template.is_empty():
		return ERR_UNCONFIGURED
	if JSON.stringify(model.actor_dict(index)) != JSON.stringify(_pending_template["source"]):
		_invalidate_template_preview()
		_template_summary.text = "当前物件已改变，请重新预览模板默认差异。"
		return ERR_BUSY
	var error: Error = library.confirm_template_update(_pending_template, true)
	if error != OK:
		_invalidate_template_preview()
		_template_summary.text = "源模板未更新（错误 %d）。请检查模板或父模板是否改变，再重新预览。" % error
		return error
	refresh()
	_template_summary.text = "源模板版本已更新，当前地图实例与撤销历史保持现状。"
	rebuild_requested.emit()
	return OK


func _invalidate_template_preview() -> void:
	_pending_template.clear()
	if _template_confirm != null:
		_template_confirm.disabled = true
	if _template_summary != null:
		_template_summary.text = "模板编辑项已改变，请重新预览。"


func _format_template_change(change: Dictionary) -> String:
	return "%s：%s → %s" % [change["path"],
		str(change["before"]) if change["before_present"] else "（无）",
		str(change["after"]) if change["after_present"] else "（删除）"]


func prepare_update() -> Dictionary:
	var batch: Dictionary = library.preview_updates(model, selection)
	_show_preview(batch)
	return batch


func prepare_restore(all_fields := false) -> Dictionary:
	var fields: Array[String] = []
	if not all_fields:
		for field: String in _fields:
			if (_fields[field] as CheckBox).button_pressed:
				fields.append(field)
		if fields.is_empty():
			var failure := {"ok": false, "error": ERR_INVALID_PARAMETER, "message": "请先勾选要恢复的字段。"}
			_show_preview(failure)
			return failure
	var preview: Dictionary = library.preview_restore_defaults(model, fields, index)
	var batch := {"ok": true, "error": OK, "updates": [preview]} if preview["ok"] else preview
	_show_preview(batch)
	return batch


func prepare_adoption() -> Dictionary:
	var preview: Dictionary = library.preview_adopt_instance(model, index)
	var batch := {"ok": true, "error": OK, "updates": [preview]} if preview["ok"] else preview
	_show_preview(batch)
	return batch


func confirm_preview(confirmed := false) -> Error:
	var error: Error = library.confirm_updates(model, _pending, confirmed, false)
	if error != OK:
		_summary.text = "未应用（错误 %d）。地图、模板或选择可能已变化，请重新预览。" % error
		_pending.clear()
		_confirm.disabled = true
		return error
	refresh()
	edited.emit()
	rebuild_requested.emit()
	return OK


func _show_preview(batch: Dictionary) -> void:
	_pending = batch.duplicate(true) if batch.get("ok", false) else {}
	_confirm.disabled = _pending.is_empty()
	if not batch.get("ok", false):
		_summary.text = str(batch.get("message", "无法生成预览。"))
		return
	var lines: Array[String] = []
	for entry: Dictionary in batch["updates"]:
		lines.append("%s → %s v%s：%s" % [str(entry["before"].get("id", "")),
			entry["name"], str(entry["target_version"]), entry["message"]])
		if entry["mode"] == "adopt":
			lines.append("保留覆盖：" + ", ".join(entry["preserved_fields"]))
		for field: String in entry["changes"]:
			lines.append("%s：%s → %s" % [field, str(entry["before"].get(field, "（无）")),
				str(entry["after"].get(field, "（删除）"))])
		if entry["changes"].is_empty():
			lines.append("物件属性不变；仅更新来源快照和版本。")
	_summary.text = "\n".join(lines)


func _add_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label


func _button(parent: Node, text: String, node_name: String, callback: Callable, enabled: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.disabled = not enabled
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
