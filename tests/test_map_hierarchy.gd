extends RefCounted

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


static func fixture() -> Dictionary:
	var actors: Array[Dictionary] = []
	for index: int in 6:
		actors.append({"id": "object_%d" % index, "label": "物件 %d" % index,
			"rect": [20 + index * 45, 40, 30, 50], "decor": true})
	return {"id": "hierarchy_test", "size": [400, 300], "walls": [], "actors": actors,
		"editor_groups": [
			{"id": "reading", "name": "阅读区", "members": ["object_1", "object_2"]},
			{"id": "storage", "name": "储物区", "members": ["object_4", "object_5"]}]}


static func run(h: TestHarness) -> void:
	var dock = Dock.new()
	dock._editor_state_path = "user://map_hierarchy_test_%d.cfg" % Time.get_ticks_usec()
	dock._build()
	_reset(dock)
	test_structure(h, dock)
	test_selection(h, dock)
	_reset(dock)
	test_visibility_and_lock(h, dock)
	_reset(dock)
	test_group_rename(h, dock)
	_reset(dock)
	test_locked_group_rename(h, dock)
	_reset(dock)
	test_frame_selection(h, dock)
	if FileAccess.file_exists(dock._editor_state_path):
		h.check("层级测试清理独立状态文件",
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dock._editor_state_path)), OK)
	dock.free()


static func _reset(dock: Control) -> void:
	dock.model = Model.new()
	dock.model.map_id = "hierarchy_test"
	dock.model.data = fixture()
	dock.model.reset_history()
	dock._hidden_actor_ids.clear()
	dock._locked_actor_ids.clear()
	dock.canvas.set_actor_editor_state({}, {})
	dock.canvas.load_map(dock.model, "", "", dock.model.map_size())
	dock._refresh_selection()


static func _find(tree: Tree, kind: String, identity: Variant) -> TreeItem:
	var pending: Array[TreeItem] = [tree.get_root()]
	while not pending.is_empty():
		var item: TreeItem = pending.pop_back()
		if item == null:
			continue
		var metadata: Variant = item.get_metadata(0)
		if metadata is Dictionary and str(metadata.get("kind", "")) == kind:
			if metadata.get("id" if kind == "group" else "index") == identity:
				return item
		var child := item.get_first_child()
		while child != null:
			pending.append(child)
			child = child.get_next()
	return null


static func _choose(dock: Control, actors: Array[int], groups: Array[String]) -> void:
	dock._object_tree.deselect_all()
	for index: int in actors:
		_find(dock._object_tree, "actor", index).select(0)
	for group_id: String in groups:
		_find(dock._object_tree, "group", group_id).select(0)
	dock._on_hierarchy_item_selected()


static func _selected(dock: Control) -> Array[int]:
	var indices: Array[int] = dock.canvas.selected_actors()
	indices.sort()
	return indices


static func _rename(dock: Control, group_id: String, requested_name: String) -> void:
	var item := _find(dock._object_tree, "group", group_id)
	item.set_text(0, requested_name)
	dock._on_hierarchy_item_edited(item)


static func test_structure(h: TestHarness, dock: Control) -> void:
	var tree: Tree = dock._object_tree
	h.check("层级树使用多选模式", tree.select_mode, Tree.SELECT_MULTI)
	h.check("层级树隐藏辅助根节点", tree.hide_root, true)
	var root := tree.get_root()
	h.check("顶层只有未编组物件和组", root.get_child_count(), 4)
	for index: int in [0, 3]:
		var actor_item := _find(tree, "actor", index)
		h.check("未编组物件%d位于顶层" % index, actor_item.get_parent(), root)
		h.check("物件%d保留模型下标" % index, actor_item.get_metadata(0),
			{"kind": "actor", "index": index, "id": str(dock.model.actor_field(index, "id", ""))})
	for group_id: String in ["reading", "storage"]:
		var group := _find(tree, "group", group_id)
		h.check("组%s位于顶层" % group_id, group.get_parent(), root)
		h.check("组%s保留稳定ID" % group_id, group.get_metadata(0).get("id"), group_id)
		h.check("组%s有两名成员" % group_id, group.get_child_count(), 2)
		h.check("组%s可编辑名称" % group_id, group.is_editable(0), true)
	for index: int in [1, 2, 4, 5]:
		var actor_item := _find(tree, "actor", index)
		var group_id := "reading" if index < 3 else "storage"
		h.check("成员%d只出现在所属组下" % index,
			actor_item.get_parent().get_metadata(0).get("id"), group_id)
		h.check("成员%d不通过树直接改名" % index, actor_item.is_editable(0), false)
	var group := _find(tree, "group", "reading")
	group.collapsed = true
	var previous_id := group.get_instance_id()
	dock._refresh_objects()
	group = _find(tree, "group", "reading")
	h.check("普通刷新不重建组节点", group.get_instance_id(), previous_id)
	h.check("普通刷新保留折叠", group.collapsed, true)
	h.check("构建层级不弄脏地图", dock.model.dirty, false)


static func test_selection(h: TestHarness, dock: Control) -> void:
	_choose(dock, [0, 3], [])
	h.check("树中多选未编组物件同步画布", _selected(dock), [0, 3])
	h.check("树多选打开物件检查器", dock._panel_scroll.visible, true)
	h.check("检查器主物件来自当前多选", [0, 3].has(dock._panel_index), true)
	_choose(dock, [], ["reading"])
	h.check("选中组父节点选择全体成员", _selected(dock), [1, 2])
	h.check("选中组后隐藏按钮可用", dock._hide_selected_button.disabled, false)
	h.check("选中组后解组按钮可用", dock._ungroup_button.disabled, false)
	h.check("选中单个完整组不可重复编组", dock._group_button.disabled, true)
	_choose(dock, [1], [])
	h.check("选中成员会展开整组选择", _selected(dock), [1, 2])
	h.check("树同步选中另一组员", _find(dock._object_tree, "actor", 2).is_selected(0), true)
	_choose(dock, [0], ["reading", "storage"])
	h.check("组与未编组物件能混合多选", _selected(dock), [0, 1, 2, 4, 5])
	h.check("多组选中可编为新组", dock._group_button.disabled, false)
	var canvas_selection: Array[int] = [3]
	dock.canvas.select_actors(canvas_selection)
	dock.canvas.selection_changed.emit()
	h.check("画布选择同步到树", _find(dock._object_tree, "actor", 3).is_selected(0), true)
	h.check("画布换选清除旧树选择", _find(dock._object_tree, "actor", 0).is_selected(0), false)
	h.check("画布选择同步检查器", dock._panel_index, 3)
	canvas_selection.clear()
	dock.canvas.select_actors(canvas_selection)
	dock.canvas.selection_changed.emit()
	h.check("清空画布选择禁用隐藏", dock._hide_selected_button.disabled, true)
	h.check("清空画布选择隐藏检查器", dock._panel_scroll.visible, false)
	h.check("选择操作不弄脏地图", dock.model.dirty, false)


static func test_visibility_and_lock(h: TestHarness, dock: Control) -> void:
	var original_data: String = Model.stringify(dock.model.data)
	_choose(dock, [], ["reading"])
	dock._toggle_selected_actor_visibility()
	for index: int in [1, 2]:
		h.check("组隐藏影响组员%d" % index, dock.canvas.actor_is_hidden(index), true)
		h.check("隐藏组员%d仍显示在树中" % index,
			_find(dock._object_tree, "actor", index).get_text(0).contains("隐藏"), true)
	h.check("全隐藏组切换为显示所选", dock._hide_selected_button.text, "显示所选")
	_choose(dock, [0], ["reading"])
	h.check("混合可见选区按钮仍为隐藏所选", dock._hide_selected_button.text, "隐藏所选")
	dock._toggle_selected_actor_visibility()
	h.check("混合可见选区隐藏全部", dock.canvas.actor_is_hidden(0), true)
	dock._show_all_actors()
	h.check("全部显示清空本图隐藏状态", dock._hidden_actor_ids, {})
	h.check("全部显示后按钮禁用", dock._show_all_button.disabled, true)
	_choose(dock, [], ["reading"])
	dock._toggle_selected_actor_lock()
	for index: int in [1, 2]:
		h.check("组锁定影响组员%d" % index, dock.canvas.actor_is_locked(index), true)
		h.check("树保留组员%d锁定标记" % index,
			_find(dock._object_tree, "actor", index).get_text(0).contains("锁定"), true)
	h.check("锁定组按钮切换为解锁所选", dock._lock_selected_button.text, "解锁所选")
	h.check("锁定组禁用解组", dock._ungroup_button.disabled, true)
	h.check("锁定组检查器只读", dock._panel_locked, true)
	h.check("锁定组禁止树编辑组名", _find(dock._object_tree, "group", "reading").is_editable(0), false)
	_choose(dock, [0], ["reading"])
	h.check("混合锁定选区按钮仍为锁定所选", dock._lock_selected_button.text, "锁定所选")
	dock._toggle_selected_actor_lock()
	h.check("混合锁定选区锁定全部", dock.canvas.actor_is_locked(0), true)
	dock._toggle_selected_actor_lock()
	h.check("再次切换解锁全部", dock._locked_actor_ids, {})
	h.check("解锁组恢复树编辑", _find(dock._object_tree, "group", "reading").is_editable(0), true)
	h.check("树的隐藏锁定不修改地图数据", Model.stringify(dock.model.data), original_data)
	h.check("树的隐藏锁定不弄脏地图", dock.model.dirty, false)


static func test_group_rename(h: TestHarness, dock: Control) -> void:
	_choose(dock, [], ["reading"])
	var original_members: Array = dock.model.editor_groups()[0]["members"].duplicate()
	_rename(dock, "reading", "  新阅读区  ")
	var renamed := _find(dock._object_tree, "group", "reading")
	h.check("树编辑调用模型改名并去首尾空格", dock.model.editor_groups()[0]["name"], "新阅读区")
	h.check("改名保留组稳定ID", dock.model.editor_groups()[0]["id"], "reading")
	h.check("改名保留所有成员", dock.model.editor_groups()[0]["members"], original_members)
	h.check("改名同步树元数据", renamed.get_metadata(0).get("name"), "新阅读区")
	h.check("改名后保留画布选区", _selected(dock), [1, 2])
	h.check("改名标记未保存", dock.model.dirty, true)
	dock._object_command("undo")
	h.check("组名编辑可撤销", dock.model.editor_groups()[0]["name"], "阅读区")
	h.check("撤销同步树组名", _find(dock._object_tree, "group", "reading").get_metadata(0).get("name"), "阅读区")
	h.check("撤销到基线清除dirty", dock.model.dirty, false)
	dock._object_command("redo")
	h.check("组名编辑可重做", dock.model.editor_groups()[0]["name"], "新阅读区")
	h.check("重做同步树组名", _find(dock._object_tree, "group", "reading").get_metadata(0).get("name"), "新阅读区")
	dock._object_command("undo")
	for rejected_name: String in ["", "   ", "储物区"]:
		_rename(dock, "reading", rejected_name)
		h.check("树拒绝空名或重名：%s" % rejected_name, dock.model.editor_groups()[0]["name"], "阅读区")
		h.check("拒绝名字后恢复树显示：%s" % rejected_name,
			_find(dock._object_tree, "group", "reading").get_text(0).contains("阅读区"), true)
		h.check("拒绝名字不弄脏地图：%s" % rejected_name, dock.model.dirty, false)
	dock._object_command("redo")
	h.check("被拒绝的改名不破坏原重做记录", dock.model.editor_groups()[0]["name"], "新阅读区")
	dock._object_command("undo")
	_rename(dock, "reading", "阅读区")
	h.check("原名提交不弄脏地图", dock.model.dirty, false)
	dock._object_command("redo")
	h.check("原名提交不破坏重做记录", dock.model.editor_groups()[0]["name"], "新阅读区")


static func test_locked_group_rename(h: TestHarness, dock: Control) -> void:
	dock._locked_actor_ids["object_2"] = true
	dock.canvas.set_actor_editor_state({}, dock._locked_actor_ids)
	dock._refresh_objects()
	h.check("仅一个组员锁定也禁止组名编辑", _find(dock._object_tree, "group", "reading").is_editable(0), false)
	_rename(dock, "reading", "锁定时强制改名")
	h.check("回调拒绝绕过锁定的组名写入", dock.model.editor_groups()[0]["name"], "阅读区")
	h.check("锁定拒绝写入后仍不脏", dock.model.dirty, false)
	dock._locked_actor_ids.clear()
	dock._hidden_actor_ids["object_1"] = true
	dock._hidden_actor_ids["object_2"] = true
	dock.canvas.set_actor_editor_state(dock._hidden_actor_ids, {})
	dock._refresh_objects()
	h.check("隐藏组仍可编辑名称", _find(dock._object_tree, "group", "reading").is_editable(0), true)
	_rename(dock, "reading", "隐藏阅读区")
	h.check("隐藏组编辑名称成功", dock.model.editor_groups()[0]["name"], "隐藏阅读区")
	h.check("组改名保留隐藏状态", dock._hidden_actor_ids, {"object_1": true, "object_2": true})


static func test_frame_selection(h: TestHarness, dock: Control) -> void:
	dock.canvas.size = Vector2(640, 480)
	_choose(dock, [0], [])
	dock.canvas.pan = Vector2(190, 270)
	dock.canvas.zoom = 0.25
	dock._frame_selection()
	var actor_center: Vector2 = dock.model.rect_of(Model.Kind.ACTOR, 0).get_center()
	h.check("定位按钮将所选物件居中",
		dock.canvas.to_screen(actor_center).distance_to(dock.canvas.size * 0.5) < 0.01, true)
	h.check("定位按钮报告成功", dock._status.text.contains("已定位"), true)
	dock.canvas.pan = Vector2(90, 130)
	dock.canvas.zoom = 0.5
	_find(dock._object_tree, "actor", 0).select(0)
	h.check("物件激活测试当前游标在物件", dock._object_tree.get_selected().get_metadata(0).get("kind"), "actor")
	dock._on_hierarchy_item_activated()
	h.check("双击物件树项定位物件",
		dock.canvas.to_screen(actor_center).distance_to(dock.canvas.size * 0.5) < 0.01, true)
	dock._hidden_actor_ids["object_1"] = true
	dock._hidden_actor_ids["object_2"] = true
	dock.canvas.set_actor_editor_state(dock._hidden_actor_ids, {})
	_choose(dock, [], ["reading"])
	dock.canvas.pan = Vector2(321, 88)
	dock.canvas.zoom = 2.0
	dock._frame_selection()
	h.check("全隐藏组定位保留平移", dock.canvas.pan, Vector2(321, 88))
	h.check("全隐藏组定位保留缩放", dock.canvas.zoom, 2.0)
	h.check("全隐藏组定位提示先显示", dock._status.text.contains("隐藏"), true)
	dock._hidden_actor_ids.clear()
	dock._locked_actor_ids["object_0"] = true
	dock.canvas.set_actor_editor_state({}, dock._locked_actor_ids)
	_choose(dock, [0], [])
	dock._frame_selection()
	h.check("锁定物件仍可定位",
		dock.canvas.to_screen(actor_center).distance_to(dock.canvas.size * 0.5) < 0.01, true)
	dock._object_tree.deselect_all()
	_find(dock._object_tree, "group", "reading").select(0)
	h.check("组激活测试当前游标在组", dock._object_tree.get_selected().get_metadata(0).get("kind"), "group")
	dock.canvas.pan = Vector2(75, 95)
	dock.canvas.zoom = 0.75
	dock._on_hierarchy_item_activated()
	h.check("组双击不触发定位平移", dock.canvas.pan, Vector2(75, 95))
	h.check("组双击不触发定位缩放", dock.canvas.zoom, 0.75)
	h.check("定位不修改地图或dirty", [dock.model.data, dock.model.dirty], [fixture(), false])
