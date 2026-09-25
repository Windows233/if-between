## 探针：打印「从 A 走到 B」的一条**只转 90 度的折线**，供剧情演出抄进 `place_player` 的 `path`。
##
## 为什么要它：手算路线得把脚底方块那 16 个像素、每一件挡人家具都算进去，
## 差两像素人就贴着墙走不过去。让 `WalkGrid` 自己去试，试出来的才是准的。
##
## 顺带把每一段都踩一遍（每 2 像素问一次 `is_free`），哪一段过不去当场报出来。
##
## 不是自动测试的一部分（`run_tests.gd` 不调它），改完地图手动跑：
##   <godot> --headless --path <项目> --script res://tests/probe_route.gd -- <地图> <x,y> <x,y>
## 例：
##   --script res://tests/probe_route.gd -- bedroom_night 95,306 336,190
extends SceneTree

const STEP := WalkGrid.STEP
const DIRS: Array[Vector2] = [
	Vector2(STEP, 0.0), Vector2(-STEP, 0.0), Vector2(0.0, STEP), Vector2(0.0, -STEP),
]


func _initialize() -> void:
	var args := PackedStringArray(OS.get_cmdline_user_args())
	if args.size() < 3:
		print("用法：-- <地图> <x,y> <x,y>")
		quit()
		return

	var def := DataLoader.load_map(StringName(args[0]))
	if def == null:
		print("读不到地图：", args[0])
		quit()
		return

	var from := _pair(args[1])
	var to := _pair(args[2])
	print("地图 %s（%s）　从 %s 走到 %s" % [def.id, def.size, from, to])
	print("脚底方块：宽 %.0f、往上 %.0f、往下 %.0f"
		% [WalkGrid.FOOT_HALF * 2.0, WalkGrid.FOOT_UP, WalkGrid.FOOT_DOWN])
	print("")

	var route := route_of(def, from, to)
	if route.is_empty():
		print("走不过去 —— 起点就站不住，或者那边根本到不了。")
		quit()
		return

	print("折线（%d 个点）：" % route.size())
	var total := 0.0
	for i: int in route.size():
		var mark := "起点"
		if i == route.size() - 1:
			mark = "终点"
		elif i > 0:
			mark = "%s %.0f" % [_turn_name(route[i - 1], route[i], route[i + 1] if i + 1 < route.size() else route[i]),
				route[i].distance_to(route[i - 1])]
		print("  %2d. %s　%s" % [i, route[i], mark])
		if i > 0:
			total += route[i].distance_to(route[i - 1])

	print("")
	print("总长 %.0f 像素，按走路速度 %.0f 像素/秒 = %.2f 秒"
		% [total, Player.SPEED, total / Player.SPEED])
	print("")
	print("抄进 JSON 的写法：")
	var parts: Array[String] = []
	for p: Vector2 in route:
		parts.append("[%d, %d]" % [int(p.x), int(p.y)])
	print("  \"path\": [%s]" % ", ".join(parts))

	_probe_legs(def, route)
	_dump(def, route)
	quit()


## 一条折线：先沿射线能走多远走多远，BFS 找**转弯次数最少**的那种。
##
## 普通的逐格 BFS 出来的是一串 2 像素的台阶，看着就是斜着走；
## 这里把「沿一个方向一直走」当成一步，出来的才是「先横后竖」的折线。
func route_of(def: MapDef, from: Vector2, to: Vector2) -> Array[Vector2]:
	var start := WalkGrid.snap(from)
	var raw := WalkGrid.path_to(def, start, to)
	if raw.is_empty():
		return []
	# 目标站不住（点在墙里 / 家具上）时，`path_to` 已经替我们挑了最近的落脚点
	var goal := raw[raw.size() - 1]

	var came: Dictionary = {}
	var seen: Dictionary = {}
	seen[WalkGrid.key(start)] = true
	var queue: Array[Vector2] = [start]
	var found := false

	while not queue.is_empty() and not found:
		var at: Vector2 = queue.pop_front()
		for d: Vector2 in DIRS:
			var p := at
			while true:
				p += d
				if not _in_bounds(def, p) or not WalkGrid.is_free(def, p):
					break
				var k := WalkGrid.key(p)
				if seen.has(k):
					continue
				seen[k] = true
				came[k] = at
				if p.distance_to(goal) < STEP * 0.5:
					found = true
					goal = p
					break
				queue.append(p)
			if found:
				break

	if not found:
		# 射线走法没能到 —— 退回落点，把原始台阶路径按「同方向合并」压一遍，
		# 虽然转弯多，但至少是通的。
		return _merge(raw)

	var out: Array[Vector2] = []
	var at := goal
	while came.has(WalkGrid.key(at)):
		out.append(at)
		at = came[WalkGrid.key(at)]
	out.append(at)
	out.reverse()
	return out


## 把一串相邻格子压成折线：同一个方向连着走的，只留最后一个。
func _merge(raw: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in raw.size():
		if i == 0 or i == raw.size() - 1:
			out.append(raw[i])
			continue
		var a := raw[i] - raw[i - 1]
		var b := raw[i + 1] - raw[i]
		if a.normalized() != b.normalized():
			out.append(raw[i])
	return out


## 每一段都踩一遍，看看有没有蹭到东西。
func _probe_legs(def: MapDef, route: Array[Vector2]) -> void:
	var bad := 0
	for i: int in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var leg := b - a
		var steps := int(ceilf(leg.length() / STEP))
		for s: int in steps + 1:
			var at := a + leg * (float(s) / maxf(1.0, float(steps)))
			if not WalkGrid.is_free(def, at):
				bad += 1
				print("过不去：第 %d 段 %s → %s，卡在 %s" % [i, a, b, at])
	print("踩了一遍：%s" % ("每一点都站得住" if bad == 0 else "%d 个点蹭到东西" % bad))
	print("")


## 把这条路线画成一张缩略图，看形状对不对（起点 `S`、终点 `E`、路径 `*`、墙 `#`）。
func _dump(def: MapDef, route: Array[Vector2]) -> void:
	const CELL := 8
	var cols := int(def.size.x / CELL) + 1
	var rows := int(def.size.y / CELL) + 1
	var grid: Array[PackedStringArray] = []
	for r: int in rows:
		var line := PackedStringArray()
		for c: int in cols:
			line.append("·")
		grid.append(line)

	for y: int in range(0, rows * CELL, 4):
		for x: int in range(0, cols * CELL, 4):
			if WalkGrid.is_free(def, Vector2(x, y)):
				continue
			grid[int(y / CELL)][int(x / CELL)] = "#"
	for i: int in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var leg := b - a
		var steps := int(ceilf(leg.length() / 4.0))
		for s: int in steps + 1:
			var at := a + leg * (float(s) / maxf(1.0, float(steps)))
			grid[int(at.y / CELL)][int(at.x / CELL)] = "*"
	grid[int(route[route.size() - 1].y / CELL)][int(route[route.size() - 1].x / CELL)] = "E"
	grid[int(route[0].y / CELL)][int(route[0].x / CELL)] = "S"

	print("缩略图（一格 %d 像素，`·` 能走、`#` 挡路，`S` 起点、`E` 终点）" % CELL)
	for r: int in rows:
		print("%3d %s" % [r * CELL, "".join(grid[r])])


func _in_bounds(def: MapDef, point: Vector2) -> bool:
	return Vector2(def.size).x > point.x and Vector2(def.size).y > point.y \
		and point.x >= -WalkGrid.FOOT_HALF and point.y >= -WalkGrid.FOOT_HALF


func _pair(text: String) -> Vector2:
	var parts := text.split(",")
	if parts.size() < 2:
		return Vector2.ZERO
	return Vector2(float(parts[0]), float(parts[1]))


func _turn_name(a: Vector2, b: Vector2, c: Vector2) -> String:
	var d1 := (b - a).normalized()
	var d2 := (c - b).normalized()
	if d1 == d2:
		return "直行"
	if d1.x != 0.0:
		return "转竖"
	return "转横"
