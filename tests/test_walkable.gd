## 走得到吗：把地图栅格化，从出生点跑一遍广度优先，看该到的地方到不到得了。
##
## 这类毛病光看截图看不出来：画面里明明有条缝，人就是钻不过去。
##
## **量具全在 `WalkGrid` 里，这个文件一份都不留。** 原先这里自己有一份
## （脚底方块那几个数、可走判定、广度优先），2026-09-24 挪进了 `core/walk_grid.gd` ——
## 鼠标导航（点地图走过去）要用同一套判定。「测试的量具和游戏的量具必须是同一个」，
## 两份并存迟早会走样，而这个文件已经被咬过一次：`FOOT_SIZE` 从 10 放到 16 时
## 它没跟着改，比游戏**宽松**了 6 个像素，一路绿着，真机上人根本走不到那些地方。
class_name TestWalkable
extends RefCounted


static func run(h: TestHarness) -> void:
	test_foot_model_matches_player(h)
	test_desk_shop_walkable(h)
	test_bedroom_walkable(h)
	test_market_walkable(h)
	test_pathfinding(h)


## 这里的量具必须和游戏里的是同一个。
##
## 这条就是为「测试比游戏宽松 6 个像素」那次事故加的：
## `FOOT_SIZE` 从 10 放到 16 之后这组测试没跟着改，一路绿着，
## 而真机上人走不到那些地方。
static func test_foot_model_matches_player(h: TestHarness) -> void:
	var size: Vector2 = Player.FOOT_SIZE
	var offset: float = Player.FOOT_OFFSET
	h.check("半宽对得上", WalkGrid.FOOT_HALF, size.x * 0.5)
	h.check("往上伸的对得上", WalkGrid.FOOT_UP, size.y * 0.5 - offset)
	h.check("往下伸的对得上", WalkGrid.FOOT_DOWN, size.y * 0.5 + offset)


static func test_desk_shop_walkable(h: TestHarness) -> void:
	var def := DataLoader.load_map(&"desk_shop")
	if def == null:
		h.check("读得到委托屋", false, true)
		return

	var reach := WalkGrid.reachable(def, def.spawn_point(&"start"))
	# 起点自己当然到得了 —— 到不了说明起点就卡在墙里
	h.check("出生点本身站得住", WalkGrid.is_free(def, def.spawn_point(&"start")), true)
	h.check("走得到卧室那扇门", _covers(reach, Rect2(73, 79, 29, 25)), true)
	h.check("走得到出门的门", _covers(reach, Rect2(206, 311, 33, 26)), true)
	# 光「到得了」不够：人走过去是停下来的，触发区得够深，
	# 不然停在门边按交互落在框外 —— 玩家那边就是「这个门是坏的」。
	#
	# 上墙那两扇门尤其吃这个：脚底方块 16 高，贴着上墙站时**脚只能到 95**，
	# 触发区原来是 79..96，余量只有 1 个像素。两扇门的触发区都往下铺过了，
	# 这个深度要求就是那次量出来的（开发纪要 32.4）。
	h.check("卧室门口站得进去", _portal_depth(reach, Rect2(73, 79, 29, 25)) >= 4, true)
	h.check("出门口站得进去", _portal_depth(reach, Rect2(206, 311, 33, 26)) >= 4, true)
	h.check("走得到书桌前", _covers(reach, Rect2(181, 158, 86, 16)), true)
	h.check("走得到地毯", _covers(reach, Rect2(187, 200, 40, 40)), true)
	h.check("走得到猫窝旁", _covers(reach, Rect2(280, 240, 19, 27)), true)
	h.check("屋里每件东西都点得到", _unreachable(def, reach), [])


static func test_bedroom_walkable(h: TestHarness) -> void:
	var def := DataLoader.load_map(&"bedroom")
	if def == null:
		h.check("读得到卧室", false, true)
		return
	var reach := WalkGrid.reachable(def, def.spawn_point(&"from_desk"))
	h.check("卧室出生点站得住", WalkGrid.is_free(def, def.spawn_point(&"from_desk")), true)
	h.check("走得到回店里的门", _covers(reach, Rect2(80, 313, 31, 26)), true)
	h.check("卧室门口站得进去", _portal_depth(reach, Rect2(80, 313, 31, 26)) >= 4, true)
	h.check("卧室里能走动", reach.size() > 500, true)
	h.check("卧室每件东西都点得到", _unreachable(def, reach), [])


## 集市（2026-09-24 按新插画重做的那张，557×314）。
##
## **这一组是照数据自己转，不写死坐标。** 传送区有几个、在哪，全在
## `market.json` 里 —— 换一张示意图之后，这里只有「够不够深、到不到得了」
## 那两条判据要守着，不用跟着改一遍数字。
##
## 集市现在是「进来逛一圈、从哪个口都回大地图」，四个口：
## 南门（出生点脚下那块地毯）、东侧小门、西侧石阶、大宅正门（先禁用着）。
static func test_market_walkable(h: TestHarness) -> void:
	var def := DataLoader.load_map(&"market")
	if def == null:
		h.check("读得到集市", false, true)
		return

	var spawn: Vector2 = def.spawn_point(&"from_overworld")
	h.check("集市出生点站得住", WalkGrid.is_free(def, spawn), true)
	var reach := WalkGrid.reachable(def, spawn)
	h.check("集市里能走动", reach.size() > 2000, true)

	# **每个传送区都要「走得到」而且「站得进去」。**
	#
	# 走得到只是能靠近；站得进去要有 4 行 —— 站不进去就是「这扇门坏了」。
	# 传送区紧贴墙底时最容易犯这个：脚底方块 16 像素高、**只往上伸**，
	# 紧贴墙底那一段一行都站不住。所以口子必须沿走道方向铺够深
	#（集市图上两处蓝块就是这么往外铺的，见开发纪要 60.4）。
	for portal: MapDef.Portal in def.portals:
		var where := portal.label if portal.label != "" else "<没写名字>"
		h.check("走得到「%s」" % where, _covers(reach, portal.rect), true)
		h.check("「%s」站得进去（≥4 行）" % where,
			_portal_depth(reach, portal.rect) >= 4, true)

	# 广场是一整块，不是被墙切成好几块 —— 只看范围就够，不必钉具体坐标
	var min_x := 99999.0
	var max_x := -99999.0
	var min_y := 99999.0
	var max_y := -99999.0
	for p: Vector2 in reach:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	h.check("广场从西到东都走得到", max_x - min_x > 400.0, true)
	h.check("广场从北到南都走得到", max_y - min_y > 180.0, true)
	h.check("没有漏到地图外面去", min_x >= 0.0 and min_y >= 0.0, true)

	h.check("集市里每件东西都点得到", _unreachable(def, reach), [])



# ---------------------------------------------------------------- 工具

## 这一片区域里有几个格子能走到。等于 0 就是过不去。
static func _covers(reach: Array[Vector2], area: Rect2) -> bool:
	for p: Vector2 in reach:
		if area.has_point(p):
			return true
	return false


## 有没有「站着却永远点不到」的东西。
##
## 家具前面再挡一件家具时最容易出这种毛病：人只能站在外圈，手伸不到。
## 修法不是挪家具，是给那件东西铺一条 `reach` 到玩家站得住的地方。
static func _unreachable(def: MapDef, cells: Array[Vector2]) -> Array:
	const RANGE := 24.0
	var bad: Array = []
	for a: MapDef.Actor in def.actors:
		var ok := false
		for p: Vector2 in cells:
			if MapDef.rect_distance(a.reach, p) >= RANGE:
				continue
			# 朝着它看 —— 朝向对了才算数，跟游戏里一致
			var look := (a.reach.get_center() - p)
			if look.length() < 1.0 or MapDef.faces_target(p, a.reach, look.normalized()):
				ok = true
				break
		if not ok:
			bad.append(str(a.id))
	return bad


## 触发区里能站到几行（每行 2 像素）。行数太少就是「门口太窄，站不进去」。
static func _portal_depth(reach: Array[Vector2], area: Rect2) -> int:
	var rows := {}
	for p: Vector2 in reach:
		if area.has_point(p):
			rows[int(p.y)] = true
	return rows.size()


## 鼠标导航要的那条路：怎么走、点偏了怎么办。
##
## 和上面那些「到得了吗」是一体两面：那些问「这个门走得到吗」，
## 这一条问「从这儿走到那儿，具体沿哪些点走」。
static func test_pathfinding(h: TestHarness) -> void:
	var def := DataLoader.load_map(&"desk_shop")
	if def == null:
		h.check("读得到委托屋", false, true)
		return

	var from := def.spawn_point(&"start")
	var to := Vector2(224, 200)

	var path := WalkGrid.path_to(def, from, to)
	h.check("拿到一条路", path.size() >= 2, true)
	if path.is_empty():
		return
	h.check("第一个点是脚下", path[0].distance_to(WalkGrid.snap(from)) < 0.01, true)

	# 路上每一点都得站得住 —— 有一点站不住，人走到那儿就卡死
	var blocked := 0
	for p: Vector2 in path:
		if not WalkGrid.is_free(def, p):
			blocked += 1
	h.check("路上每个点都站得住", blocked, 0)

	# 相邻两点只差一格，不能瞬移（瞬移会在画面上跳一段）
	var jumps := 0
	for i: int in path.size() - 1:
		if path[i].distance_to(path[i + 1]) > WalkGrid.STEP * 1.5:
			jumps += 1
	h.check("每一步只走一格", jumps, 0)

	# 目标是空地上的点，该走到它跟前
	h.check("走到了目标附近",
		path[-1].distance_to(to) <= WalkGrid.STEP * 2.0, true)

	# **点在墙里**：不该返回「到不了」，而是走到墙外最近的地方。
	# 返回空的症状是「点了没反应」，那比走错地方更让人困惑。
	if not def.walls.is_empty():
		var into_wall: Vector2 = def.walls[0].get_center()
		var detour := WalkGrid.path_to(def, from, into_wall)
		h.check("点进墙里也给一条路", detour.size() >= 1, true)
		if not detour.is_empty():
			h.check("落点站得住", WalkGrid.is_free(def, detour[-1]), true)
			h.check("而且比起点更靠近那儿",
				detour[-1].distance_to(into_wall) < from.distance_to(into_wall), true)

	# 脚下站不住（被卡住、地图改了）就没有路 —— 不能凭空把人拽出来
	h.check("起点站不住就返回空",
		WalkGrid.path_to(def, def.walls[0].get_center() if not def.walls.is_empty() else Vector2.ZERO,
			to).size(), 0)
