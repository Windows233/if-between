## 真窗口验收贴图蓝框与交互绿框分别调整；只使用内存地图及 user:// 临时文件。
## godot --path . --script res://tests/probe_map_texture_reach_ui.gd
## 不连接或操作用户正在运行的编辑器，不保存正式地图或素材。
extends SceneTree

const TextureTests := preload("res://tests/test_map_texture_ui.gd")
const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const MapDef := preload("res://core/map_def.gd")

var dock
var checks := 0
var failures := 0
var output := "user://map_texture_reach_probe"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("本探针需要真实窗口，不能使用 --headless。")
		quit(1)
		return
	root.title = "IF 地图编辑器 · 贴图与交互独立调节验收"
	root.size = Vector2i(1600, 1200)
	root.content_scale_size = Vector2i(1600, 1200)
	_check("临时输出目录可创建", DirAccess.make_dir_recursive_absolute(output), OK)
	dock = TextureTests.FixtureDock.new()
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/desk_shop.json"))
	raw["id"] = "texture_reach_memory_probe"
	raw["name"] = "贴图 / 交互独立调节（内存验收图）"
	raw["size"] = [640, 480]
	raw["walls"] = []
	raw["portals"] = []
	raw["actors"] = []
	raw["spawns"] = {"start": [20, 20]}
	dock.model.data = raw
	dock.model.map_id = str(raw["id"])
	dock.model.path = output.path_join("fixture.json")
	dock.model.draft_dir = output.path_join("unused_drafts")
	dock.model.reset_history()
	dock.canvas.load_map(dock.model, dock.model.background_path(), "", dock.model.map_size())
	await _frames()
	dock._set_initial_panel_layout()
	await _frames()
	var dropped_at := Vector2(320, 235)
	dock.canvas._drop_data(dock.canvas.to_screen(dropped_at), {
		"type": "if_map_asset", "path": "res://art/props/desk.png"})
	await _frames()
	_check("素材拖入后创建单一物件", dock.model.count(Dock.Kind.ACTOR), 1)
	_check("新物件已单选", dock.canvas.selected_actors(), [0])
	_check("新物件直接进入贴图蓝框模式", dock.canvas.tool, Dock.Canvas.Tool.TEXTURE)
	if dock.model.count(Dock.Kind.ACTOR) != 1:
		_finish()
		return
	var initial: Rect2 = dock.model.rect_of(Dock.Kind.ACTOR, 0)
	dock.model.set_actor_field(0, "label", "书桌：贴图与交互分别调节")
	dock.model.set_actor_field(0, "collision", [[4, initial.size.y - 10, maxf(initial.size.x - 8, 1), 8]])
	dock.model.set_interaction_rect(0, Rect2(initial.position - Vector2(8, 6), initial.size + Vector2(16, 12)))
	dock._on_edited()
	dock._refresh_selection()
	var before := MapDef._actor_from(dock.model.actor_dict(0))
	await _drag_world(initial.end, initial.end + Vector2(44, 28))
	var after_texture := MapDef._actor_from(dock.model.actor_dict(0))
	_check("真实鼠标拖蓝框可放大贴图", after_texture.rect.size != before.rect.size, true)
	_check("拖蓝框保持交互范围", after_texture.reach, before.reach)
	_check("拖蓝框保持碰撞范围", after_texture.collision_rects(), before.collision_rects())
	dock._on_tool(Dock.Canvas.Tool.SELECT)
	await _drag_world(after_texture.reach.end, after_texture.reach.end + Vector2(24, 18))
	var after_reach := MapDef._actor_from(dock.model.actor_dict(0))
	_check("真实鼠标拖绿框可放大交互范围", after_reach.reach.size != after_texture.reach.size, true)
	_check("拖绿框保持贴图大小位置", after_reach.rect, after_texture.rect)
	_check("拖绿框保持碰撞范围", after_reach.collision_rects(), after_texture.collision_rects())
	var width: SpinBox = dock._actor_panel.find_child("TextureWidth", true, false)
	_check("贴图宽度字段存在", width != null, true)
	if width != null:
		width.value += 22.0
		await _frames()
	var after_number := MapDef._actor_from(dock.model.actor_dict(0))
	_check("贴图数值改变贴图宽度", after_number.rect.size.x > after_reach.rect.size.x, true)
	_check("贴图数值保持交互范围", after_number.reach, after_reach.reach)
	_check("贴图数值保持碰撞范围", after_number.collision_rects(), after_reach.collision_rects())
	var geometry = dock._object_inspector
	var reach_grid: GridContainer = geometry.get_node("Reach").get_child(1)
	(reach_grid.get_child(2) as SpinBox).value += 18.0
	await _frames()
	var after_reach_number := MapDef._actor_from(dock.model.actor_dict(0))
	_check("交互数值改变交互宽度", after_reach_number.reach.size.x > after_number.reach.size.x, true)
	_check("交互数值保持贴图", after_reach_number.rect, after_number.rect)
	_check("交互数值保持碰撞", after_reach_number.collision_rects(), after_number.collision_rects())
	dock.model.undo()
	dock._refresh_selection()
	await _frames()
	_check("交互尺寸可撤销", MapDef._actor_from(dock.model.actor_dict(0)).reach, after_number.reach)
	dock.model.redo()
	dock._refresh_selection()
	await _frames()
	_check("交互尺寸可重做", MapDef._actor_from(dock.model.actor_dict(0)).reach, after_reach_number.reach)
	var fixture_path := output.path_join("round_trip.json")
	var stream := FileAccess.open(fixture_path, FileAccess.WRITE)
	_check("临时地图可写入", stream != null, true)
	if stream != null:
		stream.store_string(Dock.Model.stringify(dock.model.data))
		stream.close()
		var readback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		var loaded := MapDef.from_dictionary(readback)
		_check("保存回读保留贴图范围", loaded.actors[0].rect, after_reach_number.rect)
		_check("保存回读保留交互范围", loaded.actors[0].reach, after_reach_number.reach)
		_check("保存回读保留碰撞范围", loaded.actors[0].collision_rects(), after_reach_number.collision_rects())
	dock._on_tool(Dock.Canvas.Tool.TEXTURE)
	await _frames()
	dock._panel_scroll.scroll_vertical = 0
	await _capture("texture_and_interaction.png")
	_finish()


func _drag_world(from: Vector2, to: Vector2) -> void:
	var origin: Vector2 = dock.canvas.get_global_rect().position
	var a: Vector2 = origin + dock.canvas.to_screen(from)
	var b: Vector2 = origin + dock.canvas.to_screen(to)
	var hover := InputEventMouseMotion.new()
	hover.position = a
	hover.global_position = a
	root.push_input(hover, true)
	await _frames()
	var pressed := InputEventMouseButton.new()
	pressed.position = a
	pressed.global_position = a
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.button_mask = MOUSE_BUTTON_MASK_LEFT
	pressed.pressed = true
	root.push_input(pressed, true)
	await _frames()
	var motion := InputEventMouseMotion.new()
	motion.position = b
	motion.global_position = b
	motion.relative = b - a
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await _frames()
	var released := InputEventMouseButton.new()
	released.position = b
	released.global_position = b
	released.button_index = MOUSE_BUTTON_LEFT
	released.pressed = false
	root.push_input(released, true)
	await _frames()


func _frames() -> void:
	await process_frame
	await process_frame


func _capture(filename: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	_check("验收截图可保存", root.get_texture().get_image().save_png(output.path_join(filename)), OK)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	checks += 1
	if actual == expected:
		print("  ✓ " + label)
	else:
		failures += 1
		push_error("%s：期望%s，实际%s" % [label, str(expected), str(actual)])


func _finish() -> void:
	print("贴图/交互真窗口验收：%d/%d；截图：%s" % [checks - failures, checks,
		ProjectSettings.globalize_path(output)])
	quit(0 if failures == 0 else 1)
