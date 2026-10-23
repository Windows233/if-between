## 编辑器的画布：把地图画出来、接鼠标。
##
## 坐标系：**屏幕像素 ↔ 地图单位**。物件像素按背景原图到地图单位的比例换算。
## 所有矩形数据都以游戏单位存，界面上的数字和 JSON 里的数字是同一个。
## 缩放/平移自己实现（不借 2D 编辑器），因为整个画布是自成一体的面板，
## 不依赖当前打开哪个场景。
##
## 五种工具：选择 / 画墙 / 画传送区 / 拉基线 / 画物件碰撞箱。
## 纯绘制与交互，数据全部交给 `map_edit_model.gd`。
@tool
extends Control

enum Tool { SELECT, WALL, PORTAL, BASELINE, COLLISION }

const Kind := preload("res://addons/if_map_editor/map_edit_model.gd").Kind
const ObjectTransform := preload("res://addons/if_map_editor/map_object_transform.gd")
const EDIT_LAYER_ACTORS := "actors"
const EDIT_LAYER_STRUCTURE := "structure"
const KIND_LAYERS := {Kind.ACTOR: "actors", Kind.WALL: "walls", Kind.PORTAL: "portals",
	Kind.SPAWN: "spawns", Kind.OVERLAY: "overlay"}

const WALL_FILL := Color(0.85, 0.25, 0.25, 0.30)
const WALL_EDGE := Color(0.95, 0.35, 0.32, 1.0)
const PORTAL_FILL := Color(0.20, 0.70, 0.85, 0.32)
const PORTAL_EDGE := Color(0.25, 0.78, 0.95, 1.0)
const ACTOR_FILL := Color(0.30, 0.80, 0.40, 0.22)
const ACTOR_EDGE := Color(0.35, 0.85, 0.45, 1.0)
const BASE_AUTO := Color(1.00, 0.86, 0.20, 1.0)
const BASE_MANUAL := Color(1.00, 0.50, 0.10, 1.0)
const SPAWN_COLOR := Color(0.90, 0.45, 0.95, 1.0)
## 前景层范围的标注色（和别的层都错开）
const OVERLAY_MARK := Color(0.95, 0.60, 0.20, 1.0)
const SELECT_COLOR := Color(1, 1, 1, 0.95)
const HANDLE_SIZE := 7.0
const HIT_SLOP := 4.0

signal selection_changed
signal edited
signal status(text)
signal command_requested(command: String)

var model = null
var template_library: RefCounted = null
var shortcuts: RefCounted = null
var tex_bg: Texture2D = null
var tex_overlay: Texture2D = null
var map_size := Vector2.ZERO

var tool: int = Tool.SELECT:
	set(value):
		if tool != value:
			_clear_collision_selection()
			if _drag_mode == 8:
				_drag_mode = 0
		tool = value
		queue_redraw()
var zoom := 1.0
var pan := Vector2.ZERO
var _view_touched := false
var hidden_actor_ids: Dictionary = {}
var locked_actor_ids: Dictionary = {}
var snap_step := 1.0:
	set(value):
		snap_step = value if is_finite(value) and value > 0.0 else 1.0
		queue_redraw()
var show_grid := false:
	set(value):
		show_grid = value
		queue_redraw()
var locked_layers: Dictionary = {}
var isolated_layer := ""
var trigger_regions_visible := true:
	set(value):
		trigger_regions_visible = value
		queue_redraw()
var selected_trigger := -1

var show_bg := true
var show_overlay := true
var show_walls := true
var show_portals := true
var show_actors := true
var show_walk := false
## 出生点（小小一颗紫点）。**它不是矩形，是个坐标**，但一样能选中、拖动、
## 用数值框改 —— 数据层把它包成以点为中心的 6×6 方块（见 model）。
var show_spawns := true

## 测试工具：**在鼠标处画主角的碰撞箱**（脚底那个 16×16 方块），
## 顺便实时告诉你那儿站不站得住。量「这条缝够不够人钻过去」用的。
var show_foot := false
var _mouse_game := Vector2.ZERO
var _mouse_inside := false
## 复用的 `MapDef`（跟着 `is_free` 用）。数据一改就作废，见 `invalidate_def()`。
var _def: MapDef = null
## 前景层（`MapDef.overlay`）的不透明度。**它恒在角色之上**，
## 编辑它底下那些墙/传送区时把它调淡，才看得见底下。
var overlay_alpha := 1.0
## 前景层真正有像素的范围（`Image.get_used_rect()`），加载时算一次。
## 用它画一圈虚线 + 一句「恒在角色之上」，让「这块东西在挡人」看得见 ——
## 不然它只是一张铺着的图，和普通背景没区别。
var _overlay_used := Rect2()

var sel_kind := -1
var sel_index := -1
var actor_selection: Array[int] = []
var _drag_actor_rects: Dictionary = {}
var _drag_actor_sources: Dictionary = {}
var _duplicate_on_drag := false
var _marquee_additive := false
var _marquee_toggle := false
var _marquee_selection: Array[int] = []
var _marquee_fallback := Vector2i(-1, -1)
var _collision_index := -1
var _collision_actor := -1
var _collision_actor_id := ""
var _collision_drag_source: Dictionary = {}

var _drag_mode := 0            # 0 无 / 1 移动 / 2 改尺寸 / 3 画新框 / 4 拉基线
var _drag_start_game := Vector2.ZERO
var _drag_start_rect := Rect2()
var _drag_handle := -1
var _drag_new_rect := Rect2()
var _walk_texture: ImageTexture = null
var _tex_cache := {}


func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_viewport_resized)
	# 像素画缩小时要脆，不要糊
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_entered.connect(func() -> void:
		_mouse_inside = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_mouse_inside = false
		queue_redraw())


# ---------------------------------------------------------------- 载入

func load_map(model_ref, bg_path: String, overlay_path: String, size: Vector2) -> void:
	_clear_collision_selection()
	_drag_mode = 0
	_drag_actor_rects.clear()
	_drag_actor_sources.clear()
	_duplicate_on_drag = false
	model = model_ref
	map_size = size
	tex_bg = _load_tex(bg_path)
	tex_overlay = _load_tex(overlay_path)
	_overlay_used = _used_rect_of(tex_overlay)
	sel_kind = -1
	sel_index = -1
	actor_selection.clear()
	selected_trigger = -1
	_view_touched = false
	_walk_texture = null
	_def = null
	fit_to_view()
	queue_redraw()
	selection_changed.emit()


func set_actor_editor_state(hidden_ids: Dictionary, locked_ids: Dictionary) -> void:
	if _drag_mode == 1 or _drag_mode == 2 or _drag_mode == 4:
		_drag_mode = 0
		edited.emit()
		selection_changed.emit()
	elif _drag_mode == 3:
		_drag_mode = 0
	hidden_actor_ids = hidden_ids.duplicate()
	locked_actor_ids = locked_ids.duplicate()
	if not _collision_editable():
		_clear_collision_selection()
	queue_redraw()


func actor_is_hidden(index: int) -> bool:
	if not is_kind_visible(Kind.ACTOR):
		return true
	if model == null or index < 0 or index >= model.count(Kind.ACTOR):
		return false
	var actor_id := str(model.actor_field(index, "id", ""))
	return not actor_id.is_empty() and hidden_actor_ids.has(actor_id)


func actor_is_locked(index: int) -> bool:
	if not is_kind_editable(Kind.ACTOR):
		return true
	if model == null or index < 0 or index >= model.count(Kind.ACTOR):
		return false
	var actor_id := str(model.actor_field(index, "id", ""))
	return not actor_id.is_empty() and locked_actor_ids.has(actor_id)


func configure_grid(step := 1.0, visible := false) -> void:
	snap_step = step
	show_grid = visible


func configure_edit_layers(locks: Dictionary, isolation := "") -> void:
	if _drag_mode >= 5 and _drag_mode <= 7:
		_clear_collision_selection()
	elif _drag_mode == 1 or _drag_mode == 2 or _drag_mode == 4:
		_release()
	elif _drag_mode == 3 or _drag_mode == 8:
		_drag_mode = 0
	locked_layers = locks.duplicate()
	isolated_layer = isolation if isolation == EDIT_LAYER_STRUCTURE or isolation in KIND_LAYERS.values() else ""
	_duplicate_on_drag = false
	if not _collision_editable():
		_clear_collision_selection()
	queue_redraw()
	selection_changed.emit()


func is_kind_editable(kind: int) -> bool:
	var layer := EDIT_LAYER_ACTORS if kind == Kind.ACTOR else EDIT_LAYER_STRUCTURE
	return is_kind_visible(kind) and not bool(locked_layers.get(layer, false)) \
		and not bool(locked_layers.get(KIND_LAYERS.get(kind, ""), false))


func _actor_selection_block_reason() -> String:
	for index: int in selected_actors():
		if actor_is_hidden(index):
			return "选区包含隐藏物件，请先显示后再移动"
		if actor_is_locked(index):
			return "选区包含锁定物件，请先解锁后再移动"
	return ""


func selected_actors() -> Array[int]:
	if sel_kind != Kind.ACTOR:
		return []
	if actor_selection.is_empty() and sel_index >= 0:
		return [sel_index]
	return actor_selection.duplicate()


func select_actors(indices: Array[int]) -> void:
	_clear_collision_selection()
	selected_trigger = -1
	actor_selection = model.expand_group_selection(indices) if model != null else indices.duplicate()
	sel_kind = Kind.ACTOR if not actor_selection.is_empty() else -1
	sel_index = actor_selection.back() if not actor_selection.is_empty() else -1
	queue_redraw()


func _collision_editable() -> bool:
	if model == null or not show_actors or sel_kind != Kind.ACTOR \
			or sel_index < 0 or sel_index >= model.count(Kind.ACTOR):
		return false
	var selected := selected_actors()
	return selected.size() == 1 and selected[0] == sel_index \
		and model.expand_group_selection(selected).size() == 1 \
		and _actor_selection_block_reason().is_empty()


func _collision_owner_valid() -> bool:
	return _collision_editable() and _collision_actor == sel_index \
		and _collision_actor_id == str(model.actor_field(sel_index, "id", ""))


func _has_collision_selection() -> bool:
	return _collision_owner_valid() and _collision_index >= 0 \
		and _collision_rect_at(_collision_index).has_area()


func _clear_collision_selection() -> void:
	if _drag_mode >= 5 and _drag_mode <= 7:
		_drag_mode = 0
	_collision_drag_source.clear()
	_collision_index = -1
	_collision_actor = -1
	_collision_actor_id = ""
	queue_redraw()


func _collision_rect_at(index: int) -> Rect2:
	if model == null or sel_kind != Kind.ACTOR:
		return Rect2()
	var shapes: Variant = model.actor_dict(sel_index).get("collision", [])
	if not shapes is Array or index < 0 or index >= shapes.size():
		return Rect2()
	var shape: Variant = shapes[index]
	if not shape is Array or shape.size() != 4:
		return Rect2()
	for component: Variant in shape:
		if not (component is int or component is float):
			return Rect2()
	var origin: Vector2 = model.rect_of(Kind.ACTOR, sel_index).position
	return Rect2(origin + Vector2(shape[0], shape[1]), Vector2(shape[2], shape[3]))


func _hit_collision_handle(pos: Vector2) -> int:
	if not _has_collision_selection():
		return -1
	var points := _handle_points(_collision_rect_at(_collision_index))
	for index in points.size():
		if points[index].distance_to(pos) <= HANDLE_SIZE:
			return index
	return -1


func _press_collision(pos: Vector2) -> bool:
	if not _collision_editable():
		return false
	var handle := _hit_collision_handle(pos)
	var index := _collision_index if handle >= 0 else -1
	if index < 0:
		var shapes: Variant = model.actor_dict(sel_index).get("collision", [])
		if shapes is Array:
			for candidate in range(shapes.size() - 1, -1, -1):
				var shape := _collision_rect_at(candidate)
				if shape.has_area() and _rect_hit(shape, pos):
					index = candidate
					break
	if index < 0:
		return false
	_begin_collision_drag(6 if handle >= 0 else 5, pos, index)
	_drag_handle = handle
	_drag_start_rect = _collision_rect_at(index)
	_drag_new_rect = _drag_start_rect
	queue_redraw()
	return true


func _begin_collision_drag(mode: int, pos: Vector2, index := -1) -> void:
	_collision_index = index
	_collision_actor = sel_index
	_collision_actor_id = str(model.actor_field(sel_index, "id", ""))
	_collision_drag_source = model.actor_dict(sel_index).duplicate(true)
	_drag_mode = mode
	_drag_start_game = to_game(pos)
	_drag_new_rect = Rect2(_snap(_drag_start_game), Vector2.ZERO)


func _collision_drag_valid() -> bool:
	return _collision_owner_valid() and not _collision_drag_source.is_empty() \
		and model.actor_dict(sel_index) == _collision_drag_source


func _update_collision_drag(pos: Vector2) -> void:
	if not _collision_drag_valid():
		_clear_collision_selection()
		return
	if _drag_mode == 5:
		_drag_new_rect = Rect2(_drag_start_rect.position + _snap(to_game(pos) - _drag_start_game),
			_drag_start_rect.size)
	elif _drag_mode == 6:
		_drag_new_rect = _resized_rect(pos)
	elif _drag_mode == 7:
		var start := _snap(_drag_start_game)
		var end := _snap(to_game(pos))
		_drag_new_rect = Rect2(start.min(end), (end - start).abs())
	queue_redraw()


func _release_collision_drag() -> void:
	if not _collision_drag_valid():
		_clear_collision_selection()
		return
	var mode := _drag_mode
	_drag_mode = 0
	_collision_drag_source.clear()
	if not _drag_new_rect.has_area() or (mode != 7 and _drag_new_rect == _drag_start_rect):
		queue_redraw()
		return
	if mode == 7:
		model.add_collision_rect(sel_index, _drag_new_rect)
		_collision_index = model.actor_dict(sel_index)["collision"].size() - 1
	else:
		var shapes: Array = model.actor_dict(sel_index)["collision"].duplicate(true)
		var local: Vector2 = _drag_new_rect.position - model.rect_of(Kind.ACTOR, sel_index).position
		var shape: Array = [local.x, local.y, _drag_new_rect.size.x, _drag_new_rect.size.y]
		for component in shape.size():
			if shape[component] == roundf(shape[component]):
				shape[component] = int(shape[component])
		shapes[_collision_index] = shape
		model.set_actor_field(sel_index, "collision", shapes)
	invalidate_def()
	edited.emit()
	selection_changed.emit()
	queue_redraw()


## 一张图里真正有像素的范围（全透明的不算）。算不出来就返回空矩形。
func _used_rect_of(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2()
	var img := tex.get_image()
	if img == null:
		return Rect2()
	return img.get_used_rect()


func _load_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex_cache.has(path):
		var texture: Texture2D = null
		if FileAccess.file_exists(path):
			if path.get_extension().to_lower() == "png" and not FileAccess.file_exists(path + ".import"):
				var image := Image.load_from_file(path)
				if image != null and not image.is_empty():
					texture = ImageTexture.create_from_image(image)
			else:
				texture = load(path) as Texture2D
		_tex_cache[path] = texture
	var tex: Variant = _tex_cache[path]
	return tex if tex is Texture2D else null


## 导入新图之后清一下贴图缓存。
##
## 不清的话，那个路径上还留着「刚导入时加载不到」的空结果，新图要等重新打开
## 编辑器才出得来 —— 界面看着像导入失败了。
## 换前景层的图（不整张重载，免得把选中和光标弄丢）。
func set_overlay_texture(path: String) -> void:
	_tex_cache.erase(path)
	tex_overlay = _load_tex(path)
	_overlay_used = _used_rect_of(tex_overlay)
	queue_redraw()


func clear_texture_cache() -> void:
	_tex_cache.clear()


## 前景层**真正有像素**的范围（游戏单位）。数据里前景层只有一条路径，
## 它整张拉伸到地图大小 —— 但图里往往只有底下一条带子有内容，
## 所以选框要照实际像素画，不能照整张地图（那样框住整个画面，等于没框）。
func overlay_game_rect() -> Rect2:
	if tex_overlay == null:
		return Rect2()
	var picture := tex_overlay.get_size()
	if picture.x <= 0.0 or picture.y <= 0.0:
		return Rect2()
	if _overlay_used.size.x <= 0.0:
		return Rect2(Vector2.ZERO, map_size)
	var scale := map_size / picture
	return Rect2(_overlay_used.position * scale, _overlay_used.size * scale)


## 数据改过之后作废；下次问 `is_free` 时重建。
func invalidate_def() -> void:
	_def = null


func _map_def() -> MapDef:
	if _def == null and model != null:
		var MapDefLib := preload("res://core/map_def.gd")
		_def = MapDefLib.from_dictionary(model.data)
	return _def


## 脚底方块：**以落点为底、往上伸**（脚下一线为 0）。
## 和 `WalkGrid` 里那套判据同一份常量 —— 所以画出来的框就是真机判定用的框。
func foot_rect_at(point: Vector2) -> Rect2:
	var WalkGrid := preload("res://core/walk_grid.gd")
	return Rect2(
		point.x - WalkGrid.FOOT_HALF,
		point.y - WalkGrid.FOOT_UP,
		WalkGrid.FOOT_HALF * 2.0,
		WalkGrid.FOOT_UP - WalkGrid.FOOT_DOWN)


## 这个落点站不站得住（调的是游戏同一份 `WalkGrid.is_free`）。
func foot_is_free(point: Vector2) -> bool:
	var def := _map_def()
	if def == null:
		return false
	var WalkGrid := preload("res://core/walk_grid.gd")
	return WalkGrid.is_free(def, point)


func fit_to_view() -> void:
	if map_size == Vector2.ZERO or size.x <= 0.0 or size.y <= 0.0:
		return
	_view_touched = false
	zoom = maxf(0.01, minf((size.x - 24.0) / map_size.x, (size.y - 24.0) / map_size.y))
	pan = (size - map_size * zoom) * 0.5
	queue_redraw()


func frame_selection() -> bool:
	if selected_trigger >= 0:
		return _frame_bounds(_trigger_rect(selected_trigger))
	if model == null or sel_kind < 0 or size.x <= 24.0 or size.y <= 24.0:
		return false
	if _drag_mode != 0:
		return false
	if not is_kind_visible(sel_kind):
		status.emit("所选项所在图层未显示，请先在顶部打开显示开关。")
		return false
	var bounds := Rect2()
	var has_bounds := false
	if sel_kind == Kind.ACTOR:
		for index: int in selected_actors():
			if index < 0 or index >= model.count(Kind.ACTOR) or actor_is_hidden(index):
				continue
			var actor_rect: Rect2 = model.rect_of(Kind.ACTOR, index)
			bounds = bounds.merge(actor_rect) if has_bounds else actor_rect
			for part: Dictionary in actor_visual_items(index):
				bounds = bounds.merge(part["rect"])
			has_bounds = true
	else:
		if sel_index < 0 or sel_index >= model.count(sel_kind):
			return false
		bounds = overlay_game_rect() if sel_kind == Kind.OVERLAY else model.rect_of(sel_kind, sel_index)
		has_bounds = true
	if not has_bounds:
		status.emit("选区中没有可见物件，请先显示后再定位。")
		return false
	return _frame_bounds(bounds)


func _frame_bounds(bounds: Rect2) -> bool:
	if not bounds.has_area() or size.x <= 24.0 or size.y <= 24.0 or _drag_mode != 0:
		return false
	var framing_size := Vector2(maxf(bounds.size.x, 24.0), maxf(bounds.size.y, 24.0)) * 1.25
	zoom = clampf(minf((size.x - 24.0) / framing_size.x, (size.y - 24.0) / framing_size.y), 0.01, 12.0)
	pan = size * 0.5 - bounds.get_center() * zoom
	_view_touched = true
	queue_redraw()
	return true


func set_trigger_selection(index: int) -> void:
	selected_trigger = index if _trigger_rect(index).has_area() else -1
	if selected_trigger >= 0:
		_frame_bounds(_trigger_rect(selected_trigger))
	queue_redraw()


func _trigger_rect(index: int) -> Rect2:
	if model == null:
		return Rect2()
	var triggers: Variant = model.data.get("triggers", [])
	if not triggers is Array or index < 0 or index >= triggers.size() or not triggers[index] is Dictionary:
		return Rect2()
	return ObjectTransform.rect_from(triggers[index].get("rect"))


func _on_viewport_resized() -> void:
	if not _view_touched:
		fit_to_view()


func recompute_walk() -> void:
	_walk_texture = null
	if model == null:
		return
	var WalkGrid := preload("res://core/walk_grid.gd")
	var MapDefLib := preload("res://core/map_def.gd")
	var def: MapDef = MapDefLib.from_dictionary(model.data)
	var step := WalkGrid.STEP
	var w := int(ceilf(map_size.x / step))
	var h := int(ceilf(map_size.y / step))
	if w <= 0 or h <= 0:
		return
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.85, 0.25, 0.25, 0.18))
	for gy in range(h):
		for gx in range(w):
			# 取格子中心判断（和 `test_walkable` 一套口径）
			var point := Vector2((gx + 0.5) * step, (gy + 0.5) * step)
			if WalkGrid.is_free(def, point):
				img.set_pixel(gx, gy, Color(0.35, 0.95, 0.65, 0.22))
	_walk_texture = ImageTexture.create_from_image(img)
	queue_redraw()
	status.emit("可走格算完了：绿=站得住，红=站不住")


func set_walk_visible(on: bool) -> void:
	show_walk = on
	if on and _walk_texture == null:
		recompute_walk()
	queue_redraw()


# ---------------------------------------------------------------- 坐标

func to_screen(p: Vector2) -> Vector2:
	return pan + p * zoom


func to_game(p: Vector2) -> Vector2:
	return (p - pan) / zoom


func _snap(p: Vector2) -> Vector2:
	return p.snapped(Vector2.ONE * snap_step)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if model == null or tool != Tool.SELECT or not is_kind_editable(Kind.ACTOR) \
			or map_size.x <= 0.0 or map_size.y <= 0.0:
		return false
	if not Rect2(Vector2.ZERO, map_size).has_point(to_game(at_position)):
		return false
	if not data is Dictionary:
		return false
	if data.get("type") == "if_map_template":
		return template_library != null and template_library.resolve_template(str(data.get("name", ""))).get("ok", false)
	if str(data.get("type", "")) != "if_map_asset":
		return false
	var path := str(data.get("path", ""))
	if not path.begins_with("res://art/props/") or path.get_extension().to_lower() != "png":
		return false
	return FileAccess.file_exists(path) and load(path) is Texture2D


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	if data.get("type") == "if_map_template":
		var name := str(data["name"])
		var resolved: Dictionary = template_library.resolve_template(name)
		var actor := MapDef._actor_from(resolved["actor"])
		var placed: Array[int] = template_library.instantiate(name, model, _snap(to_game(at_position) - actor.rect.get_center()))
		if not placed.is_empty():
			select_actors(placed)
			edited.emit()
			selection_changed.emit()
			queue_redraw()
			status.emit("已放置模板「%s」，碰撞、交互与模板跟踪一并保留。" % name)
		return
	var path := str(data["path"])
	var index: int = model.add_actor_with_sprite(path)
	if index < 0:
		return
	var size: Vector2 = model.rect_of(Kind.ACTOR, index).size
	var position := _snap(to_game(at_position) - size * 0.5)
	model.set_actor_field(index, "rect", [position.x, position.y, size.x, size.y])
	select_actors([index])
	_drag_mode = 0
	edited.emit()
	selection_changed.emit()
	queue_redraw()
	status.emit("已按背景原图像素比例放置 %s（%.2f×%.2f 地图单位），可继续手动缩放。" % [path.get_file().get_basename(), size.x, size.y])


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if map_size == Vector2.ZERO:
		return
	var full := Rect2(to_screen(Vector2.ZERO), map_size * zoom)
	if show_bg and tex_bg != null:
		draw_texture_rect(tex_bg, full, false)
	else:
		draw_rect(full, Color(0.12, 0.12, 0.16), true)
	if show_grid:
		_draw_grid()
	if model != null and is_kind_visible(Kind.ACTOR):
		for index in model.count(Kind.ACTOR):
			if not actor_is_hidden(index):
				_draw_rect_game(model.rect_of(Kind.ACTOR, index), ACTOR_FILL, Color.TRANSPARENT)
	_draw_visual_layer("back")
	_draw_visual_layer("auto")
	if is_kind_visible(Kind.OVERLAY) and tex_overlay != null:
		draw_texture_rect(tex_overlay, full, false, Color(1, 1, 1, overlay_alpha))
		# 前景层不是物件，但它**恒在角色之上**（OVERLAY_Z 13）——
		# 圈一下它的实际范围，标注一句，免得被当成普通背景。
		if _overlay_used.size.x > 0.0:
			var band := overlay_game_rect()
			var band_screen := Rect2(to_screen(band.position), band.size * zoom)
			draw_dashed_line(band_screen.position, band_screen.position + Vector2(band_screen.size.x, 0),
				OVERLAY_MARK, 1.0, 5.0)
			draw_dashed_line(band_screen.position + Vector2(band_screen.size.x, 0),
				band_screen.position + band_screen.size, OVERLAY_MARK, 1.0, 5.0)
			_label(band.position + Vector2(2, -3), "前景层：恒在角色之上", OVERLAY_MARK)
	_draw_visual_layer("front")
	if show_walk and _walk_texture != null:
		draw_texture_rect(_walk_texture, full, false)
	if model == null:
		return

	if is_kind_visible(Kind.WALL):
		for i in model.count(Kind.WALL):
			_draw_rect_game(model.rect_of(Kind.WALL, i), WALL_FILL, WALL_EDGE)
	if is_kind_visible(Kind.PORTAL):
		for i in model.count(Kind.PORTAL):
			var r: Rect2 = model.rect_of(Kind.PORTAL, i)
			_draw_rect_game(r, PORTAL_FILL, PORTAL_EDGE)
			_label(r.position + Vector2(2, 9), model.label_of(Kind.PORTAL, i), PORTAL_EDGE)
	if is_kind_visible(Kind.ACTOR):
		for i in model.count(Kind.ACTOR):
			if actor_is_hidden(i):
				continue
			var r: Rect2 = model.rect_of(Kind.ACTOR, i)
			var actor_edge := Color(0.62, 0.66, 0.70, 0.9) if actor_is_locked(i) else ACTOR_EDGE
			_draw_rect_game(r, Color.TRANSPARENT, actor_edge)
			_label(r.position + Vector2(2, r.size.y - 3), model.label_of(Kind.ACTOR, i), actor_edge)
			if model.is_cover_actor(i):
				_draw_baseline(i)
			if selected_actors().has(i):
				var actor := MapDef._actor_from(model.actor_dict(i))
				var shapes := actor.collision_rects()
				for shape_index in shapes.size():
					var shape: Rect2 = shapes[shape_index]
					if i == _collision_actor and shape_index == _collision_index \
							and (_drag_mode == 5 or _drag_mode == 6) and _collision_drag_valid():
						shape = _drag_new_rect
					_draw_rect_game(shape, WALL_FILL, WALL_EDGE, 2.0)
				_draw_rect_game(actor.reach, Color(0.2, 0.7, 1, 0.08), PORTAL_EDGE)
				_draw_rect_game(r, Color.TRANSPARENT, SELECT_COLOR, 2.0)

	# 出生点（紫点 + 名字）
	if is_kind_visible(Kind.SPAWN):
		for i in model.count(Kind.SPAWN):
			var p := to_screen(model.spawn_point(i))
			draw_circle(p, 4.0, SPAWN_COLOR)
			draw_string(ThemeDB.fallback_font, p + Vector2(7, 4), model.label_of(Kind.SPAWN, i),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SPAWN_COLOR)

	if _drag_mode == 3 or _drag_mode == 7 or _drag_mode == 8:
		_draw_rect_game(_drag_new_rect, Color(1, 1, 1, 0.15), SELECT_COLOR)

	# 测试工具：鼠标处的脚底框（绿=站得住，红=站不住）
	if show_foot and _mouse_inside and model != null:
		var foot := foot_rect_at(_mouse_game)
		var ok := foot_is_free(_mouse_game)
		var color := Color(0.35, 0.95, 0.55, 1.0) if ok else Color(1.0, 0.4, 0.4, 1.0)
		_draw_rect_game(foot, Color(color.r, color.g, color.b, 0.22), color, 2.0)
		draw_line(to_screen(Vector2(foot.position.x, _mouse_game.y)),
			to_screen(Vector2(foot.end.x, _mouse_game.y)), color, 1.0)
		_label(Vector2(foot.position.x, foot.position.y - 3),
			"%s  (%d, %d)" % ["站得住" if ok else "站不住", int(_mouse_game.x), int(_mouse_game.y)], color)

	if sel_kind >= 0 and is_kind_visible(sel_kind) \
			and not (sel_kind == Kind.ACTOR and actor_is_hidden(sel_index)):
		var r: Rect2 = overlay_game_rect() if sel_kind == Kind.OVERLAY \
			else model.rect_of(sel_kind, sel_index)
		_draw_rect_game(r, Color(0, 0, 0, 0), SELECT_COLOR, 2.0)
		# 出生点是个点、前景层整张拉伸 —— 都没有「改尺寸」这回事，不给手柄
		if tool == Tool.SELECT and is_kind_editable(sel_kind) \
				and sel_kind != Kind.SPAWN and sel_kind != Kind.OVERLAY \
				and selected_actors().size() <= 1 and _actor_selection_block_reason().is_empty() \
				and not _has_collision_selection():
			for h in _handle_points(r):
				draw_rect(Rect2(h - Vector2(HANDLE_SIZE, HANDLE_SIZE) * 0.5,
					Vector2(HANDLE_SIZE, HANDLE_SIZE)), SELECT_COLOR, true)
	if (tool == Tool.SELECT or tool == Tool.COLLISION) and _has_collision_selection():
		var collision_rect := _drag_new_rect if _drag_mode == 5 or _drag_mode == 6 \
			else _collision_rect_at(_collision_index)
		_draw_rect_game(collision_rect, Color.TRANSPARENT, SELECT_COLOR, 2.0)
		for handle in _handle_points(collision_rect):
			draw_rect(Rect2(handle - Vector2.ONE * HANDLE_SIZE * 0.5,
				Vector2.ONE * HANDLE_SIZE), WALL_EDGE, true)
	_draw_trigger_regions()


func _draw_trigger_regions() -> void:
	if model == null or not trigger_regions_visible or isolated_layer == EDIT_LAYER_ACTORS:
		return
	var triggers: Variant = model.data.get("triggers", [])
	if not triggers is Array:
		return
	for index in triggers.size():
		var rect := _trigger_rect(index)
		if not rect.has_area():
			continue
		var selected: bool = index == selected_trigger
		var color := SELECT_COLOR if selected else Color(0.72, 0.50, 1.0, 0.9)
		_draw_rect_game(rect, Color.TRANSPARENT, color, 3.0 if selected else 1.0)
		_label(rect.position + Vector2(2, 10), str(triggers[index].get("id", "触发区域 %d" % index)), color)


func _draw_grid() -> void:
	var step := snap_step * maxf(1.0, ceilf(8.0 / (snap_step * zoom)))
	var start := to_game(Vector2.ZERO).max(Vector2.ZERO)
	var end := to_game(size).min(map_size)
	if end.x < start.x or end.y < start.y:
		return
	var color := Color(0.8, 0.85, 1.0, 0.16)
	for column in range(int(ceilf(start.x / step)), int(floorf(end.x / step)) + 1):
		var coordinate := float(column) * step
		draw_line(to_screen(Vector2(coordinate, start.y)), to_screen(Vector2(coordinate, end.y)), color)
	for row in range(int(ceilf(start.y / step)), int(floorf(end.y / step)) + 1):
		var coordinate := float(row) * step
		draw_line(to_screen(Vector2(start.x, coordinate)), to_screen(Vector2(end.x, coordinate)), color)


func actor_visual_items(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if model == null or index < 0 or index >= model.count(Kind.ACTOR):
		return result
	var actor: Dictionary = model.actor_dict(index)
	var rect: Rect2 = model.rect_of(Kind.ACTOR, index)
	var parts: Variant = actor.get("visual_parts", [])
	if parts is Array and not parts.is_empty():
		for part: Variant in parts:
			if not part is Dictionary:
				continue
			var local := ObjectTransform.rect_from(part.get("rect"))
			var layer := str(part.get("layer", "auto"))
			result.append({"actor_index": index, "sprite": str(part.get("sprite", "")),
				"rect": Rect2(rect.position + local.position, local.size),
				"layer": layer if layer in ["back", "auto", "front"] else "auto",
				"sort_offset": float(part.get("sort_offset", 0.0))})
	else:
		result.append({"actor_index": index, "sprite": str(actor.get("sprite", "")),
			"rect": rect, "layer": "front" if bool(actor.get("over", false)) else "auto",
			"sort_offset": 0.0})
	return result


func _draw_visual_layer(layer: String) -> void:
	if model == null or not is_kind_visible(Kind.ACTOR):
		return
	for index in model.count(Kind.ACTOR):
		if actor_is_hidden(index):
			continue
		for item: Dictionary in actor_visual_items(index):
			if str(item["layer"]) != layer:
				continue
			var texture := _load_tex(str(item["sprite"]))
			var rect: Rect2 = item["rect"]
			if texture == null or not rect.has_area():
				continue
			var screen := Rect2(to_screen(rect.position), rect.size * zoom)
			draw_set_transform_matrix(ObjectTransform.visual_transform(screen, model.actor_dict(index)))
			draw_texture_rect(texture, Rect2(-0.5, -0.5, 1, 1), false)
			draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_rect_game(r: Rect2, fill: Color, edge: Color, width := 1.0) -> void:
	var screen := Rect2(to_screen(r.position), r.size * zoom)
	if fill.a > 0.0:
		draw_rect(screen, fill, true)
	draw_rect(screen, edge, false, width)


func _draw_baseline(index: int) -> void:
	var r: Rect2 = model.rect_of(Kind.ACTOR, index)
	var y: float = model.actor_cover_y(index)
	var from := to_screen(Vector2(r.position.x, y))
	var to := to_screen(Vector2(r.position.x + r.size.x, y))
	var color := BASE_MANUAL if model.has_cover_override(index) else BASE_AUTO
	draw_dashed_line(from, to, color, 2.0, 6.0)
	_label(Vector2(r.position.x + 2, y - 3), "基线 %.0f" % y, color)


func _label(game_pos: Vector2, text: String, color: Color) -> void:
	if text == "":
		return
	draw_string(ThemeDB.fallback_font, to_screen(game_pos), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _handle_points(r: Rect2) -> Array[Vector2]:
	var a := to_screen(r.position)
	var b := to_screen(r.position + r.size)
	var mx := (a.x + b.x) * 0.5
	var my := (a.y + b.y) * 0.5
	return [
		Vector2(a.x, a.y), Vector2(mx, a.y), Vector2(b.x, a.y),
		Vector2(a.x, my), Vector2(b.x, my),
		Vector2(a.x, b.y), Vector2(mx, b.y), Vector2(b.x, b.y),
	]


# ---------------------------------------------------------------- 鼠标

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE \
			or what == NOTIFICATION_FOCUS_EXIT:
		_clear_collision_selection()
		if _drag_mode == 8:
			_drag_mode = 0
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_clear_collision_selection()
		if _drag_mode == 8:
			_drag_mode = 0


func _input(event: InputEvent) -> void:
	if _drag_mode < 1 or _drag_mode > 8:
		return
	if event is InputEventMouseMotion:
		_update_pointer_drag(get_global_transform_with_canvas().affine_inverse() * event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_update_pointer_drag(get_global_transform_with_canvas().affine_inverse() * event.position)
		_release()
		if is_inside_tree():
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and shortcuts != null:
		_route_shortcut(event)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_clear_collision_selection()
		if _drag_mode == 8:
			_drag_mode = 0
			queue_redraw()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if model == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_clear_collision_selection()
				_drag_mode = 9
				_drag_start_game = mb.position - pan
			elif _drag_mode == 9:
				_drag_mode = 0
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_press(mb.position, mb.shift_pressed, mb.ctrl_pressed or mb.meta_pressed, mb.alt_pressed)
			else:
				_update_pointer_drag(mb.position)
				_release()
			return
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse_game = to_game(mm.position)
		if show_foot:
			queue_redraw()
		_update_pointer_drag(mm.position)
		return
	elif event is InputEventKey:
		if shortcuts != null:
			_route_shortcut(event)
			return
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			_clear_collision_selection()
			if _drag_mode == 8:
				_drag_mode = 0
				queue_redraw()
			accept_event()
			return
		if key.pressed and not key.echo and key.keycode == KEY_F \
				and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
			frame_selection()
			accept_event()
			return
		if key.pressed and not key.echo and key.ctrl_pressed:
			var command: String = {KEY_C: "copy", KEY_V: "paste", KEY_D: "duplicate",
				KEY_Y: "redo", KEY_Z: "redo" if key.shift_pressed else "undo"}.get(key.keycode, "")
			if command != "":
				_clear_collision_selection()
				command_requested.emit(command)
				accept_event()
				return
		if key.pressed and key.keycode == KEY_DELETE and sel_kind >= 0:
			_clear_collision_selection()
			if not is_kind_editable(sel_kind):
				return
			if sel_kind == Kind.ACTOR:
				status.emit("删除物件请使用「选择与尺寸 → 删除选中」，以便检查剧情引用。")
				return
			model.remove_at(sel_kind, sel_index)
			sel_kind = -1
			sel_index = -1
			edited.emit()
			selection_changed.emit()
			queue_redraw()


func _route_shortcut(event: InputEvent) -> void:
	var command := str(shortcuts.action_for(event))
	if command.is_empty():
		return
	_clear_collision_selection()
	if command == "cancel" and _drag_mode == 8:
		_drag_mode = 0
		queue_redraw()
	command_requested.emit(command)
	accept_event()


func _update_pointer_drag(pos: Vector2) -> void:
	match _drag_mode:
		9:
			_view_touched = true
			pan = pos - _drag_start_game
			queue_redraw()
		1:
			var delta := _snap(to_game(pos) - _drag_start_game)
			if _duplicate_on_drag and delta != Vector2.ZERO:
				_duplicate_drag_selection()
			if sel_kind == Kind.ACTOR:
				for index: int in _drag_actor_rects:
					var initial: Rect2 = _drag_actor_rects[index]
					var target := Rect2(initial.position + delta, initial.size)
					if model.rect_of(Kind.ACTOR, index) != target:
						model.set_rect(Kind.ACTOR, index, target)
			else:
				var target := Rect2(_drag_start_rect.position + delta, _drag_start_rect.size)
				if model.rect_of(sel_kind, sel_index) != target:
					model.set_rect(sel_kind, sel_index, target)
			queue_redraw()
		2:
			_resize_to(pos)
			queue_redraw()
		3, 8:
			var start := to_game(pos) if _drag_mode == 8 else _snap(to_game(pos))
			var origin := _drag_start_game if _drag_mode == 8 else _snap(_drag_start_game)
			_drag_new_rect = Rect2(origin.min(start), (start - origin).abs())
			queue_redraw()
		4:
			var baseline := _snap(to_game(pos)).y
			model.set_actor_cover_y(sel_index, baseline)
			queue_redraw()
			status.emit("基线拖动中：%.2f（松手即写入）" % baseline)
		5, 6, 7:
			_update_collision_drag(pos)


func _press(pos: Vector2, additive := false, toggle := false, duplicate := false) -> void:
	_duplicate_on_drag = false
	selected_trigger = -1
	if (tool == Tool.SELECT or tool == Tool.COLLISION) and not duplicate \
			and (not additive and not toggle or _hit_collision_handle(pos) >= 0) and _press_collision(pos):
		return
	_clear_collision_selection()
	match tool:
		Tool.COLLISION:
			if sel_kind != Kind.ACTOR:
				status.emit("先在左侧选中一个物件，再在图上拖出它的碰撞箱。")
				return
			if not _actor_selection_block_reason().is_empty():
				status.emit("物件已隐藏或锁定，请先在左侧场景列表中显示并解锁。")
				return
			if not _collision_editable():
				status.emit("编辑碰撞箱需要单选一个可见且未锁定的独立物件。")
				return
			_begin_collision_drag(7, pos)
		Tool.WALL, Tool.PORTAL:
			if not is_kind_editable(Kind.WALL if tool == Tool.WALL else Kind.PORTAL):
				return
			_drag_mode = 3
			_drag_start_game = to_game(pos)
			_drag_new_rect = Rect2(_snap(_drag_start_game), Vector2.ZERO)
		Tool.BASELINE:
			var index := _hit_cover_actor(pos)
			if index >= 0:
				sel_kind = Kind.ACTOR
				sel_index = index
				_drag_mode = 4
				selection_changed.emit()
				status.emit("拖动中：上下移动鼠标改基线，松手写入 JSON")
				queue_redraw()
		_:
			var handle := _hit_handle(pos) if selected_actors().size() <= 1 \
				and not additive and not toggle and not duplicate else -1
			if handle >= 0:
				_drag_mode = 2
				_drag_handle = handle
				_drag_start_rect = model.rect_of(sel_kind, sel_index)
				_drag_actor_sources.clear()
				if sel_kind == Kind.ACTOR:
					_drag_actor_sources[sel_index] = model.actor_dict(sel_index).duplicate(true)
				return
			var hit := _hit_item(pos)
			if hit.x < 0 or hit.x == Kind.OVERLAY:
				for index: int in selected_actors():
					if (actor_is_hidden(index) or actor_is_locked(index)) \
						and _rect_hit(model.rect_of(Kind.ACTOR, index), pos, HIT_SLOP):
						status.emit("物件已隐藏或锁定，请先显示并解锁。")
						return
				_drag_mode = 8
				_drag_start_game = to_game(pos)
				_drag_new_rect = Rect2(_drag_start_game, Vector2.ZERO)
				_marquee_additive = additive
				_marquee_toggle = toggle
				_marquee_selection = selected_actors()
				_marquee_fallback = hit
				queue_redraw()
				return
			if hit.x == Kind.ACTOR:
				var selection := selected_actors()
				if additive or toggle:
					var hit_selection: Array[int] = [hit.y]
					var members: Array[int] = model.expand_group_selection(hit_selection)
					var remove := toggle and selection.has(hit.y)
					for member: int in members:
						if remove:
							selection.erase(member)
						elif not selection.has(member):
							selection.append(member)
					select_actors(selection)
					selection_changed.emit()
					return
				if not selection.has(hit.y):
					selection = [hit.y]
				actor_selection = model.expand_group_selection(selection)
			else:
				actor_selection.clear()
			sel_kind = hit.x
			sel_index = hit.y
			selection_changed.emit()
			if sel_kind >= 0:
				var block_reason := _actor_selection_block_reason() if sel_kind == Kind.ACTOR else ""
				if block_reason.is_empty():
					_drag_mode = 1
					_drag_start_game = to_game(pos)
					_drag_start_rect = model.rect_of(sel_kind, sel_index)
					_drag_actor_rects.clear()
					_drag_actor_sources.clear()
					for index: int in selected_actors():
						_drag_actor_rects[index] = model.rect_of(Kind.ACTOR, index)
						_drag_actor_sources[index] = model.actor_dict(index).duplicate(true)
					_duplicate_on_drag = duplicate and sel_kind == Kind.ACTOR
				else:
					status.emit(block_reason)
			queue_redraw()


func _finish_marquee() -> void:
	var selection: Array[int] = []
	if _marquee_additive or _marquee_toggle:
		selection.assign(_marquee_selection)
	var candidates: Array[int] = []
	if _drag_new_rect.size.length() * zoom >= 3.0 and _drag_new_rect.has_area() \
			and is_kind_editable(Kind.ACTOR):
		for index in model.count(Kind.ACTOR):
			if actor_is_hidden(index) or actor_is_locked(index):
				continue
			var intersects: bool = _drag_new_rect.intersects(model.rect_of(Kind.ACTOR, index))
			for part: Dictionary in actor_visual_items(index):
				intersects = intersects or _drag_new_rect.intersects(part["rect"])
			if not intersects:
				continue
			var hit_selection: Array[int] = [index]
			var members: Array[int] = model.expand_group_selection(hit_selection)
			var editable := true
			for member: int in members:
				if actor_is_hidden(member) or actor_is_locked(member):
					editable = false
					break
			if editable:
				for member: int in members:
					if not candidates.has(member):
						candidates.append(member)
	for index: int in candidates:
		if _marquee_toggle and _marquee_selection.has(index):
			selection.erase(index)
		elif not selection.has(index):
			selection.append(index)
	select_actors(selection)
	if selection.is_empty() and not _marquee_additive and not _marquee_toggle \
			and _drag_new_rect.size.length() * zoom < 3.0 and _marquee_fallback.x == Kind.OVERLAY:
		sel_kind = Kind.OVERLAY
		sel_index = 0
	selection_changed.emit()


func _duplicate_drag_selection() -> void:
	_duplicate_on_drag = false
	var originals := selected_actors()
	var clipboard: Array = model._clipboard.duplicate(true)
	var clipboard_groups: Array = model._clipboard_groups.duplicate(true)
	var serial: int = model._paste_serial
	model.copy_actors(originals)
	var copies: Array[int] = model.paste_actors()
	model._clipboard.assign(clipboard)
	model._clipboard_groups.assign(clipboard_groups)
	model._paste_serial = serial
	for offset in copies.size():
		model.set_rect(Kind.ACTOR, copies[offset], model.rect_of(Kind.ACTOR, originals[offset]))
	select_actors(copies)
	_drag_actor_rects.clear()
	_drag_actor_sources.clear()
	for index: int in copies:
		_drag_actor_rects[index] = model.rect_of(Kind.ACTOR, index)
		_drag_actor_sources[index] = model.actor_dict(index).duplicate(true)
	selection_changed.emit()


func _release() -> void:
	if _drag_mode >= 5 and _drag_mode <= 7:
		_release_collision_drag()
		return
	if _drag_mode == 8:
		_finish_marquee()
		_drag_mode = 0
		queue_redraw()
		return
	if _drag_mode == 3:
		var r := Rect2(_snap(_drag_new_rect.position),
			_snap(_drag_new_rect.size).max(Vector2.ONE * minf(1.0, snap_step)))
		if tool == Tool.COLLISION:
			model.add_collision_rect(sel_index, r)
		else:
			var kind: int = Kind.WALL if tool == Tool.WALL else Kind.PORTAL
			sel_index = model.add_rect(kind, r)
			sel_kind = kind
		edited.emit()
		selection_changed.emit()
	elif _drag_mode == 4:
		edited.emit()
	elif _drag_mode == 1 or _drag_mode == 2:
		edited.emit()
	_drag_mode = 0
	_duplicate_on_drag = false
	_drag_actor_sources.clear()
	invalidate_def()
	queue_redraw()


func _zoom_at(pos: Vector2, factor: float) -> void:
	var before := to_game(pos)
	_view_touched = true
	zoom = clampf(zoom * factor, 0.01, 12.0)
	pan = pos - before * zoom
	queue_redraw()


func _resize_to(pos: Vector2) -> void:
	var target := _resized_rect(pos)
	if sel_kind == Kind.ACTOR and _drag_actor_sources.has(sel_index):
		ObjectTransform.write_actor(model, sel_index,
			ObjectTransform.resized_actor(_drag_actor_sources[sel_index], target))
	else:
		model.set_rect(sel_kind, sel_index, target)


func _resized_rect(pos: Vector2) -> Rect2:
	var r := _drag_start_rect
	var g := _snap(to_game(pos))
	match _drag_handle:
		0:
			r.position.x = g.x; r.size.x = _drag_start_rect.end.x - r.position.x
			r.position.y = g.y; r.size.y = _drag_start_rect.end.y - r.position.y
		1:
			r.position.y = g.y; r.size.y = _drag_start_rect.end.y - r.position.y
		2:
			r.size.x = g.x - r.position.x
			r.position.y = g.y; r.size.y = _drag_start_rect.end.y - r.position.y
		3:
			r.position.x = g.x; r.size.x = _drag_start_rect.end.x - r.position.x
		4:
			r.size.x = g.x - r.position.x
		5:
			r.position.x = g.x; r.size.x = _drag_start_rect.end.x - r.position.x
			r.size.y = g.y - r.position.y
		6:
			r.size.y = g.y - r.position.y
		7:
			r.size.x = g.x - r.position.x
			r.size.y = g.y - r.position.y
	if r.size.x < 1.0:
		r.size.x = 1.0
	if r.size.y < 1.0:
		r.size.y = 1.0
	return r


## 这一类现在露不露。
##
## **显示开关同时管「能不能点中」** —— 物件压在碰撞块上时（委托屋那张书桌），
## 只关显示不改选中，底下那块墙一辈子点不到。关掉那一类，就等于把它
## 从「可点」里摘出去。
func is_kind_visible(kind: int) -> bool:
	var layer := EDIT_LAYER_ACTORS if kind == Kind.ACTOR else EDIT_LAYER_STRUCTURE
	if not isolated_layer.is_empty() and isolated_layer != layer \
			and isolated_layer != str(KIND_LAYERS.get(kind, "")):
		return false
	match kind:
		Kind.WALL:
			return show_walls
		Kind.PORTAL:
			return show_portals
		Kind.ACTOR:
			return show_actors
		Kind.SPAWN:
			return show_spawns
		_:
			return show_overlay


func set_layer_visible(prop: String, on: bool) -> void:
	set(prop, on)
	if not show_actors:
		_clear_collision_selection()
	if prop == "show_walk":
		set_walk_visible(on)
	elif sel_kind >= 0 and not is_kind_visible(sel_kind):
		# 把选中项所在的那一类关掉了，选中也跟着收起来 ——
		# 不然会出现「看不见的白框还挂着八个手柄」
		sel_kind = -1
		sel_index = -1
		selection_changed.emit()
	queue_redraw()


func _hit_item(pos: Vector2) -> Vector2i:
	# 后画的压在上面 —— 和渲染顺序相反着找。
	# 隐藏的那几类直接跳过（见 `is_kind_visible`）。
	# **出生点排在最前**：它只有 6×6，压在墙或物件上时不该被盖住选不中。
	if is_kind_editable(Kind.SPAWN):
		for i in range(model.count(Kind.SPAWN) - 1, -1, -1):
			if _rect_hit(model.rect_of(Kind.SPAWN, i), pos, 2.0):
				return Vector2i(Kind.SPAWN, i)
	if is_kind_editable(Kind.ACTOR):
		for i in range(model.count(Kind.ACTOR) - 1, -1, -1):
			if not actor_is_hidden(i) and not actor_is_locked(i) \
					and _actor_hit(i, pos):
				return Vector2i(Kind.ACTOR, i)
	if is_kind_editable(Kind.PORTAL):
		for i in range(model.count(Kind.PORTAL) - 1, -1, -1):
			if _rect_hit(model.rect_of(Kind.PORTAL, i), pos):
				return Vector2i(Kind.PORTAL, i)
	if is_kind_editable(Kind.WALL):
		for i in range(model.count(Kind.WALL) - 1, -1, -1):
			if _rect_hit(model.rect_of(Kind.WALL, i), pos):
				return Vector2i(Kind.WALL, i)
	# 前景层排最后：它盖着大半张图，别的能点中就优先点别的。
	# 想专门点它，把「墙 / 物件」那几层关掉就干净了（显示开关同时管能不能点中）。
	if is_kind_editable(Kind.OVERLAY) and model.count(Kind.OVERLAY) > 0:
		if _rect_hit(overlay_game_rect(), pos):
			return Vector2i(Kind.OVERLAY, 0)
	return Vector2i(-1, -1)


func _hit_cover_actor(pos: Vector2) -> int:
	if not is_kind_editable(Kind.ACTOR):
		return -1
	for i in range(model.count(Kind.ACTOR) - 1, -1, -1):
		if actor_is_hidden(i) or actor_is_locked(i) or not model.is_cover_actor(i):
			continue
		if _rect_hit(model.rect_of(Kind.ACTOR, i), pos, 6.0):
			return i
	return -1


func _actor_hit(index: int, pos: Vector2) -> bool:
	if _rect_hit(model.rect_of(Kind.ACTOR, index), pos):
		return true
	for part: Dictionary in actor_visual_items(index):
		if _rect_hit(part["rect"], pos):
			return true
	return false


func _rect_hit(r: Rect2, pos: Vector2, slop := 0.0) -> bool:
	var screen := Rect2(to_screen(r.position), r.size * zoom)
	return screen.grow(slop).has_point(pos)


func _hit_handle(pos: Vector2) -> int:
	if sel_kind < 0 or tool != Tool.SELECT or not is_kind_editable(sel_kind):
		return -1
	if _has_collision_selection():
		return -1
	if sel_kind == Kind.SPAWN or sel_kind == Kind.OVERLAY:
		return -1          # 出生点没有尺寸；前景层整张拉伸，也改不了
	if sel_kind == Kind.ACTOR and not _actor_selection_block_reason().is_empty():
		return -1
	var r: Rect2 = model.rect_of(sel_kind, sel_index)
	var points := _handle_points(r)
	for i in points.size():
		if (points[i] as Vector2).distance_to(pos) <= HANDLE_SIZE:
			return i
	return -1
