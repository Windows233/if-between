## 贴图框与交互框独立的画布回归：真实GUI鼠标路径、预览取消和整步撤销。
## 内存地图，不修改正式地图；可独立运行或由地图编辑器全量入口调用run(h)。
extends SceneTree

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const Shortcuts := preload("res://addons/if_map_editor/map_shortcuts.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var h := TestHarness.new()
	h.setup(root)
	run(h)
	quit(0 if h.report() else 1)


static func fixture() -> Dictionary:
	return {"id": "texture_canvas", "size": [640, 480], "walls": [], "actors": [{
		"id": "desk", "rect": [100, 80, 120, 100], "sprite": "res://art/props/desk.png",
		"collision": [[20, 25, 50, 40], [-30, -20, 25, 18]], "sort_collider": 1,
		"reach_local": [-5, 70, 130, 45], "cover": true,
		"event": "gatehouse_door", "custom": {"kept": true}}]}


static func new_canvas(h: TestHarness):
	var model = Model.new()
	model.data = fixture()
	model.reset_history()
	var canvas = Canvas.new()
	h.root.add_child(canvas)
	canvas.model = model
	canvas.map_size = model.map_size()
	canvas.zoom = 2.5
	canvas.pan = Vector2(31, 17)
	canvas.size = Vector2(900, 700)
	canvas.select_actors([0])
	canvas.edited.connect(model.record_history)
	return canvas


static func button(canvas, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = canvas.to_screen(point)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	canvas._gui_input(event)


static func motion(canvas, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = canvas.to_screen(point)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(event)


static func key(canvas, code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	canvas._gui_input(event)


static func run(h: TestHarness) -> void:
	h.section("独立贴图框拖拽与交互范围保持")
	test_resize_and_history(h)
	test_move_and_default_reach(h)
	test_cancel(h)
	test_protected_selection(h)
	test_stale_and_outside_release(h)
	test_parts_and_pick(h)


static func test_resize_and_history(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	var before: Dictionary = canvas.model.data.duplicate(true)
	var definition := MapDef._actor_from(canvas.model.actor_dict(0))
	h.check("明确入口启动独立贴图工具", canvas.begin_texture_edit(), true)
	h.check("贴图工具位于原枚举末尾", int(Canvas.Tool.TEXTURE), 5)
	button(canvas, Vector2(220, 180), true)
	h.check("蓝框角柄使用独立拖拽状态", canvas._drag_mode, 10)
	motion(canvas, Vector2(260, 200))
	motion(canvas, Vector2(300, 240))
	h.check("拖图只预览不提前改数据", canvas.model.data, before)
	h.check("贴图预览不置脏或记录历史", [canvas.model.dirty, canvas.model._history.size()], [false, 1])
	h.check("预览中的贴图尺寸已更新", canvas.actor_visual_items(0)[0]["rect"], Rect2(100, 80, 200, 160))
	button(canvas, Vector2(320, 260), false)
	h.check("松手按最后鼠标位置修改贴图", canvas.model.rect_of(Model.Kind.ACTOR, 0), Rect2(100, 80, 220, 180))
	var resized := MapDef._actor_from(canvas.model.actor_dict(0))
	h.check("调贴图不改世界交互区", resized.reach, definition.reach)
	h.check("调贴图不改世界碰撞", resized.collision_rects(), definition.collision_rects())
	h.check("调贴图保留剧情与自定义字段", [canvas.model.actor_field(0, "event"), canvas.model.actor_field(0, "custom")],
		["gatehouse_door", {"kept": true}])
	var committed: Dictionary = canvas.model.data.duplicate(true)
	h.check("整次贴图拖拽只记一步", canvas.model._history.size(), 2)
	h.check("贴图拖拽可撤销", canvas.model.undo(), true)
	h.check("撤销恢复原始字段", canvas.model.data, before)
	h.check("没有多余预览历史", canvas.model.undo(), false)
	h.check("贴图拖拽可重做", canvas.model.redo(), true)
	h.check("重做恢复完整结果", canvas.model.data, committed)
	canvas.free()


static func test_move_and_default_reach(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	canvas.model.data["actors"][0].erase("reach_local")
	canvas.model.reset_history()
	var before := MapDef._actor_from(canvas.model.actor_dict(0))
	canvas.begin_texture_edit()
	button(canvas, Vector2(155, 125), true)
	motion(canvas, Vector2(171, 140))
	button(canvas, Vector2(175, 150), false)
	h.check("拖框内只移动贴图位置", canvas.model.rect_of(Model.Kind.ACTOR, 0), Rect2(120, 105, 120, 100))
	var after := MapDef._actor_from(canvas.model.actor_dict(0))
	h.check("旧隐式交互区移图后保持世界位置", after.reach, before.reach)
	h.check("移图不带动碰撞", after.collision_rects(), before.collision_rects())
	canvas.model.undo()
	var source: Dictionary = canvas.model.data.duplicate(true)
	canvas.begin_texture_edit()
	button(canvas, Vector2(155, 125), true)
	button(canvas, Vector2(155, 125), false)
	h.check("纯单击不物化隐式交互字段", canvas.model.data, source)
	h.check("纯单击不产生历史", canvas.model.undo(), false)
	canvas.free()


static func test_cancel(h: TestHarness) -> void:
	for reason: String in ["escape", "shortcut", "right", "tool", "selection", "hidden", "locked", "layer", "map", "focus", "window", "exit"]:
		var canvas = new_canvas(h)
		var original_model = canvas.model
		canvas.begin_texture_edit()
		button(canvas, Vector2(220, 180), true)
		motion(canvas, Vector2(270, 230))
		var other = Model.new()
		other.data = fixture()
		other.reset_history()
		match reason:
			"escape": key(canvas, KEY_ESCAPE)
			"shortcut":
				canvas.shortcuts = Shortcuts.new()
				key(canvas, KEY_ESCAPE)
			"right":
				var event := InputEventMouseButton.new()
				event.pressed = true
				event.button_index = MOUSE_BUTTON_RIGHT
				canvas._gui_input(event)
			"tool": canvas.tool = Canvas.Tool.SELECT
			"selection": canvas.select_actors([])
			"hidden": canvas.set_actor_editor_state({"desk": true}, {})
			"locked": canvas.set_actor_editor_state({}, {"desk": true})
			"layer": canvas.set_layer_visible("show_actors", false)
			"map": canvas.load_map(other, "", "", Vector2(640, 480))
			"focus": canvas._notification(Control.NOTIFICATION_FOCUS_EXIT)
			"window": canvas._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"exit": canvas._notification(Node.NOTIFICATION_EXIT_TREE)
		canvas._release()
		h.check(reason + "取消贴图预览不改原地图", original_model.data, fixture())
		h.check(reason + "取消不产生撤销和脏状态", [original_model.undo(), original_model.dirty], [false, false])
		h.check(reason + "迟到松手不改新地图", [other.data, other.dirty], [fixture(), false])
		canvas.free()


static func test_protected_selection(h: TestHarness) -> void:
	for reason: String in ["locked", "hidden", "multi", "group", "empty", "no_texture"]:
		var canvas = new_canvas(h)
		match reason:
			"locked": canvas.set_actor_editor_state({}, {"desk": true})
			"hidden": canvas.set_actor_editor_state({"desk": true}, {})
			"multi", "group":
				canvas.model.add_actor()
				var indices: Array[int] = [0, 1]
				if reason == "group":
					canvas.model.group_actors(indices, "桌椅")
					canvas.select_actors([0])
				else:
					canvas.select_actors(indices)
			"empty": canvas.select_actors([])
			"no_texture": canvas.model.data["actors"][0].erase("sprite")
		var before: Dictionary = canvas.model.data.duplicate(true)
		h.check(reason + "禁止进入贴图工具", canvas.begin_texture_edit(), false)
		canvas.tool = Canvas.Tool.TEXTURE
		button(canvas, Vector2(220, 180), true)
		motion(canvas, Vector2(270, 230))
		button(canvas, Vector2(270, 230), false)
		h.check(reason + "不能绕过保护修改贴图", canvas.model.data, before)
		canvas.free()


static func test_stale_and_outside_release(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	canvas.begin_texture_edit()
	button(canvas, Vector2(220, 180), true)
	motion(canvas, Vector2(260, 220))
	canvas.model.set_actor_field(0, "label", "外部修改")
	var external: Dictionary = canvas.model.data.duplicate(true)
	button(canvas, Vector2(290, 250), false)
	h.check("外部数据变化使旧贴图拖拽失效", canvas.model.data, external)
	canvas.free()
	canvas = new_canvas(h)
	canvas.position = Vector2(35, 45)
	canvas.scale = Vector2(0.8, 0.9)
	canvas.begin_texture_edit()
	button(canvas, Vector2(220, 180), true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	# _input接收视口坐标，不能使用_gui_input的画布局部坐标；全量测试可能改变视口变换。
	event.position = canvas.get_global_transform_with_canvas() * canvas.to_screen(Vector2(500, 400))
	canvas._input(event)
	h.check("画布外全局松手仍提交最终贴图范围", canvas.model.rect_of(Model.Kind.ACTOR, 0), Rect2(100, 80, 400, 320))
	h.check("画布外松手也只有一步历史", canvas.model._history.size(), 2)
	canvas.free()


static func test_parts_and_pick(h: TestHarness) -> void:
	var canvas = new_canvas(h)
	canvas.model.data["actors"][0]["visual_parts"] = [
		{"id": "piece", "sprite": "res://art/props/desk.png", "rect": [-10, 20, 60, 30], "layer": "front"}]
	canvas.model.data["actors"][0]["quarter_turns"] = 1
	canvas.model.data["actors"][0]["flip_h"] = true
	canvas.model.reset_history()
	var before := MapDef._actor_from(canvas.model.actor_dict(0))
	canvas.begin_texture_edit()
	button(canvas, Vector2(220, 180), true)
	motion(canvas, Vector2(340, 280))
	h.check("多部件预览跟随贴图缩放", canvas.actor_visual_items(0)[0]["rect"], Rect2(80, 120, 120, 60))
	button(canvas, Vector2(340, 280), false)
	var after := MapDef._actor_from(canvas.model.actor_dict(0))
	h.check("多部件缩放保持世界交互与碰撞", [after.reach, after.collision_rects()], [before.reach, before.collision_rects()])
	h.check("贴图尺寸调整保留旋转与翻转", [canvas.model.actor_field(0, "quarter_turns"), canvas.model.actor_field(0, "flip_h")], [1, true])
	canvas.tool = Canvas.Tool.SELECT
	h.check("普通选择不因贴图扩大拾取范围", canvas._actor_hit(0, canvas.to_screen(Vector2(300, 90))), false)
	h.check("普通选择仍命中绿色交互范围", canvas._actor_hit(0, canvas.to_screen(Vector2(150, 160))), true)
	canvas.free()
