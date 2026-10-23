## Focused regression tests for map validation compatibility and runtime rules.
extends RefCounted

const Validation := preload("res://addons/if_map_editor/map_validation.gd")
const MapDef := preload("res://core/map_def.gd")
const WalkGrid := preload("res://core/walk_grid.gd")


static func run(harness: TestHarness) -> void:
	_test_portal_ids(harness)
	_test_required_ids(harness)
	_test_spawn_walkability(harness)
	_test_existing_maps(harness)


static func _test_portal_ids(h: TestHarness) -> void:
	var data := _fixture()
	var report := Validation.validate(data)
	h.check("旧格式省略 portal ID 可保存", report["can_save"], true)
	h.check("旧格式 portal 使用 MapDef 生成的 ID",
		MapDef.from_dictionary(data).portals[0].id, &"portal_0")

	data["portals"].append({"rect": [32, 48, 16, 16], "action": "overworld"})
	report = Validation.validate(data)
	h.check("旧格式多个 portal 均可使用运行时默认 ID",
		_has(report, "portal", "id"), false)

	data = _fixture()
	data["portals"][0]["id"] = "exit"
	data["portals"].append({"id": "exit", "rect": [32, 48, 16, 16], "action": "overworld"})
	h.check("显式重复 portal ID 仍拒绝",
		_has(Validation.validate(data), "portal", "id"), true)


static func _test_required_ids(h: TestHarness) -> void:
	var data := _fixture()
	data["actors"] = [{"rect": [24, 24, 8, 8]}]
	h.check("actor 缺 ID 仍拒绝", _has(Validation.validate(data), "actor", "id"), true)

	data = _fixture()
	data["actors"] = [
		{"id": "chair", "rect": [24, 24, 8, 8]},
		{"id": "chair", "rect": [40, 24, 8, 8]},
	]
	h.check("重复 actor ID 仍拒绝", _has(Validation.validate(data), "actor", "id"), true)

	data = _fixture()
	data["triggers"] = [{"rect": [24, 24, 8, 8], "event": "test_event"}]
	h.check("trigger 缺 ID 仍拒绝", _has(Validation.validate(data), "trigger", "id"), true)


static func _test_spawn_walkability(h: TestHarness) -> void:
	var data := _fixture()
	h.check("无碰撞出生点通过 WalkGrid 校验", Validation.validate(data)["can_save"], true)

	data["walls"] = [[8, 16, 16, 16]]
	data["spawns"]["start"] = [16, 24]
	var definition := MapDef.from_dictionary(data)
	h.check("夹具出生点按 WalkGrid 确实被墙阻挡",
		WalkGrid.is_free(definition, Vector2(16, 24)), false)
	h.check("真实被墙阻挡的出生点仍拒绝保存",
		_has(Validation.validate(data), "spawn", "start"), true)

	var legacy := Validation.read_map("res://data/maps/school_yard.json")
	var legacy_report := Validation.validate(legacy["data"])
	h.check("既有地图省略 portal ID 不再误报",
		_has(legacy_report, "portal", "id"), false)


static func _test_existing_maps(h: TestHarness) -> void:
	var directory := DirAccess.open("res://data/maps")
	if directory == null:
		h.check("读取现有地图目录", directory != null, true)
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var loaded := Validation.read_map("res://data/maps/%s" % file_name)
			if loaded.get("ok", false):
				var report := Validation.validate(loaded["data"])
				h.check("现有地图 %s 的门户 ID 符合 MapDef 规则" % file_name,
					_has(report, "portal", "id"), false)
				h.check("现有地图 %s 的出生点没有阻挡错误" % file_name,
					_has_error_kind(report, "spawn"), false)
		file_name = directory.get_next()
	directory.list_dir_end()


static func _fixture() -> Dictionary:
	return {
		"id": "map_validation_fixture",
		"size": [64, 64],
		"walls": [],
		"actors": [],
		"portals": [{"rect": [0, 48, 16, 16], "action": "overworld"}],
		"triggers": [],
		"spawns": {"start": [16, 32]},
	}


static func _has(report: Dictionary, kind: String, field: String) -> bool:
	for problem: Dictionary in report["issues"]:
		if problem["kind"] == kind and problem["field"] == field:
			return true
	return false


static func _has_error_kind(report: Dictionary, kind: String) -> bool:
	for problem: Dictionary in report["issues"]:
		if problem["severity"] == "error" and problem["kind"] == kind:
			return true
	return false
