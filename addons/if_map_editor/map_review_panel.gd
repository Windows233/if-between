## 可嵌入 dock/dialog 的校验与迁移审阅面板，普通用户通过列表勾选墙归属。
## UI 只操作当前模型的可撤销迁移；跨地图报告只读，正式保存交给主界面确认。
## configure 后模型变化会使计划失效；主界面用 issue_selected 定位，用 edited 刷新画布。
@tool
extends VBoxContainer

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Validation := preload("res://addons/if_map_editor/map_validation.gd")
const Batch := preload("res://addons/if_map_editor/map_migration_batch.gd")

signal validated(report: Dictionary)
signal issue_selected(issue: Dictionary)
signal edited
signal review_requested(review: Dictionary)

var _model: Variant
var _library: Variant
var _source: Dictionary = {}
var _map_id := ""
var _entries: Array[Dictionary] = []
var _preview: Dictionary = {}
var _manifest: Dictionary = {}
var _report: Dictionary = {}
var _actor_choice: OptionButton
var _walls: Tree
var _plans: Tree
var _preserve: CheckBox
var _issues: ItemList
var _comparison: RichTextLabel
var _status: Label
var _apply_button: Button
var _save_button: Button
var _cross_maps: VBoxContainer
var _map_choices: ItemList
var _map_reports: ItemList
var _export_button: Button
var _manifest_dialog: FileDialog
var _export_dialog: FileDialog
var _export_payload: Dictionary = {}
var _syncing := false


## 可反复 configure；不会修改模型、自动勾墙、保存或打开迁移窗口。
func configure(model: Variant, library: Variant = null) -> void:
	if _status == null:
		_build()
	_model = model
	_library = library
	_source = model.data.duplicate(true) if model is Model and Validation.geometry_issues(model.data).is_empty() else {}
	_map_id = model.map_id if model is Model else ""
	_entries.clear()
	_preview.clear()
	_manifest.clear()
	_report.clear()
	_export_payload.clear()
	_export_button.disabled = true
	_map_reports.clear()
	_refresh_maps()
	_syncing = true
	_actor_choice.clear()
	_walls.clear()
	var root := _walls.create_item()
	for index: int in _source.get("actors", []).size():
		var actor: Dictionary = _source["actors"][index]
		_actor_choice.add_item("%s (%s)" % [actor.get("label", "物件"), actor.get("id", "")], index)
	for index: int in _source.get("walls", []).size():
		var item := _walls.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, false)
		item.set_text(0, "墙 #%d  %s" % [index, str(_source["walls"][index])])
		item.set_metadata(0, index)
	_preserve.button_pressed = true
	_syncing = false
	_refresh_plan_list()
	_issues.clear()
	_apply_button.disabled = true
	_save_button.disabled = true
	_status.text = "选择物件并明确勾选归属墙，再加入计划。"
	_comparison.text = "预览展示墙、局部碰撞、交互范围和遮挡基线的前后对比。"


func _build() -> void:
	var actions := HBoxContainer.new()
	add_child(actions)
	_button(actions, "一键校验", validate_current)
	_save_button = _button(actions, "审阅并保存…", request_save_review)
	_button(actions, "跨地图报告", func() -> void: _cross_maps.visible = not _cross_maps.visible)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_issues = ItemList.new()
	_issues.custom_minimum_size.y = 120
	_issues.item_selected.connect(_on_issue_selected)
	add_child(_issues)
	_build_cross_maps()
	_actor_choice = OptionButton.new()
	_actor_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_actor_choice)
	_walls = Tree.new()
	_walls.hide_root = true
	_walls.custom_minimum_size.y = 130
	add_child(_walls)
	_preserve = CheckBox.new()
	_preserve.text = "保持当前遮挡基线"
	add_child(_preserve)
	var plan_actions := HBoxContainer.new()
	add_child(plan_actions)
	_button(plan_actions, "加入 / 更新此物件", _put_entry)
	_button(plan_actions, "移除所选计划", _remove_entry)
	_plans = Tree.new()
	_plans.hide_root = true
	_plans.columns = 2
	_plans.set_column_title(0, "参与迁移 / 物件")
	_plans.set_column_title(1, "墙归属 / 保持基线")
	_plans.column_titles_visible = true
	_plans.custom_minimum_size.y = 110
	_plans.item_edited.connect(_on_plan_edited)
	_plans.item_selected.connect(_on_plan_selected)
	add_child(_plans)
	var preview_actions := HBoxContainer.new()
	add_child(preview_actions)
	_button(preview_actions, "预览整批迁移", preview_plan)
	_apply_button = _button(preview_actions, "应用到当前地图（可撤销）", apply_preview.bind(true))
	_apply_button.disabled = true
	_comparison = RichTextLabel.new()
	_comparison.custom_minimum_size.y = 180
	_comparison.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_comparison)
	_manifest_dialog = FileDialog.new()
	_manifest_dialog.title = "选择已有迁移 manifest（只读审阅）"
	_manifest_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_manifest_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_manifest_dialog.filters = PackedStringArray(["*.json ; 迁移 manifest"])
	_manifest_dialog.file_selected.connect(review_manifest)
	add_child(_manifest_dialog)
	_export_dialog = FileDialog.new()
	_export_dialog.title = "导出地图审阅报告"
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.filters = PackedStringArray(["*.json ; 结构化报告", "*.txt ; 可读报告"])
	_export_dialog.current_file = "map_review_report.json"
	_export_dialog.file_selected.connect(_on_export_selected)
	add_child(_export_dialog)


func _build_cross_maps() -> void:
	_cross_maps = VBoxContainer.new()
	_cross_maps.visible = false
	add_child(_cross_maps)
	var hint := Label.new()
	hint.text = "多选已有地图生成只读报告；当前迁移计划仍由单图表格明确指定。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cross_maps.add_child(hint)
	_map_choices = ItemList.new()
	_map_choices.name = "ReviewMapChoices"
	_map_choices.select_mode = ItemList.SELECT_MULTI
	_map_choices.custom_minimum_size.y = 100
	_cross_maps.add_child(_map_choices)
	var actions := HBoxContainer.new()
	_cross_maps.add_child(actions)
	_button(actions, "刷新地图目录", _refresh_maps)
	_button(actions, "生成所选地图报告", review_selected_maps)
	_button(actions, "选择 manifest 文件…", open_manifest_dialog)
	_export_button = _button(actions, "导出报告…", open_export_dialog)
	_export_button.disabled = true
	_map_reports = ItemList.new()
	_map_reports.name = "ReviewMapReports"
	_map_reports.custom_minimum_size.y = 90
	_map_reports.item_selected.connect(_show_map_summary)
	_cross_maps.add_child(_map_reports)


func _refresh_maps() -> void:
	_map_choices.clear()
	for map_id: String in Model.list_maps():
		var index := _map_choices.add_item(map_id)
		_map_choices.set_item_metadata(index, map_id)


## 多选列表的只读报告入口；没有任何墙归属推断或地图写回。
func review_selected_maps() -> Dictionary:
	var entries: Array[Dictionary] = []
	for index: int in _map_choices.get_selected_items():
		entries.append({"map_id": str(_map_choices.get_item_metadata(index))})
	return review_manifest({"maps": entries})


func open_manifest_dialog() -> void:
	_manifest_dialog.popup_centered_ratio(0.7)


func open_export_dialog() -> void:
	if not _export_payload.is_empty():
		_export_dialog.popup_centered_ratio(0.7)


func _on_export_selected(path: String) -> void:
	var error := export_report(path, true)
	_status.text = "报告已导出：%s" % path if error == OK else "报告导出失败：%d" % error


## 仅导出 json/txt 报告。禁止覆盖正式地图；已存在报告须有文件选择器的覆盖确认。
func export_report(path: String, overwrite_confirmed := false) -> Error:
	if _export_payload.is_empty() or not path.get_extension().to_lower() in ["json", "txt"]:
		return ERR_INVALID_PARAMETER
	var target := ProjectSettings.globalize_path(path).simplify_path().replace("\\", "/").to_lower()
	var protected := ProjectSettings.globalize_path("res://data").simplify_path().replace("\\", "/").to_lower()
	if target == protected or target.begins_with(protected + "/"):
		return ERR_UNAUTHORIZED
	if _model is Model and not _model.path.is_empty() and target == ProjectSettings.globalize_path(_model.path).simplify_path().replace("\\", "/").to_lower():
		return ERR_UNAUTHORIZED
	for item: Dictionary in _manifest.get("maps", []):
		if item.has("path") and target == ProjectSettings.globalize_path(item["path"]).simplify_path().replace("\\", "/").to_lower():
			return ERR_UNAUTHORIZED
	if FileAccess.file_exists(path) and not overwrite_confirmed:
		return ERR_ALREADY_EXISTS
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(Model.stringify(_export_payload) if path.get_extension().to_lower() == "json" else _report_text())
	var error := file.get_error()
	file.close()
	return error


func _report_text() -> String:
	var lines: Array[String] = ["地图审阅报告", "错误 %d / 警告 %d" % [
		_export_payload.get("errors", []).size(), _export_payload.get("warnings", []).size()]]
	for item: Dictionary in _export_payload.get("maps", []):
		lines.append("地图 %s：%s" % [item.get("map_id", "无效条目"), item.get("path", "")])
	for problem: Dictionary in _export_payload.get("issues", []):
		lines.append("[%s] %s / %s #%s / %s：%s" % [problem["severity"], problem["map_id"],
			problem["kind"], str(problem["index"]), problem["field"], problem["message"]])
	return "\n".join(lines) + "\n"


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


## 主界面也可从既有迁移 dialog 收集计划后调用；不接收 JSON 文本。
func set_plan(plan: Array) -> bool:
	if _status == null or not Validation.geometry_issues(_source).is_empty():
		return false
	for entry: Variant in plan:
		if not entry is Dictionary or not entry.get("actor_id") is String \
				or not entry.get("wall_indices") is Array or not entry.get("preserve_baseline") is bool:
			return false
	_entries.clear()
	for entry: Dictionary in plan:
		_entries.append({"actor_id": entry["actor_id"], "wall_indices": entry["wall_indices"].duplicate(),
			"preserve_baseline": entry["preserve_baseline"], "enabled": true})
	_refresh_plan_list()
	_invalidate_preview()
	return true


## 返回已勾选的显式计划；外部修改返回值不影响面板。
func get_plan() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if entry["enabled"]:
			result.append({"actor_id": entry["actor_id"], "wall_indices": entry["wall_indices"].duplicate(),
				"preserve_baseline": entry["preserve_baseline"]})
	return result


func _put_entry() -> void:
	var actor_index := _actor_choice.get_selected_id()
	if actor_index < 0 or actor_index >= _source.get("actors", []).size():
		return
	var indices: Array[int] = []
	var item := _walls.get_root().get_first_child()
	while item != null:
		if item.is_checked(0):
			indices.append(item.get_metadata(0))
		item = item.get_next()
	var entry := {"actor_id": str(_source["actors"][actor_index].get("id", "")), "wall_indices": indices,
		"preserve_baseline": _preserve.button_pressed, "enabled": true}
	var existing := -1
	for index: int in _entries.size():
		if _entries[index]["actor_id"] == entry["actor_id"]:
			existing = index
	if existing >= 0:
		_entries[existing] = entry
	else:
		_entries.append(entry)
	_refresh_plan_list()
	_invalidate_preview()


func _remove_entry() -> void:
	var item := _plans.get_selected()
	if item != null:
		_entries.remove_at(item.get_metadata(0))
		_refresh_plan_list()
		_invalidate_preview()


func _refresh_plan_list() -> void:
	_syncing = true
	_plans.clear()
	var root := _plans.create_item()
	for index: int in _entries.size():
		var entry: Dictionary = _entries[index]
		var item := _plans.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, entry["enabled"])
		item.set_text(0, entry["actor_id"])
		item.set_metadata(0, index)
		item.set_text(1, "%s / %s" % [str(entry["wall_indices"]), "保持基线" if entry["preserve_baseline"] else "自动基线"])
	_syncing = false


func _on_plan_edited() -> void:
	if _syncing:
		return
	var item := _plans.get_edited()
	if item != null:
		_entries[item.get_metadata(0)]["enabled"] = item.is_checked(0)
		_invalidate_preview()


func _on_plan_selected() -> void:
	if _syncing:
		return
	var item := _plans.get_selected()
	if item == null:
		return
	var entry: Dictionary = _entries[item.get_metadata(0)]
	for index: int in _source.get("actors", []).size():
		if _source["actors"][index].get("id") == entry["actor_id"]:
			_actor_choice.select(index)
	_preserve.button_pressed = entry["preserve_baseline"]
	var wall := _walls.get_root().get_first_child()
	while wall != null:
		wall.set_checked(0, entry["wall_indices"].has(wall.get_metadata(0)))
		wall = wall.get_next()
	_show_comparison(str(entry["actor_id"]))


func _invalidate_preview() -> void:
	_preview.clear()
	_apply_button.disabled = true
	_status.text = "计划已修改，请重新预览。"


## 校验当前数据并发出 validated；errors 禁止请求保存，warnings 保持可见。
func validate_current() -> Dictionary:
	if _status == null:
		_build()
	_report = Validation.validate(_model.data if _model is Model else null, {}, _library)
	_show_issues(_report)
	validated.emit(_report.duplicate(true))
	return _report.duplicate(true)


## 不改任何地图；供主界面选择 manifest 后调用。
func review_manifest(manifest: Variant) -> Dictionary:
	if _status == null:
		_build()
	_manifest = Batch.report_manifest(manifest, _library)
	_show_issues(_manifest)
	_cross_maps.visible = true
	_map_reports.clear()
	for item: Dictionary in _manifest["maps"]:
		var counts := Validation.summarize(item["issues"])
		_map_reports.add_item("%s：%d 错误 / %d 警告" % [item.get("map_id", "无效条目"), counts["errors"].size(), counts["warnings"].size()])
	if not _manifest["maps"].is_empty():
		_map_reports.select(0)
		_show_map_summary(0)
	validated.emit(_manifest.duplicate(true))
	return _manifest.duplicate(true)


## 只生成副本并更新对比；review_requested 仅用于保存，预览不会触发宿主保存。
func preview_plan() -> Dictionary:
	if not _model is Model or _model.map_id != _map_id or _model.data != _source:
		_preview = Validation.summarize([Validation.issue("error", "地图已变化，请重新配置审阅面板。", "map", -1, "source", _map_id)])
	else:
		_preview = Batch.preview(_source, get_plan())
	_show_issues(_preview)
	_apply_button.disabled = not _preview["ok"]
	_show_comparison()
	return _preview.duplicate(true)


## 应用一次完整计划；不保存，成功后发出 edited，由主界面刷新画布和选择。
func apply_preview(confirmed := false) -> bool:
	if not Batch.apply(_model, _preview, confirmed):
		_status.text = "迁移计划无效或已过期，请重新审阅。"
		_apply_button.disabled = true
		return false
	configure(_model, _library)
	edited.emit()
	validate_current()
	_status.text += " 迁移已应用，可整步撤销；尚未保存。"
	return true


## 只发出请求，主界面展示确认与警告后才可调用 Batch.save_current()。
func request_save_review() -> void:
	var report := validate_current()
	if report["can_save"]:
		review_requested.emit({"action": "save", "validation": report,
			"requires_confirmation": true, "requires_warning_acknowledgement": not report["warnings"].is_empty()})


func _show_issues(report: Dictionary) -> void:
	_export_payload = report.duplicate(true)
	_export_button.disabled = false
	_issues.clear()
	for problem: Dictionary in report.get("issues", []):
		var index := _issues.add_item("[%s] %s: %s" % [problem["severity"], problem["map_id"], problem["message"]])
		_issues.set_item_metadata(index, problem.duplicate(true))
	_status.text = "%d 个错误，%d 个警告。警告须在保存前明确确认。" % [report.get("errors", []).size(), report.get("warnings", []).size()]
	_save_button.disabled = not report.get("can_save", false)


func _show_map_summary(index: int) -> void:
	if index < 0 or index >= _manifest.get("maps", []).size():
		return
	var item: Dictionary = _manifest["maps"][index]
	var lines: Array[String] = ["地图 %s\n%s" % [item.get("map_id", ""), item.get("path", "")]]
	var navigation: Dictionary = item.get("validation", {}).get("navigation", {})
	if not navigation.is_empty():
		lines.append("可站立区域：%d；出生点所在区域：%d；校验%s完成。" % [navigation.get("components", []).size(),
			navigation.get("spawn_region_count", 0),
			"已" if navigation.get("complete", false) else "未"])
	for problem: Dictionary in item.get("issues", []):
		lines.append("[%s] %s" % [problem["severity"], problem["message"]])
	var diff: Dictionary = item.get("diff", {})
	if not diff.is_empty():
		lines.append("世界墙：%s → %s" % [str(diff["before"]["walls"]), str(diff["after"]["walls"])])
		for change: Dictionary in diff.get("changes", []):
			lines.append("物件 %s（明确归属墙 %s）" % [change["actor_id"], str(change["wall_indices"])])
			for field: String in ["collision", "reach", "reach_local", "cover", "cover_y"]:
				lines.append("%s：%s → %s" % [field, str(change["before"].get(field)), str(change["after"].get(field))])
	_comparison.text = "\n".join(lines)


func _on_issue_selected(index: int) -> void:
	var problem: Dictionary = _issues.get_item_metadata(index)
	_comparison.text = "%s\n地图 %s / %s #%s / %s\n%s" % [problem["message"], problem["map_id"],
		problem["kind"], str(problem["index"]), problem["field"], problem.get("resource", "")]
	issue_selected.emit(problem.duplicate(true))


func _show_comparison(actor_id := "") -> void:
	var diff: Dictionary = _preview.get("diff", {})
	if diff.is_empty():
		_comparison.text = "预检未通过，未生成可应用的迁移。"
		return
	var lines: Array[String] = ["世界墙：%s → %s" % [str(diff["before"]["walls"]), str(diff["after"]["walls"])]]
	for change: Dictionary in diff["changes"]:
		if not actor_id.is_empty() and change["actor_id"] != actor_id:
			continue
		lines.append("\n物件 %s（归入墙 %s）" % [change["actor_id"], str(change["wall_indices"])])
		for field: String in ["collision", "world_collision", "reach", "reach_local", "cover", "cover_y", "sort_collider", "sort_offset"]:
			lines.append("%s：%s → %s" % [field, str(change["before"].get(field)), str(change["after"].get(field))])
	_comparison.text = "\n".join(lines)
