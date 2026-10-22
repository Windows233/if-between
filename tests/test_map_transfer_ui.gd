## 旧墙迁移助手的 UI 定向测试：通过 static run(h) 供全量入口调用。
##
## 离树构造 dock 与对话框，验证勾选、预览、确认权限和整步撤销，不打开图形窗口。
##
## 也可作为 --headless --script 入口独立运行；调用端须隔离 APPDATA，避免用户数据干扰。
extends SceneTree

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


func _initialize() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	run(harness)
	quit(0 if harness.report() else 1)


static func fixture() -> Dictionary:
	return {"id": "transfer_ui", "size": [400, 300],
		"walls": [[70, 72, 60, 14], [250, 120, 35, 20]],
		"actors": [{"id": "desk", "label": "书桌", "rect": [60, 40, 80, 60],
			"cover": true, "reach": [54, 82, 92, 36]},
			{"id": "shelf", "label": "书架", "rect": [220, 100, 50, 50], "decor": true}]}


static func run(h: TestHarness) -> void:
	test_preview_and_cancel(h)
	test_empty_selection(h)
	test_confirm_and_history(h)
	test_auto_baseline(h)
	test_existing_geometry(h)
	test_blocked_targets(h)
	test_stale_previews(h)
	test_layout(h)


static func _dock() -> Control:
	var dock = Dock.new()
	dock._editor_state_path = "user://map_transfer_ui_%d.cfg" % Time.get_ticks_usec()
	dock._build()
	dock.model = Model.new()
	dock.model.map_id = "transfer_ui"
	dock.model.data = fixture()
	dock.model.reset_history()
	dock.canvas.load_map(dock.model, "", "", dock.model.map_size())
	_select(dock, [0])
	dock._refresh_selection()
	return dock


static func _select(dock: Control, indices: Array[int]) -> void:
	dock.canvas.select_actors(indices)


static func _choose(dialog: ConfirmationDialog, indices: Array[int]) -> void:
	var item: TreeItem = dialog._wall_list.get_root().get_first_child()
	while item != null:
		item.set_checked(0, indices.has(int(item.get_metadata(0))))
		item = item.get_next()
	dialog._refresh_preview()


static func test_preview_and_cancel(h: TestHarness) -> void:
	var dock := _dock()
	var before: Dictionary = dock.model.data.duplicate(true)
	h.check("迁移入口靠近物件属性", dock._transfer_button.get_parent(), dock._actor_panel)
	h.check("单个可编辑物件可以打开助手", dock._transfer_button.disabled, false)
	dock._open_geometry_transfer()
	var dialog = dock._transfer_dialog
	h.check("打开助手默认保持基线", dialog._preserve_sort.button_pressed, true)
	h.check("重叠墙不自动勾选", dialog.selected_wall_indices(), [])
	h.check("列表包含所有旧墙", dialog._wall_list.get_root().get_child_count(), 2)
	var first: TreeItem = dialog._wall_list.get_root().get_first_child()
	h.check("旧墙展示原始索引与世界坐标", first.get_text(0).contains("#0  世界 (%s, %s)" % [70.0, 72.0]), true)
	h.check("重叠仅显示提示", first.get_text(0).contains("重叠"), true)
	_choose(dialog, [0, 1])
	h.check("预览显示明确选择的墙数", dialog._preview.text.contains("已选旧墙：2 / 2"), true)
	h.check("预览显示新增碰撞数", dialog._preview.text.contains("新增碰撞：2"), true)
	h.check("预览显示基线数值", dialog._preview.text.contains("%s → %s" % [100.0, 100.0]), true)
	h.check("预览显示移除旧墙数量", dialog._preview.text.contains("将移除旧墙：2"), true)
	h.check("预览显示有效碰撞前后数量", dialog._preview.text.contains("目标有效碰撞：0 → 2"), true)
	h.check("预览显示重叠墙的局部矩形", dialog._preview.text.contains("墙 #0 → 局部矩形 " + str([10, 32, 60, 14])), true)
	h.check("预览显示非重叠墙的局部矩形", dialog._preview.text.contains("墙 #1 → 局部矩形 " + str([190, 80, 35, 20])), true)
	h.check("非重叠墙的警告可见", dialog._preview.text.contains("警告："), true)
	dialog._preserve_sort.button_pressed = false
	dialog._preserve_sort.button_pressed = true
	h.check("打开与切换预览不改源数据", dock.model.data, before)
	h.check("打开与切换预览不标脏", dock.model.dirty, false)
	dialog.get_cancel_button().pressed.emit()
	h.check("取消不改源数据", dock.model.data, before)
	h.check("取消不增加撤销历史", dock.model._history.size(), 1)
	h.check("取消不标脏", dock.model.dirty, false)
	dock._open_geometry_transfer()
	h.check("重开助手清空勾选", dialog.selected_wall_indices(), [])
	h.check("重开助手恢复保持基线", dialog._preserve_sort.button_pressed, true)
	dock.free()


static func test_empty_selection(h: TestHarness) -> void:
	var dock := _dock()
	dock._open_geometry_transfer()
	var dialog = dock._transfer_dialog
	h.check("空选择禁止确认", dialog.get_ok_button().disabled, true)
	h.check("空选择显示明确提示", dialog._preview.text.contains("请选择至少一面旧墙"), true)
	dialog._confirm_transfer()
	h.check("强行调用空确认仍无改动", dock.model.data, fixture())
	h.check("空确认不标脏", dock.model.dirty, false)
	h.check("空确认不增加历史", dock.model._history.size(), 1)
	dock.free()


static func test_confirm_and_history(h: TestHarness) -> void:
	var dock := _dock()
	var before: Dictionary = dock.model.data.duplicate(true)
	var old_definition: MapDef = dock.canvas._map_def()
	dock.canvas.set_walk_visible(true)
	var old_walk: ImageTexture = dock.canvas._walk_texture
	dock._open_geometry_transfer()
	_choose(dock._transfer_dialog, [0])
	h.check("有效预览允许确认", dock._transfer_dialog.get_ok_button().disabled, false)
	dock._transfer_dialog._confirm_transfer()
	var after: Dictionary = dock.model.data.duplicate(true)
	h.check("确认只移除明确勾选的墙", dock.model.walls(), [[250, 120, 35, 20]])
	h.check("确认生成物件局部碰撞", dock.model.actor_field(0, "collision"), [[10, 32, 60, 14]])
	h.check("确认保留世界交互区域", MapDef._actor_from(dock.model.actor_dict(0)).reach, Rect2(54, 82, 92, 36))
	h.check("确认保持原遮挡基线", dock.model.actor_cover_y(0), 100.0)
	h.check("确认标记未保存布局", dock.model.dirty, true)
	h.check("确认仅产生一整步历史", dock.model._history.size(), 2)
	h.check("确认保留目标选择", dock.canvas.selected_actors(), [0])
	h.check("确认刷新检查器目标", dock._panel_index, 0)
	h.check("确认刷新场景树目标", dock._hierarchy_actor_items.has(0), true)
	h.check("确认使画布与可走格定义重建", dock.canvas._map_def() == old_definition, false)
	h.check("确认重新计算已显示的可走格", dock.canvas._walk_texture == old_walk, false)
	h.check("状态明确尚未保存", dock._status.text.contains("尚未保存"), true)
	dock._object_command("undo")
	h.check("一次撤销恢复全部迁移数据", dock.model.data, before)
	h.check("撤回保存状态后不标脏", dock.model.dirty, false)
	dock._object_command("redo")
	h.check("一次重做恢复全部迁移数据", dock.model.data, after)
	h.check("重做仍为未保存布局", dock.model.dirty, true)
	dock.free()


static func test_auto_baseline(h: TestHarness) -> void:
	var dock := _dock()
	dock._open_geometry_transfer()
	var dialog = dock._transfer_dialog
	_choose(dialog, [0])
	dialog._preserve_sort.button_pressed = false
	h.check("取消保持后预览自动上边缘", dialog._plan.get("after_baseline"), 72.0)
	h.check("取消保持后显示基线变化", dialog._preview.text.contains("%s → %s" % [100.0, 72.0]), true)
	h.check("基线预览不标脏", dock.model.dirty, false)
	dialog._confirm_transfer()
	h.check("确认采用自动碰撞上边缘", dock.model.actor_cover_y(0), 72.0)
	h.check("自动模式不保留手动排序偏移", dock.model.actor_dict(0).has("sort_offset"), false)
	dock.free()


static func test_existing_geometry(h: TestHarness) -> void:
	for existing: String in ["collision", "solid"]:
		var dock := _dock()
		dock.model.data["actors"][0][existing] = [[1, 2, 10, 15]] if existing == "collision" else true
		dock.model.data["actors"][0]["cover"] = false
		var old_actor: MapDef.Actor = MapDef._actor_from(dock.model.actor_dict(0))
		dock._open_geometry_transfer()
		var dialog = dock._transfer_dialog
		_choose(dialog, [0])
		h.check("%s迁移预览包含原有有效碰撞" % existing, dialog._preview.text.contains("目标有效碰撞：1 → 2"), true)
		h.check("%s迁移预览单独列出新增墙局部坐标" % existing, dialog._preview.text.contains("墙 #0 → 局部矩形 " + str([10, 32, 60, 14])), true)
		dialog._confirm_transfer()
		var new_actor: MapDef.Actor = MapDef._actor_from(dock.model.actor_dict(0))
		h.check("%s迁移保留原有效阻挡" % existing, new_actor.collision_rects()[0], old_actor.collision_rects()[0])
		h.check("%s迁移增加明确指定的墙" % existing, new_actor.collision_rects().size(), 2)
		h.check("%s迁移不启用原本关闭的遮挡" % existing, dock.model.actor_field(0, "cover"), false)
		if existing == "solid":
			h.check("迁移保留已有solid字段", dock.model.actor_field(0, "solid"), true)
		dock.free()


static func test_blocked_targets(h: TestHarness) -> void:
	for state: String in ["hidden", "locked", "multi", "group", "tree_multi"]:
		var dock := _dock()
		_block(dock, state)
		if state == "tree_multi":
			dock._refresh_transfer_button()
		else:
			dock._refresh_selection()
		h.check("%s目标入口禁用" % state, dock._transfer_button.disabled, true)
		dock._open_geometry_transfer()
		h.check("%s目标拒绝打开" % state, dock._transfer_dialog == null, true)
		h.check("%s目标报错可见" % state, not dock._status.text.is_empty(), true)
		h.check("%s目标不标脏" % state, dock.model.dirty, false)
		dock.free()
	for field: String in ["person", "over", "if", "duplicate_id"]:
		var dock := _dock()
		if field == "duplicate_id":
			dock.model.data["actors"][1]["id"] = "desk"
		elif field == "if":
			dock.model.data["actors"][0][field] = {"flag": "blocked"}
		else:
			dock.model.data["actors"][0][field] = true
		dock._open_geometry_transfer()
		_choose(dock._transfer_dialog, [0])
		h.check("%s不安全目标禁止确认" % field, dock._transfer_dialog.get_ok_button().disabled, true)
		h.check("%s不安全目标显示错误" % field, dock._transfer_dialog._preview.text.contains("错误："), true)
		dock._transfer_dialog._confirm_transfer()
		h.check("%s不安全目标不标脏" % field, dock.model.dirty, false)
		dock.free()


static func _block(dock: Control, state: String) -> void:
	match state:
		"hidden":
			dock._hidden_actor_ids["desk"] = true
		"locked":
			dock._locked_actor_ids["desk"] = true
		"multi":
			_select(dock, [0, 1])
		"group":
			dock.model.data["editor_groups"] = [{"id": "pair", "name": "一组", "members": ["desk", "shelf"]}]
		"tree_multi":
			(dock._hierarchy_actor_items[1] as TreeItem).select(0, false)
	dock.canvas.set_actor_editor_state(dock._hidden_actor_ids, dock._locked_actor_ids)


static func test_stale_previews(h: TestHarness) -> void:
	for change: String in ["hidden", "locked", "multi", "group", "tree_multi", "selection", "id", "walls", "other_data", "map", "model"]:
		var dock := _dock()
		dock._open_geometry_transfer()
		var dialog = dock._transfer_dialog
		_choose(dialog, [0])
		match change:
			"selection":
				_select(dock, [1])
			"id":
				dock.model.data["actors"][0]["id"] = "renamed_desk"
			"walls":
				dock.model.data["walls"][0][0] = 71
			"other_data":
				dock.model.data["actors"][1]["label"] = "变动后的书架"
			"map":
				dock.model.map_id = "another_map"
			"model":
				var replacement = Model.new()
				replacement.map_id = dock.model.map_id
				replacement.data = dock.model.data.duplicate(true)
				replacement.reset_history()
				dock.model = replacement
			_:
				_block(dock, change)
		var before: Dictionary = dock.model.data.duplicate(true)
		dialog._confirm_transfer()
		h.check("%s变化使确认失效" % change, dialog.get_ok_button().disabled, true)
		h.check("%s失效错误可见" % change, dialog._preview.text.contains("错误："), true)
		h.check("%s失效确认不应用" % change, dock.model.data, before)
		h.check("%s失效确认不标脏" % change, dock.model.dirty, false)
		h.check("%s失效确认不写历史" % change, dock.model._history.size(), 1)
		dock.free()


static func test_layout(h: TestHarness) -> void:
	var dock := _dock()
	dock._open_geometry_transfer()
	var dialog = dock._transfer_dialog
	h.check("助手使用独立确认窗口", dialog is ConfirmationDialog, true)
	h.check("入口为独立小按钮", dock._transfer_button.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN)
	h.check("旧墙列表允许滚动分配空间", dialog._wall_list.size_flags_vertical, Control.SIZE_EXPAND_FILL)
	h.check("预览区域启用滚动", dialog._preview.scroll_active, true)
	h.check("预览不以内容撑高窗口", dialog._preview.fit_content, false)
	h.check("预览小窗口自动换行", dialog._preview.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	h.check("目标名称小窗口自动换行", dialog._target_label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	h.check("列表不固定大窗口宽度", dialog._wall_list.custom_minimum_size.x, 0.0)
	h.check("窗口最小尺寸适配小屏", dialog.min_size.x <= 320 and dialog.min_size.y <= 360, true)
	h.check("失效确认窗口保持可见供查看错误", dialog.dialog_hide_on_ok, false)
	dialog._prepare_popup_layout(Vector2i(620, 560))
	h.check("首次弹出前已为换行标题分配宽度", dialog._target_label.size.x, 588.0)
	h.check("首次弹出前内容最小高度不撑破560窗口", dialog._content.get_combined_minimum_size().y <= 480.0, true)
	h.check("首次布局仍为列表与预览保留滚动最小高度", dialog._wall_list.custom_minimum_size.y + dialog._preview.custom_minimum_size.y, 144.0)
	dialog._prepare_popup_layout(Vector2i(360, 520))
	h.check("小窗口重新按可用宽度计算换行", dialog._target_label.size.x, 328.0)
	h.check("小窗口内容最小高度仍可放入", dialog._content.get_combined_minimum_size().y <= 440.0, true)
	dock.free()
