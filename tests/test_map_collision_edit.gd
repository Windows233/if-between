## 地图画布的局部碰撞编辑回归：通过鼠标和键盘路径验证实际数据变化。
##
## 拖动预览与提交分开，保证取消不改数据、一次松手只有一个撤销步骤。
##
## 保持 run(h) 入口，由父测试入口登记；覆盖保护状态与画布外松手。
extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")


static func fixture() -> Dictionary:
	return {"id": "collision_fixture", "size": [640, 480], "walls": [], "actors": [{
		"id": "desk", "rect": [100, 80, 120, 100], "label": "书桌", "cover": true,
		"collision": [[20, 25, 50, 40], [-30, -20, 25, 18]], "sort_collider": 1,
		"reach_local": [-5, 70, 130, 45], "event": "gatehouse_door"}]}


static func new_canvas():
	var model = Model.new()
	model.data = fixture()
	model.reset_history()
	var canvas = Canvas.new()
	canvas.model = model
	canvas.map_size = model.map_size()
	canvas.zoom = 2.5
	canvas.pan = Vector2(40, 25)
	canvas.size = Vector2(800, 600)
	canvas.select_actors([0])
	canvas.edited.connect(model.record_history)
	return canvas


static func motion(canvas, game_position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = canvas.to_screen(game_position)
	canvas._gui_input(event)


static func key(canvas, code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	canvas._gui_input(event)


static func run(h: TestHarness) -> void:
	test_move_and_history(h)
	test_handles(h)
	test_outside_handles(h)
	test_priority(h)
	test_draw(h)
	test_protection(h)
	test_cancel(h)
	test_outside_release(h)
	test_external_edit(h)
	test_large_map_zoom(h)


static func test_move_and_history(h: TestHarness) -> void:
	for tool in [Canvas.Tool.SELECT, Canvas.Tool.COLLISION]:
		var canvas = new_canvas()
		var model = canvas.model
		canvas.tool = tool
		var before: Dictionary = model.data.duplicate(true)
		canvas._press(canvas.to_screen(Vector2(145, 125)))
		h.check("工具%d点击碰撞开始移动" % tool, canvas._drag_mode, 5)
		h.check("碰撞仍属于原物件选择", canvas.selected_actors(), [0])
		motion(canvas, Vector2(149, 128))
		motion(canvas, Vector2(160, 140))
		motion(canvas, Vector2(152, 136))
		h.check("拖动只预览，不污染模型", model.data, before)
		h.check("拖动预览不置脏", model.dirty, false)
		canvas._release()
		h.check("碰撞移动换回物件局部坐标", model.actor_field(0, "collision"),
			[[27, 36, 50, 40], [-30, -20, 25, 18]])
		h.check("编辑碰撞不移动物件", model.rect_of(Model.Kind.ACTOR, 0), Rect2(100, 80, 120, 100))
		var expected: Dictionary = before.duplicate(true)
		expected["actors"][0]["collision"][0] = [27, 36, 50, 40]
		h.check("其他碰撞、排序、交互和剧情字段不变", model.data, expected)
		h.check("一次拖动只记录一次历史", model._history.size(), 2)
		h.check("碰撞移动可以撤销", model.undo(), true)
		h.check("撤销恢复整个物件", model.data, before)
		h.check("没有多余的鼠标帧撤销步骤", model.undo(), false)
		h.check("碰撞移动可以重做", model.redo(), true)
		h.check("重做恢复移动结果", model.data, expected)
		canvas.free()
	var canvas = new_canvas()
	canvas._press(canvas.to_screen(Vector2(145, 125)))
	canvas._release()
	h.check("单击选碰撞不会置脏", canvas.model.dirty, false)
	h.check("单击选碰撞不产生撤销", canvas.model.undo(), false)
	key(canvas, KEY_DELETE)
	h.check("选中碰撞按Delete不会删除物件", canvas.model.count(Model.Kind.ACTOR), 1)
	h.check("Delete不会意外改碰撞", canvas.model.data, fixture())
	canvas.free()


static func test_handles(h: TestHarness) -> void:
	var handles := [Vector2(120, 105), Vector2(145, 105), Vector2(170, 105),
		Vector2(120, 125), Vector2(170, 125), Vector2(120, 145), Vector2(145, 145), Vector2(170, 145)]
	var expected := [[24, 31, 46, 34], [20, 31, 50, 34], [20, 31, 54, 34],
		[24, 25, 46, 40], [20, 25, 54, 40], [24, 25, 46, 46], [20, 25, 50, 46], [20, 25, 54, 46]]
	for tool in [Canvas.Tool.SELECT, Canvas.Tool.COLLISION]:
		for handle_index in handles.size():
			var canvas = new_canvas()
			canvas.tool = tool
			canvas._press(canvas.to_screen(Vector2(145, 125)))
			canvas._release()
			canvas._press(canvas.to_screen(handles[handle_index]))
			h.check("工具%d手柄%d开始缩放" % [tool, handle_index], canvas._drag_mode, 6)
			motion(canvas, handles[handle_index] + Vector2(4, 6))
			h.check("缩放松手前局部数据不变", canvas.model.actor_field(0, "collision"),
				fixture()["actors"][0]["collision"])
			canvas._release()
			h.check("工具%d手柄%d缩放对应边" % [tool, handle_index],
				canvas.model.actor_field(0, "collision")[0], expected[handle_index])
			h.check("缩放不改变贴图尺寸", canvas.model.rect_of(Model.Kind.ACTOR, 0), Rect2(100, 80, 120, 100))
			h.check("手柄缩放整步撤销", canvas.model.undo(), true)
			h.check("手柄撤销还原碰撞", canvas.model.data, fixture())
			canvas.free()
	var canvas = new_canvas()
	canvas._press(canvas.to_screen(Vector2(145, 125)))
	canvas._release()
	canvas._press(canvas.to_screen(Vector2(170, 145)))
	motion(canvas, Vector2(110, 100))
	canvas._release()
	h.check("缩放跨过对边保持最小一单位", canvas.model.actor_field(0, "collision")[0], [20, 25, 1, 1])
	canvas.free()


static func test_outside_handles(h: TestHarness) -> void:
	var handles := [Vector2(70, 60), Vector2(82.5, 60), Vector2(95, 60),
		Vector2(70, 69), Vector2(95, 69), Vector2(70, 78), Vector2(82.5, 78), Vector2(95, 78)]
	var expected := [[-26, -14, 21, 12], [-30, -14, 25, 12], [-30, -14, 29, 12],
		[-26, -20, 21, 18], [-30, -20, 29, 18], [-26, -20, 21, 24], [-30, -20, 25, 24], [-30, -20, 29, 24]]
	for tool in [Canvas.Tool.SELECT, Canvas.Tool.COLLISION]:
		for handle_index in handles.size():
			var canvas = new_canvas()
			canvas.tool = tool
			canvas._press(canvas.to_screen(Vector2(82.5, 69)))
			canvas._release()
			canvas._press(canvas.to_screen(handles[handle_index]))
			h.check("工具%d物件框外手柄%d可拾取" % [tool, handle_index],
				[canvas._drag_mode, canvas._drag_handle], [6, handle_index])
			motion(canvas, handles[handle_index] + Vector2(4, 6))
			canvas._release()
			h.check("框外手柄写回负局部坐标", canvas.model.actor_field(0, "collision")[1], expected[handle_index])
			h.check("框外缩放保留物件尺寸", canvas.model.rect_of(Model.Kind.ACTOR, 0), Rect2(100, 80, 120, 100))
			canvas.free()
	var canvas = new_canvas()
	canvas._press(canvas.to_screen(Vector2(145, 125)))
	canvas._release()
	canvas._press(canvas.to_screen(Vector2(170, 145)))
	motion(canvas, Vector2(260, 210))
	canvas._release()
	h.check("碰撞缩放允许超出物件右下边界", canvas.model.actor_field(0, "collision")[0], [20, 25, 140, 105])
	canvas.free()


static func test_priority(h: TestHarness) -> void:
	var canvas = new_canvas()
	var model = canvas.model
	model.set_actor_field(0, "collision", [[-10, -10, 50, 40], [-30, -20, 25, 18]])
	model.data["actors"].append({"id": "front", "rect": [90, 70, 140, 120]})
	model.reset_history()
	canvas._press(canvas.to_screen(Vector2(100, 80)))
	h.check("已选物件碰撞优先于物件角柄和上层物件", [canvas._drag_mode, canvas.sel_index], [5, 0])
	motion(canvas, Vector2(107, 86))
	canvas._release()
	h.check("负局部坐标可移动", model.actor_field(0, "collision")[0], [-3, -4, 50, 40])
	h.check("优先编辑碰撞不改变上层物件", model.rect_of(Model.Kind.ACTOR, 1), Rect2(90, 70, 140, 120))
	canvas.select_actors([0])
	canvas._press(canvas.to_screen(Vector2(80, 65)))
	h.check("贴图外的局部碰撞也可选中", canvas._collision_index, 1)
	motion(canvas, Vector2(70, 55))
	canvas._release()
	h.check("贴图外碰撞按局部坐标移动", model.actor_field(0, "collision")[1], [-40, -30, 25, 18])
	canvas.free()


static func test_draw(h: TestHarness) -> void:
	var canvas = new_canvas()
	canvas.tool = Canvas.Tool.COLLISION
	canvas._press(canvas.to_screen(Vector2(220, 190)))
	motion(canvas, Vector2(200, 170))
	h.check("新碰撞松手前没有插入模型", canvas.model.actor_field(0, "collision").size(), 2)
	canvas._release()
	h.check("逆向绘制写入局部矩形", canvas.model.actor_field(0, "collision")[2], [100, 90, 20, 20])
	h.check("新碰撞整步撤销", canvas.model.undo(), true)
	h.check("撤销新碰撞还原物件", canvas.model.data, fixture())
	canvas.select_actors([0])
	canvas._press(canvas.to_screen(Vector2(250, 220)))
	canvas._release()
	h.check("绘制工具单击空白不生成一像素碰撞", canvas.model.data, fixture())
	canvas.free()


static func test_protection(h: TestHarness) -> void:
	for protection: String in ["hidden", "locked", "layer", "multi", "group", "group_hidden", "group_locked"]:
		for tool in [Canvas.Tool.SELECT, Canvas.Tool.COLLISION]:
			var canvas = new_canvas()
			var model = canvas.model
			canvas.tool = tool
			if protection.begins_with("group") or protection == "multi":
				model.data["actors"].append({"id": "peer", "rect": [300, 80, 120, 100]})
				if protection != "multi":
					var group_members: Array[int] = [0, 1]
					model.group_actors(group_members, "组合")
				var selected: Array[int] = [0]
				if protection == "multi":
					selected.append(1)
				canvas.select_actors(selected)
			if protection == "hidden":
				canvas.set_actor_editor_state({"desk": true}, {})
			elif protection == "locked":
				canvas.set_actor_editor_state({}, {"desk": true})
			elif protection == "layer":
				canvas.show_actors = false
			elif protection == "group_hidden":
				canvas.set_actor_editor_state({"peer": true}, {})
			elif protection == "group_locked":
				canvas.set_actor_editor_state({}, {"peer": true})
			model.reset_history()
			var before: Dictionary = model.data.duplicate(true)
			canvas._press(canvas.to_screen(Vector2(145, 125)))
			h.check("%s工具%d不会开始局部碰撞编辑" % [protection, tool],
				canvas._drag_mode >= 5 and canvas._drag_mode <= 7, false)
			if tool == Canvas.Tool.COLLISION or protection not in ["multi", "group"]:
				motion(canvas, Vector2(160, 140))
			canvas._release()
			h.check("%s工具%d保护碰撞和物件数据" % [protection, tool], model.data, before)
			h.check("受阻碰撞操作不产生撤销", model.undo(), false)
			canvas.free()


static func test_cancel(h: TestHarness) -> void:
	for mode in [5, 6, 7]:
		for reason: String in ["escape", "right", "tool", "selection", "hidden", "locked", "layer", "map", "focus", "window", "exit"]:
			var canvas = new_canvas()
			var model = canvas.model
			if mode == 7:
				canvas.tool = Canvas.Tool.COLLISION
				canvas._press(canvas.to_screen(Vector2(220, 190)))
			else:
				canvas._press(canvas.to_screen(Vector2(145, 125)))
				if mode == 6:
					canvas._release()
					canvas._press(canvas.to_screen(Vector2(170, 145)))
			motion(canvas, Vector2(240, 210))
			var other_model = Model.new()
			other_model.data = fixture()
			other_model.reset_history()
			match reason:
				"escape": key(canvas, KEY_ESCAPE)
				"right":
					var event := InputEventMouseButton.new()
					event.button_index = MOUSE_BUTTON_RIGHT
					event.pressed = true
					canvas._gui_input(event)
				"tool": canvas.tool = Canvas.Tool.WALL
				"selection": canvas.select_actors([])
				"hidden": canvas.set_actor_editor_state({"desk": true}, {})
				"locked": canvas.set_actor_editor_state({}, {"desk": true})
				"layer": canvas.set_layer_visible("show_actors", false)
				"map": canvas.load_map(other_model, "", "", Vector2(640, 480))
				"focus": canvas._notification(Control.NOTIFICATION_FOCUS_EXIT)
				"window": canvas._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
				"exit": canvas._notification(Node.NOTIFICATION_EXIT_TREE)
			canvas._release()
			h.check("%s取消模式%d清理碰撞选择" % [reason, mode], canvas._collision_index, -1)
			h.check("%s取消模式%d保留原数据" % [reason, mode], model.data, fixture())
			h.check("取消不产生历史或脏状态", [model.undo(), model.dirty], [false, false])
			h.check("切图及迟到松手不修改另一张图", [other_model.data, other_model.dirty], [fixture(), false])
			canvas.free()


static func test_outside_release(h: TestHarness) -> void:
	var canvas = new_canvas()
	canvas.zoom = 1
	canvas.pan = Vector2.ZERO
	canvas.position = Vector2(35, 45)
	canvas.size = Vector2(260, 220)
	h.root.add_child(canvas)
	canvas._press(canvas.to_screen(Vector2(145, 125)))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = canvas.get_global_transform_with_canvas() * canvas.to_screen(Vector2(460, 370))
	canvas._input(event)
	h.check("画布外松手采用最终位置并提交", canvas.model.actor_field(0, "collision")[0], [335, 270, 50, 40])
	h.check("画布外松手结束拖动", canvas._drag_mode, 0)
	canvas._release()
	h.check("重复收到松手不会重复记录", canvas.model._history.size(), 2)
	h.check("画布外提交可以单步撤销", canvas.model.undo(), true)
	h.check("画布外撤销恢复原始几何", canvas.model.data, fixture())
	canvas.free()


static func test_large_map_zoom(h: TestHarness) -> void:
	var canvas = new_canvas()
	canvas.size = Vector2(320, 240)
	canvas.map_size = Vector2(4096, 4096)
	canvas.fit_to_view()
	h.check("4K地图适配可低于旧缩放下限", canvas.zoom < 0.1, true)
	h.check("4K地图完整落入画布", Rect2(Vector2.ZERO, canvas.size).encloses(
		Rect2(canvas.to_screen(Vector2.ZERO), canvas.map_size * canvas.zoom)), true)
	canvas.map_size = Vector2(100000, 100000)
	canvas.fit_to_view()
	h.check("适配地图最小缩放为0.01", canvas.zoom, 0.01)
	canvas.model.set_rect(Model.Kind.ACTOR, 0, Rect2(0, 0, 4096, 4096))
	canvas.select_actors([0])
	h.check("定位大物件成功", canvas.frame_selection(), true)
	h.check("定位大物件允许缩小到0.1以下", canvas.zoom < 0.1, true)
	h.check("定位完整显示大物件", Rect2(Vector2.ZERO, canvas.size).encloses(
		Rect2(canvas.to_screen(Vector2.ZERO), Vector2(4096, 4096) * canvas.zoom)), true)
	canvas.model.set_rect(Model.Kind.ACTOR, 0, Rect2(0, 0, 100000, 100000))
	canvas.frame_selection()
	h.check("选区定位最小缩放为0.01", canvas.zoom, 0.01)
	canvas.zoom = 0.05
	var anchor := Vector2(125, 95)
	var anchor_game: Vector2 = canvas.to_game(anchor)
	canvas._zoom_at(anchor, 0.5)
	h.check("滚轮允许缩小到0.025", canvas.zoom, 0.025)
	h.check("低倍缩放仍保持鼠标锚点", canvas.to_game(anchor).is_equal_approx(anchor_game), true)
	canvas._zoom_at(anchor, 0.01)
	h.check("滚轮最小缩放为0.01", canvas.zoom, 0.01)
	canvas.free()


static func test_external_edit(h: TestHarness) -> void:
	var canvas = new_canvas()
	canvas._press(canvas.to_screen(Vector2(145, 125)))
	motion(canvas, Vector2(165, 145))
	canvas.model.set_actor_field(0, "label", "外部更新")
	canvas.model.record_history()
	canvas._release()
	h.check("拖动期间外部改动不会被旧快照覆盖", canvas.model.actor_field(0, "label"), "外部更新")
	h.check("外部更新使待提交碰撞拖动取消", canvas.model.actor_field(0, "collision"), fixture()["actors"][0]["collision"])
	h.check("外部更新后没有额外碰撞历史", canvas.model._history.size(), 2)
	canvas.free()
