## 可走格缓存回归：用内存地图验证碰撞编辑后画布显示实际随数据刷新。
##
## 小型 SubViewport 只承载测试面板；不载入、不保存正式地图，也不改素材。
##
## 独立 --script 或由插件入口 await run(harness)，同时守住脚底框判定的留边。
extends SceneTree

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Shortcuts := preload("res://addons/if_map_editor/map_shortcuts.gd")


class MemoryShortcuts extends Shortcuts:
	func load_settings() -> Error:
		return ERR_FILE_NOT_FOUND


class FixtureDock extends Dock:
	func _ready() -> void:
		_shortcuts = MemoryShortcuts.new()
		_build()

	func _save_actor_editor_state() -> Error:
		return OK


func _initialize() -> void:
	call_deferred("_standalone")


func _standalone() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	await run(harness)
	quit(0 if harness.report() else 1)


static func _fixture() -> Dictionary:
	return {"id": "walk_refresh_fixture", "name": "可走格刷新内存夹具", "size": [240, 180],
		"walls": [[40, 30, 20, 20]], "portals": [], "spawns": {"start": [20, 100]},
		"actors": [{"id": "desk", "label": "桌子", "rect": [110, 70, 60, 50],
			"decor": true, "collision": [[0, 0, 20, 20]]}]}


static func run(h: TestHarness) -> void:
	h.section("可走格随碰撞编辑、撤销与显示开关刷新")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.gui_embed_subwindows = true
	h.root.add_child(viewport)
	var dock := FixtureDock.new()
	viewport.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.model.data = _fixture()
	dock.model.map_id = "walk_refresh_fixture"
	dock.model.reset_history()
	dock.canvas.load_map(dock.model, "", "", dock.model.map_size())
	await h.root.get_tree().process_frame
	_test_layer_defaults(h, dock)
	var stats := {"builds": 0}
	dock.canvas.status.connect(func(message: String) -> void:
		if message.begins_with("可走格算完了"):
			stats["builds"] += 1)
	dock.canvas.set_walk_visible(true)
	_check_point(h, dock.canvas, Vector2(49, 39), false, "初始墙内")
	_check_point(h, dock.canvas, Vector2(119, 79), false, "初始局部碰撞内")
	_test_foot_clearance(h, dock.canvas)
	await _test_wall_edit(h, dock, stats)
	await _test_local_collision_edit(h, dock)
	await _test_actor_move_and_history(h, dock)
	await _test_debounce(h, dock, stats)
	await _test_visibility(h, dock, stats)
	await _test_explicit_recompute(h, dock, stats)
	await _test_map_replacement(h, dock, stats)
	viewport.queue_free()
	await h.root.get_tree().process_frame
	await h.root.get_tree().process_frame


static func _wait(dock) -> void:
	await dock.get_tree().create_timer(0.24).timeout


static func _test_layer_defaults(h: TestHarness, dock) -> void:
	var labels := {"背景": "show_bg", "前景层": "show_overlay", "墙": "show_walls",
		"传送区": "show_portals", "物件": "show_actors", "出生点": "show_spawns",
		"可走格": "show_walk", "脚底框（跟鼠标）": "show_foot"}
	var found := {}
	for checkbox: CheckBox in dock.find_children("*", "CheckBox", true, false):
		if labels.has(checkbox.text):
			found[checkbox.text] = true
			h.check(checkbox.text + "初始勾选与实际显示一致", checkbox.button_pressed,
				bool(dock.canvas.get(labels[checkbox.text])))
	h.check("所有画布显示开关均已检查", found.size(), labels.size())


static func _check_point(h: TestHarness, canvas, point: Vector2, free: bool, label: String) -> void:
	var def := MapDef.from_dictionary(canvas.model.data)
	h.check(label + "的游戏判定", WalkGrid.is_free(def, point), free)
	h.check(label + "存在可走格纹理", canvas._walk_texture != null, true)
	if canvas._walk_texture == null:
		return
	var grid_point := Vector2i(floori(point.x / WalkGrid.STEP), floori(point.y / WalkGrid.STEP))
	var pixel: Color = canvas._walk_texture.get_image().get_pixelv(grid_point)
	h.check(label + "的网格显示与游戏判定相同", pixel.g > pixel.r, free)


static func _test_foot_clearance(h: TestHarness, canvas) -> void:
	var wall: Rect2 = canvas._map_def().walls[0]
	var center_x := wall.get_center().x - 1.0
	var left_point := Vector2(wall.position.x - WalkGrid.FOOT_HALF * 0.5 - 1.0,
		wall.position.y + 9.0)
	h.check("墙左侧留边点自身在墙外", wall.has_point(left_point), false)
	_check_point(h, canvas, left_point, false, "脚底框左右伸出的墙外点")
	_check_point(h, canvas, Vector2(center_x, wall.position.y - 1.0), true,
		"脚底框不向下伸出的墙上方点")
	_check_point(h, canvas, Vector2(center_x, wall.end.y + WalkGrid.FOOT_UP * 0.5 + 1.0),
		false, "脚底框向上伸出的墙下方点")
	_check_point(h, canvas, Vector2(center_x, wall.end.y + WalkGrid.FOOT_UP + 1.0),
		true, "已离开整个脚底框范围的墙下方点")


static func _test_wall_edit(h: TestHarness, dock, stats: Dictionary) -> void:
	var builds: int = stats["builds"]
	dock.model.set_rect(Model.Kind.WALL, 0, Rect2(70, 30, 20, 20))
	dock._on_edited()
	h.check("属性编辑立即移除旧可走格", dock.canvas._walk_texture, null)
	await _wait(dock)
	h.check("墙编辑后自动重算一次", stats["builds"], builds + 1)
	_check_point(h, dock.canvas, Vector2(49, 39), true, "墙移开后的旧位置")
	_check_point(h, dock.canvas, Vector2(79, 39), false, "墙移入的新位置")


static func _test_local_collision_edit(h: TestHarness, dock) -> void:
	dock.model.set_actor_field(0, "collision", [[28, 0, 20, 20]])
	dock.canvas.edited.emit()
	h.check("画布编辑信号立即移除旧可走格", dock.canvas._walk_texture, null)
	await _wait(dock)
	_check_point(h, dock.canvas, Vector2(119, 79), true, "局部碰撞移开后的旧位置")
	_check_point(h, dock.canvas, Vector2(147, 79), false, "局部碰撞移入的新位置")


static func _test_actor_move_and_history(h: TestHarness, dock) -> void:
	dock.model.set_rect(Model.Kind.ACTOR, 0, Rect2(160, 70, 60, 50))
	dock._on_edited()
	await _wait(dock)
	_check_point(h, dock.canvas, Vector2(147, 79), true, "物件移动后的旧碰撞位置")
	_check_point(h, dock.canvas, Vector2(197, 79), false, "物件移动后的新碰撞位置")
	dock._object_command("undo")
	h.check("撤销走面板入口并恢复物件位置", dock.model.rect_of(Model.Kind.ACTOR, 0).position,
		Vector2(110, 70))
	h.check("撤销立即移除旧可走格", dock.canvas._walk_texture, null)
	await _wait(dock)
	_check_point(h, dock.canvas, Vector2(147, 79), false, "撤销恢复后的旧碰撞位置")
	_check_point(h, dock.canvas, Vector2(197, 79), true, "撤销释放的新碰撞位置")
	dock._object_command("redo")
	h.check("重做走面板入口并恢复物件移动", dock.model.rect_of(Model.Kind.ACTOR, 0).position,
		Vector2(160, 70))
	await _wait(dock)
	_check_point(h, dock.canvas, Vector2(147, 79), true, "重做释放的旧碰撞位置")
	_check_point(h, dock.canvas, Vector2(197, 79), false, "重做恢复的新碰撞位置")


static func _test_debounce(h: TestHarness, dock, stats: Dictionary) -> void:
	var builds: int = stats["builds"]
	for x: float in [100.0, 130.0, 160.0]:
		dock.model.set_rect(Model.Kind.WALL, 0, Rect2(x, 30, 20, 20))
		dock._on_edited()
	await _wait(dock)
	h.check("同一帧多次碰撞编辑合并为一次重算", stats["builds"], builds + 1)
	_check_point(h, dock.canvas, Vector2(79, 39), true, "连续编辑释放初始墙位置")
	_check_point(h, dock.canvas, Vector2(109, 39), true, "连续编辑不保留中间墙位置")
	_check_point(h, dock.canvas, Vector2(169, 39), false, "连续编辑采用最后墙位置")


static func _test_visibility(h: TestHarness, dock, stats: Dictionary) -> void:
	dock.canvas.set_walk_visible(false)
	var builds: int = stats["builds"]
	dock.model.set_actor_field(0, "collision", [])
	dock._on_edited()
	h.check("关闭显示时编辑也作废旧缓存", dock.canvas._walk_texture, null)
	await _wait(dock)
	h.check("关闭显示时编辑不重算", stats["builds"], builds)
	dock.canvas.set_walk_visible(true)
	h.check("重新开启后计算最新数据", stats["builds"], builds + 1)
	_check_point(h, dock.canvas, Vector2(197, 79), true, "重新开启释放已删除的局部碰撞")
	builds = stats["builds"]
	dock.model.set_actor_field(0, "collision", [[28, 0, 20, 20]])
	dock._on_edited()
	dock.canvas.set_walk_visible(false)
	await _wait(dock)
	h.check("等待重算时关闭显示不继续计算", stats["builds"], builds)
	h.check("等待重算时关闭显示不恢复旧纹理", dock.canvas._walk_texture, null)
	dock.canvas.set_walk_visible(true)
	_check_point(h, dock.canvas, Vector2(197, 79), false, "再次开启恢复最新局部碰撞")


static func _test_explicit_recompute(h: TestHarness, dock, stats: Dictionary) -> void:
	dock.model.set_rect(Model.Kind.WALL, 0, Rect2(40, 30, 20, 20))
	dock._on_edited()
	var builds: int = stats["builds"]
	dock.canvas.recompute_walk()
	var texture: ImageTexture = dock.canvas._walk_texture
	await _wait(dock)
	h.check("手动重算取消尚未执行的自动重算", stats["builds"], builds + 1)
	h.check("手动重算后的纹理不被过时任务替换", dock.canvas._walk_texture, texture)
	_check_point(h, dock.canvas, Vector2(49, 39), false, "手动重算的新墙位置")


static func _test_map_replacement(h: TestHarness, dock, stats: Dictionary) -> void:
	dock.model.set_rect(Model.Kind.WALL, 0, Rect2(70, 30, 20, 20))
	dock._on_edited()
	var next_model := Model.new()
	next_model.data = {"id": "empty_walk_fixture", "size": [240, 180],
		"walls": [], "actors": [], "spawns": {"start": [20, 100]}}
	var builds: int = stats["builds"]
	dock.canvas.load_map(next_model, "", "", next_model.map_size())
	h.check("切地图立即移除上一张图的可走格", dock.canvas._walk_texture, null)
	await _wait(dock)
	h.check("开启显示时切地图自动按新布局计算一次", stats["builds"], builds + 1)
	_check_point(h, dock.canvas, Vector2(49, 39), true, "新地图原墙位置")
	_check_point(h, dock.canvas, Vector2(197, 79), true, "新地图原物件位置")
	var texture: ImageTexture = dock.canvas._walk_texture
	await _wait(dock)
	h.check("切地图不残留上一张图的延迟重算", stats["builds"], builds + 1)
	h.check("切地图的新纹理不被旧任务替换", dock.canvas._walk_texture, texture)
