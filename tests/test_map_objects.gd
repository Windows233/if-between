extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Library := preload("res://addons/if_map_editor/map_object_library.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")


static func fixture() -> Dictionary:
	return {"id": "fixture", "size": [400, 300], "walls": [], "actors": [{
		"id": "desk", "rect": [60, 40, 80, 60], "label": "书桌", "cover": true,
		"sprite": "res://art/props/gatehouse_desk.png", "collision": [[5, 30, 70, 20]],
		"reach_local": [-6, 42, 92, 36], "sort_collider": 0, "event": "gatehouse_door"}]}


static func run(h: TestHarness) -> void:
	test_geometry(h)
	test_copy_and_history(h)
	test_groups(h)
	test_actor_layout(h)
	test_backups(h)
	test_library(h)
	test_canvas(h)
	test_frame_selection(h)
	test_editor_state(h)
	test_runtime(h)


static func test_geometry(h: TestHarness) -> void:
	var definition := MapDef.from_dictionary(fixture())
	var desk: MapDef.Actor = definition.actors[0]
	h.check("新物件碰撞由局部坐标换到世界", desk.collision_rects(), [Rect2(65, 70, 70, 20)])
	h.check("交互范围跟着物件变换", desk.reach, Rect2(54, 82, 92, 36))
	h.check("排序取碰撞上边缘", desk.effective_cover_y(), 70.0)
	desk.sort_offset = -4
	h.check("手动偏移叠加自动基线", desk.effective_cover_y(), 66.0)
	h.check("玩家脚底撞到局部碰撞", WalkGrid.is_free(definition, Vector2(90, 80)), false)
	h.check("玩家能在贴图上方站立", WalkGrid.is_free(definition, Vector2(90, 60)), true)
	h.check("局部碰撞影响导航落点", WalkGrid.has_landing_room(definition, Vector2(90, 80)), false)
	h.check("新的物件几何合法", definition.validate(), [])
	desk.sort_collider = 4
	h.check("无效排序参考不能静默保存", definition.validate().is_empty(), false)
	var legacy := MapDef._actor_from({"rect": [10, 20, 30, 40], "solid": true})
	h.check("旧地图仍取贴图底边", legacy.effective_cover_y(), 60.0)
	h.check("旧 solid 保持整块碰撞", legacy.collision_rects(), [Rect2(10, 20, 30, 40)])


static func test_copy_and_history(h: TestHarness) -> void:
	var model = Model.new()
	var selected_actor: Array[int] = [0]
	model.data = fixture()
	model.reset_history()
	model.copy_actors(selected_actor)
	var selection: Array[int] = model.paste_actors()
	model.record_history()
	h.check("复制生成新 id", model.actor_field(selection[0], "id"), "desk_2")
	h.check("复制保留剧情入口", model.actor_field(selection[0], "event"), "gatehouse_door")
	h.check("复制碰撞仍是局部值", model.actor_field(selection[0], "collision"), [[5, 30, 70, 20]])
	h.check("复制碰撞随实例移动", MapDef._actor_from(model.actor_dict(selection[0])).collision_rects(),
		[Rect2(77, 82, 70, 20)])
	model.set_rect(Model.Kind.ACTOR, 1, Rect2(100, 90, 80, 60))
	model.record_history()
	h.check("移动交互区域跟随", MapDef._actor_from(model.actor_dict(1)).reach, Rect2(94, 132, 92, 36))
	h.check("移动排序上边缘跟随", model.actor_cover_y(1), 120.0)
	h.check("移动可撤销", model.undo(), true)
	h.check("撤销恢复位置", model.rect_of(Model.Kind.ACTOR, 1).position, Vector2(72, 52))
	h.check("粘贴可撤销", model.undo(), true)
	h.check("撤销粘贴恢复对象数", model.count(Model.Kind.ACTOR), 1)
	h.check("回到载入状态不脏", model.dirty, false)
	h.check("粘贴可以重做", model.redo(), true)
	model.set_actor_cover_y(1, 88)
	model.record_history()
	h.check("新对象手调记录偏移", model.actor_field(1, "sort_offset"), 6.0)
	h.check("分叉编辑后旧重做失效", model.redo(), false)
	model.clear_actor_cover_y(1)
	h.check("恢复自动回到碰撞上边缘", model.actor_cover_y(1), 82.0)
	var legacy := {"id": "old", "rect": [1, 2, 3, 4], "reach": [0, 1, 20, 20], "cover_y": 7}
	var sources: Array[Dictionary] = [legacy]
	model.insert_actors(sources, Vector2(10, 20))
	h.check("复制旧交互范围也跟随", model.actor_field(2, "reach"), [10, 21, 20, 20])
	h.check("复制旧手动基线也跟随", model.actor_field(2, "cover_y"), 27.0)


static func test_groups(h: TestHarness) -> void:
	var model: Variant = layout_model()
	var pair: Array[int] = [0, 1]
	var one_member: Array[int] = [1]
	var first_member: Array[int] = [0]
	var copied_member: Array[int] = [3]
	var invalid_members: Array[int] = [0, 3]
	var group_name: String = model.group_actors(pair, "桌面组合")
	h.check("多选物件可编组", group_name, "桌面组合")
	model.record_history()
	h.check("组成员保存稳定物件 ID", model.editor_groups()[0].get("members"), ["desk", "chair_a"])
	h.check("选择组员扩展到整组", model.expand_group_selection(one_member), [1, 0])
	h.check("地图运行时忽略编辑器分组数据", MapDef.from_dictionary(model.data).validate(), [])
	var group_id: String = model.editor_groups()[0].get("id", "")
	h.check("组名可按稳定组 ID 重命名", model.rename_group(group_id, "书桌与椅子"), true)
	model.record_history()
	h.check("重命名保留组 ID 与成员", model.editor_groups()[0], {
		"id": group_id, "name": "书桌与椅子", "members": ["desk", "chair_a"]})
	h.check("空白组名被拒绝", model.rename_group(group_id, "  "), false)
	h.check("未知组 ID 被拒绝", model.rename_group("missing", "新组名"), false)
	var conflict_model: Variant = layout_model()
	conflict_model.data["actors"].append({"id": "chair_c", "rect": [330, 40, 30, 25]})
	var conflict_first: Array[int] = [0, 1]
	var conflict_second: Array[int] = [2, 3]
	conflict_model.group_actors(conflict_first, "第一组")
	conflict_model.group_actors(conflict_second, "其他组")
	conflict_model.reset_history()
	conflict_model.dirty = false
	var conflict_before: String = Model.stringify(conflict_model.data)
	h.check("重复组名被拒绝", conflict_model.rename_group(
		str(conflict_model.editor_groups()[0].get("id", "")), "其他组"), false)
	h.check("组名冲突不修改地图", Model.stringify(conflict_model.data), conflict_before)
	h.check("组名冲突不产生未保存变更", conflict_model.dirty, false)
	h.check("同名提交可保持现状", conflict_model.rename_group(
		str(conflict_model.editor_groups()[0].get("id", "")), "第一组"), true)
	h.check("同名提交不产生未保存变更", conflict_model.dirty, false)
	h.check("重命名被拒绝时组数据不变", model.editor_groups()[0].get("name"), "书桌与椅子")
	h.check("组名可以撤销", model.undo(), true)
	h.check("撤销恢复旧组名", model.editor_groups()[0].get("name"), "桌面组合")
	h.check("组名可以重做", model.redo(), true)
	h.check("重做恢复新组名", model.editor_groups()[0].get("name"), "书桌与椅子")
	model.undo()
	var invalid_model: Variant = layout_model()
	invalid_model.data["actors"].append({"id": "desk", "rect": [5, 5, 10, 10]})
	h.check("重复物件 ID 不允许编组", invalid_model.group_actors(invalid_members), "")
	var canvas = Canvas.new()
	canvas.model = model
	canvas.zoom = 1.0
	canvas.pan = Vector2.ZERO
	canvas.edited.connect(model.record_history)
	canvas._press(Vector2(70, 100))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(80, 110)
	canvas._gui_input(motion)
	canvas._release()
	h.check("拖动组员会整体移动", [model.rect_of(Model.Kind.ACTOR, 0).position,
		model.rect_of(Model.Kind.ACTOR, 1).position], [Vector2(70, 50), Vector2(180, 30)])
	canvas.free()
	h.check("整组拖动作为一次撤销", model.undo(), true)
	h.check("撤销移动后组员各自回位", [model.rect_of(Model.Kind.ACTOR, 0).position,
		model.rect_of(Model.Kind.ACTOR, 1).position], [Vector2(60, 40), Vector2(170, 20)])
	h.check("撤销移动仍保留组关系", model.group_name_for_actor(0), "桌面组合")
	h.check("编组操作可撤销", model.undo(), true)
	h.check("撤销会清除组关系", model.editor_groups().size(), 0)
	h.check("编组操作可重做", model.redo(), true)
	h.check("编组重做后恢复原组名", model.group_name_for_actor(0), "桌面组合")
	model.copy_actors(first_member)
	var pasted: Array[int] = model.paste_actors()
	model.record_history()
	h.check("复制组内单个物件会复制完整组", pasted, [3, 4])
	h.check("复制组获得独立组名", model.group_name_for_actor(3), "桌面组合 副本")
	h.check("复制组成员互不引用原组", model.group_members_for_actor(4), [3, 4])
	var serialized: Variant = JSON.parse_string(Model.stringify(model.data))
	h.check("组元数据随地图 JSON 保存", serialized.get("editor_groups"), model.editor_groups())
	var target: Dictionary = {}
	Model.copy_layout(model.data, target)
	h.check("跨地布局复制保留编组", target.get("editor_groups"), model.editor_groups())
	h.check("整组复制可撤销", model.undo(), true)
	h.check("撤销组复制恢复对象数", model.count(Model.Kind.ACTOR), 3)
	h.check("整组复制可重做", model.redo(), true)
	h.check("解组不删除物件", model.ungroup_actors(copied_member), 1)
	model.record_history()
	h.check("解组后物件仍存在", model.count(Model.Kind.ACTOR), 5)
	h.check("解组记录可撤销", model.undo(), true)
	h.check("撤销恢复组关系", model.group_name_for_actor(3), "桌面组合 副本")
	model.remove_at(Model.Kind.ACTOR, 4)
	h.check("删除成员会清除只剩单件的组", model.group_name_for_actor(3), "")
	h.check("删除成员保留另一组", model.group_name_for_actor(0), "桌面组合")


static func layout_model() -> Variant:
	var model = Model.new()
	model.data = fixture()
	var actors: Array = model.data["actors"]
	actors.append({"id": "chair_a", "label": "椅子", "rect": [170, 20, 40, 20]})
	actors.append({"id": "chair_b", "label": "椅子", "rect": [250, 160, 60, 40]})
	model.reset_history()
	return model


static func test_actor_layout(h: TestHarness) -> void:
	var model = layout_model()
	var selected: Array[int] = [0, 1, 2]
	var single: Array[int] = [0]
	var pair: Array[int] = [0, 1]
	h.check("单物件不能批量对齐", model.align_actors(single, Model.ActorAlignment.LEFT), false)
	h.check("左对齐可执行", model.align_actors(selected, Model.ActorAlignment.LEFT), true)
	model.record_history()
	h.check("左对齐统一左边缘", [model.rect_of(Model.Kind.ACTOR, 0).position.x,
		model.rect_of(Model.Kind.ACTOR, 1).position.x, model.rect_of(Model.Kind.ACTOR, 2).position.x], [60.0, 60.0, 60.0])
	h.check("对齐随物件移动局部碰撞", MapDef._actor_from(model.actor_dict(0)).collision_rects(),
		[Rect2(65, 70, 70, 20)])
	h.check("对齐作为一次撤销", model.undo(), true)
	h.check("撤销完整还原所有物件位置", [model.rect_of(Model.Kind.ACTOR, 0).position.x,
		model.rect_of(Model.Kind.ACTOR, 1).position.x, model.rect_of(Model.Kind.ACTOR, 2).position.x],
		[60.0, 170.0, 250.0])
	h.check("对齐可以重做", model.redo(), true)
	model = layout_model()
	h.check("水平居中可执行", model.align_actors(selected, Model.ActorAlignment.CENTER_X), true)
	h.check("水平居中对齐物件中心", [model.rect_of(Model.Kind.ACTOR, 0).get_center().x,
		model.rect_of(Model.Kind.ACTOR, 1).get_center().x, model.rect_of(Model.Kind.ACTOR, 2).get_center().x],
		[185.0, 185.0, 185.0])
	h.check("对齐移动后局部碰撞随实例", MapDef._actor_from(model.actor_dict(0)).collision_rects(),
		[Rect2(150, 70, 70, 20)])
	model = layout_model()
	h.check("右对齐可执行", model.align_actors(selected, Model.ActorAlignment.RIGHT), true)
	h.check("右对齐统一右边缘", [model.rect_of(Model.Kind.ACTOR, 0).end.x,
		model.rect_of(Model.Kind.ACTOR, 1).end.x, model.rect_of(Model.Kind.ACTOR, 2).end.x], [310.0, 310.0, 310.0])
	model = layout_model()
	h.check("顶对齐可执行", model.align_actors(selected, Model.ActorAlignment.TOP), true)
	h.check("顶对齐统一上边缘", [model.rect_of(Model.Kind.ACTOR, 0).position.y,
		model.rect_of(Model.Kind.ACTOR, 1).position.y, model.rect_of(Model.Kind.ACTOR, 2).position.y], [20.0, 20.0, 20.0])
	model = layout_model()
	h.check("垂直居中可执行", model.align_actors(selected, Model.ActorAlignment.CENTER_Y), true)
	h.check("垂直居中对齐物件中心", [model.rect_of(Model.Kind.ACTOR, 0).get_center().y,
		model.rect_of(Model.Kind.ACTOR, 1).get_center().y, model.rect_of(Model.Kind.ACTOR, 2).get_center().y],
		[110.0, 110.0, 110.0])
	model = layout_model()
	h.check("底对齐可执行", model.align_actors(selected, Model.ActorAlignment.BOTTOM), true)
	h.check("底对齐统一下边缘", [model.rect_of(Model.Kind.ACTOR, 0).end.y,
		model.rect_of(Model.Kind.ACTOR, 1).end.y, model.rect_of(Model.Kind.ACTOR, 2).end.y], [200.0, 200.0, 200.0])

	var horizontal_model = layout_model()
	h.check("两件物件不能等间距", horizontal_model.distribute_actors(pair, Model.DistributionAxis.HORIZONTAL), false)
	h.check("水平等间距可执行", horizontal_model.distribute_actors(selected, Model.DistributionAxis.HORIZONTAL), true)
	h.check("不同宽度物件之间边缘等间距", [horizontal_model.rect_of(Model.Kind.ACTOR, 1).position.x -
		horizontal_model.rect_of(Model.Kind.ACTOR, 0).end.x,
		horizontal_model.rect_of(Model.Kind.ACTOR, 2).position.x -
		horizontal_model.rect_of(Model.Kind.ACTOR, 1).end.x], [35.0, 35.0])
	horizontal_model.record_history()
	h.check("水平排布整体撤销", horizontal_model.undo(), true)
	h.check("撤销恢复排布前位置", horizontal_model.rect_of(Model.Kind.ACTOR, 1).position.x, 170.0)
	h.check("水平排布整体重做", horizontal_model.redo(), true)

	var vertical_model = layout_model()
	h.check("垂直等间距可执行", vertical_model.distribute_actors(selected, Model.DistributionAxis.VERTICAL), true)
	h.check("不同高度物件之间边缘等间距", [vertical_model.rect_of(Model.Kind.ACTOR, 0).position.y -
		vertical_model.rect_of(Model.Kind.ACTOR, 1).end.y,
		vertical_model.rect_of(Model.Kind.ACTOR, 2).position.y -
		vertical_model.rect_of(Model.Kind.ACTOR, 0).end.y], [30.0, 30.0])


static func test_library(h: TestHarness) -> void:
	var library = Library.new()
	library.directory = "user://test_map_objects_%d" % Time.get_ticks_usec()
	var model = Model.new()
	model.data = fixture()
	h.check("模板能保存", library.save_template("desk", model.actor_dict(0)), OK)
	h.check("模板不会覆盖同名文件", library.save_template("desk", model.actor_dict(0)), ERR_ALREADY_EXISTS)
	h.check("模板名拒绝路径穿越", library.save_template("../bad", model.actor_dict(0)), ERR_INVALID_PARAMETER)
	h.check("模板能列出", library.list_templates(), ["desk"])
	var selected: Array[int] = library.instantiate("desk", model, Vector2(200, 100))
	h.check("模板能放置实例", selected.size(), 1)
	h.check("模板按目标位置放置", model.rect_of(Model.Kind.ACTOR, selected[0]).position, Vector2(200, 100))
	h.check("模板带出碰撞并正确排序", model.actor_cover_y(selected[0]), 130.0)
	h.check("修改实例不会修改源对象", model.actor_field(0, "id"), "desk")
	DirAccess.remove_absolute(library.directory.path_join("desk.json"))
	DirAccess.remove_absolute(library.directory)


static func test_backups(h: TestHarness) -> void:
	var root := OS.get_environment("TEMP").path_join("if_map_editor_backup_test_%d" % Time.get_ticks_usec())
	var backup_root := root.path_join("backups")
	var map_path := root.path_join("fixture.json")
	DirAccess.make_dir_recursive_absolute(root)
	var original := fixture()
	var source := FileAccess.open(map_path, FileAccess.WRITE)
	source.store_string(Model.stringify(original))
	source.close()
	var model = Model.new()
	model.map_id = "fixture"
	model.path = "res://data/maps/fixture.json"
	model.data = original.duplicate(true)
	model.backup_store.directory = backup_root
	model.data["size"] = [420, 300]
	model.reset_history()
	h.check("覆盖前先成功创建快照", model.save_to(map_path), OK)
	var snapshots: Array[String] = model.backup_store.list_snapshots("fixture")
	h.check("快照按地图列出", snapshots.size(), 1)
	var first_snapshot := snapshots[0]
	h.check("快照保留原地图内容", Model.stringify(model.backup_store.read_snapshot("fixture", first_snapshot)),
		Model.stringify(original))
	model.reset_history()
	model.data["size"] = [400, 300]
	model.record_history()
	h.check("恢复快照载入成功", model.restore_backup(first_snapshot), OK)
	h.check("恢复内容一致", Model.stringify(model.data), Model.stringify(original))
	h.check("恢复后仍标记未保存", model.dirty, true)
	h.check("恢复操作可撤销", model.undo(), true)
	h.check("恢复操作可重做", model.redo(), true)
	for _index: int in 21:
		model.backup_store.create_snapshot("fixture", map_path)
	snapshots = model.backup_store.list_snapshots("fixture")
	h.check("快照数量限制为 20", snapshots.size(), 20)
	h.check("超量时优先删除最旧快照", snapshots.has(first_snapshot), false)
	var unbackable_path := root.path_join("invalid map id.json")
	var unbackable_file := FileAccess.open(unbackable_path, FileAccess.WRITE)
	unbackable_file.store_string("keep")
	unbackable_file.close()
	var unbackable_text := FileAccess.get_file_as_string(unbackable_path)
	h.check("无法创建安全备份时取消覆盖", model.save_to(unbackable_path), ERR_CANT_CREATE)
	h.check("备份失败保留原地图文件", FileAccess.get_file_as_string(unbackable_path), unbackable_text)
	h.check("界面能区分备份失败", model.last_backup_failed, true)
	var snapshot_dir := backup_root.path_join("fixture")
	for name: String in snapshots:
		DirAccess.remove_absolute(snapshot_dir.path_join(name))
	DirAccess.remove_absolute(snapshot_dir)
	DirAccess.remove_absolute(backup_root)
	DirAccess.remove_absolute(map_path)
	DirAccess.remove_absolute(unbackable_path)
	DirAccess.remove_absolute(root)


static func test_canvas(h: TestHarness) -> void:
	var model = Model.new()
	var selected_actor: Array[int] = [0]
	var selected_pair: Array[int] = [0, 1]
	model.data = fixture()
	model.copy_actors(selected_actor)
	model.paste_actors()
	var canvas = Canvas.new()
	canvas.model = model
	canvas.zoom = 1
	canvas.pan = Vector2.ZERO
	canvas.select_actors(selected_pair)
	h.check("支持多个物件选择", canvas.selected_actors(), [0, 1])
	canvas.tool = Canvas.Tool.COLLISION
	canvas.select_actors(selected_actor)
	canvas._press(Vector2(70, 65))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(90, 75)
	canvas._gui_input(motion)
	canvas._release()
	h.check("画布画出的碰撞写成局部坐标", model.actor_field(0, "collision"),
		[[5, 30, 70, 20], [10, 25, 20, 10]])
	canvas.free()


static func test_frame_selection(h: TestHarness) -> void:
	var model = layout_model()
	var canvas = Canvas.new()
	canvas.model = model
	canvas.size = Vector2(700, 500)
	canvas.map_size = model.map_size()
	var before: String = Model.stringify(model.data)
	h.check("没有选中项时定位失败", canvas.frame_selection(), false)
	var selected: Array[int] = [0, 1]
	canvas.select_actors(selected)
	h.check("多选物件可定位", canvas.frame_selection(), true)
	var bounds: Rect2 = model.rect_of(Model.Kind.ACTOR, 0) \
		.merge(model.interaction_rect_of(0)) \
		.merge(model.rect_of(Model.Kind.ACTOR, 1)) \
		.merge(model.interaction_rect_of(1))
	h.check("定位把选区中心放到画布中心", canvas.to_screen(bounds.get_center()), canvas.size * 0.5)
	h.check("定位后两个物件都在画布内", Rect2(Vector2.ZERO, canvas.size).encloses(
		Rect2(canvas.to_screen(bounds.position), bounds.size * canvas.zoom)), true)
	var position_before: Vector2 = canvas.pan
	var zoom_before: float = canvas.zoom
	canvas._on_viewport_resized()
	h.check("定位后不被自动适配重置", [canvas.pan, canvas.zoom], [position_before, zoom_before])
	canvas.set_actor_editor_state({"desk": true, "chair_a": true}, {})
	h.check("全隐藏的选区不定位", canvas.frame_selection(), false)
	h.check("失败定位保留视角", [canvas.pan, canvas.zoom], [position_before, zoom_before])
	canvas.set_actor_editor_state({}, {"desk": true})
	canvas.show_actors = false
	h.check("关闭的物件图层不定位", canvas.frame_selection(), false)
	canvas.show_actors = true
	h.check("锁定物件仍可定位", canvas.frame_selection(), true)
	var focus_key := InputEventKey.new()
	focus_key.keycode = KEY_F
	focus_key.pressed = true
	canvas.pan = Vector2(-1000, -2000)
	canvas._gui_input(focus_key)
	h.check("F快捷键定位当前选区", canvas.to_screen(bounds.get_center()), canvas.size * 0.5)
	canvas._drag_mode = 1
	h.check("拖动期间不改变定位视角", canvas.frame_selection(), false)
	canvas._drag_mode = 0
	canvas.sel_kind = Model.Kind.SPAWN
	canvas.sel_index = 0
	h.check("无效出生点不定位", canvas.frame_selection(), false)
	model.data["spawns"] = {"entry": [100, 120]}
	h.check("出生点可定位", canvas.frame_selection(), true)
	h.check("出生点定位到中心", canvas.to_screen(Vector2(100, 120)), canvas.size * 0.5)
	model.data.erase("spawns")
	h.check("定位不修改地图数据", Model.stringify(model.data), before)
	h.check("定位不增加未保存状态", model.dirty, false)
	canvas.free()


static func test_editor_state(h: TestHarness) -> void:
	var model = Model.new()
	model.data = fixture()
	model.reset_history()
	var original_data: Dictionary = model.data.duplicate(true)
	var original_text: String = Model.stringify(model.data)
	var original_dirty: bool = model.dirty
	var selected_actor: Array[int] = [0]
	var canvas = Canvas.new()
	canvas.model = model
	canvas.zoom = 1.0
	canvas.pan = Vector2.ZERO
	var motion := InputEventMouseMotion.new()
	var actor_point := Vector2(100, 100)
	var cover_point := Vector2(100, 70)
	var handle_point := Vector2(54, 82)
	var edit_attempts: Array[Dictionary] = [
		{"name": "移动", "tool": Canvas.Tool.SELECT,
			"start": actor_point, "end": Vector2(120, 80)},
		{"name": "改尺寸", "tool": Canvas.Tool.SELECT,
			"start": handle_point, "end": Vector2(80, 50)},
		{"name": "拉基线", "tool": Canvas.Tool.BASELINE,
			"start": actor_point, "end": Vector2(100, 120)},
		{"name": "画碰撞", "tool": Canvas.Tool.COLLISION,
			"start": Vector2(70, 65), "end": Vector2(90, 75)},
	]
	canvas.select_actors(selected_actor)
	h.check("未受限物件可拾取", canvas._hit_item(actor_point), Vector2i(Model.Kind.ACTOR, 0))
	h.check("未受限物件可命中尺寸手柄", canvas._hit_handle(handle_point), 0)
	h.check("未受限物件可命中遮挡基线", canvas._hit_cover_actor(cover_point), 0)
	for state_name: String in ["隐藏", "锁定"]:
		canvas.set_actor_editor_state({"desk": true} if state_name == "隐藏" else {},
			{"desk": true} if state_name == "锁定" else {})
		h.check("%s状态按物件ID生效" % state_name,
			[canvas.actor_is_hidden(0), canvas.actor_is_locked(0)],
			[state_name == "隐藏", state_name == "锁定"])
		h.check("%s物件不可拾取" % state_name, canvas._hit_item(actor_point), Vector2i(-1, -1))
		canvas.tool = Canvas.Tool.SELECT
		canvas.select_actors(selected_actor)
		h.check("%s物件不能命中尺寸手柄" % state_name, canvas._hit_handle(handle_point), -1)
		h.check("%s物件不能命中遮挡基线" % state_name, canvas._hit_cover_actor(cover_point), -1)
		for attempt: Dictionary in edit_attempts:
			canvas.tool = attempt["tool"]
			canvas.select_actors(selected_actor)
			var start: Vector2 = cover_point if attempt["name"] == "拉基线" else attempt["start"]
			canvas._press(start)
			h.check("%s物件阻止%s起手" % [state_name, attempt["name"]], canvas._drag_mode, 0)
			motion.position = attempt["end"]
			canvas._gui_input(motion)
			canvas._release()
			h.check("%s物件拒绝%s后数据不变" % [state_name, attempt["name"]],
				model.data, original_data)
		h.check("%s不污染地图JSON" % state_name, Model.stringify(model.data), original_text)
		h.check("%s及被拒绝的操作不改变dirty" % state_name, model.dirty, original_dirty)
		var definition := MapDef.from_dictionary(JSON.parse_string(Model.stringify(model.data)))
		h.check("%s后存盘仍保留物件" % state_name, definition.actors.size(), 1)
		h.check("%s后运行时仍有脚底碰撞" % state_name,
			WalkGrid.is_free(definition, Vector2(90, 80)), false)
		h.check("%s后导航仍避让物件碰撞" % state_name,
			WalkGrid.has_landing_room(definition, Vector2(90, 80)), false)
		var nearby_actor: MapDef.Actor = definition.actor_near(Vector2(90, 100), 1.0)
		h.check("%s后运行时交互仍可命中" % state_name,
			nearby_actor.id if nearby_actor != null else &"", &"desk")
	model.dirty = true
	canvas.set_actor_editor_state({"desk": true}, {})
	h.check("隐藏保留已有未保存状态", model.dirty, true)
	h.check("重复设置隐藏仍不修改地图数据", model.data, original_data)
	var external_hidden: Dictionary = {"desk": true}
	var external_locked: Dictionary = {"desk": true}
	canvas.set_actor_editor_state(external_hidden, external_locked)
	h.check("传入状态字典不会被修改", [external_hidden, external_locked],
		[{"desk": true}, {"desk": true}])
	external_hidden.clear()
	external_locked.clear()
	h.check("清空外部字典不清空画布状态",
		[canvas.actor_is_hidden(0), canvas.actor_is_locked(0)], [true, true])
	canvas.set_actor_editor_state(external_hidden, external_locked)
	external_hidden["desk"] = true
	external_locked["desk"] = true
	h.check("外部字典新增条目不污染画布状态",
		[canvas.actor_is_hidden(0), canvas.actor_is_locked(0)], [false, false])
	canvas.set_actor_editor_state({"desk": true}, {"desk": true})
	var other_model = Model.new()
	other_model.data = fixture()
	other_model.data["id"] = "other_fixture"
	canvas.model = other_model
	canvas.set_actor_editor_state({"other_actor": true}, {"other_actor": true})
	canvas.tool = Canvas.Tool.SELECT
	canvas.select_actors(selected_actor)
	h.check("换地图范围后相同物件ID不继承旧状态",
		[canvas.actor_is_hidden(0), canvas.actor_is_locked(0)], [false, false])
	h.check("换地图范围后可恢复拾取", canvas._hit_item(actor_point), Vector2i(Model.Kind.ACTOR, 0))
	h.check("换地图范围后可恢复尺寸手柄", canvas._hit_handle(handle_point), 0)
	h.check("换地图范围后可恢复基线拾取", canvas._hit_cover_actor(actor_point), 0)
	canvas._press(actor_point)
	motion.position = Vector2(120, 120)
	canvas._gui_input(motion)
	canvas._release()
	h.check("换地图范围后可恢复实际拖动", other_model.rect_of(Model.Kind.ACTOR, 0),
		Rect2(80, 60, 80, 60))
	canvas.model = model
	canvas.set_actor_editor_state({"desk": true}, {"desk": true})
	h.check("切回原地图可重新应用该地图状态",
		[canvas.actor_is_hidden(0), canvas.actor_is_locked(0)], [true, true])
	h.check("另一地图拖动不修改原地图", model.data, original_data)
	var overlap_model = Model.new()
	overlap_model.data = fixture()
	var front_actor: Dictionary = overlap_model.data["actors"][0].duplicate(true)
	front_actor["id"] = "desk_front"
	overlap_model.data["actors"].append(front_actor)
	canvas.model = overlap_model
	canvas.set_actor_editor_state({}, {})
	h.check("重叠物件默认拾取上层", canvas._hit_item(actor_point), Vector2i(Model.Kind.ACTOR, 1))
	for state_name: String in ["隐藏", "锁定"]:
		canvas.set_actor_editor_state({"desk_front": true} if state_name == "隐藏" else {},
			{"desk_front": true} if state_name == "锁定" else {})
		h.check("%s上层物件后可穿透拾取下层" % state_name,
			canvas._hit_item(actor_point), Vector2i(Model.Kind.ACTOR, 0))
		h.check("%s上层物件后基线拾取穿透到下层" % state_name,
			canvas._hit_cover_actor(cover_point), 0)
		overlap_model.data["actors"].reverse()
		h.check("%s状态随物件ID而不是数组下标" % state_name,
			[canvas.actor_is_hidden(0), canvas.actor_is_locked(0),
			canvas.actor_is_hidden(1), canvas.actor_is_locked(1)],
			[state_name == "隐藏", state_name == "锁定", false, false])
		overlap_model.data["actors"].reverse()
	var group_model = Model.new()
	group_model.data = fixture()
	group_model.data["actors"].append({"id": "desk_peer", "rect": [200, 40, 80, 60]})
	var group_members: Array[int] = [0, 1]
	group_model.group_actors(group_members, "受限组合")
	var original_group_data: Dictionary = group_model.data.duplicate(true)
	var original_group_dirty: bool = group_model.dirty
	canvas.model = group_model
	for state_name: String in ["隐藏", "锁定"]:
		canvas.set_actor_editor_state({"desk_peer": true} if state_name == "隐藏" else {},
			{"desk_peer": true} if state_name == "锁定" else {})
		canvas.tool = Canvas.Tool.SELECT
		canvas.select_actors(selected_actor)
		h.check("%s另一组员不影响当前成员拾取" % state_name,
			canvas._hit_item(actor_point), Vector2i(Model.Kind.ACTOR, 0))
		canvas._press(actor_point)
		h.check("%s另一组员时当前物件仍未受限" % state_name,
			[canvas.sel_index, canvas.actor_is_hidden(0), canvas.actor_is_locked(0)], [0, false, false])
		h.check("%s另一组员时选择仍扩展到整组" % state_name, canvas.selected_actors(), [0, 1])
		h.check("%s另一组员不能绕过整体拖动保护" % state_name, canvas._drag_mode, 0)
		motion.position = Vector2(120, 80)
		canvas._gui_input(motion)
		canvas._release()
		h.check("%s组员的组拒绝拖动且两成员不变" % state_name, group_model.data, original_group_data)
		h.check("%s另一组员时整体手柄不可用" % state_name, canvas._hit_handle(handle_point), -1)
		canvas.tool = Canvas.Tool.COLLISION
		canvas._press(Vector2(70, 65))
		h.check("%s另一组员不能绕过碰撞绘制保护" % state_name, canvas._drag_mode, 0)
		motion.position = Vector2(90, 75)
		canvas._gui_input(motion)
		canvas._release()
		h.check("%s组员的组拒绝碰撞绘制且数据不变" % state_name, group_model.data, original_group_data)
		h.check("%s另一组员的受阻操作保留dirty" % state_name, group_model.dirty, original_group_dirty)
	canvas.free()


static func test_runtime(h: TestHarness) -> void:
	var view := MapView.new()
	h.root.add_child(view)
	var definition := MapDef.from_dictionary(fixture())
	view.build(definition)
	var body := view.get_node_or_null("Built/Actors")
	if body == null:
		for child: Node in view.get_children():
			if child.has_node("Actors"):
				body = child.get_node("Actors")
	h.check("运行时建立物件局部碰撞", body != null, true)
	if body != null:
		h.check("局部碰撞不是整张贴图", body.get_child(0).shape.size, Vector2(70, 20))
	view.set_player_y(69)
	h.check("碰撞上边缘北侧被遮挡", view.cover_z(0) > 10, true)
	view.set_player_y(71)
	h.check("碰撞上边缘南侧盖住物件", view.cover_z(0) < 10, true)
	view.queue_free()
