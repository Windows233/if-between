## 编辑器的画布：把地图画出来、接鼠标。
##
## 坐标系：**屏幕像素 ↔ 游戏单位**（地图 `size`，1 游戏单位 = 背景图上的 12 像素）。
## 所有矩形数据都以游戏单位存，界面上的数字和 JSON 里的数字是同一个。
## 缩放/平移自己实现（不借 2D 编辑器），因为整个画布是自成一体的面板，
## 不依赖当前打开哪个场景。
##
## 四种工具：选择 / 画墙 / 画传送区 / 拉基线。
## 纯绘制与交互，数据全部交给 `map_edit_model.gd`。
extends Control

enum Tool { SELECT, WALL, PORTAL, BASELINE }

const Kind := preload("res://addons/if_map_editor/map_edit_model.gd").Kind

const WALL_FILL := Color(0.85, 0.25, 0.25, 0.30)
const WALL_EDGE := Color(0.95, 0.35, 0.32, 1.0)
const PORTAL_FILL := Color(0.20, 0.70, 0.85, 0.32)
const PORTAL_EDGE := Color(0.25, 0.78, 0.95, 1.0)
const ACTOR_FILL := Color(0.30, 0.80, 0.40, 0.22)
const ACTOR_EDGE := Color(0.35, 0.85, 0.45, 1.0)
const BASE_AUTO := Color(1.00, 0.86, 0.20, 1.0)
const BASE_MANUAL := Color(1.00, 0.50, 0.10, 1.0)
const SPAWN_COLOR := Color(0.90, 0.45, 0.95, 1.0)
const SELECT_COLOR := Color(1, 1, 1, 0.95)
const HANDLE_SIZE := 7.0
const HIT_SLOP := 4.0

signal selection_changed
signal edited
signal status(text)

var model = null
var tex_bg: Texture2D = null
var tex_overlay: Texture2D = null
var map_size := Vector2.ZERO

var tool: int = Tool.SELECT
var zoom := 1.0
var pan := Vector2.ZERO

var show_bg := true
var show_overlay := true
var show_walls := true
var show_portals := true
var show_actors := true
var show_walk := false

var sel_kind := -1
var sel_index := -1

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
	# 像素画缩小时要脆，不要糊
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# ---------------------------------------------------------------- 载入

func load_map(model_ref, bg_path: String, overlay_path: String, size: Vector2) -> void:
	model = model_ref
	map_size = size
	tex_bg = _load_tex(bg_path)
	tex_overlay = _load_tex(overlay_path)
	sel_kind = -1
	sel_index = -1
	_walk_texture = null
	fit_to_view()
	queue_redraw()
	selection_changed.emit()


func _load_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	var tex: Variant = _tex_cache[path]
	return tex if tex is Texture2D else null


func fit_to_view() -> void:
	if map_size == Vector2.ZERO or size.x <= 0.0 or size.y <= 0.0:
		return
	zoom = maxf(0.2, minf((size.x - 24.0) / map_size.x, (size.y - 24.0) / map_size.y))
	pan = (size - map_size * zoom) * 0.5
	queue_redraw()


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
	return Vector2(roundf(p.x), roundf(p.y))


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if map_size == Vector2.ZERO:
		return
	var full := Rect2(to_screen(Vector2.ZERO), map_size * zoom)
	if show_bg and tex_bg != null:
		draw_texture_rect(tex_bg, full, false)
	else:
		draw_rect(full, Color(0.12, 0.12, 0.16), true)
	if show_overlay and tex_overlay != null:
		draw_texture_rect(tex_overlay, full, false)
	if show_walk and _walk_texture != null:
		draw_texture_rect(_walk_texture, full, false)
	if model == null:
		return

	if show_walls:
		for i in model.count(Kind.WALL):
			_draw_rect_game(model.rect_of(Kind.WALL, i), WALL_FILL, WALL_EDGE)
	if show_portals:
		for i in model.count(Kind.PORTAL):
			var r: Rect2 = model.rect_of(Kind.PORTAL, i)
			_draw_rect_game(r, PORTAL_FILL, PORTAL_EDGE)
			_label(r.position + Vector2(2, 9), model.label_of(Kind.PORTAL, i), PORTAL_EDGE)
	if show_actors:
		for i in model.count(Kind.ACTOR):
			var r: Rect2 = model.rect_of(Kind.ACTOR, i)
			var item: Variant = model.actors()[i]
			var sprite_path := str((item as Dictionary).get("sprite", "")) if item is Dictionary else ""
			var tex := _load_tex(sprite_path)
			_draw_rect_game(r, ACTOR_FILL, ACTOR_EDGE)
			if tex != null:
				draw_texture_rect(tex, Rect2(to_screen(r.position), r.size * zoom), false)
			_label(r.position + Vector2(2, r.size.y - 3), model.label_of(Kind.ACTOR, i), ACTOR_EDGE)
			if model.is_cover_actor(i):
				_draw_baseline(i)

	# 出生点
	for key: Variant in model.spawns():
		var raw: Variant = model.spawns()[key]
		if raw is Array and (raw as Array).size() >= 2:
			var p := to_screen(Vector2(float(raw[0]), float(raw[1])))
			draw_circle(p, 4.0, SPAWN_COLOR)
			draw_string(ThemeDB.fallback_font, p + Vector2(7, 4), str(key),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SPAWN_COLOR)

	if _drag_mode == 3:
		_draw_rect_game(_drag_new_rect, Color(1, 1, 1, 0.15), SELECT_COLOR)

	if sel_kind >= 0 and is_kind_visible(sel_kind):
		var r: Rect2 = model.rect_of(sel_kind, sel_index)
		_draw_rect_game(r, Color(0, 0, 0, 0), SELECT_COLOR, 2.0)
		if tool == Tool.SELECT:
			for h in _handle_points(r):
				draw_rect(Rect2(h - Vector2(HANDLE_SIZE, HANDLE_SIZE) * 0.5,
					Vector2(HANDLE_SIZE, HANDLE_SIZE)), SELECT_COLOR, true)


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
				_drag_mode = 9
				_drag_start_game = mb.position - pan
			elif _drag_mode == 9:
				_drag_mode = 0
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position)
			else:
				_release()
			return
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		match _drag_mode:
			9:
				pan = mm.position - _drag_start_game
				queue_redraw()
			1:
				var delta := _snap(to_game(mm.position) - _drag_start_game)
				model.set_rect(sel_kind, sel_index, Rect2(_drag_start_rect.position + delta, _drag_start_rect.size))
				queue_redraw()
			2:
				_resize_to(mm.position)
				queue_redraw()
			3:
				var a := _snap(_drag_start_game)
				var b := _snap(to_game(mm.position))
				_drag_new_rect = Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)),
					Vector2(absf(b.x - a.x), absf(b.y - a.y)))
				queue_redraw()
			4:
				var y := roundf(to_game(mm.position).y)
				model.set_actor_cover_y(sel_index, y)
				queue_redraw()
				status.emit("基线拖动中：%.0f（松手即写入）" % y)
		return
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_DELETE and sel_kind >= 0:
			model.remove_at(sel_kind, sel_index)
			sel_kind = -1
			sel_index = -1
			edited.emit()
			selection_changed.emit()
			queue_redraw()


func _press(pos: Vector2) -> void:
	match tool:
		Tool.WALL, Tool.PORTAL:
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
			var handle := _hit_handle(pos)
			if handle >= 0:
				_drag_mode = 2
				_drag_handle = handle
				_drag_start_rect = model.rect_of(sel_kind, sel_index)
				return
			var hit := _hit_item(pos)
			sel_kind = hit.x
			sel_index = hit.y
			selection_changed.emit()
			if sel_kind >= 0:
				_drag_mode = 1
				_drag_start_game = to_game(pos)
				_drag_start_rect = model.rect_of(sel_kind, sel_index)
			queue_redraw()


func _release() -> void:
	if _drag_mode == 3:
		var r := Rect2(_snap(_drag_new_rect.position),
			Vector2(maxf(1.0, roundf(_drag_new_rect.size.x)), maxf(1.0, roundf(_drag_new_rect.size.y))))
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
	queue_redraw()


func _zoom_at(pos: Vector2, factor: float) -> void:
	var before := to_game(pos)
	zoom = clampf(zoom * factor, 0.1, 12.0)
	pan = pos - before * zoom
	queue_redraw()


func _resize_to(pos: Vector2) -> void:
	var r := _drag_start_rect
	var g := to_game(pos)
	match _drag_handle:
		0:
			r.position.x = roundf(g.x); r.size.x = _drag_start_rect.end.x - r.position.x
			r.position.y = roundf(g.y); r.size.y = _drag_start_rect.end.y - r.position.y
		1:
			r.position.y = roundf(g.y); r.size.y = _drag_start_rect.end.y - r.position.y
		2:
			r.size.x = roundf(g.x) - r.position.x
			r.position.y = roundf(g.y); r.size.y = _drag_start_rect.end.y - r.position.y
		3:
			r.position.x = roundf(g.x); r.size.x = _drag_start_rect.end.x - r.position.x
		4:
			r.size.x = roundf(g.x) - r.position.x
		5:
			r.position.x = roundf(g.x); r.size.x = _drag_start_rect.end.x - r.position.x
			r.size.y = roundf(g.y) - r.position.y
		6:
			r.size.y = roundf(g.y) - r.position.y
		7:
			r.size.x = roundf(g.x) - r.position.x
			r.size.y = roundf(g.y) - r.position.y
	if r.size.x < 1.0:
		r.size.x = 1.0
	if r.size.y < 1.0:
		r.size.y = 1.0
	model.set_rect(sel_kind, sel_index, r)


## 这一类现在露不露。
##
## **显示开关同时管「能不能点中」** —— 物件压在碰撞块上时（委托屋那张书桌），
## 只关显示不改选中，底下那块墙一辈子点不到。关掉那一类，就等于把它
## 从「可点」里摘出去。
func is_kind_visible(kind: int) -> bool:
	match kind:
		Kind.WALL:
			return show_walls
		Kind.PORTAL:
			return show_portals
		Kind.ACTOR:
			return show_actors
	return false


func set_layer_visible(prop: String, on: bool) -> void:
	set(prop, on)
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
	if show_actors:
		for i in range(model.count(Kind.ACTOR) - 1, -1, -1):
			if _rect_hit(model.rect_of(Kind.ACTOR, i), pos):
				return Vector2i(Kind.ACTOR, i)
	if show_portals:
		for i in range(model.count(Kind.PORTAL) - 1, -1, -1):
			if _rect_hit(model.rect_of(Kind.PORTAL, i), pos):
				return Vector2i(Kind.PORTAL, i)
	if show_walls:
		for i in range(model.count(Kind.WALL) - 1, -1, -1):
			if _rect_hit(model.rect_of(Kind.WALL, i), pos):
				return Vector2i(Kind.WALL, i)
	return Vector2i(-1, -1)


func _hit_cover_actor(pos: Vector2) -> int:
	if not show_actors:
		return -1
	for i in range(model.count(Kind.ACTOR) - 1, -1, -1):
		if not model.is_cover_actor(i):
			continue
		if _rect_hit(model.rect_of(Kind.ACTOR, i), pos, 6.0):
			return i
	return -1


func _rect_hit(r: Rect2, pos: Vector2, slop := 0.0) -> bool:
	var screen := Rect2(to_screen(r.position), r.size * zoom)
	return screen.grow(slop).has_point(pos)


func _hit_handle(pos: Vector2) -> int:
	if sel_kind < 0 or tool != Tool.SELECT:
		return -1
	var r: Rect2 = model.rect_of(sel_kind, sel_index)
	var points := _handle_points(r)
	for i in points.size():
		if (points[i] as Vector2).distance_to(pos) <= HANDLE_SIZE:
			return i
	return -1
