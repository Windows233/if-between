## 画布基础操作定向回归，通过真实 _gui_input 事件和 model 历史验证。
##
## 独立运行：godot --headless --path <项目> --script res://tests/test_map_canvas_workflow.gd
##
## 只使用内存地图与 user:// 临时图片，不导入资源、不注入 OS 输入。
extends SceneTree

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const ObjectTransform := preload("res://addons/if_map_editor/map_object_transform.gd")
const AssetList := preload("res://addons/if_map_editor/map_asset_list.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	run(harness)
	if "--with-collision-regression" in OS.get_cmdline_user_args():
		harness.section("原有碰撞手柄与取消路径回归")
		preload("res://tests/test_map_collision_edit.gd").run(harness)
	quit(0 if harness.report() else 1)


static func fixture() -> Dictionary:
	return {"id": "canvas_workflow", "size": [640, 480], "walls": [[350, 250, 30, 30]],
		"portals": [{"id": "door", "rect": [420, 250, 20, 20]}], "actors": [
		{"id": "desk", "rect": [40, 40, 40, 20], "collision": [[2, 10, 20, 6], [-4, 5, 8, 4]],
			"sort_collider": 1, "reach_local": [-3, 4, 46, 22], "cover_y": 47, "cover": true},
		{"id": "chair", "rect": [140, 45, 30, 30], "collision": []},
		{"id": "cabinet", "rect": [240, 160, 35, 50], "collision": []}]}


static func geometry_actor() -> Dictionary:
	return {"id": "geometry", "rect": [100, 80, 120, 100], "sprite": "legacy.png",
		"collision": [[20, 25, 50, 40], [-30, -20, 25, 18]], "sort_collider": 1,
		"reach_local": [-10, 60, 100, 50], "cover_y": 67, "cover": true,
		"event": "story_owned_elsewhere", "custom": {"kept": true}, "visual_parts": [
			{"id": "shelf", "sprite": "shelf.png", "rect": [-10, 20, 60, 30], "layer": "back"},
			{"sprite": "roof.png", "rect": [10, -20, 80, 45], "layer": "front", "sort_offset": 6}]}


static func new_canvas(h: TestHarness):
	var model = Model.new()
	model.data = fixture()
	model.reset_history()
	var canvas = Canvas.new()
	h.root.add_child(canvas)
	canvas.model = model
	canvas.map_size = model.map_size()
	canvas.size = Vector2(900, 700)
	canvas.zoom = 2.5
	canvas.pan = Vector2(31, 17)
	canvas._view_touched = true
	canvas.edited.connect(model.record_history)
	return canvas


static func button(canvas, point: Vector2, pressed: bool, shift := false,
		ctrl := false, alt := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = canvas.to_screen(point)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	canvas._gui_input(event)


static func motion(canvas, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = canvas.to_screen(point)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(event)


static func drag(canvas, start: Vector2, end: Vector2, shift := false,
		ctrl := false, alt := false) -> void:
	button(canvas, start, true, shift, ctrl, alt)
	motion(canvas, start.lerp(end, 0.6))
	button(canvas, end, false, shift, ctrl, alt)


static func run(h: TestHarness) -> void:
	h.section("画布框选、复制、网格与几何变换")
	test_marquee(h)
	test_marquee_groups_and_handles(h)
	test_grid_and_resize(h)
	test_duplicate(h)
	test_nested_duplicate(h)
	test_edit_layers(h)
	test_transform_geometry(h)
	test_transform_orientation(h)
	test_transform_history(h)
	test_visual_parts(h)
	test_asset_preview(h)
	test_trigger_selection(h)
	test_shortcut_delegation(h)


static func test_marquee(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	var before: Dictionary = canvas.model.data.duplicate(true)
	drag(canvas, Vector2(5, 5), Vector2(100, 90))
	h.check("空白框选使用地图坐标和松手位置", canvas.selected_actors(), [0])
	drag(canvas, Vector2(115, 20), Vector2(190, 90), true)
	h.check("Shift框选追加", canvas.selected_actors(), [0, 1])
	drag(canvas, Vector2(115, 20), Vector2(190, 90), true)
	h.check("Shift重复框选保留已选", canvas.selected_actors(), [0, 1])
	drag(canvas, Vector2(25, 25), Vector2(190, 90), false, true)
	h.check("Ctrl框选切换整个命中选区", canvas.selected_actors(), [])
	drag(canvas, Vector2(300, 230), Vector2(220, 140))
	h.check("逆向框选正常", canvas.selected_actors(), [2])
	button(canvas, Vector2(60, 44), true, true)
	button(canvas, Vector2(60, 44), false, true)
	h.check("Shift单击追加", canvas.selected_actors(), [2, 0])
	button(canvas, Vector2(60, 44), true, true)
	button(canvas, Vector2(60, 44), false, true)
	h.check("Shift单击不会反选", canvas.selected_actors(), [2, 0])
	button(canvas, Vector2(60, 44), true, false, true)
	button(canvas, Vector2(60, 44), false, false, true)
	h.check("Ctrl单击反选", canvas.selected_actors(), [2])
	h.check("框选不改地图数据", canvas.model.data, before)
	h.check("框选不产生撤销步骤", canvas.model.undo(), false)
	h.check("框选不置脏", canvas.model.dirty, false)
	canvas.free()


static func test_marquee_groups_and_handles(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	var members: Array[int] = [0, 1]
	canvas.model.group_actors(members, "桌椅")
	canvas.model.reset_history()
	drag(canvas, Vector2(5, 5), Vector2(100, 90))
	h.check("框选命中一个成员扩展整组", canvas.selected_actors(), [0, 1])
	drag(canvas, Vector2(5, 5), Vector2(100, 90), false, true)
	h.check("Ctrl框选整组反选", canvas.selected_actors(), [])
	canvas.set_actor_editor_state({}, {"chair": true})
	drag(canvas, Vector2(5, 5), Vector2(100, 90))
	h.check("整组含锁定成员时框选不绕过保护", canvas.selected_actors(), [])
	canvas.free()
	canvas = new_canvas(h)
	canvas.select_actors([0])
	button(canvas, Vector2(48, 52), true)
	button(canvas, Vector2(48, 52), false)
	button(canvas, Vector2(42, 50), true, true)
	h.check("Shift不劫持已选碰撞手柄", canvas._drag_mode, 6)
	button(canvas, Vector2(42, 50), false, true)
	h.check("碰撞手柄单击不修改数据", canvas.model.data, fixture())
	button(canvas, Vector2(42, 50), true, false, true)
	h.check("Ctrl不劫持已选碰撞手柄", canvas._drag_mode, 6)
	button(canvas, Vector2(42, 50), false, false, true)
	canvas.free()


static func test_grid_and_resize(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	h.check("默认一步吸附且不显示网格", [canvas.snap_step, canvas.show_grid], [1.0, false])
	canvas.configure_grid(8.0, true)
	h.check("网格配置与吸附一致", canvas._snap(Vector2(6, 13)), Vector2(8, 16))
	canvas.select_actors([0])
	drag(canvas, Vector2(60, 44), Vector2(66, 57))
	h.check("拖动按配置步长吸附且保留尺寸", canvas.model.rect_of(Model.Kind.ACTOR, 0), Rect2(48, 56, 40, 20))
	h.check("网格拖动一次撤销", canvas.model.undo(), true)
	h.check("网格拖动撤销还原", canvas.model.data, fixture())
	canvas.configure_grid(0.25, false)
	h.check("支持小数吸附步长", canvas._snap(Vector2(0.36, 0.62)), Vector2(0.25, 0.5))
	canvas.configure_grid(0.0)
	h.check("非法吸附步长回退一单位", canvas.snap_step, 1.0)
	canvas.model.data["actors"] = [geometry_actor()]
	canvas.model.reset_history()
	canvas.select_actors([0])
	button(canvas, Vector2(220, 180), true)
	h.check("物件外框手柄使用尺寸工具", canvas._drag_mode, 2)
	motion(canvas, Vector2(250, 230))
	button(canvas, Vector2(340, 280), false)
	h.check("尺寸拖动从手势源重算而不累乘", canvas.model.actor_field(0, "collision"),
		[[40, 50, 100, 80], [-60, -40, 50, 36]])
	h.check("尺寸拖动同步局部交互", canvas.model.actor_field(0, "reach_local"), [-20, 120, 200, 100])
	h.check("尺寸拖动同步子部件", canvas.model.actor_field(0, "visual_parts")[0]["rect"], [-20, 40, 120, 60])
	h.check("尺寸拖动只记一次历史", canvas.model._history.size(), 2)
	h.check("尺寸拖动能整体撤销", canvas.model.undo(), true)
	h.check("尺寸拖动撤销保留原始字段", canvas.model.actor_dict(0), geometry_actor())
	canvas.free()


static func test_duplicate(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	var model = canvas.model
	var members: Array[int] = [0, 1]
	model.group_actors(members, "桌椅")
	model.reset_history()
	var before: Dictionary = model.data.duplicate(true)
	canvas.select_actors([0])
	var copied: Array[int] = [2]
	model.copy_actors(copied)
	var clipboard: Array = model._clipboard.duplicate(true)
	button(canvas, Vector2(60, 44), true, false, false, true)
	button(canvas, Vector2(60, 44), false, false, false, true)
	h.check("Alt单击不会创建副本", model.count(Model.Kind.ACTOR), 3)
	drag(canvas, Vector2(60, 44), Vector2(80, 74), false, false, true)
	h.check("Alt拖动复制整组选区", canvas.selected_actors(), [3, 4])
	h.check("Alt复制使用新ID", [model.actor_field(3, "id"), model.actor_field(4, "id")], ["desk_2", "chair_2"])
	h.check("Alt拖动松手位置正确", model.rect_of(Model.Kind.ACTOR, 3), Rect2(60, 70, 40, 20))
	h.check("副本保持成员相对位置", model.rect_of(Model.Kind.ACTOR, 4), Rect2(160, 75, 30, 30))
	h.check("副本保留局部碰撞", model.actor_field(3, "collision"), before["actors"][0]["collision"])
	h.check("副本绝对基线跟随移动", model.actor_field(3, "cover_y"), 77)
	h.check("原始物件未移动", model.actor_dict(0), before["actors"][0])
	h.check("副本拥有新组", model.group_members_for_actor(3), [3, 4])
	h.check("Alt复制保留用户剪贴板", model._clipboard, clipboard)
	h.check("复制加多帧移动只记一次", model._history.size(), 2)
	h.check("Alt复制可一笔撤销", model.undo(), true)
	h.check("撤销恢复物件和组", model.data, before)
	h.check("Alt复制可一笔重做", model.redo(), true)
	h.check("重做仍保留新ID", model.actor_field(3, "id"), "desk_2")
	canvas.free()


static func test_nested_duplicate(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	var model = canvas.model
	model.data["editor_groups"] = [
		{"id": "reading", "name": "阅读区", "members": ["cabinet"]},
		{"id": "table", "name": "桌椅", "members": ["desk", "chair"], "parent": "reading"}]
	model.reset_history()
	var before: Dictionary = model.data.duplicate(true)
	canvas.select_actors([0])
	h.check("嵌套组选择扩展顶组全部成员", canvas.selected_actors().size(), 3)
	drag(canvas, Vector2(60, 44), Vector2(75, 64), false, false, true)
	h.check("嵌套Alt拖动复制所有成员", canvas.selected_actors().size(), 3)
	var original_groups: Array = before["editor_groups"]
	var groups: Array = model.editor_groups()
	h.check("嵌套Alt拖动复制两级组", groups.size(), 4)
	h.check("嵌套原组未修改", groups.slice(0, 2), original_groups)
	var copied_top: Dictionary = groups[2]
	var copied_child: Dictionary = groups[3]
	h.check("嵌套副本父级指向新组", copied_child.get("parent", ""), copied_top["id"])
	h.check("新父组仅含副本成员", copied_top["members"], ["cabinet_2"])
	h.check("新子组仅含副本成员", copied_child["members"], ["desk_2", "chair_2"])
	h.check("嵌套副本ID唯一", copied_top["id"] != "reading" and copied_child["id"] != "table", true)
	h.check("嵌套拖动只记一笔历史", model._history.size(), 2)
	h.check("嵌套拖动整体撤销", model.undo(), true)
	h.check("嵌套撤销恢复地图和父子关系", model.data, before)
	canvas.free()


static func test_edit_layers(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	var before: Dictionary = canvas.model.data.duplicate(true)
	canvas.configure_edit_layers({"structure": true})
	h.check("结构锁仍然显示", canvas.is_kind_visible(Model.Kind.WALL), true)
	h.check("结构锁排除拾取", canvas._hit_item(canvas.to_screen(Vector2(360, 260))), Vector2i(-1, -1))
	canvas.sel_kind = Model.Kind.WALL
	canvas.sel_index = 0
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_DELETE
	canvas._gui_input(key)
	h.check("结构锁禁止Delete", canvas.model.data, before)
	canvas.tool = Canvas.Tool.WALL
	drag(canvas, Vector2(450, 300), Vector2(470, 330))
	h.check("结构锁禁止新增墙", canvas.model.data, before)
	canvas.configure_edit_layers({"actors": true})
	canvas.tool = Canvas.Tool.COLLISION
	canvas.select_actors([0])
	drag(canvas, Vector2(50, 50), Vector2(55, 53))
	h.check("物件层锁禁止局部碰撞编辑", canvas.model.data, before)
	canvas.tool = Canvas.Tool.SELECT
	h.check("物件层锁禁止素材拖入", canvas._can_drop_data(canvas.to_screen(Vector2(100, 100)),
		{"type": "if_map_asset", "path": "res://art/props/anything.png"}), false)
	canvas.configure_edit_layers({}, "structure")
	h.check("临时隔离结构隐藏物件", canvas.actor_is_hidden(0), true)
	h.check("隔离结构不影响结构拾取", canvas._hit_item(canvas.to_screen(Vector2(360, 260))), Vector2i(Model.Kind.WALL, 0))
	canvas.configure_edit_layers({}, "actors")
	h.check("临时隔离物件隐藏结构", canvas.is_kind_visible(Model.Kind.WALL), false)
	h.check("物件隔离不影响物件拾取", canvas._hit_item(canvas.to_screen(Vector2(60, 44))), Vector2i(Model.Kind.ACTOR, 0))
	canvas.configure_edit_layers({})
	h.check("退出隔离恢复原可见性", canvas.is_kind_visible(Model.Kind.WALL), true)
	canvas.configure_edit_layers({"walls": true})
	h.check("父级单层墙锁受支持", canvas.is_kind_editable(Model.Kind.WALL), false)
	h.check("单层墙锁不锁传送区", canvas.is_kind_editable(Model.Kind.PORTAL), true)
	canvas.configure_edit_layers({}, "walls")
	h.check("父级单层隔离保留墙", canvas.is_kind_visible(Model.Kind.WALL), true)
	h.check("父级单层隔离排除传送区", canvas.is_kind_visible(Model.Kind.PORTAL), false)
	canvas.configure_edit_layers({})
	h.check("图层状态没有进入运行时地图", canvas.model.data, before)
	h.check("图层状态不产生撤销", canvas.model.undo(), false)
	canvas.select_actors([0])
	button(canvas, Vector2(48, 52), true)
	motion(canvas, Vector2(50, 54))
	canvas.configure_edit_layers({"actors": true})
	button(canvas, Vector2(50, 54), false)
	h.check("拖碰撞中锁层取消待提交几何", canvas.model.data, before)
	h.check("拖碰撞中锁层不产生撤销", canvas.model.undo(), false)
	canvas.free()


static func test_transform_geometry(h: TestHarness) -> void:
	var source := geometry_actor()
	var flipped := ObjectTransform.transformed_actor(source, "flip_h")
	h.check("水平翻转完整映射负坐标碰撞", flipped["collision"], [[50, 25, 50, 40], [125, -20, 25, 18]])
	h.check("水平翻转局部交互", flipped["reach_local"], [30, 60, 100, 50])
	h.check("水平翻转子部件", flipped["visual_parts"][0]["rect"], [70, 20, 60, 30])
	var rotated := ObjectTransform.transformed_actor(source, "rotate_cw")
	h.check("90度旋转使用中心新AABB", rotated["rect"], [110, 70, 100, 120])
	h.check("90度旋转完整局部碰撞", rotated["collision"], [[35, 20, 40, 50], [102, -30, 18, 25]])
	h.check("90度旋转局部交互", rotated["reach_local"], [-10, -10, 50, 100])
	h.check("90度旋转子部件", rotated["visual_parts"][0]["rect"], [50, -10, 30, 60])
	h.check("参考碰撞索引不丢", rotated["sort_collider"], 1)
	h.check("绝对cover_y转换为相对偏移", [rotated.has("cover_y"), rotated["sort_offset"]], [false, 7])
	h.check("偏移落在旋转后的参考基线", MapDef._actor_from(rotated).effective_cover_y(), 47)
	var scaled := ObjectTransform.transformed_actor(source, "scale", Vector2(2, 0.5))
	h.check("非等比缩放中心固定", scaled["rect"], [40, 105, 240, 50])
	h.check("非等比缩放碰撞", scaled["collision"], [[40, 12.5, 100, 20], [-60, -10, 50, 9]])
	h.check("非等比缩放局部交互", scaled["reach_local"], [-20, 30, 200, 25])
	h.check("比例缩放手动基线偏移", scaled["sort_offset"], 3.5)
	h.check("比例缩放子部件排序偏移", scaled["visual_parts"][1]["sort_offset"], 3)
	h.check("旧sprite保留", scaled["sprite"], "legacy.png")
	h.check("非几何字段完整保留", [scaled["event"], scaled["custom"]], [source["event"], source["custom"]])
	h.check("变换不污染源字典", source, geometry_actor())
	source.erase("reach_local")
	source["reach"] = [90, 140, 100, 50]
	rotated = ObjectTransform.transformed_actor(source, "rotate_cw")
	h.check("旧绝对交互框转换为正确的局部交互框", [rotated.has("reach"), rotated["reach_local"]], [false, [-10, -10, 50, 100]])


static func test_transform_orientation(h: TestHarness) -> void:
	for turns in 4:
		for horizontal: bool in [false, true]:
			for vertical: bool in [false, true]:
				var source := geometry_actor()
				source["quarter_turns"] = turns
				source["flip_h"] = horizontal
				source["flip_v"] = vertical
				var rect := ObjectTransform.rect_from(source["rect"])
				var before := ObjectTransform.visual_transform(rect, source)
				for operation: String in ["flip_h", "flip_v", "rotate_cw", "rotate_ccw", "scale"]:
					var value: Variant = Vector2(2, 0.5) if operation == "scale" else null
					var result := ObjectTransform.transformed_actor(source, operation, value)
					var after := ObjectTransform.visual_transform(ObjectTransform.rect_from(result["rect"]), result)
					var basis := Transform2D.IDENTITY
					match operation:
						"flip_h":
							basis.x = Vector2(-1, 0)
						"flip_v":
							basis.y = Vector2(0, -1)
						"rotate_cw":
							basis.x = Vector2(0, 1)
							basis.y = Vector2(-1, 0)
						"rotate_ccw":
							basis.x = Vector2(0, -1)
							basis.y = Vector2(1, 0)
						"scale":
							basis.x.x = 2
							basis.y.y = 0.5
					basis.origin = rect.get_center() - basis * rect.get_center()
					for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
						var expected: Vector2 = basis * (before * corner)
						h.check("方向组合%d/%s/%s/%s" % [turns, horizontal, vertical, operation],
							(after * corner).is_equal_approx(expected), true)


static func test_transform_history(h: TestHarness) -> void:
	var model = Model.new()
	model.data = fixture()
	model.data["actors"][0] = geometry_actor()
	model.reset_history()
	var before: Dictionary = model.data.duplicate(true)
	h.check("helper直接调用model setters完成整批变换", ObjectTransform.apply(model, [0, 1], "rotate_cw"), true)
	h.check("helper整批仅一笔历史", model._history.size(), 2)
	var after: Dictionary = model.data.duplicate(true)
	h.check("helper完整undo", model.undo(), true)
	h.check("helper撤销恢复原始几何及字段", model.data, before)
	h.check("helper没有额外撤销帧", model.undo(), false)
	h.check("helper完整redo", model.redo(), true)
	h.check("helper重做几何一致", model.data, after)
	h.check("零比例被拒绝", ObjectTransform.apply(model, [0], "scale", Vector2.ZERO), false)
	h.check("负比例被拒绝", ObjectTransform.apply(model, [0], "scale", -1.0), false)
	h.check("非法比例不污染任何物件", model.data, after)
	h.check("非法比例不产生历史", model._history.size(), 2)
	h.check("原比例是无操作", ObjectTransform.apply(model, [0], "scale", 1.0), false)
	h.check("旋转整圈是无操作", ObjectTransform.apply(model, [0], "rotate", 4), false)
	h.check("无操作保留原字段及历史", [model.data, model._history.size()], [after, 2])
	model.undo()
	var members: Array[int] = [0, 1]
	model.group_actors(members, "geometry_group")
	model.record_history()
	h.check("变换自动扩展组成员", ObjectTransform.apply(model, [0], "scale", 2.0), true)
	h.check("组成员跟随比例缩放", model.rect_of(Model.Kind.ACTOR, 1).size, Vector2(60, 60))


static func test_visual_parts(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	canvas.model.data["actors"] = [geometry_actor()]
	var parts: Array[Dictionary] = canvas.actor_visual_items(0)
	h.check("非空visual_parts替代旧单sprite", parts.size(), 2)
	h.check("子部件局部rect换为世界rect", parts[0]["rect"], Rect2(90, 100, 60, 30))
	h.check("多个子部件属于同一actor", [parts[0]["actor_index"], parts[1]["actor_index"]], [0, 0])
	h.check("子部件保留前后层和偏移", [parts[0]["layer"], parts[1]["layer"], parts[1]["sort_offset"]], ["back", "front", 6.0])
	h.check("点击Actor框外的子部件仍拾取整个Actor", canvas._hit_item(canvas.to_screen(Vector2(95, 110))), Vector2i(Model.Kind.ACTOR, 0))
	canvas.model.set_actor_field(0, "visual_parts", [])
	parts = canvas.actor_visual_items(0)
	h.check("空visual_parts保留旧sprite路径", [parts.size(), parts[0]["sprite"], parts[0]["rect"]], [1, "legacy.png", Rect2(100, 80, 120, 100)])
	canvas.free()


static func test_asset_preview(h: TestHarness) -> void:
	var directory := "user://canvas_workflow_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	h.check("素材预览临时目录可创建", error, OK)
	if error != OK:
		return
	var background := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	background.fill(Color.WHITE)
	var prop := Image.create(60, 30, false, Image.FORMAT_RGBA8)
	prop.fill(Color.RED)
	var background_path := directory.path_join("background.png")
	var prop_path := directory.path_join("prop.png")
	h.check("临时背景写入成功", background.save_png(background_path), OK)
	h.check("临时素材写入成功", prop.save_png(prop_path), OK)
	var canvas = new_canvas(h)
	canvas.model.data["size"] = [100, 100]
	canvas.model.data["background"] = background_path
	canvas.zoom = 2.25
	var thumbnail := ImageTexture.create_from_image(Image.create(16, 8, false, Image.FORMAT_RGBA8))
	var assets = AssetList.new()
	assets.canvas = canvas
	h.check("预览使用原图像素、背景比例与zoom而非缩略图尺寸",
		assets.preview_size_for_asset(prop_path, thumbnail), Vector2(67.5, 67.5))
	var preview: Control = assets.make_drag_preview(prop_path, thumbnail)
	h.check("拖动预览尺寸匹配地图", preview.get_child(0).size, Vector2(67.5, 67.5))
	h.check("拖动预览中心跟随鼠标", preview.get_child(0).position, Vector2(-33.75, -33.75))
	preview.free()
	assets.free()
	canvas.free()
	h.check("清理临时背景", DirAccess.remove_absolute(background_path), OK)
	h.check("清理临时素材", DirAccess.remove_absolute(prop_path), OK)
	h.check("清理临时目录", DirAccess.remove_absolute(directory), OK)


static func test_trigger_selection(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	canvas.model.data["triggers"] = [{"id": "read_shelf", "rect": [300, 130, 60, 40]},
		{"id": "invalid", "rect": [1, 2, 0, 0]}]
	canvas.model.reset_history()
	var before: Dictionary = canvas.model.data.duplicate(true)
	canvas.set_trigger_selection(0)
	h.check("触发面板可以联动画布选择", canvas.selected_trigger, 0)
	h.check("触发选择自动居中取景", canvas.to_screen(Vector2(330, 150)).is_equal_approx(canvas.size * 0.5), true)
	h.check("触发选择支持再次聚焦", canvas.frame_selection(), true)
	canvas.trigger_regions_visible = false
	h.check("触发区域显示可以临时关闭", canvas.trigger_regions_visible, false)
	canvas.set_trigger_selection(1)
	h.check("无面积触发不成为有效选区", canvas.selected_trigger, -1)
	canvas.set_trigger_selection(999)
	h.check("无效触发序号安全清除选区", canvas.selected_trigger, -1)
	canvas.set_trigger_selection(0)
	canvas.select_actors([0])
	h.check("物件选区清除触发高亮", canvas.selected_trigger, -1)
	h.check("触发区取景不改运行时地图", canvas.model.data, before)
	h.check("触发区取景不产生撤销", canvas.model.undo(), false)
	canvas.free()


static func test_shortcut_delegation(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	var shortcuts = preload("res://addons/if_map_editor/map_shortcuts.gd").new(
		"user://unused_canvas_shortcuts_%d.cfg" % Time.get_ticks_usec())
	var commands: Array[String] = []
	canvas.shortcuts = shortcuts
	canvas.command_requested.connect(func(command: String) -> void: commands.append(command))
	var copy_key := InputEventKey.new()
	copy_key.keycode = KEY_Q
	copy_key.pressed = true
	h.check("复制可重绑且不写设置文件", shortcuts.set_binding("copy", [copy_key], false), "")
	canvas._gui_input(copy_key)
	h.check("模块动作统一发送command_requested", commands, ["copy"])
	var old_copy := InputEventKey.new()
	old_copy.keycode = KEY_C
	old_copy.ctrl_pressed = true
	old_copy.pressed = true
	canvas._gui_input(old_copy)
	h.check("旧硬编码Ctrl+C不覆盖用户重绑", commands, ["copy"])
	var frame_key := InputEventKey.new()
	frame_key.keycode = KEY_G
	frame_key.pressed = true
	shortcuts.set_binding("frame_selection", [frame_key], false)
	canvas.select_actors([0])
	var old_frame := InputEventKey.new()
	old_frame.keycode = KEY_F
	old_frame.pressed = true
	var zoom: float = canvas.zoom
	canvas._gui_input(old_frame)
	h.check("旧硬编码F不自行取景", canvas.zoom, zoom)
	canvas._gui_input(frame_key)
	h.check("取景重绑发送统一动作", commands.back(), "frame_selection")
	canvas.sel_kind = Model.Kind.WALL
	canvas.sel_index = 0
	var delete_key := InputEventKey.new()
	delete_key.keycode = KEY_DELETE
	delete_key.pressed = true
	canvas._gui_input(delete_key)
	h.check("Delete由统一命令交给父级处理", commands.back(), "delete")
	h.check("画布不会抢先删除数据", canvas.model.count(Model.Kind.WALL), 1)
	var cancel_key := InputEventKey.new()
	cancel_key.keycode = KEY_R
	cancel_key.pressed = true
	shortcuts.set_binding("cancel", [cancel_key], false)
	button(canvas, Vector2(5, 5), true)
	var old_cancel := InputEventKey.new()
	old_cancel.keycode = KEY_ESCAPE
	old_cancel.pressed = true
	canvas._input(old_cancel)
	h.check("拖动期间旧Esc也不覆盖重绑", canvas._drag_mode, 8)
	canvas._input(cancel_key)
	h.check("重绑取消可结束框选", canvas._drag_mode, 0)
	h.check("重绑取消发出统一命令", commands.back(), "cancel")
	canvas.free()
