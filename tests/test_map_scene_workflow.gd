extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Hierarchy := preload("res://addons/if_map_editor/map_scene_hierarchy.gd")
const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const Visuals := preload("res://addons/if_map_editor/map_visual_inspector.gd")
const Validation := preload("res://addons/if_map_editor/map_validation.gd")
const Library := preload("res://addons/if_map_editor/map_object_library.gd")


static func run(h: TestHarness) -> void:
	var model := Model.new()
	model.map_id = "scene_workflow"
	model.data = {"id": "scene_workflow", "size": [400, 300], "spawns": {"start": [20, 20]},
		"actors": [{"id": "desk", "rect": [40, 40, 30, 20], "decor": true,
			"collision": [[0, 10, 30, 10]], "reach_local": [-2, -2, 34, 24]},
			{"id": "chair", "rect": [80, 40, 20, 20], "decor": true},
			{"id": "shelf", "rect": [120, 40, 30, 60], "decor": true}],
		"editor_groups": [{"id": "room", "name": "房间", "members": ["shelf"]},
			{"id": "desk_set", "name": "桌椅", "members": ["desk", "chair"], "parent": "room"}]}
	model.reset_history()
	h.check("嵌套编组数据有效", Hierarchy.errors(model.data), [] as Array[String])
	h.check("嵌套子成员选择会扩展到完整父组", model.expand_group_selection([0] as Array[int]), [0, 1, 2])
	var original := model.data.duplicate(true)
	h.check("拒绝将父组放进后代", Hierarchy.reparent(model.data, "group", "room", "desk_set"), false)
	h.check("循环拒绝后数据不动", model.data, original)
	var empty_parent := Model.new()
	empty_parent.data = original.duplicate(true)
	empty_parent.data["editor_groups"][0]["members"] = []
	h.check("空容器父组参与整体解组", empty_parent.ungroup_actors([0] as Array[int]), 2)
	h.check("整体解组不留下空的父组", empty_parent.editor_groups().is_empty(), true)
	model.copy_actors([0] as Array[int])
	var pasted: Array[int] = model.paste_actors()
	h.check("复制完整嵌套组", pasted.size(), 3)
	h.check("复制组不会丢失层级", model.editor_groups().size(), 4)
	var copied_parent: String = model.editor_groups()[2]["id"]
	h.check("子组指向复制后的父组", model.editor_groups()[3]["parent"], copied_parent)
	h.check("复制后组成员仍无多重归属", Hierarchy.errors(model.data), [] as Array[String])
	model.record_history()
	h.check("整组复制一次撤销", model.undo(), true)
	h.check("撤销恢复原数据", model.data, original)
	var dock := Dock.new()
	dock._build()
	dock.model = model
	dock.canvas.load_map(model, "", "", model.map_size())
	dock._refresh_objects()
	h.check("子组在树中归入父组", dock._hierarchy_group_items[1].get_parent(), dock._hierarchy_group_items[0])
	dock._on_hierarchy_drop({"kind": "actor", "id": "chair"}, {"kind": "group", "id": "room"}, 0)
	h.check("树拖动物件改变归属", Hierarchy.parent_of_actor(model.data, "chair"), "room")
	h.check("树拖动一次撤销", model.undo(), true)
	h.check("撤销树拖动恢复原归属", Hierarchy.parent_of_actor(model.data, "chair"), "desk_set")
	model.set_actor_field(1, "id", "chair_renamed")
	h.check("改ID同步嵌套组引用", Hierarchy.parent_of_actor(model.data, "chair_renamed"), "desk_set")
	h.check("改ID后引用仍有效", Hierarchy.errors(model.data), [] as Array[String])
	var broken := model.data.duplicate(true)
	broken["actors"][0]["visual_parts"] = [{"sprite": "res://art/missing_part.png", "rect": [0, 0, 10, 10], "layer": "front"}]
	var report := Validation.validate(broken)
	h.check("缺失部件贴图能定位实例与部件字段", report["errors"].any(func(problem: Dictionary) -> bool:
		return problem.get("kind") == "actor" and problem.get("index") == 0 and problem.get("field") == "visual_parts.0.sprite"), true)
	var panel := Visuals.new()
	panel.configure(model, 0)
	panel.edited.connect(model.record_history)
	panel.add_part()
	h.check("属性卡添加本地部件", model.actor_field(0, "visual_parts", [])[0]["rect"], [0, 0, 30, 20])
	h.check("属性卡可设置独立前层", panel.set_part(0, "layer", "front"), true)
	h.check("部件矩形拒绝零面积", panel.set_part(0, "rect", [0, 0, 0, 20]), false)
	panel._transform("rotate_cw")
	h.check("旋转同步物件矩形", model.rect_of(Model.Kind.ACTOR, 0).size, Vector2(20, 30))
	h.check("旋转保留物件局部碰撞", model.actor_field(0, "collision", []).size(), 1)
	h.check("旋转后视觉部件仍存在", model.actor_field(0, "visual_parts", []).size(), 1)
	panel.remove_part(0)
	h.check("删除末部件恢复单图模式", model.actor_dict(0).has("visual_parts"), false)
	dock.canvas.select_actors([0] as Array[int])
	var count_before: int = model.count(Model.Kind.ACTOR)
	dock._on_delete()
	h.check("删除嵌套组整体选区", model.count(Model.Kind.ACTOR), 0)
	h.check("组删除只需一步撤销", model.undo(), true)
	h.check("撤销恢复整个嵌套组", model.count(Model.Kind.ACTOR), count_before)
	panel.free()
	dock.free()
	_test_template_drag(h, original)


static func _test_template_drag(h: TestHarness, source: Dictionary) -> void:
	var library := Library.new()
	library.directory = "user://scene_template_drag_%d" % Time.get_ticks_usec()
	h.check("建立拖入模板样例", library.save_template("desk", source["actors"][0]), OK)
	var dock := Dock.new()
	dock._library = library
	dock._build()
	dock.model.data = {"id": "template_drop", "size": [400, 300], "actors": []}
	dock.model.map_id = "template_drop"
	dock.model.reset_history()
	dock.canvas.load_map(dock.model, "", "", Vector2(400, 300))
	dock.canvas.zoom = 2
	dock.canvas.pan = Vector2.ZERO
	h.check("模板浏览器可列出样例", dock._template_list.item_count, 1)
	dock._template_filter.text = "missing"
	dock._refresh_templates()
	h.check("模板浏览器支持文本筛选", dock._template_list.item_count, 0)
	dock._template_filter.text = "desk"
	dock._refresh_templates()
	var payload := {"type": "if_map_template", "name": "desk"}
	h.check("画布接受来自模板库的拖入", dock.canvas._can_drop_data(Vector2(300, 200), payload), true)
	dock.canvas._drop_data(Vector2(300, 200), payload)
	h.check("模板放置保留跟踪来源", dock.model.actor_field(0, "source_template", ""), "desk")
	h.check("模板按画布缩放换算鼠标位置", dock.model.rect_of(Model.Kind.ACTOR, 0).get_center(), Vector2(150, 100))
	h.check("拖入保留模板碰撞", MapDef._actor_from(dock.model.actor_dict(0)).collisions,
		MapDef._actor_from(source["actors"][0]).collisions)
	h.check("模板拖入是一笔撤销", dock.model.undo(), true)
	h.check("撤销模板放置恢复空地图", dock.model.count(Model.Kind.ACTOR), 0)
	dock.canvas.configure_edit_layers({"actors": true})
	h.check("锁定物件层拒绝模板拖入", dock.canvas._can_drop_data(Vector2(300, 200), payload), false)
	dock.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(library.directory.path_join("desk.json")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(library.directory))
