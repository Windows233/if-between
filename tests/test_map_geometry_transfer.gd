## 地图墙归入物件的独立回归，入口为 run(h)。
## 使用合法小地图与真实地图副本，分别核对世界碰撞并集、导航和交互排序。
## 所有变更限于内存；历史由调用者 record_history()，格网差异聚合断言。
extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Transfer := preload("res://addons/if_map_editor/map_geometry_transfer.gd")
const TARGET := 1


## h 为现有 TestHarness；由主测试入口调用，不读写地图或编辑器草稿。
static func run(h: TestHarness) -> void:
	_test_explicit_selection(h)
	_test_detached_copies(h)
	_test_reach(h)
	_test_sorting(h)
	_test_existing_collisions(h)
	_test_history(h)
	_test_stale_source(h)
	_test_tampered_plans(h)
	_test_invalid_inputs(h)
	_test_precision_boundaries(h)
	_test_real_maps(h)


static func _fixture() -> Dictionary:
	return {"id": "geometry_transfer_fixture", "size": [160, 128],
		"name": "迁移回归", "background": "", "overlay": "", "music": "fixture_theme",
		"walls": [[0, 0, 160, 4], [48, 60, 20, 12], [110, 20, 5, 50],
			[60, 66, 28, 8], [8, 100, 32, 4]],
		"portals": [], "spawns": {"start": [20, 50]},
		"editor_groups": [{"id": "furniture", "name": "桌边组合", "members": ["desk", "nearby"]}],
		"actors": [{"id": "nearby", "rect": [48, 60, 16, 16], "decor": true},
			{"id": "desk", "rect": [40, 30, 64, 50], "reach": [30, 64, 85, 30],
				"cover": true, "decor": false, "solid": false, "person": false, "over": false,
				"label": "书桌", "sprite": "res://art/props/gatehouse_desk.png",
				"event": "gatehouse_door", "talk": [{"text": "登记册还在桌上。"}],
				"template_id": "fixture_desk", "template": {"id": "desk", "revision": 3},
				"custom": {"nested": ["原值", {"enabled": true}]}}]}


static func _test_explicit_selection(h: TestHarness) -> void:
	var source := _fixture()
	h.check("迁移小地图本身通过 MapDef 校验", MapDef.from_dictionary(source).validate(), [])
	var selected: Array[int] = [1]
	var plan := _preview(h, "单墙", source, TARGET, selected)
	if plan.is_empty():
		return
	var candidate: Dictionary = plan["data"]
	var actor: Dictionary = candidate["actors"][TARGET]
	h.check("明确选择只删除指定源墙", candidate["walls"],
		[source["walls"][0], source["walls"][2], source["walls"][3], source["walls"][4]])
	h.check("源墙换为相对目标左上角的碰撞", actor.get("collision"), [[8, 30, 20, 12]])
	h.check("新参考使用首个归入碰撞", actor.get("sort_collider", -1), 0)
	h.check("默认把原贴图底边换算为排序偏移", actor.get("sort_offset"), 20.0)
	h.check("更近的未选物件不获得碰撞", candidate["actors"][0], source["actors"][0])
	_check_business(h, "单墙", source, candidate, TARGET)
	_check_equivalence(h, "单墙", source, candidate)
	var overlapping: Array[int] = [3, 1]
	var multi := _preview(h, "逆序多墙", source, TARGET, overlapping)
	if multi.is_empty():
		return
	var combined: Dictionary = multi["data"]
	var shapes: Array = combined["actors"][TARGET].get("collision", [])
	h.check("逆序删墙没有索引漂移", combined["walls"],
		[source["walls"][0], source["walls"][2], source["walls"][4]])
	h.check("相交墙各自归入且没有重复或合并丢失", [shapes.size(),
		shapes.has([8, 30, 20, 12]), shapes.has([20, 36, 28, 8])], [2, true, true])
	_check_equivalence(h, "逆序多墙", source, combined)
	var fractional := _fixture()
	fractional["actors"][TARGET]["rect"] = [40.5, 30.25, 64, 50]
	fractional["walls"][1] = [43.25, 55.5, 7.5, 8.25]
	var precise := _preview(h, "小数几何", fractional, TARGET, selected)
	if not precise.is_empty():
		h.check("局部换算不取整", precise["data"]["actors"][TARGET].get("collision"),
			[[2.75, 25.25, 7.5, 8.25]])
		_check_equivalence(h, "小数几何", fractional, precise["data"])


static func _test_detached_copies(h: TestHarness) -> void:
	var source := _fixture()
	var original := source.duplicate(true)
	var selected: Array[int] = [1]
	var plan := _preview(h, "深拷贝", source, TARGET, selected)
	if plan.is_empty():
		return
	plan["data"]["actors"][TARGET]["custom"]["nested"][0] = "候选改动"
	h.check("候选嵌套数据不与来源共用", plan["source"], original)
	h.check("候选嵌套数据不与输入共用", source, original)
	plan["source"]["actors"][TARGET]["custom"]["nested"][1]["enabled"] = false
	h.check("来源嵌套数据不与输入共用", source, original)
	h.check("来源嵌套数据不与候选共用",
		plan["data"]["actors"][TARGET]["custom"]["nested"][1]["enabled"], true)
	var clean := _preview(h, "应用副本", source, TARGET, selected)
	if clean.is_empty():
		return
	var model: Variant = _model(source)
	h.check("干净计划可以应用", Transfer.apply(model, clean), true)
	var applied: Dictionary = model.data.duplicate(true)
	clean["data"]["actors"][TARGET]["custom"]["nested"][0] = "应用后篡改候选"
	clean["source"]["walls"][0][2] = 1
	h.check("应用后计划变动不穿透模型", model.data, applied)
	model.data["actors"][TARGET]["custom"]["nested"][1]["enabled"] = false
	h.check("模型后续编辑不穿透候选",
		clean["data"]["actors"][TARGET]["custom"]["nested"][1]["enabled"], true)


static func _test_reach(h: TestHarness) -> void:
	var variants: Array[Dictionary] = [
		{"label": "世界 reach", "fields": {"reach": [30, 64, 85, 30]},
			"expected": [-10, 34, 85, 30]},
		{"label": "默认 reach", "fields": {}, "expected": [0, 0, 64, 50]},
		{"label": "已有局部 reach", "fields": {"reach": [0, 0, 1, 1],
			"reach_local": [-5.5, 20.25, 72.5, 40]}, "expected": [-5.5, 20.25, 72.5, 40]}]
	var selected: Array[int] = [1]
	for variant: Dictionary in variants:
		var source := _fixture()
		source["actors"][TARGET].erase("reach")
		source["actors"][TARGET].merge(variant["fields"], true)
		var label: String = variant["label"]
		var plan := _preview(h, label, source, TARGET, selected)
		if plan.is_empty():
			continue
		var actor: Dictionary = plan["data"]["actors"][TARGET]
		h.check(label + "转为正确局部范围", actor.get("reach_local"), variant["expected"])
		h.check(label + "世界交互范围保持", MapDef._actor_from(actor).reach,
			MapDef._actor_from(source["actors"][TARGET]).reach)


static func _test_sorting(h: TestHarness) -> void:
	var selected: Array[int] = [1]
	for manual: bool in [false, true]:
		for preserve: bool in [true, false]:
			var source := _fixture()
			source["actors"][TARGET]["sort_offset"] = -3.25
			if manual:
				source["actors"][TARGET]["cover_y"] = 93.5
			var label := "排序 manual=%s preserve=%s" % [manual, preserve]
			var baseline: float = MapDef._actor_from(source["actors"][TARGET]).effective_cover_y()
			var plan := _preview(h, label, source, TARGET, selected, preserve)
			if plan.is_empty():
				continue
			var actor: Dictionary = plan["data"]["actors"][TARGET]
			var migrated: MapDef.Actor = MapDef._actor_from(actor)
			h.check(label + "清理绝对旧覆盖", actor.has("cover_y"), false)
			h.check(label + "参考碰撞上缘", migrated.auto_cover_y(), 60.0)
			if preserve:
				h.check(label + "保持有效基线", migrated.effective_cover_y(), baseline)
				h.check(label + "用偏移表达原基线", actor.get("sort_offset", 0), baseline - 60.0)
			else:
				h.check(label + "清理旧偏移", actor.has("sort_offset"), false)
				h.check(label + "恢复自动上缘", migrated.effective_cover_y(), 60.0)
	var hidden_cover := _fixture()
	hidden_cover["actors"][TARGET]["cover"] = false
	hidden_cover["actors"][TARGET]["decor"] = true
	var plan := _preview(h, "关闭遮挡", hidden_cover, TARGET, selected)
	if not plan.is_empty():
		h.check("归入墙不擅自打开 cover", plan["data"]["actors"][TARGET].get("cover"), false)
		h.check("装饰属性原样保留", plan["data"]["actors"][TARGET].get("decor"), true)


static func _test_existing_collisions(h: TestHarness) -> void:
	var selected: Array[int] = [1, 3]
	var variants: Array[Dictionary] = [
		{"label": "已有局部碰撞", "fields": {"collision": [[-12, 5, 8, 7], [6, 9, 15, 6]],
			"sort_collider": 1, "sort_offset": 4.5}, "prefix": [[-12, 5, 8, 7], [6, 9, 15, 6]], "reference": 1},
		{"label": "已有 solid", "fields": {"solid": true},
			"prefix": [[0, 0, 64, 50]], "reference": 1},
		{"label": "局部碰撞优先于 solid", "fields": {"solid": true,
			"collision": [[5, 12, 10, 8]], "sort_collider": 0},
			"prefix": [[5, 12, 10, 8]], "reference": 0},
		{"label": "空局部碰撞覆盖 solid", "fields": {"solid": true, "cover": false,
			"collision": []}, "prefix": [], "reference": 0},
		{"label": "无效旧参考选首个归入墙", "fields": {"cover": false,
			"collision": [[-12, 5, 8, 7], [6, 9, 15, 6]], "sort_collider": 3},
			"prefix": [[-12, 5, 8, 7], [6, 9, 15, 6]], "reference": 2}]
	for variant: Dictionary in variants:
		var source := _fixture()
		source["actors"][TARGET].merge(variant["fields"], true)
		var label: String = variant["label"]
		var plan := _preview(h, label, source, TARGET, selected)
		if plan.is_empty():
			continue
		var actor: Dictionary = plan["data"]["actors"][TARGET]
		var shapes: Array = actor.get("collision", [])
		var prefix: Array = variant["prefix"]
		h.check(label + "原有效碰撞不被替换", shapes.slice(0, prefix.size()), prefix)
		h.check(label + "只追加选中两墙", shapes.size(), prefix.size() + 2)
		h.check(label + "排序参考", actor.get("sort_collider", -1), variant["reference"])
		h.check(label + "排序有效值保持", MapDef._actor_from(actor).effective_cover_y(),
			MapDef._actor_from(source["actors"][TARGET]).effective_cover_y())
		_check_business(h, label, source, plan["data"], TARGET)
		_check_equivalence(h, label, source, plan["data"])
		var automatic := _preview(h, label + "恢复自动", source, TARGET, selected, false)
		if not automatic.is_empty():
			var automatic_actor: Dictionary = automatic["data"]["actors"][TARGET]
			var parsed: MapDef.Actor = MapDef._actor_from(automatic_actor)
			h.check(label + "自动仍保留正确参考", automatic_actor.get("sort_collider", -1),
				variant["reference"])
			h.check(label + "自动不残留手动覆盖", [automatic_actor.has("cover_y"),
				automatic_actor.has("sort_offset"), parsed.effective_cover_y()],
				[false, false, parsed.auto_cover_y()])


static func _test_history(h: TestHarness) -> void:
	var source := _fixture()
	var model: Variant = _model(source)
	model.data["name"] = "先前已记录编辑"
	model.record_history()
	var prior: Dictionary = model.data.duplicate(true)
	var state := _state(model)
	var selected: Array[int] = [1, 3]
	var plan := _preview(h, "历史", model.data, TARGET, selected)
	h.check("预览不改变模型和历史", _state(model), state)
	if plan.is_empty():
		return
	var candidate: Dictionary = plan["data"].duplicate(true)
	h.check("应用迁移成功", Transfer.apply(model, plan), true)
	h.check("应用写入候选且置脏", [model.data, model.dirty], [candidate, true])
	h.check("应用本身不记录历史", [model._history.size(), model._history_index], [2, 1])
	model.record_history()
	h.check("调用者记录后仅增加一步", [model._history.size(), model._history_index], [3, 2])
	var after := _state(model)
	h.check("重复应用拒绝", Transfer.apply(model, plan), false)
	h.check("重复应用不改数据脏位和历史", _state(model), after)
	h.check("迁移能撤销", model.undo(), true)
	h.check("一次撤销完整恢复源墙和物件", model.data, prior)
	h.check("迁移撤销保留先前脏编辑", model.dirty, true)
	h.check("先前编辑仍可撤销", model.undo(), true)
	h.check("再撤销恢复载入快照和干净标记", [model.data, model.dirty], [source, false])
	h.check("先前编辑能重做", model.redo(), true)
	h.check("迁移能重做", model.redo(), true)
	h.check("重做恢复完整候选和脏标记", [model.data, model.dirty], [candidate, true])
	h.check("没有多余历史步", model.redo(), false)
	var unrecorded: Variant = _model(source)
	var unrecorded_plan := _preview(h, "无自动历史", source, TARGET, selected)
	if not unrecorded_plan.is_empty():
		h.check("未记录迁移可应用", Transfer.apply(unrecorded, unrecorded_plan), true)
		h.check("调用者记录前没有撤销步", unrecorded.undo(), false)
		h.check("未记录的候选仍在内存", unrecorded.data, unrecorded_plan["data"])


static func _test_stale_source(h: TestHarness) -> void:
	var selected: Array[int] = [1]
	for change: String in ["未选墙", "源墙", "目标业务字段", "地图字段", "分组", "物件顺序"]:
		var source := _fixture()
		var model: Variant = _model(source)
		var plan := _preview(h, "陈旧来源 " + change, source, TARGET, selected)
		if plan.is_empty():
			continue
		match change:
			"未选墙":
				model.data["walls"][4][0] += 2
			"源墙":
				model.data["walls"][1][2] += 2
			"目标业务字段":
				model.data["actors"][TARGET]["label"] = "预览后的修改"
			"地图字段":
				model.data["music"] = "changed_theme"
			"分组":
				model.data["editor_groups"][0]["name"] = "改过的组名"
			"物件顺序":
				model.data["actors"].reverse()
		model.dirty = true
		_expect_apply_rejected(h, "陈旧来源 " + change, model, plan)


static func _test_tampered_plans(h: TestHarness) -> void:
	var selected: Array[int] = [1]
	for change: String in ["候选碰撞", "候选源墙", "候选业务", "候选其他物件", "候选分组",
		"来源内容", "目标索引", "墙索引", "排序模式", "失败标志",
		"缺少来源", "缺少候选", "候选类型", "空计划"]:
		var source := _fixture()
		var model: Variant = _model(source)
		var plan := _preview(h, "篡改 " + change, source, TARGET, selected)
		if plan.is_empty():
			continue
		match change:
			"候选碰撞":
				plan["data"]["actors"][TARGET]["collision"][0][0] += 1
			"候选源墙":
				plan["data"]["walls"].pop_back()
			"候选业务":
				plan["data"]["actors"][TARGET]["event"] = "other_event"
			"候选其他物件":
				plan["data"]["actors"][0]["rect"][0] += 1
			"候选分组":
				plan["data"]["editor_groups"][0]["members"].clear()
			"来源内容":
				plan["source"]["walls"][0][2] = 1
			"目标索引":
				plan["actor_index"] = 0
			"墙索引":
				var other: Array[int] = [3]
				plan["wall_indices"] = other
			"排序模式":
				plan["preserve_sort"] = false
			"失败标志":
				plan["ok"] = false
			"缺少来源":
				plan.erase("source")
			"缺少候选":
				plan.erase("data")
			"候选类型":
				plan["data"] = []
			"空计划":
				plan.clear()
		_expect_apply_rejected(h, "篡改 " + change, model, plan)


static func _test_invalid_inputs(h: TestHarness) -> void:
	var source := _fixture()
	var none: Array[int] = []
	var repeated: Array[int] = [1, 1]
	var negative: Array[int] = [-1]
	var past_end: Array[int] = [5]
	var selected: Array[int] = [1]
	_expect_rejected(h, "空墙选择", source, TARGET, none)
	_expect_rejected(h, "重复墙索引", source, TARGET, repeated)
	_expect_rejected(h, "负墙索引", source, TARGET, negative)
	_expect_rejected(h, "越界墙索引", source, TARGET, past_end)
	_expect_rejected(h, "负物件索引", source, -1, selected)
	_expect_rejected(h, "越界物件索引", source, 2, selected)
	_expect_rejected(h, "空地图", {}, 0, selected)
	var missing_actors := _fixture()
	missing_actors.erase("actors")
	_expect_rejected(h, "缺失 actors", missing_actors, 0, selected)
	var cases: Array[Dictionary] = [
		{"label": "空地图 ID", "scope": "map", "key": "id", "value": ""},
		{"label": "无效地图尺寸", "scope": "map", "key": "size", "value": [0, 128]},
		{"label": "地图尺寸类型", "scope": "map", "key": "size", "value": [160, "128"]},
		{"label": "越界出生点", "scope": "map", "key": "spawns", "value": {"start": [-1, 50]}},
		{"label": "无目标传送口", "scope": "map", "key": "portals", "value": [{"rect": [1, 1, 8, 8]}]},
		{"label": "墙集合类型", "scope": "map", "key": "walls", "value": {}},
		{"label": "物件集合类型", "scope": "map", "key": "actors", "value": {}},
		{"label": "目标不是字典", "scope": "actor_entry", "value": []},
		{"label": "空目标 ID", "scope": "actor", "key": "id", "value": ""},
		{"label": "目标 ID 重复", "scope": "actor", "key": "id", "value": "nearby"},
		{"label": "目标 rect 类型", "scope": "actor", "key": "rect", "value": "40,30,64,50"},
		{"label": "目标 rect 长度", "scope": "actor", "key": "rect", "value": [40, 30, 64]},
		{"label": "目标 rect 字符数值", "scope": "actor", "key": "rect", "value": ["40", 30, 64, 50]},
		{"label": "目标 rect 布尔数值", "scope": "actor", "key": "rect", "value": [true, 30, 64, 50]},
		{"label": "目标 rect 非有限", "scope": "actor", "key": "rect", "value": [INF, 30, 64, 50]},
		{"label": "目标 rect 负尺寸", "scope": "actor", "key": "rect", "value": [40, 30, -1, 50]},
		{"label": "源墙类型", "scope": "wall", "value": {"rect": [48, 60, 20, 12]}},
		{"label": "源墙长度", "scope": "wall", "value": [48, 60, 20]},
		{"label": "源墙零尺寸", "scope": "wall", "value": [48, 60, 0, 12]},
		{"label": "源墙负尺寸", "scope": "wall", "value": [48, 60, 20, -1]},
		{"label": "源墙字符数值", "scope": "wall", "value": [48, "60", 20, 12]},
		{"label": "源墙布尔数值", "scope": "wall", "value": [48, false, 20, 12]},
		{"label": "源墙 NaN", "scope": "wall", "value": [NAN, 60, 20, 12]},
		{"label": "源墙无穷", "scope": "wall", "value": [48, 60, INF, 12]},
		{"label": "局部碰撞集合类型", "scope": "actor", "key": "collision", "value": {}},
		{"label": "局部碰撞长度", "scope": "actor", "key": "collision", "value": [[1, 2, 3]]},
		{"label": "局部碰撞非数值", "scope": "actor", "key": "collision", "value": [[1, "2", 3, 4]]},
		{"label": "局部碰撞 NaN", "scope": "actor", "key": "collision", "value": [[1, 2, NAN, 4]]},
		{"label": "局部碰撞零尺寸", "scope": "actor", "key": "collision", "value": [[1, 2, 3, 0]]},
		{"label": "世界交互类型", "scope": "actor", "key": "reach", "value": {}},
		{"label": "世界交互无穷", "scope": "actor", "key": "reach", "value": [1, INF, 3, 4]},
		{"label": "世界交互零尺寸", "scope": "actor", "key": "reach", "value": [1, 2, 0, 4]},
		{"label": "局部交互长度", "scope": "actor", "key": "reach_local", "value": [1, 2, 3]},
		{"label": "局部交互负尺寸", "scope": "actor", "key": "reach_local", "value": [1, 2, -3, 4]},
		{"label": "排序偏移非数值", "scope": "actor", "key": "sort_offset", "value": "3"},
		{"label": "排序偏移 NaN", "scope": "actor", "key": "sort_offset", "value": NAN},
		{"label": "旧排序覆盖无穷", "scope": "actor", "key": "cover_y", "value": INF},
		{"label": "旧排序覆盖类型", "scope": "actor", "key": "cover_y", "value": "80"},
		{"label": "人物目标", "scope": "actor", "key": "person", "value": true},
		{"label": "前景目标", "scope": "actor", "key": "over", "value": true}]
	for entry: Dictionary in cases:
		var invalid := _fixture()
		match entry["scope"]:
			"map":
				invalid[entry["key"]] = entry["value"]
			"actor":
				invalid["actors"][TARGET][entry["key"]] = entry["value"]
			"actor_entry":
				invalid["actors"][TARGET] = entry["value"]
			"wall":
				invalid["walls"][1] = entry["value"]
		_expect_rejected(h, entry["label"], invalid, TARGET, selected)
	for condition: Variant in [{"var": "night"}, "night", ["night"], true, 1]:
		var conditional := _fixture()
		conditional["actors"][TARGET]["if"] = condition
		_expect_rejected(h, "非空 if " + var_to_str(condition), conditional, TARGET, selected)
	for condition: Variant in [null, {}]:
		var unconditional := _fixture()
		unconditional["actors"][TARGET]["if"] = condition
		var plan := _preview(h, "空条件 " + var_to_str(condition), unconditional, TARGET, selected)
		if not plan.is_empty():
			h.check("空条件字段保持", plan["data"]["actors"][TARGET].get("if"), condition)
	var invalid_elsewhere := _fixture()
	invalid_elsewhere["walls"][4] = [8, 100, 32, 0]
	_expect_rejected(h, "未选墙非法也拒绝整图", invalid_elsewhere, TARGET, selected)
	var duplicate_elsewhere := _fixture()
	duplicate_elsewhere["actors"].append({"id": "nearby", "rect": [10, 10, 8, 8]})
	_expect_rejected(h, "非目标 ID 重复也拒绝整图", duplicate_elsewhere, TARGET, selected)
	var invalid_reference := _fixture()
	invalid_reference["actors"][TARGET]["collision"] = [[1, 2, 3, 4]]
	invalid_reference["actors"][TARGET]["sort_collider"] = 5
	_expect_rejected(h, "MapDef 排序参考非法不先修后迁移", invalid_reference, TARGET, selected)


static func _test_precision_boundaries(h: TestHarness) -> void:
	var selected: Array[int] = [1]
	var lossy_wall := _fixture()
	lossy_wall["actors"][TARGET]["rect"] = [1000000, 30, 64, 50]
	lossy_wall["walls"][1] = [0.03125, 60, 20, 12]
	h.check("有损墙输入仍是合法 MapDef", MapDef.from_dictionary(lossy_wall).validate(), [])
	_expect_rejected(h, "墙世界转局部再转世界不能丢失 1/32", lossy_wall, TARGET, selected)
	var lossy_reach := _fixture()
	lossy_reach["actors"][TARGET]["rect"] = [1000000, 30, 64, 50]
	lossy_reach["walls"][1] = [1000000, 60, 20, 12]
	lossy_reach["actors"][TARGET]["reach"] = [0.03125, 64, 85, 30]
	h.check("有损交互输入仍是合法 MapDef", MapDef.from_dictionary(lossy_reach).validate(), [])
	_expect_rejected(h, "reach 世界转局部必须无损", lossy_reach, TARGET, selected)
	var existing := _fixture()
	existing["actors"][TARGET]["rect"] = [524288, 30, 64, 50]
	existing["actors"][TARGET]["reach"] = [524280, 64, 85, 30]
	existing["actors"][TARGET]["collision"] = [[0.03125, 4, 2, 3]]
	existing["walls"][1] = [524290, 60, 20, 12]
	var plan := _preview(h, "已有碰撞精度边界", existing, TARGET, selected)
	if not plan.is_empty():
		var before: MapDef.Actor = MapDef._actor_from(existing["actors"][TARGET])
		var after: MapDef.Actor = MapDef._actor_from(plan["data"]["actors"][TARGET])
		h.check("边界碰撞保持原来实际世界几何", after.collision_rects()[0], before.collision_rects()[0])
		_check_equivalence(h, "已有碰撞精度边界", existing, plan["data"])
	var near_limit := _fixture()
	near_limit["actors"][TARGET]["rect"] = [999990, 30, 64, 50]
	near_limit["actors"][TARGET]["reach"] = [999980, 64, 85, 30]
	near_limit["walls"][1] = [999990.0625, 60, 20, 12]
	var lossless := _preview(h, "大坐标无损边界", near_limit, TARGET, selected)
	if not lossless.is_empty():
		h.check("恰可表示的 1/16 局部值保留", lossless["data"]["actors"][TARGET]["collision"],
			[[0.0625, 30, 20, 12]])
		_check_equivalence(h, "大坐标无损边界", near_limit, lossless["data"])
	var tiny := _fixture()
	tiny["actors"][TARGET]["rect"] = [0, 30, 64, 50]
	tiny["walls"][1] = [0.00000005, 60, 20, 12]
	var tiny_plan := _preview(h, "贴近零的小数不压成整数", tiny, TARGET, selected)
	if not tiny_plan.is_empty():
		h.check("小数碰撞偏移保留非零", tiny_plan["data"]["actors"][TARGET]["collision"][0][0] > 0.0, true)
		var parsed := MapDef._actor_from(tiny_plan["data"]["actors"][TARGET])
		h.check("小数碰撞世界几何精确保留", parsed.collision_rects()[0], MapDef._to_rect(tiny["walls"][1]))


static func _test_real_maps(h: TestHarness) -> void:
	for map_id: String in ["gatehouse", "market", "market_night"]:
		var path := "res://data/maps/%s.json" % map_id
		var text := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		h.check(map_id + "真实地图读取得到字典", parsed is Dictionary, true)
		if not parsed is Dictionary:
			continue
		var source: Dictionary = parsed.duplicate(true)
		var target_id := "desk" if map_id == "gatehouse" else "fountain"
		var actor_index := -1
		for index: int in source["actors"].size():
			if source["actors"][index].get("id") == target_id:
				actor_index = index
		h.check(map_id + "明确目标物件存在", actor_index >= 0, true)
		if actor_index < 0:
			continue
		var selected: Array[int] = [5]
		if map_id != "gatehouse":
			selected.assign([37, 29, 35, 30, 33, 32])
		var plan := _preview(h, map_id, source, actor_index, selected)
		if plan.is_empty():
			continue
		var candidate: Dictionary = plan["data"]
		_check_business(h, map_id, source, candidate, actor_index)
		_check_equivalence(h, map_id, source, candidate)
		h.check(map_id + "只删明确墙数", candidate["walls"].size(), source["walls"].size() - selected.size())
		if map_id == "gatehouse":
			h.check("门卫室墙 5 归入桌子", candidate["actors"][actor_index]["collision"], [[0, 12, 76, 40]])
			h.check("门卫室桌子有效基线保持 165", plan["after_baseline"], 165.0)
		else:
			var before := MapDef.from_dictionary(source)
			var after := MapDef.from_dictionary(candidate)
			var route_errors: Array[Vector2] = []
			for vertical: int in range(162, 233, 2):
				var point := Vector2(324, vertical)
				if not WalkGrid.is_free(before, point) or not WalkGrid.is_free(after, point):
					route_errors.append(point)
					break
			h.check(map_id + "喷泉东侧贴边窄道连续可通行", route_errors, [])
			# 贴边落点跟随所迁移墙体和当前脚底宽度，不能钉死旧主角比例下的坐标。
			var edge_wall := MapDef._to_rect(source["walls"][selected.back()])
			var foot := WalkGrid.foot_rect(Vector2.ZERO, before.player_scale)
			var edge := Vector2(edge_wall.end.x + foot.size.x * 0.5, edge_wall.get_center().y)
			h.check(map_id + "窄道站立和导航落点余量区别保持",
				[WalkGrid.is_free(before, edge), WalkGrid.has_landing_room(before, edge),
				WalkGrid.is_free(after, edge), WalkGrid.has_landing_room(after, edge)],
				[true, false, true, false])
		h.check(map_id + "测试后真实地图字节未改", FileAccess.get_file_as_string(path), text)


static func _model(data: Dictionary) -> Variant:
	var model: Variant = Model.new()
	model.data = data.duplicate(true)
	model.reset_history()
	return model


static func _state(model: Variant) -> Dictionary:
	return {"data": var_to_str(model.data), "dirty": model.dirty,
		"history": var_to_str(model._history), "history_index": model._history_index,
		"saved": model._saved_text, "path": model.path, "map_id": model.map_id}


static func _preview(h: TestHarness, label: String, data: Dictionary,
		actor_index: int, wall_indices: Array[int], preserve_sort: bool = true) -> Dictionary:
	var snapshot := var_to_str(data)
	var selection := wall_indices.duplicate()
	var plan: Dictionary = Transfer.preview(data, actor_index, wall_indices) if preserve_sort \
		else Transfer.preview(data, actor_index, wall_indices, false)
	h.check(label + "预览不改变输入", [var_to_str(data), wall_indices], [snapshot, selection])
	h.check(label + "预览成功", plan.get("ok"), true)
	var fields := ["ok", "errors", "data", "source", "actor_index", "wall_indices",
		"preserve_sort", "before_baseline", "after_baseline", "added_shapes", "warnings"]
	var missing: Array[String] = []
	for field: String in fields:
		if not plan.has(field):
			missing.append(field)
	h.check(label + "预览结果字段齐全", missing, [])
	if not plan.get("ok", false) or not missing.is_empty():
		return {}
	var errors: Variant = plan["errors"]
	h.check(label + "成功错误列表为空", errors, [])
	h.check(label + "错误列表保持 Array[String]", errors is Array and errors.is_typed() \
		and errors.get_typed_builtin() == TYPE_STRING, true)
	h.check(label + "来源是完整快照", plan["source"], data)
	selection.sort()
	h.check(label + "记录操作参数和归入数", [plan["actor_index"], plan["wall_indices"],
		plan["preserve_sort"], plan["added_shapes"]],
		[actor_index, selection, preserve_sort, wall_indices.size()])
	h.check(label + "警告列表类型", plan["warnings"] is Array, true)
	var candidate: Dictionary = plan["data"]
	h.check(label + "候选通过 MapDef 校验", MapDef.from_dictionary(candidate).validate(), [])
	var before: MapDef.Actor = MapDef._actor_from(data["actors"][actor_index])
	var after: MapDef.Actor = MapDef._actor_from(candidate["actors"][actor_index])
	h.check(label + "报告原基线", plan["before_baseline"], before.effective_cover_y())
	h.check(label + "报告候选基线", plan["after_baseline"], after.effective_cover_y())
	return plan


static func _expect_apply_rejected(h: TestHarness, label: String, model: Variant, plan: Dictionary) -> void:
	var state := _state(model)
	h.check(label + "应用被拒绝", Transfer.apply(model, plan), false)
	h.check(label + "拒绝后数据脏位和历史不变", _state(model), state)


static func _expect_rejected(h: TestHarness, label: String, data: Dictionary,
		actor_index: int, wall_indices: Array[int]) -> void:
	var snapshot := var_to_str(data)
	var selection := wall_indices.duplicate()
	var plan: Dictionary = Transfer.preview(data, actor_index, wall_indices)
	h.check(label + "预览拒绝", plan.get("ok"), false)
	var errors: Variant = plan.get("errors", [])
	h.check(label + "给出错误", errors is Array and not errors.is_empty(), true)
	h.check(label + "失败输入和选择不变", [var_to_str(data), wall_indices], [snapshot, selection])
	var model: Variant = _model(_fixture())
	model.data = data.duplicate(true)
	model.dirty = true
	_expect_apply_rejected(h, label, model, plan)


static func _check_business(h: TestHarness, label: String, before: Dictionary,
		after: Dictionary, actor_index: int) -> void:
	var old_map := before.duplicate(true)
	var new_map := after.duplicate(true)
	old_map.erase("actors")
	old_map.erase("walls")
	new_map.erase("actors")
	new_map.erase("walls")
	h.check(label + "地图业务与分组不变", new_map, old_map)
	h.check(label + "物件数量不变", after["actors"].size(), before["actors"].size())
	var old_actors: Array = before["actors"].duplicate(true)
	var new_actors: Array = after["actors"].duplicate(true)
	for field: String in ["collision", "reach", "reach_local", "cover_y", "sort_offset", "sort_collider"]:
		old_actors[actor_index].erase(field)
		new_actors[actor_index].erase(field)
	h.check(label + "仅目标几何字段改变且模板与视觉属性保持", new_actors, old_actors)


static func _check_equivalence(h: TestHarness, label: String, before: Dictionary, after: Dictionary) -> void:
	var original := MapDef.from_dictionary(before)
	var candidate := MapDef.from_dictionary(after)
	h.check(label + "精确世界碰撞并集等价", _union_difference(original, candidate), {})
	h.check(label + "全图 WalkGrid 站立与落点等价", _walk_differences(original, candidate), [])
	h.check(label + "世界交互范围保持", _reach_list(candidate), _reach_list(original))


static func _reach_list(definition: MapDef) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for actor: MapDef.Actor in definition.actors:
		result.append(actor.reach)
	return result


static func _world_shapes(definition: MapDef) -> Array[Rect2]:
	var result: Array[Rect2] = definition.walls.duplicate()
	for actor: MapDef.Actor in definition.actors:
		result.append_array(actor.collision_rects())
	return result


static func _union_difference(before: MapDef, after: MapDef) -> Dictionary:
	var old_shapes := _world_shapes(before)
	var new_shapes := _world_shapes(after)
	var edges: Dictionary = {}
	for shape: Rect2 in old_shapes + new_shapes:
		edges[shape.position.x] = true
		edges[shape.end.x] = true
	var ordered: Array = edges.keys()
	ordered.sort()
	for index: int in range(ordered.size() - 1):
		var left: float = ordered[index]
		var right: float = ordered[index + 1]
		var old_intervals := _interval_union(old_shapes, left, right)
		var new_intervals := _interval_union(new_shapes, left, right)
		if old_intervals != new_intervals:
			return {"x_range": [left, right], "before": old_intervals, "after": new_intervals}
	return {}


static func _interval_union(shapes: Array[Rect2], left: float, right: float) -> Array[Vector2]:
	var intervals: Array[Vector2] = []
	for shape: Rect2 in shapes:
		if shape.position.x < right and shape.end.x > left:
			intervals.append(Vector2(shape.position.y, shape.end.y))
	intervals.sort_custom(func(first: Vector2, second: Vector2) -> bool:
		return first.x < second.x or (first.x == second.x and first.y < second.y))
	var merged: Array[Vector2] = []
	for interval: Vector2 in intervals:
		if merged.is_empty() or interval.x > merged[-1].y:
			merged.append(interval)
		else:
			var previous: Vector2 = merged[-1]
			merged[-1] = Vector2(previous.x, maxf(previous.y, interval.y))
	return merged


static func _walk_differences(before: MapDef, after: MapDef) -> Array[Dictionary]:
	var differences: Array[Dictionary] = []
	for vertical: int in range(0, before.size.y + 1, int(WalkGrid.STEP)):
		for horizontal: int in range(0, before.size.x + 1, int(WalkGrid.STEP)):
			var difference := _walk_difference(before, after, Vector2(horizontal, vertical))
			if not difference.is_empty():
				differences.append(difference)
				if differences.size() >= 4:
					return differences
	for shape: Rect2 in _world_shapes(before):
		for horizontal: float in [shape.position.x - WalkGrid.FOOT_HALF, shape.end.x + WalkGrid.FOOT_HALF]:
			for vertical: float in [shape.position.y - WalkGrid.FOOT_DOWN, shape.end.y + WalkGrid.FOOT_UP]:
				for offset: Vector2 in [Vector2.ZERO, Vector2(-0.125, -0.125), Vector2(0.125, 0.125)]:
					var difference := _walk_difference(before, after, Vector2(horizontal, vertical) + offset)
					if not difference.is_empty():
						differences.append(difference)
						if differences.size() >= 4:
							return differences
	return differences


static func _walk_difference(before: MapDef, after: MapDef, point: Vector2) -> Dictionary:
	var original := [WalkGrid.is_free(before, point), WalkGrid.has_landing_room(before, point)]
	var candidate := [WalkGrid.is_free(after, point), WalkGrid.has_landing_room(after, point)]
	return {} if original == candidate else {"point": point, "before": original, "after": candidate}
