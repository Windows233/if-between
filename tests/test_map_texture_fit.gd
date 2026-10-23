## 换图保留布置，并用地图框选范围调整物件贴图的行为回归。
##
## 独立运行：godot --headless --path <项目> --script res://tests/test_map_texture_fit.gd
##
## 只创建 user:// 临时 PNG；通过画布手势、数据与撤销验证，不改正式地图或导入资源。
extends SceneTree

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("贴图换图与地图框选尺寸")
	var model_script: Script = Model
	var canvas_script: Script = Canvas
	var scripts_ready: bool = model_script.can_instantiate() and canvas_script.can_instantiate()
	h.check("框选依赖脚本可实例化", scripts_ready, true)
	if not scripts_ready:
		return
	var directory := "user://test_map_texture_fit_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	h.check("框选测试临时目录可创建", error, OK)
	if error != OK:
		return
	var ready := true
	var images := {"background.png": Vector2i(1280, 960),
		"oversized.png": Vector2i(2048, 1024), "replacement.png": Vector2i(320, 160)}
	for filename: String in images:
		var dimensions: Vector2i = images[filename]
		var image := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.5, 0.8, 1.0))
		var saved := image.save_png(directory.path_join(filename))
		h.check("框选测试图片可保存 %s" % filename, saved, OK)
		ready = ready and saved == OK
	if ready:
		test_assignment(h, directory)
		test_drag_and_geometry(h, directory)
		test_reverse_and_bounds(h, directory)
		test_small_gesture(h, directory)
		test_cancel(h, directory)
		test_protection(h, directory)
		test_baseline_selection(h, directory)
	var temporary := DirAccess.open(directory)
	if temporary != null:
		for filename: String in temporary.get_files():
			h.check("清理框选测试图片 %s" % filename,
				DirAccess.remove_absolute(directory.path_join(filename)), OK)
	h.check("清理框选测试目录", DirAccess.remove_absolute(directory), OK)


static func fixture(directory: String) -> Dictionary:
	return {"id": "texture_fit", "size": [640, 480], "walls": [],
		"background": directory.path_join("background.png"), "actors": [{
			"id": "desk", "rect": [100, 80, 120, 100], "label": "书桌",
			"sprite": directory.path_join("replacement.png"), "cover": true,
			"collision": [[20, 25, 50, 40], [-30, -20, 25, 18]], "sort_collider": 1,
			"reach_local": [-10, 60, 100, 50], "cover_y": 67,
			"quarter_turns": 1, "flip_h": true, "flip_v": false,
			"event": "story_owned_elsewhere", "custom": {"kept": true}, "visual_parts": [
				{"id": "shelf", "sprite": "shelf.png", "rect": [-10, 20, 60, 30], "layer": "back"},
				{"sprite": "roof.png", "rect": [10, -20, 80, 45], "layer": "front", "sort_offset": 6}]}]}


static func new_canvas(directory: String):
	var model = Model.new()
	model.data = fixture(directory)
	model.reset_history()
	var canvas = Canvas.new()
	canvas.model = model
	canvas.map_size = model.map_size()
	canvas.zoom = 2.5
	canvas.pan = Vector2(40, 25)
	canvas.size = Vector2(1800, 1400)
	canvas.select_actors([0])
	canvas.tool = Canvas.Tool.TEXTURE_RECT
	canvas.edited.connect(model.record_history)
	return canvas


static func test_baseline_selection(h: TestHarness, directory: String) -> void:
	var canvas = new_canvas(directory)
	var model = canvas.model
	model.data["actors"].append({"id": "other", "rect": [300, 200, 80, 60], "cover": true})
	canvas.select_actors([0, 1])
	canvas.tool = Canvas.Tool.BASELINE
	canvas._press(canvas.to_screen(Vector2(320, 220)))
	h.check("拉另一物件基线会清掉旧多选", canvas.selected_actors(), [1])
	h.check("基线检查器主选中项跟随实际命中", canvas.sel_index, 1)
	canvas._update_pointer_drag(canvas.to_screen(Vector2(320, 245)))
	canvas._release()
	h.check("基线只写入实际命中的物件", model.actor_cover_y(1), 245.0)
	h.check("旧多选成员的基线不变", model.actor_cover_y(0), 67.0)
	canvas.free()


static func drag(canvas, start: Vector2, end: Vector2) -> void:
	canvas._press(canvas.to_screen(start))
	canvas._update_pointer_drag(canvas.to_screen(start.lerp(end, 0.6)))
	canvas._update_pointer_drag(canvas.to_screen(end))
	canvas._release()


static func test_assignment(h: TestHarness, directory: String) -> void:
	var model = Model.new()
	model.data = fixture(directory)
	model.reset_history()
	var expected: Dictionary = model.data.duplicate(true)
	var oversized := directory.path_join("oversized.png")
	expected["actors"][0]["sprite"] = oversized
	h.check("导入大图到现有物件成功", model.assign_actor_sprite(0, oversized), true)
	h.check("换成大图只替换贴图，不放大已有框或局部几何", model.data, expected)
	model.record_history()
	h.check("替换贴图可整体撤销", model.undo(), true)
	h.check("撤销换图还原原有布置", model.data, fixture(directory))
	h.check("替换贴图可整体重做", model.redo(), true)
	h.check("重做大图仍保持已有尺寸", model.data, expected)
	h.check("显式恢复原图尺寸成功", model.restore_original_size(0), true)
	h.check("原图尺寸按背景比例换算", model.rect_of(Model.Kind.ACTOR, 0), Rect2(100, 80, 1024, 512))
	var before_invalid: Dictionary = model.data.duplicate(true)
	h.check("无效贴图不能覆盖物件", model.assign_actor_sprite(0, directory.path_join("missing.png")), false)
	h.check("无效贴图不改现有字段", model.data, before_invalid)
	h.check("无效索引不能替换", model.assign_actor_sprite(-1, oversized), false)
	h.check("清空贴图成功", model.assign_actor_sprite(0, ""), true)
	before_invalid["actors"][0]["sprite"] = ""
	h.check("清空贴图保留地图尺寸和其他字段", model.data, before_invalid)


static func test_drag_and_geometry(h: TestHarness, directory: String) -> void:
	var canvas = new_canvas(directory)
	var model = canvas.model
	var before: Dictionary = model.data.duplicate(true)
	canvas._press(canvas.to_screen(Vector2(40, 30)))
	canvas._update_pointer_drag(canvas.to_screen(Vector2(150, 120)))
	canvas._update_pointer_drag(canvas.to_screen(Vector2(280, 230)))
	h.check("框选预览不改物件数据", model.data, before)
	h.check("框选预览不置脏", model.dirty, false)
	canvas._release()
	h.check("框选将物件完整放入目标地图范围", model.rect_of(Model.Kind.ACTOR, 0), Rect2(40, 30, 240, 200))
	h.check("框选同步两个局部碰撞且允许负坐标", model.actor_field(0, "collision"),
		[[40, 50, 100, 80], [-60, -40, 50, 36]])
	h.check("框选同步局部交互范围", model.actor_field(0, "reach_local"), [-20, 120, 200, 100])
	h.check("框选同步部件范围与排序偏移", model.actor_field(0, "visual_parts"), [
		{"id": "shelf", "sprite": "shelf.png", "rect": [-20, 40, 120, 60], "layer": "back"},
		{"sprite": "roof.png", "rect": [20, -40, 160, 90], "layer": "front", "sort_offset": 12}])
	h.check("框选把旧绝对基线换为随物件移动的偏移", model.actor_field(0, "sort_offset"), 14)
	h.check("框选移除旧绝对基线", model.actor_dict(0).has("cover_y"), false)
	var expected: Dictionary = before.duplicate(true)
	var actor: Dictionary = expected["actors"][0]
	actor["rect"] = [40, 30, 240, 200]
	actor["collision"] = [[40, 50, 100, 80], [-60, -40, 50, 36]]
	actor["reach_local"] = [-20, 120, 200, 100]
	actor["visual_parts"][0]["rect"] = [-20, 40, 120, 60]
	actor["visual_parts"][1]["rect"] = [20, -40, 160, 90]
	actor["visual_parts"][1]["sort_offset"] = 12
	actor.erase("cover_y")
	actor["sort_offset"] = 14
	h.check("框选保留贴图、朝向、剧情和所有无关字段", model.data, expected)
	h.check("一次框选只记一次历史", model._history.size(), 2)
	h.check("框选可以一次撤销", model.undo(), true)
	h.check("撤销框选恢复所有局部几何", model.data, before)
	h.check("多帧框选没有多余撤销步骤", model.undo(), false)
	h.check("框选可重做", model.redo(), true)
	h.check("重做恢复完整框选结果", model.data, expected)
	canvas.free()


static func test_reverse_and_bounds(h: TestHarness, directory: String) -> void:
	var canvas = new_canvas(directory)
	drag(canvas, Vector2(280, 230), Vector2(40, 30))
	h.check("反向框选得到同一位置和尺寸", canvas.model.rect_of(Model.Kind.ACTOR, 0), Rect2(40, 30, 240, 200))
	canvas.free()
	canvas = new_canvas(directory)
	drag(canvas, Vector2(300, 250), Vector2(-25, -40))
	h.check("框选左上越界限制在地图边缘", canvas.model.rect_of(Model.Kind.ACTOR, 0), Rect2(0, 0, 300, 250))
	canvas.free()
	canvas = new_canvas(directory)
	drag(canvas, Vector2(300, 250), Vector2(900, 700))
	h.check("框选右下越界限制在地图边缘", canvas.model.rect_of(Model.Kind.ACTOR, 0), Rect2(300, 250, 340, 230))
	canvas.free()


static func test_small_gesture(h: TestHarness, directory: String) -> void:
	for test_zoom in [0.1, 2.5, 8.0]:
		var canvas = new_canvas(directory)
		canvas.zoom = test_zoom
		var before: Dictionary = canvas.model.data.duplicate(true)
		var start := canvas.to_screen(Vector2(300, 250))
		canvas._press(start)
		canvas._release()
		h.check("缩放%s单击不缩放物件" % test_zoom, canvas.model.data, before)
		canvas._press(start)
		canvas._update_pointer_drag(start + Vector2(1.5, 1.5))
		canvas._release()
		h.check("缩放%s小于三屏幕像素的抖动不改物件" % test_zoom, canvas.model.data, before)
		h.check("误点击不产生撤销记录", canvas.model.undo(), false)
		h.check("误点击不置脏", canvas.model.dirty, false)
		canvas.free()


static func test_cancel(h: TestHarness, directory: String) -> void:
	for operation: String in ["escape", "cancel", "switch"]:
		var canvas = new_canvas(directory)
		var before: Dictionary = canvas.model.data.duplicate(true)
		canvas._press(canvas.to_screen(Vector2(40, 30)))
		canvas._update_pointer_drag(canvas.to_screen(Vector2(280, 230)))
		if operation == "escape":
			var event := InputEventKey.new()
			event.pressed = true
			event.keycode = KEY_ESCAPE
			canvas._gui_input(event)
		elif operation == "cancel":
			canvas.cancel_interaction()
		else:
			canvas.tool = Canvas.Tool.SELECT
		canvas._release()
		h.check("%s取消框选后松手不修改物件" % operation, canvas.model.data, before)
		h.check("%s取消框选不产生撤销记录" % operation, canvas.model.undo(), false)
		h.check("%s取消框选不置脏" % operation, canvas.model.dirty, false)
		canvas.free()


static func test_protection(h: TestHarness, directory: String) -> void:
	for protection: String in ["none", "multi", "group", "hidden", "locked", "layer_hidden", "layer_locked"]:
		var canvas = new_canvas(directory)
		var model = canvas.model
		if protection == "none":
			canvas.select_actors([])
		elif protection == "multi" or protection == "group":
			model.data["actors"].append({"id": "peer", "rect": [300, 80, 120, 100]})
			var indices: Array[int] = [0, 1]
			if protection == "group":
				model.group_actors(indices, "组合")
				canvas.select_actors([0])
			else:
				canvas.select_actors(indices)
		elif protection == "hidden":
			canvas.set_actor_editor_state({"desk": true}, {})
		elif protection == "locked":
			canvas.set_actor_editor_state({}, {"desk": true})
		elif protection == "layer_hidden":
			canvas.show_actors = false
		elif protection == "layer_locked":
			canvas.locked_layers = {"actors": true}
		model.reset_history()
		model.dirty = false
		var before: Dictionary = model.data.duplicate(true)
		drag(canvas, Vector2(40, 30), Vector2(280, 230))
		h.check("%s保护状态不允许框选改尺寸" % protection, model.data, before)
		h.check("%s保护状态不产生撤销记录" % protection, model.undo(), false)
		h.check("%s保护状态不置脏" % protection, model.dirty, false)
		canvas.free()
