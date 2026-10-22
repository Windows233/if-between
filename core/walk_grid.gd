## 走得到吗、怎么走：把地图栅格化，用**玩家脚下的碰撞方块**去比划。
##
## 判定不是「这个点在不在墙里」，而是「以这个点为准的那个方块会不会蹭到墙」——
## 原点在脚底，左右各宽 8，**只往上伸 16、不往下伸**。窄道、门缝、桌子缝
## 这类地方，差这几像素就走不过去。
##
## 三个数是从 `Player.FOOT_SIZE` / `Player.FOOT_OFFSET` 算出来的
## （`size/2`、`size/2 - offset`、`size/2 + offset`），但**不能写成表达式** ——
## 常量里引用另一个类的 `Vector2` 常量，GDScript 解析不过。所以写字面值，
## 另配一条 `test_foot_model_matches_player` 守着：谁改了 `Player` 却没回来改
## 这里，测试会先叫。
##
## **这份代码原来是 `tests/test_walkable.gd` 自己的一份。** 2026-09-24 挪出来，
## 因为鼠标导航（点地图走过去）要用同一套判定。那个文件已经被咬过一次：
## `FOOT_SIZE` 从 10 放到 16 时它没跟着改，比游戏**宽松**了 6 个像素，
## 一路绿着，而真机上人根本走不到那些地方。**量具只能有一份。**
class_name WalkGrid
extends RefCounted

## 栅格精度。2 像素够细，也不至于慢。
const STEP := 2.0
## 脚底方块的一半宽（左右各伸这么多）
const FOOT_HALF := 8.0
## 脚底方块从原点**往上**伸多少、**往下**伸多少。原点在脚底，所以不对称。
const FOOT_UP := 16.0
const FOOT_DOWN := 0.0


## 这个点站得住吗（脚底方块不蹭到任何实体）。
##
## 实体有两类：地图数据里的 `walls`，以及整块挡路的家具（`solid` 的 actor）。
## 少了后一类，玩家就会被判成「能走进书架里」。
static func is_free(def: MapDef, point: Vector2) -> bool:
	for wall: Rect2 in def.walls:
		if foot_hits(wall, point):
			return false
	for actor: MapDef.Actor in def.actors:
		if actor.has_local_collision:
			for shape: Rect2 in actor.collision_rects():
				if foot_hits(shape, point):
					return false
		elif actor.solid and foot_hits(actor.rect, point):
			return false
	return true


## 脚底方块会不会蹭到 `wall`。方块是 [点-8, 点+8]（左右）、[点-16, 点]（上下）。
static func foot_hits(wall: Rect2, point: Vector2) -> bool:
	return point.x + FOOT_HALF > wall.position.x and point.x - FOOT_HALF < wall.end.x \
		and point.y + FOOT_DOWN > wall.position.y and point.y - FOOT_UP < wall.end.y


## 落脚时留的余量。**这不是碰撞判定**，只用在「挑落点」那一步。
##
## 人走到格点附近可能差 1 个像素（`ARRIVE` 那个容差），所以贴边的格子不能当落点
## —— 那一像素会把人蹭进墙里。把墙往外撑这么一点再判，撑开之后还站得住才算。
const LANDING_MARGIN := 2.0


## 这个格子适不适合**停下来**：站得住，而且四周还各有 `LANDING_MARGIN` 的余量。
##
## **和 `is_free` 分开，别把这条用到走路判定上** —— 那时候要的是「过得去」，
## 多要求余量会把窄道和门缝全堵死。
static func has_landing_room(def: MapDef, point: Vector2) -> bool:
	for wall: Rect2 in def.walls:
		if foot_hits(wall.grow(LANDING_MARGIN), point):
			return false
	for actor: MapDef.Actor in def.actors:
		if actor.has_local_collision:
			for shape: Rect2 in actor.collision_rects():
				if foot_hits(shape.grow(LANDING_MARGIN), point):
					return false
		elif actor.solid and foot_hits(actor.rect.grow(LANDING_MARGIN), point):
			return false
	return true


## 从起点铺一遍能走到的格子（世界坐标）。走不到任何地方就返回空数组。
static func reachable(def: MapDef, start: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var origin := snap(start)
	if not is_free(def, origin):
		return out

	var seen: Dictionary = {}
	var queue: Array[Vector2] = [origin]
	seen[key(origin)] = true
	var limit := bounds(def)

	while not queue.is_empty():
		var at: Vector2 = queue.pop_front()
		out.append(at)
		for d: Vector2 in _DIRS:
			var next := at + d
			if not limit.has_point(next):
				continue
			var k := key(next)
			if seen.has(k) or not is_free(def, next):
				continue
			seen[k] = true
			queue.append(next)
	return out


## 从 `from` 走到 `to` 附近的一条路。返回**一串落脚点**（含起点和终点），
## 迈不开步就返回空数组。
##
## **`to` 站不住也照样有结果**：会在「站得住而且从起点真能走到」的格子里
## 挑一个离它最近的。鼠标点进墙里、点到家具上时，人该走过去站在旁边，
## 而不是原地不动 —— 那看起来像点了没反应。
##
## 返回值是路径本身，不是「一条直线」：挡在中间的墙和家具会绕开。
## 这也是为什么要有它 —— 光把落点修到最近的可走点，中间隔着东西照样走不到。
static func path_to(def: MapDef, from: Vector2, to: Vector2) -> Array[Vector2]:
	var empty: Array[Vector2] = []
	var origin := snap(from)
	if not is_free(def, origin):
		return empty

	var goal := snap(to)
	var came: Dictionary = {}
	var seen: Dictionary = {}
	var queue: Array[Vector2] = [origin]
	seen[key(origin)] = true
	var limit := bounds(def)

	while not queue.is_empty():
		var at: Vector2 = queue.pop_front()
		for d: Vector2 in _DIRS:
			var next := at + d
			if not limit.has_point(next):
				continue
			var k := key(next)
			if seen.has(k) or not is_free(def, next):
				continue
			seen[k] = true
			came[k] = at
			queue.append(next)

	# 铺完之后再挑落点：**能走到**的格子里离目标最近的那个。
	# 边铺边挑会更省，但铺完再选逻辑简单得多，而这点格子量（2 像素一格）
	# 在一张房间图上跑一次是毫秒级的事。
	#
	# **落点要多留一点余量**（`LANDING_MARGIN`）：人走到格点附近时可能差
	# 1 个像素（`ARRIVE` 那个容差），贴边的格子会被这一像素蹭进墙里 ——
	# 表现是「停下的位置差一点点，脚踩进墙做了」。挑不到留得下余量的格子
	# （窄道里就是这样）才退回去用普通判据。
	var best := origin
	var best_distance := INF
	var fallback := origin
	var fallback_distance := INF
	for k: Vector2i in seen:
		var at := Vector2(k) * STEP
		var distance := at.distance_squared_to(goal)
		if distance < fallback_distance:
			fallback_distance = distance
			fallback = at
		if distance < best_distance and has_landing_room(def, at):
			best_distance = distance
			best = at
	if best_distance == INF:
		best = fallback

	# 顺着来路倒回起点
	var out: Array[Vector2] = []
	var walk := best
	while true:
		out.append(walk)
		var k := key(walk)
		if not came.has(k):
			break
		walk = came[k]
	out.reverse()
	return out


## 这个点应该落在哪个格子上。
static func snap(point: Vector2) -> Vector2:
	return Vector2(snappedf(point.x, STEP), snappedf(point.y, STEP))


## 格子的整数坐标。字典的键用它而不是 `Vector2` —— 浮点当键迟早会踩误差。
static func key(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x / STEP), roundi(point.y / STEP))


## 搜索范围。比地图四周各放宽一个方块，免得贴边的格子因为半宽出界被漏掉。
static func bounds(def: MapDef) -> Rect2:
	return Rect2(
		Vector2(-FOOT_HALF, -FOOT_HALF),
		Vector2(def.size) + Vector2(FOOT_HALF * 2.0, FOOT_HALF * 2.0)
	)


const _DIRS: Array[Vector2] = [
	Vector2(STEP, 0), Vector2(-STEP, 0), Vector2(0, STEP), Vector2(0, -STEP),
]
