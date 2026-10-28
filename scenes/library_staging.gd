## 图书馆演出脚点跟随地图出生点、猫的交互区和倒架落点。
## 不改编辑器布局；行走由演出执行器沿 WalkGrid 的合法路径完成。
## 两次地毯对话共用同一目标，回溯恢复入口 C 并面向左。
extends RefCounted

static func point(def: MapDef, role: String) -> Vector2:
	var target := def.spawn_point(&"from_school_gate") + Vector2(18, 0)
	if role == "carpet_c":
		for actor: MapDef.Actor in def.actors:
			if actor.id == &"cat_monster":
				target = Vector2(actor.reach.end.x - 20, actor.reach.end.y - 26)
	elif role == "barrier_c":
		target = preload("res://scenes/library_shelf_fall.gd").positions(def)["c"]
	return preload("res://scenes/library_shelf_fall.gd")._free_near(def, target)

## 合并同方向的小格，保留转角；避免逐格补间的最短时长令行走忽快忽慢。
static func route(def: MapDef, from: Vector2, to: Vector2) -> Array[Vector2]:
	var path := WalkGrid.path_to(def, from, to)
	if path.size() < 3:
		return path
	var out: Array[Vector2] = [path[0]]
	for i: int in range(1, path.size() - 1):
		if not (path[i] - path[i - 1]).normalized().is_equal_approx((path[i + 1] - path[i]).normalized()):
			out.append(path[i])
	out.append(path[-1])
	return out
