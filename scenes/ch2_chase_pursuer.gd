## 第二章校门追逐里的黑猫：独立的追兵实体。
##
## 自己寻路、自己走：每隔一小段时间用 AStarGrid2D 在「主角脚底框站得住」的格子上
## 重算一条到主角当前位置的八方向路线（绕开喷泉等墙体），再用 move_and_slide
## 顺着路线走。碰撞体与主角脚底框同尺寸，只撞场景墙体，不推主角。
## 「追上」= 两个脚底框相贴（`is_touching`），由 `Ch2ChaseSession` 读取后发起 QTE。
##
## 速度、出场时长等手感参数都在本文件常量里；标定依据见 `tests/probe_chase_pacing.gd`。
## 寻路格子和 `WalkGrid` 同一套脚底判定，地图改了墙体不需要改这里。
class_name Ch2ChasePursuer
extends CharacterBody2D

## 追兵速度（统一显示尺度，和 `Player.SPEED` 同一量纲；实际按节点 scale 换算）。
## 主角 96；校门地图上主角 48/秒、猫 64/秒。标定见 `tests/probe_chase_pacing.gd`。
const SPEED := 128.0
## 从地图边缘「浮现」的时间：这段时间里只淡入、不移动，给主角拉开起跑距离。
const EMERGE_TIME := 1.0
## 被闪开（QTE 成功冲刺结束）后扑空愣住的时间，让玩家看清自己甩开了它，也是拉开节奏的主要来源。
const RECOVER_TIME := 0.8
## 重新寻路的间隔（秒）。路线跟着主角变，太长会追着旧位置跑。
const REPATH_INTERVAL := 0.12
## 脚底框相贴的判定余量（地图单位）。
const TOUCH_MARGIN := 1.0
const CELL := WalkGrid.STEP
## 寻路时墙体外扩的余量（地图单位），避免沿墙边走时被物理安全边距卡住。
const WALL_MARGIN := 1.0
## 拉直路线时最多往前看多少个路点。
const LOOKAHEAD := 48

var target: Node2D
var map_def: MapDef
## 为 true 时原地不动（QTE、冲刺、救援、已进门）。
var holding := false
## 实际使用的速度；默认 `SPEED`，标定探针会临时改它扫参数。
var speed_value := SPEED

var _grid: AStarGrid2D
var _path: Array[Vector2] = []
var _aim := Vector2.ZERO
## 当前目标就是主角本人（直线可达），朝向逐帧跟着主角更新。
var _aim_is_target := false
var _repath_left := 0.0
var _emerge_left := 0.0
var _recover_left := 0.0
var _sprite: Sprite2D


## 建好碰撞体、贴图与寻路格子。`texture` 为空时只有碰撞体（测试用）。
func setup(definition: MapDef, chase_target: Node2D, texture: Texture2D, unit_scale: Vector2) -> void:
	name = "ch2_chase_mist"
	map_def = definition
	target = chase_target
	scale = unit_scale
	collision_layer = 0
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	z_index = 30
	if chase_target is PhysicsBody2D:
		add_collision_exception_with(chase_target)
	var collision := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Player.FOOT_SIZE
	collision.shape = box
	collision.position = Vector2(0.0, Player.FOOT_OFFSET)
	add_child(collision)
	if texture != null:
		_sprite = Sprite2D.new()
		_sprite.name = "Visual"
		_sprite.texture = texture
		# 高清原图：限制在主角约 1.5 倍高度，脚底落在节点原点。
		var ratio := Player.DISPLAY_HEIGHT * 1.5 / maxf(texture.get_height(), 1.0)
		_sprite.scale = Vector2.ONE * ratio
		_sprite.offset.y = -texture.get_height() * 0.5
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	_build_grid()


## 从地图边缘浮现：先透明、原地不动 `EMERGE_TIME` 秒，再开始追。
func emerge() -> void:
	_emerge_left = EMERGE_TIME
	modulate.a = 0.0
	velocity = Vector2.ZERO
	_path.clear()
	_repath_left = 0.0


## 被主角闪开：扑空后愣住 `RECOVER_TIME` 秒（在 holding 解除后才开始计时）。
func stagger() -> void:
	_recover_left = RECOVER_TIME
	velocity = Vector2.ZERO


func is_emerging() -> bool:
	return _emerge_left > 0.0


func speed() -> float:
	return speed_value * scale.x


## 两个脚底框（同尺寸）相贴即算追上。
func is_touching(other: Node2D) -> bool:
	if other == null:
		return false
	var foot := Player.FOOT_SIZE * scale
	var gap := (other.global_position - global_position).abs()
	return gap.x <= foot.x + TOUCH_MARGIN and gap.y <= foot.y + TOUCH_MARGIN


## 到主角的实际可走路程（绕障后的路线长度）。
func path_gap() -> float:
	if target == null:
		return INF
	var route := find_path(global_position, target.global_position)
	if route.is_empty():
		return INF
	var total := global_position.distance_to(route[0])
	for index in range(1, route.size()):
		total += route[index - 1].distance_to(route[index])
	return total + route[-1].distance_to(target.global_position)


## 地图边缘的出生点：与 `near` 同一高度附近、最靠 `side` 一侧的可站立格子。
static func edge_spawn(definition: MapDef, near: Vector2, side: int = -1) -> Vector2:
	var columns := int(ceil(definition.size.x / CELL))
	for dy_index in 24:
		for sign_y: int in [1, -1]:
			var y := snappedf(near.y, CELL) + sign_y * dy_index * CELL
			for step in columns:
				var column := step if side < 0 else columns - step
				var at := Vector2(column * CELL, y)
				if WalkGrid.is_free(definition, at) and WalkGrid.has_landing_room(definition, at) \
						and not WalkGrid.path_to(definition, at, near).is_empty():
					return at
	return near


func find_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _grid == null:
		return out
	var start := _nearest_free(_cell(from))
	var goal := _nearest_free(_cell(to))
	if start == Vector2i(-1, -1) or goal == Vector2i(-1, -1):
		return out
	for id: Vector2i in _grid.get_id_path(start, goal, true):
		out.append(Vector2(id) * CELL)
	return out


func _physics_process(delta: float) -> void:
	if delta <= 0.0 or target == null:
		return
	if _emerge_left > 0.0:
		_emerge_left -= delta
		modulate.a = clampf(1.0 - _emerge_left / EMERGE_TIME, 0.0, 1.0)
		velocity = Vector2.ZERO
		return
	if holding:
		velocity = Vector2.ZERO
		_repath_left = 0.0
		return
	if _recover_left > 0.0:
		_recover_left -= delta
		velocity = Vector2.ZERO
		return
	if is_touching(target):
		velocity = Vector2.ZERO
		return

	var budget := speed() * delta
	_repath_left -= delta
	if _repath_left <= 0.0 or _path.is_empty():
		_repath_left = REPATH_INTERVAL
		_path = find_path(global_position, target.global_position)
		_aim = _choose_aim(budget)
	elif not _aim_is_target and global_position.distance_to(_aim) <= maxf(budget, 0.5):
		_aim = _choose_aim(budget)
	var heading := _heading_to(_aim)
	if heading.is_zero_approx():
		velocity = Vector2.ZERO
		return
	velocity = heading * speed()
	move_and_slide()
	if _sprite != null and absf(heading.x) > 0.2:
		# 素材本身朝右；往左跑才翻转。
		_sprite.flip_h = heading.x < 0.0


## 吃掉已经走到的路点，返回这一帧的前进方向。
## 格子路线是八方向折线；朝「直线可达的最远路点」走，路线就拉直成自然的斜线绕障。
## 能直线看到主角时直接扑过去。
## 寻路时与走到当前目标点时各算一次（直线检测较贵，不逐帧算）。
func _choose_aim(budget: float) -> Vector2:
	while not _path.is_empty() and global_position.distance_to(_path[0]) <= maxf(budget, 0.5):
		_path.pop_front()
	_aim_is_target = _path.is_empty() or has_clear_line(global_position, target.global_position)
	if _aim_is_target:
		return target.global_position
	for index in range(mini(_path.size(), LOOKAHEAD) - 1, 0, -1):
		if has_clear_line(global_position, _path[index]):
			return _path[index]
	return _path[0]


func _heading_to(aim: Vector2) -> Vector2:
	# 直扑主角时目标点要跟着主角走，否则会追向半拍前的位置。
	if _aim_is_target:
		aim = target.global_position
	var offset := aim - global_position
	if offset.length() <= 0.01:
		return Vector2.ZERO
	return offset.normalized()


## 两点之间脚底框一路都站得住（按寻路格子逐格采样）。
func has_clear_line(from: Vector2, to: Vector2) -> bool:
	if _grid == null:
		return false
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / (CELL * 0.5)))
	for step in steps + 1:
		var point := from.lerp(to, float(step) / steps)
		var corner := Vector2i(floori(point.x / CELL), floori(point.y / CELL))
		# 采样点夹在格子之间时，查围住它的四个格子，免得脚底框蹭到相邻格的墙。
		for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
			var probe := corner + offset
			if not _grid.is_in_boundsv(probe) or _grid.is_point_solid(probe):
				return false
	return true


func _cell(point: Vector2) -> Vector2i:
	return WalkGrid.key(point)


func _nearest_free(cell: Vector2i) -> Vector2i:
	if not _grid.is_in_boundsv(cell):
		cell = cell.clamp(_grid.region.position, _grid.region.end - Vector2i.ONE)
	if not _grid.is_point_solid(cell):
		return cell
	for radius in range(1, 8):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var next := cell + Vector2i(dx, dy)
				if _grid.is_in_boundsv(next) and not _grid.is_point_solid(next):
					return next
	return Vector2i(-1, -1)


## 寻路格子：与 `WalkGrid.is_free` 同一判定，但按墙体逐块栅格化，避免逐格扫全部墙。
func _build_grid() -> void:
	_grid = AStarGrid2D.new()
	var columns := int(ceil(map_def.size.x / CELL)) + 1
	var rows := int(ceil(map_def.size.y / CELL)) + 1
	_grid.region = Rect2i(0, 0, columns, rows)
	_grid.cell_size = Vector2.ONE * CELL
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	var blockers: Array[Rect2] = []
	blockers.append_array(map_def.walls)
	for actor: MapDef.Actor in map_def.actors:
		if actor.has_local_collision:
			blockers.append_array(actor.collision_rects())
		elif actor.solid:
			blockers.append(actor.rect)
	var foot := WalkGrid.foot_rect(Vector2.ZERO, map_def.player_scale)
	for raw_wall: Rect2 in blockers:
		# 墙外多留一点：物理碰撞有安全边距，贴着墙边算出来的格子实际会蹭墙。
		var wall := raw_wall.grow(WALL_MARGIN)
		# 脚底框与墙相交的原点范围 = 墙按脚底框反向扩张。
		var reach := Rect2(wall.position - foot.end, wall.size + foot.size)
		var first := Vector2i(floori(reach.position.x / CELL), floori(reach.position.y / CELL))
		var last := Vector2i(ceili(reach.end.x / CELL), ceili(reach.end.y / CELL))
		for x in range(maxi(first.x, 0), mini(last.x, columns - 1) + 1):
			for y in range(maxi(first.y, 0), mini(last.y, rows - 1) + 1):
				if WalkGrid.foot_hits(wall, Vector2(x, y) * CELL, map_def.player_scale):
					_grid.set_point_solid(Vector2i(x, y), true)
