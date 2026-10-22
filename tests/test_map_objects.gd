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
	var invalid_model: Variant = layout_model()
	invalid_model.data["actors"].append({"id": "desk", "rect": [5, 5, 10, 10]})
	h.check("重复物件 ID 不允许编组", invalid_model.group_actors(invalid_members), "")
	var canvas = Canvas.new()
	canvas.model = model
	canvas.zoom = 1.0
	canvas.pan = Vector2.ZERO
	canvas.edited.connect(model.record_history)
	canvas._press(Vector2(70, 50))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(80, 60)
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
	h.check("编组操作可重做后再恢复位置", model.redo(), true)
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
