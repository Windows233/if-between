## 导航分区保存提示回归：空地孤区不影响可用路线，实际断路仍必须提示。
## 只构造内存夹具，使用正式 WalkGrid/校验器，不读取或修改用户地图。
## run(h) 接入插件测试，也可通过 --script 单独运行。
extends SceneTree

const Validation := preload("res://addons/if_map_editor/map_validation.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("导航分区与保存提示")
	_test_unused_pockets(h)
	_test_separate_spawns(h)
	_test_unreachable_exit(h)
	_test_missing_spawns(h)
	_test_blocked_spawn(h)


static func _fixture() -> Dictionary:
	# 两圈封闭墙各留一块可站立空地；主区可从墙圈下方通往出口。
	return {"id": "navigation_regions_fixture", "size": [272, 192],
		"walls": [[56, 48, 64, 4], [56, 108, 64, 4], [56, 48, 4, 64], [116, 48, 4, 64],
			[148, 48, 64, 4], [148, 108, 64, 4], [148, 48, 4, 64], [208, 48, 4, 64]],
		"spawns": {"main": [24, 152]}, "actors": [],
		"portals": [{"id": "exit", "rect": [232, 132, 24, 32], "action": "overworld"}]}


static func _has(report: Dictionary, kind: String, field: String, severity: String) -> bool:
	for problem: Dictionary in report.get("issues", []):
		if problem.get("kind") == kind and problem.get("field") == field \
				and problem.get("severity") == severity:
			return true
	return false


static func _test_unused_pockets(h: TestHarness) -> void:
	var data := _fixture()
	var before := data.duplicate(true)
	var definition := MapDef.from_dictionary(data)
	var start := definition.spawn_point(&"main")
	var destination := definition.portals[0].rect.get_center()
	var path := WalkGrid.path_to(definition, start, destination)
	h.check("夹具主区出生点能寻路到出口", not path.is_empty() and
		definition.portals[0].rect.has_point(path.back()), true)
	var report := Validation.validate(data)
	h.check("空地孤区导航完成", report["navigation"]["complete"], true)
	h.check("仍完整记录主区和两个空地孤区", report["navigation"]["components"].size(), 3)
	h.check("统计真实出生点只占一个区域", report["navigation"]["spawn_region_count"], 1)
	h.check("保留两个无出生点区域供审阅", report["navigation"]["unseeded_components"].size(), 2)
	h.check("空地孤区无地图导航警告", _has(report, "map", "navigation", "warning"), false)
	h.check("空地孤区保留可查看的导航说明", _has(report, "map", "navigation", "info"), true)
	h.check("导航说明进入独立信息列表", report["infos"].size(), 1)
	h.check("可达出口不误报", _has(report, "portal", "rect", "warning"), false)
	h.check("纯空地孤区不进入保存确认列表", report["warnings"], [])
	h.check("纯空地孤区不阻止保存", report["can_save"], true)
	h.check("导航校验不改源地图", data, before)
	data["spawns"]["another_entry"] = [36, 164]
	report = Validation.validate(data)
	h.check("同一区的多个入口不误报断路", _has(report, "map", "navigation", "warning"), false)
	h.check("同一区多个入口仍无需保存确认", report["warnings"], [])


static func _test_separate_spawns(h: TestHarness) -> void:
	var data := _fixture()
	data["spawns"]["enclosed"] = [88, 88]
	var report := Validation.validate(data)
	var components: Dictionary = report["navigation"]["spawn_components"]
	h.check("分离入口夹具的两个出生点都有效", report["errors"], [])
	h.check("分离入口确实位于不同可走区", components["main"] != components["enclosed"], true)
	h.check("实际分离入口仍提示导航警告", _has(report, "map", "navigation", "warning"), true)
	h.check("实际断路仍进入保存确认", not report["warnings"].is_empty(), true)
	h.check("导航断路仍可明确确认后保存", report["can_save"], true)


static func _test_unreachable_exit(h: TestHarness) -> void:
	var data := _fixture()
	data["portals"][0]["rect"] = [76, 76, 20, 24]
	var report := Validation.validate(data)
	var navigation: Dictionary = report["navigation"]
	h.check("孤区出口仍存在可站立落脚格", not navigation["portal_components"]["0"].is_empty(), true)
	h.check("孤区出口所在区不属于主出生点", navigation["portal_components"]["0"].has(
		navigation["spawn_components"]["main"]), false)
	h.check("无出生点可达的出口仍提示警告", _has(report, "portal", "rect", "warning"), true)
	h.check("出口断路仍进入保存确认", not report["warnings"].is_empty(), true)
	h.check("孤区出口不被误升级为几何错误", report["errors"], [])


static func _test_missing_spawns(h: TestHarness) -> void:
	var data := _fixture()
	data["spawns"] = {}
	var report := Validation.validate(data)
	h.check("无出生点仍保留全部导航分区", report["navigation"]["components"].size(), 3)
	h.check("无出生点无法证明主区可达，保留导航警告", _has(report, "map", "navigation", "warning"), true)
	h.check("无出生点多区仍进入保存确认", not report["warnings"].is_empty(), true)


static func _test_blocked_spawn(h: TestHarness) -> void:
	var data := _fixture()
	data["spawns"]["blocked"] = [56, 80]
	var report := Validation.validate(data)
	h.check("有正常入口时也不能隐藏阻挡出生点", _has(report, "spawn", "blocked", "error"), true)
	h.check("阻挡出生点仍禁止保存", report["can_save"], false)
	h.check("阻挡出生点仍记录为无效分区", report["navigation"]["spawn_components"]["blocked"], -1)
	data["spawns"] = {"blocked": [56, 80]}
	report = Validation.validate(data)
	h.check("全部出生点阻挡时保留错误", _has(report, "spawn", "blocked", "error"), true)
	h.check("全部出生点阻挡时仍禁止保存", report["can_save"], false)
