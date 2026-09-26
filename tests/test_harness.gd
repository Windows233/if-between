## 测试用的公共工具：计数、断言、建主场景、把对话推到底。
##
## 测试拆成多个文件之后，这些东西不能各写一份 ——
## 断言的比对规则尤其不能，否则「同样一条断言，在不同组里判定不一样」。
class_name TestHarness
extends RefCounted

## 测试要往里挂节点的根。由入口（`run_tests.gd`）在创建时给。
var root: Node = null

var passed := 0
var failed := 0
var failures: Array[String] = []


func setup(p_root: Node) -> void:
	root = p_root


## 打印一组测试的开头，让输出能看出跑到哪了。
func section(name: String) -> void:
	print("")
	print("--- " + name)


## 断言。相等就记通过，不相等记失败并把两边都留下来。
func check(label: String, actual: Variant, expected: Variant) -> void:
	if same(actual, expected):
		passed += 1
		return
	failed += 1
	failures.append("%s —— 期望 %s，实际 %s" % [
		label, var_to_str(expected), var_to_str(actual),
	])


## 建一个已经 boot 过的主场景。测试跑完记得 `queue_free()`。
func new_main() -> Node2D:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	root.add_child(main)
	# --script 模式下 _ready 不会同步触发，显式拉起来
	main.boot()
	# 调试开关在这里统一关掉，测试跑的是正常流程（见 main.gd 各开关的说明）。
	# 不关的话「新游戏直接落进门卫室」会让开场守卫红一片。
	main.debug_start_map = ""
	return main


## 把对话框推到底（每行按两下：先显示完，再翻页）。
##
## 加次数上限，免得剧情有环的时候把测试卡死。
func drain_dialogue(box: DialogueBox) -> void:
	var guard := 0
	while box.is_open() and guard < 40:
		box.advance()
		box.advance()
		guard += 1


## 新开一局，并把开场那段**即时**跑完。
##
## 「即时」是必须的：无头测试里没有帧循环，演出里的补间、计时器、
## 等点击全都等不到。即时模式下这些一律跳过，只落实状态。
## 返回时停在开场那个 IF 选择框上（面板留着、选项摆在中间）。
func start_opening(main: Node2D) -> void:
	main.cutscene.instant = true
	# **不碰 `main.skip_opening`。** 它以前在这里被显式改成 false，结果
	# 2026-09-23 那次「开新游戏没有剧情」测试一条都没红 —— 测试跑的是它自己
	# 摆好的配置，不是游戏真正在跑的那份。现在照默认值跑，
	# 谁把那个调试开关留着，测试就会叫。
	main.new_game()


## 在当前的选项框上按 id 选一项。找不到返回 false。
func pick(main: Node2D, id: StringName) -> bool:
	if not main.choice_menu.select_id(id):
		return false
	main.choice_menu.confirm()
	return true


## 开场走一遍，走到 end1：选「不接受委托」，一路到底。
func play_to_end1(main: Node2D) -> void:
	start_opening(main)
	pick(main, &"decline")
	drain_dialogue(main.dialogue)


## 某个坐标附近能交互到谁。给地图组与对话组共用。
func actor_id(def: MapDef, point: Vector2, reach: float) -> StringName:
	var actor := def.actor_near(point, reach)
	return actor.id if actor != null else &"<none>"


## 打印结果。返回是否全过。
func report() -> bool:
	print("")
	print("通过 %d / %d" % [passed, passed + failed])
	if failed > 0:
		print("失败 %d 条：" % failed)
		for line: String in failures:
			print("  × " + line)
		return false
	print("全部通过。")
	return true


## 浮点断言。归一化过的向量直接 == 会因为精度误差失败。
func check_float(label: String, actual: float, expected: float, eps: float = 0.0001) -> void:
	if absf(actual - expected) <= eps:
		passed += 1
		return
	failed += 1
	failures.append("%s —— 期望 %f，实际 %f" % [label, expected, actual])


## 比对两个值。Variant 之间的相等判定有些坑，
## 统一在这里处理，别在各组里各写一套。
func same(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	# 浮点一律按容差比：整数和浮点混着比也是按数值比
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b
