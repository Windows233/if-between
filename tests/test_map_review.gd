## 校验、原子迁移、跨图审阅和面板信号的定向测试，可直接 --script 运行。
## 复用 TestHarness；所有落盘用例只写本次创建的 user:// 临时目录。
## run(h) 可由父级插件测试入口调用，不要求导入素材或运行游戏全套。
extends SceneTree

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Transfer := preload("res://addons/if_map_editor/map_geometry_transfer.gd")
const Validation := preload("res://addons/if_map_editor/map_validation.gd")
const Batch := preload("res://addons/if_map_editor/map_migration_batch.gd")
const ReviewPanel := preload("res://addons/if_map_editor/map_review_panel.gd")
const Library := preload("res://addons/if_map_editor/map_object_library.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("地图审阅与跨图迁移")
	_test_bad_data(h)
	_test_locations(h)
	_test_triggers(h)
	_test_navigation(h)
	_test_atomic_batch(h)
	_test_rejections(h)
	var directory := "user://map_review_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_test_templates(h, directory)
	_test_manifest(h, directory)
	_test_saving(h, directory)
	_test_panel(h)
	_test_report_ui(h, directory)
	_remove_temporary(directory, directory)


static func _fixture(map_id := "review_fixture") -> Dictionary:
	return {"id": map_id, "size": [96, 80], "walls": [[24, 28, 12, 8], [62, 36, 12, 8]],
		"actors": [{"id": "desk", "rect": [18, 18, 30, 30], "cover": true, "decor": true,
			"reach": [12, 42, 38, 16], "cover_y": 43},
			{"id": "shelf", "rect": [54, 18, 30, 40], "cover": true, "decor": true}],
		"portals": [], "spawns": {"start": [12, 22]}}


static func _plan() -> Array[Dictionary]:
	return [{"actor_id": "desk", "wall_indices": [0], "preserve_baseline": true},
		{"actor_id": "shelf", "wall_indices": [1], "preserve_baseline": false}]


static func _model(data: Dictionary) -> Variant:
	var model := Model.new()
	model.map_id = str(data.get("id", ""))
	model.data = data.duplicate(true)
	model.reset_history()
	return model


static func _state(model: Variant) -> Dictionary:
	return {"data": model.data.duplicate(true), "dirty": model.dirty,
		"history": model._history.duplicate(true), "index": model._history_index,
		"saved": model._saved_text, "map_id": model.map_id, "path": model.path}


static func _has(report: Dictionary, kind: String, field: String, severity := "error") -> bool:
	for problem: Dictionary in report.get("issues", []):
		if problem["kind"] == kind and problem["field"] == field and problem["severity"] == severity:
			return true
	return false


static func _test_bad_data(h: TestHarness) -> void:
	var broken: Array = [null, 4, [], {}, {"id": "broken", "size": [NAN, 20]},
		{"id": "broken", "size": [64, 64], "actors": [null]},
		{"id": "broken", "size": [64, 64], "walls": "bad"},
		{"id": "broken", "size": [64, 64], "portals": ["bad"]},
		{"id": "broken", "size": [64, 64], "spawns": []}]
	for field: String in ["rect", "collision", "reach_local", "sort_collider", "cover_y", "talk", "actions"]:
		var data := _fixture()
		data["actors"][0][field] = "wrong"
		broken.append(data)
	for index: int in broken.size():
		var report := Validation.validate(broken[index])
		h.check("坏数据 %d 返回错误且不崩" % index, report["can_save"], false)
		h.check("坏数据 %d 有结构化错误" % index, report["errors"].is_empty(), false)
		var migration := Batch.preview(broken[index], _plan())
		h.check("坏数据 %d 不能迁移" % index, migration["ok"], false)
	var cyclic := _fixture()
	cyclic["loop"] = cyclic
	h.check("循环数据不崩", Validation.validate(cyclic)["can_save"], false)
	cyclic.erase("loop")
	var base := _fixture()
	base["actors"][0]["talk"] = [{"shake": {"bad": 1}}]
	h.check("畸形对话数值在 MapDef 前被拦截", Validation.validate(base)["can_save"], false)
	base = _fixture()
	h.check("合法图通过校验", Validation.validate(base)["can_save"], true)
	h.check("只读校验不改数据", base, _fixture())


static func _test_locations(h: TestHarness) -> void:
	var data := _fixture()
	data["background"] = "res://missing_review_background.png"
	data["actors"][1]["sprite"] = "res://missing_review_actor.png"
	data["actors"][1]["event"] = "missing_review_event"
	data["actors"][1]["actions"] = [{"event": 42}]
	data["actors"][1]["id"] = "desk"
	data["portals"] = [{"id": "exit", "rect": [0, 40, 14, 20], "to": "missing_review_map", "spawn": "start"}]
	var report := Validation.validate(data)
	for pair: Array in [["map", "background"], ["actor", "sprite"], ["actor", "event"],
			["actor", "actions.0.event"], ["actor", "id"], ["portal", "to"]]:
		h.check("问题定位 %s.%s" % pair, _has(report, pair[0], pair[1]), true)
	for problem: Dictionary in report["issues"]:
		for field: String in ["severity", "message", "kind", "index", "field", "map_id"]:
			h.check("issue 包含 %s" % field, problem.has(field), true)
		if problem["field"] == "sprite":
			h.check("资源定位到正确物件", problem["index"], 1)
			h.check("保留缺资源路径", problem["resource"], data["actors"][1]["sprite"])
	var missing := _fixture()
	missing["actors"][0].erase("id")
	h.check("缺 ID 阻止保存", _has(Validation.validate(missing), "actor", "id"), true)
	missing = _fixture()
	missing["spawns"]["outside"] = [-1, 20]
	h.check("越界出生点可点击定位", _has(Validation.validate(missing), "spawn", "outside"), true)
	missing = _fixture()
	missing["actors"][0]["collision"] = [[0, 0, 8, 8]]
	missing["actors"][0]["sort_collider"] = 9
	h.check("失效遮挡参考可点击定位", _has(Validation.validate(missing), "actor", "sort_collider"), true)
	var target := _fixture("review_target")
	var context := {"maps": {"review_target": target}, "events": {"review_event": true}}
	data = _fixture()
	data["portals"] = [{"id": "exit", "rect": [0, 40, 14, 20], "to": "review_target", "spawn": "absent"}]
	h.check("目标出生点必须存在", _has(Validation.validate(data, context), "portal", "spawn"), true)
	data["portals"][0]["spawn"] = "start"
	data["actors"][0]["event"] = "review_event"
	h.check("有效地图/出生点/事件引用通过", Validation.validate(data, context)["can_save"], true)
	data["portals"].append(data["portals"][0].duplicate(true))
	h.check("重复 portal ID 被发现", _has(Validation.validate(data, context), "portal", "id"), true)
	data["portals"][1].erase("id")
	h.check("缺 portal ID 被发现", _has(Validation.validate(data, context), "portal", "id"), true)
	context["events"]["review_event"] = {"id": "wrong", "nodes": []}
	h.check("损坏事件不能冒充有效事件", _has(Validation.validate(data, context), "actor", "event"), true)
	context["events"]["review_event"] = {"id": "review_event", "nodes": [null]}
	h.check("损坏事件节点不能冒充有效事件", _has(Validation.validate(data, context), "actor", "event"), true)
	context["events"]["review_event"] = {"id": "review_event", "nodes": [{"id": "entry"}]}
	h.check("有效事件节点可用", _has(Validation.validate(data, context), "actor", "event"), false)


static func _test_triggers(h: TestHarness) -> void:
	var data := _fixture()
	var context := {"events": {"review_event": true}}
	data["triggers"] = [{"id": "zone", "rect": [0, 40, 20, 20], "event": "review_event",
		"mode": "enter", "enabled": true, "once": false, "condition": {"exists": "flag"}}]
	h.check("合法触发区域通过", Validation.validate(data, context)["can_save"], true)
	for pair: Array in [["event", "absent"], ["event", ""], ["mode", "unknown"],
			["rect", "wrong"], ["once", 1], ["enabled", "yes"], ["condition", {"all": [7]}],
			["condition", {"var": "flag", "op": "wrong", "value": true}]]:
		var invalid := data.duplicate(true)
		invalid["triggers"][0][pair[0]] = pair[1]
		var report := Validation.validate(invalid, context)
		h.check("触发错误定位 %s" % str(pair[0]), _has(report, "trigger", pair[0]), true)
		var located := false
		for problem: Dictionary in report["issues"]:
			if problem["kind"] == "trigger":
				located = problem["index"] == 0 and problem["map_id"] == data["id"]
		h.check("触发错误保留图和索引 %s" % str(pair[0]), located, true)
	var missing := data.duplicate(true)
	missing["triggers"][0].erase("event")
	h.check("触发缺少事件定位 event", _has(Validation.validate(missing, context), "trigger", "event"), true)
	missing = data.duplicate(true)
	missing["triggers"].append(missing["triggers"][0].duplicate(true))
	h.check("重复触发 ID 定位 trigger.id", _has(Validation.validate(missing, context), "trigger", "id"), true)
	missing["triggers"][1].erase("id")
	h.check("缺触发 ID 定位 trigger.id", _has(Validation.validate(missing, context), "trigger", "id"), true)
	data["triggers"][0]["mode"] = "enter_map"
	data["triggers"][0].erase("rect")
	h.check("enter_map 保持共享运行时的矩形约束", Validation.validate(data, context)["can_save"], false)
	h.check("enter_map 缺少矩形能定位到字段", _has(Validation.validate(data, context), "trigger", "rect"), true)
	data["triggers"] = [null]
	h.check("损坏 trigger 条目不崩", _has(Validation.validate(data), "trigger", ""), true)
	data["triggers"] = 3
	h.check("损坏 triggers 集合不崩", _has(Validation.validate(data), "map", "triggers"), true)


static func _test_navigation(h: TestHarness) -> void:
	var data := _fixture()
	data["walls"] = [[44, -10, 8, 102]]
	data["spawns"] = {"left": [20, 30], "right": [76, 30]}
	data["portals"] = [{"id": "exit", "rect": [72, 40, 18, 20], "to": data["id"], "spawn": "right"}]
	var report := Validation.validate(data)
	h.check("导航完整完成", report["navigation"]["complete"], true)
	h.check("WalkGrid 检出两个分量", report["navigation"]["components"].size(), 2)
	h.check("两个出生点属于不同分量", report["navigation"]["spawn_components"]["left"] ==
		report["navigation"]["spawn_components"]["right"], false)
	h.check("分量割裂显式警告", _has(report, "map", "navigation", "warning"), true)
	h.check("出口不可达显式警告", _has(report, "portal", "rect", "warning"), true)
	h.check("导航警告不变为错误", report["can_save"], true)
	data["spawns"]["blocked"] = [48, 30]
	data["actors"][0]["collision"] = [[0, 0, 16, 20]]
	data["actors"][0]["sort_collider"] = 0
	data["spawns"]["local"] = [24, 32]
	report = Validation.validate(data)
	h.check("墙阻挡出生点是错误", _has(report, "spawn", "blocked"), true)
	h.check("物件局部碰撞阻挡出生点是错误", _has(report, "spawn", "local"), true)
	data = _fixture()
	data["size"] = [100000, 100000]
	report = Validation.validate(data)
	h.check("巨大地图有导航上限，不会挂住", report["navigation"]["complete"], false)
	h.check("跳过导航显式警告", _has(report, "map", "size", "warning"), true)


static func _test_atomic_batch(h: TestHarness) -> void:
	var data := _fixture()
	var model: Variant = _model(data)
	var source := _state(model)
	var review := Batch.preview(data, _plan())
	h.check("显式两物件计划通过", review["ok"], true)
	h.check("预览不改源模型和历史", _state(model), source)
	h.check("两个目标都出现在对比", review["diff"]["changes"].size(), 2)
	h.check("默认 apply 未确认不修改", Batch.apply(model, review), false)
	h.check("未确认不改任何状态", _state(model), source)
	var first_indices: Array[int] = [0]
	var single := Transfer.preview(data, 0, first_indices, true)
	h.check("复用单物件迁移结果", review["data"]["actors"][0], single["data"]["actors"][0])
	h.check("diff 保留遮挡基线", review["diff"]["changes"][0]["before"]["cover_y"],
		review["diff"]["changes"][0]["after"]["cover_y"])
	h.check("diff 保留世界交互范围", review["diff"]["changes"][0]["before"]["reach"],
		review["diff"]["changes"][0]["after"]["reach"])
	h.check("确认后原子应用", Batch.apply(model, review, true), true)
	h.check("完整批量仅新增一笔历史", model._history.size(), source["history"].size() + 1)
	h.check("两面墙一起迁出", model.data["walls"], [])
	var migrated: Dictionary = model.data.duplicate(true)
	h.check("一次 undo 撤销整批", model.undo(), true)
	h.check("undo 恢复所有数据", model.data, data)
	h.check("undo 恢复原 dirty", model.dirty, false)
	h.check("一次 redo 重做整批", model.redo(), true)
	h.check("redo 恢复完整迁移", model.data, migrated)
	var before_def := MapDef.from_dictionary(data)
	var after_def := MapDef.from_dictionary(migrated)
	var mismatch := 0
	for row: int in range(0, 80, 2):
		for column: int in range(0, 96, 2):
			var point := Vector2(column, row)
			if WalkGrid.is_free(before_def, point) != WalkGrid.is_free(after_def, point):
				mismatch += 1
	h.check("全图 WalkGrid 碰撞等价", mismatch, 0)
	review["data"]["actors"][0]["rect"][0] = -999
	h.check("应用后不共享报告字典", model.data, migrated)


static func _test_rejections(h: TestHarness) -> void:
	var data := _fixture()
	var plans: Array = [[], null, [{"actor_id": "desk"}],
		[{"actor_id": "desk", "wall_indices": [], "preserve_baseline": true}],
		[{"actor_id": "absent", "wall_indices": [0], "preserve_baseline": true}],
		[{"actor_id": "desk", "wall_indices": [900], "preserve_baseline": true}],
		[{"actor_id": "desk", "wall_indices": [0, 0], "preserve_baseline": true}],
		[{"actor_id": "desk", "wall_indices": [0.5], "preserve_baseline": true}]]
	var duplicate_wall := _plan()
	duplicate_wall[1]["wall_indices"] = [0]
	plans.append(duplicate_wall)
	var duplicate_target := _plan()
	duplicate_target[1]["actor_id"] = "desk"
	plans.append(duplicate_target)
	for index: int in plans.size():
		var model: Variant = _model(data)
		var state := _state(model)
		var review := Batch.preview(data, plans[index])
		h.check("无效计划 %d 全量预检拒绝" % index, review["ok"], false)
		h.check("无效计划 %d 无可应用半成品" % index, review["data"], {})
		h.check("无效计划 %d apply 拒绝" % index, Batch.apply(model, review, true), false)
		h.check("无效计划 %d 状态完全不变" % index, _state(model), state)
	var invalid := _fixture()
	invalid["actors"][1]["person"] = true
	h.check("最后一项失败，前面也不生成半成品", Batch.preview(invalid, _plan())["data"], {})
	var parsed: Variant = JSON.parse_string(JSON.stringify(_plan()))
	h.check("manifest JSON 整数索引可使用", Batch.preview(data, parsed)["ok"], true)
	var model: Variant = _model(data)
	var review := Batch.preview(model.data, _plan())
	model.data["name"] = "其他编辑"
	var state := _state(model)
	h.check("地图任意编辑使预览过期", Batch.apply(model, review, true), false)
	h.check("过期拒绝保持已有编辑", _state(model), state)
	model = _model(data)
	review = Batch.preview(model.data, _plan())
	review["data"]["actors"][1]["rect"][0] = 0
	state = _state(model)
	h.check("篡改结果被重新预检拒绝", Batch.apply(model, review, true), false)
	h.check("篡改拒绝无历史副作用", _state(model), state)
	review = Batch.preview(model.data, _plan())
	review["plan"][1]["wall_indices"] = [0]
	h.check("应用前重验重复墙归属", Batch.apply(model, review, true), false)


static func _test_templates(h: TestHarness, directory: String) -> void:
	var library := Library.new()
	library.directory = directory.path_join("templates")
	var data := _fixture()
	h.check("使用既有模板写入接口创建测试模板", library.save_template("review_desk", data["actors"][0]), OK)
	data["actors"][0]["source_template"] = "review_desk"
	data["actors"][0]["collision"] = [[0, 10, 24, 10]]
	data["actors"][0]["sort_collider"] = 0
	var report := Validation.validate(data, {}, library)
	h.check("实例覆盖有定位警告", _has(report, "actor", "collision", "warning"), true)
	h.check("有效实例覆盖允许确认保存", report["can_save"], true)
	data["actors"][0]["source_template"] = "absent"
	h.check("缺模板禁止保存", _has(Validation.validate(data, {}, library), "actor", "source_template"), true)
	data["actors"][0]["source_template"] = "../unsafe"
	h.check("模板路径穿越作为缺失处理", Validation.validate(data, {}, library)["can_save"], false)


static func _test_manifest(h: TestHarness, directory: String) -> void:
	var first := _fixture("review_first")
	var second := _fixture("review_second")
	first["portals"] = [{"id": "exit", "rect": [0, 40, 14, 20], "to": "review_second", "spawn": "start"}]
	var first_path := directory.path_join("review_first.json")
	var second_path := directory.path_join("review_second.json")
	_write(first_path, first)
	_write(second_path, second)
	var manifest := {"maps": [{"map_id": first["id"], "path": first_path, "source": first.duplicate(true), "plan": _plan()},
		{"map_id": second["id"], "path": second_path}]}
	var first_text := FileAccess.get_file_as_string(first_path)
	var second_text := FileAccess.get_file_as_string(second_path)
	var report := Batch.report_manifest(manifest)
	h.check("跨图报告解析全部地图", report["maps"].size(), 2)
	h.check("跨图目标使用 manifest 快照", report["can_save"], true)
	h.check("跨图报告没有错误", report["errors"], [])
	h.check("manifest 不写正式图一", FileAccess.get_file_as_string(first_path), first_text)
	h.check("manifest 不写正式图二", FileAccess.get_file_as_string(second_path), second_text)
	h.check("迁移项保留 diff", report["maps"][0].get("diff", {}).get("changes", []).size(), 2)
	h.check("只读项没有隐式迁移", report["maps"][1]["data"], JSON.parse_string(second_text))
	var manifest_path := directory.path_join("manifest.json")
	_write(manifest_path, manifest)
	h.check("支持读取 manifest 文件", Batch.report_manifest(manifest_path)["maps"].size(), 2)
	var duplicate := manifest.duplicate(true)
	duplicate["maps"].append(duplicate["maps"][0].duplicate(true))
	h.check("重复跨图目标拒绝", Batch.report_manifest(duplicate)["can_save"], false)
	first["name"] = "已由其他人修改"
	_write(first_path, first)
	h.check("manifest 预期源快照过期拒绝", Batch.report_manifest(manifest)["can_save"], false)
	manifest["maps"][0].erase("source")
	second["actors"][1]["sprite"] = "res://review_missing_multi_map.png"
	_write(second_path, second)
	report = Batch.report_manifest(manifest)
	h.check("跨图缺资源阻止保存", report["can_save"], false)
	var found := false
	for problem: Dictionary in report["issues"]:
		if problem["field"] == "sprite":
			found = problem["map_id"] == second["id"] and problem["index"] == 1 \
				and problem["path"] == second_path and problem["resource"] == second["actors"][1]["sprite"]
	h.check("跨图资源定位保留图、物件、字段与路径", found, true)
	_write(second_path, {"id": "review_second", "size": [64, 64], "walls": 5})
	h.check("损坏地图的跨图报告不崩", Batch.report_manifest(manifest)["can_save"], false)


static func _test_saving(h: TestHarness, directory: String) -> void:
	var data := _fixture("review_save")
	data["actors"][0]["reach_local"] = [-6, 24, 38, 16]
	var path := directory.path_join("review_save.json")
	_write(path, data)
	var before := FileAccess.get_file_as_string(path)
	var model: Variant = _model(data)
	model.path = path
	model.backup_store.directory = directory.path_join("backups")
	model.data["name"] = "待确认的编辑"
	var review := Validation.validate(model.data)
	h.check("默认保存未确认拒绝", Batch.save_current(model, review)["ok"], false)
	h.check("未确认不改文件", FileAccess.get_file_as_string(path), before)
	h.check("警告未确认拒绝保存", Batch.save_current(model, review, true)["ok"], false)
	h.check("未确认警告不创建备份", model.last_backup_name, "")
	var saved := Batch.save_current(model, review, true, true)
	h.check("确认后经安全接口保存", saved["ok"], true)
	h.check("保存确实创建备份", not saved["backup"].is_empty(), true)
	h.check("备份与保存前字节一致", FileAccess.get_file_as_string(model.backup_store.directory.path_join(
		model.map_id).path_join(saved["backup"])), before)
	h.check("保存后模型不脏", model.dirty, false)
	var manifest := {"maps": [{"map_id": data["id"], "path": path}]}
	var report := Batch.report_manifest(manifest)
	var other := _fixture("review_save_other")
	var other_path := directory.path_join("review_save_other.json")
	_write(other_path, other)
	var multiple := {"maps": [{"map_id": data["id"], "path": path},
		{"map_id": other["id"], "path": other_path}]}
	var multi_report := Batch.report_manifest(multiple)
	other["name"] = "跨图目标已改变"
	_write(other_path, other)
	var saved_text := FileAccess.get_file_as_string(path)
	h.check("跨图任意源过期拒绝确认保存", Batch.save_current(model, multi_report, true, true)["ok"], false)
	h.check("跨图过期不改当前文件", FileAccess.get_file_as_string(path), saved_text)
	var changed: Dictionary = model.data.duplicate(true)
	changed["name"] = "外部新版本"
	_write(path, changed)
	var external := FileAccess.get_file_as_string(path)
	h.check("磁盘变化使报告过期", Batch.save_current(model, report, true, true)["ok"], false)
	h.check("过期保存保留外部新版本", FileAccess.get_file_as_string(path), external)
	model.data["actors"][0]["sprite"] = "res://review_save_missing.png"
	h.check("不能通过伪造 can_save 绕过错误", Batch.save_current(model,
		{"source": model.data.duplicate(true), "can_save": true}, true, true)["ok"], false)


static func _test_panel(h: TestHarness) -> void:
	var panel := ReviewPanel.new()
	h.root.add_child(panel)
	var model: Variant = _model(_fixture())
	var state := _state(model)
	var signals := {"validated": 0, "edited": 0, "review": 0, "issue": {}}
	panel.validated.connect(func(_report: Dictionary) -> void: signals["validated"] += 1)
	panel.edited.connect(func() -> void: signals["edited"] += 1)
	panel.review_requested.connect(func(_report: Dictionary) -> void: signals["review"] += 1)
	panel.issue_selected.connect(func(problem: Dictionary) -> void: signals["issue"] = problem)
	panel.configure(model)
	var wall := panel._walls.get_root().get_first_child()
	var checked := 0
	while wall != null:
		checked += 1 if wall.is_checked(0) else 0
		wall = wall.get_next()
	h.check("面板不会猜测墙归属", checked, 0)
	h.check("configure 不改模型", _state(model), state)
	h.check("表格 API 接收显式计划", panel.set_plan(_plan()), true)
	var detached := panel.get_plan()
	detached[0]["wall_indices"].clear()
	h.check("计划 API 不泄漏引用", panel.get_plan()[0]["wall_indices"], [0])
	h.check("面板预览通过", panel.preview_plan()["ok"], true)
	h.check("迁移预览不会发出保存审阅请求", signals["review"], 0)
	h.check("面板预览不改模型", _state(model), state)
	h.check("面板默认应用需要确认", panel.apply_preview(), false)
	h.check("明确确认可应用", panel.apply_preview(true), true)
	h.check("成功应用一次 edited", signals["edited"], 1)
	h.check("成功应用发出 validated", signals["validated"], 1)
	h.check("面板应用只生成一笔历史", model._history.size(), 2)
	h.check("应用后墙列表同步清空", panel._walls.get_root().get_child_count(), 0)
	h.check("应用后不自动保存", model.dirty, true)
	panel.request_save_review()
	h.check("保存走审阅请求信号", signals["review"], 1)
	model.data["actors"][0]["sprite"] = "res://review_panel_missing.png"
	panel.validate_current()
	panel._issues.item_selected.emit(0)
	h.check("问题点击定位字段", signals["issue"].get("field"), "sprite")
	h.check("错误时禁用保存入口", panel._save_button.disabled, true)
	panel.configure(_model(_fixture()))
	h.check("重复 configure 清理旧计划", panel.get_plan(), [])
	panel.set_plan(_plan())
	panel.preview_plan()
	panel._model.data["name"] = "切换后的编辑"
	var changed := _state(panel._model)
	h.check("面板过期应用拒绝", panel.apply_preview(true), false)
	h.check("面板过期拒绝无状态副作用", _state(panel._model), changed)
	panel.free()


static func _test_report_ui(h: TestHarness, directory: String) -> void:
	var panel := ReviewPanel.new()
	h.root.add_child(panel)
	var data := _fixture("review_ui_manifest")
	var path := directory.path_join("review_ui_manifest.json")
	_write(path, data)
	var model: Variant = _model(data)
	model.path = path
	panel.configure(model)
	h.check("跨图目录列出现有地图", panel._map_choices.item_count, Model.list_maps().size())
	h.check("存在打开 manifest 的文件选择器", panel._manifest_dialog is FileDialog, true)
	h.check("存在导出报告的文件选择器", panel._export_dialog.file_mode, FileDialog.FILE_MODE_SAVE_FILE)
	var cross_button := _find_button(panel, "跨地图报告")
	h.check("跨图报告按钮可达", cross_button != null, true)
	cross_button.pressed.emit()
	h.check("跨图按钮显示目录", panel._cross_maps.visible, true)
	panel._map_choices.select(0, false)
	var state := _state(model)
	_find_button(panel, "生成所选地图报告").pressed.emit()
	h.check("目录按钮生成单图报告", panel._manifest["maps"].size(), 1)
	h.check("目录报告不改当前模型", _state(model), state)
	var manifest_path := directory.path_join("ui_manifest.json")
	_write(manifest_path, {"maps": [{"map_id": data["id"], "path": path, "plan": _plan()}]})
	panel._manifest_dialog.file_selected.emit(manifest_path)
	h.check("manifest 文件选择信号进入报告", panel._manifest["maps"][0]["map_id"], data["id"])
	h.check("跨图报告包含可选地图摘要", panel._map_reports.item_count, 1)
	h.check("选择地图展示明确迁移对比", panel._comparison.text.contains("desk"), true)
	var report_path := directory.path_join("exported_report.json")
	panel._export_dialog.file_selected.emit(report_path)
	h.check("导出按钮流程生成结构化报告", Validation.read_map(report_path)["ok"], true)
	h.check("已存在导出须确认覆盖", panel.export_report(report_path), ERR_ALREADY_EXISTS)
	h.check("禁止报告覆盖当前地图", panel.export_report(path, true), ERR_UNAUTHORIZED)
	h.check("禁止报告覆盖正式数据", panel.export_report("res://data/maps/review_forbidden.json", true), ERR_UNAUTHORIZED)
	var text_path := directory.path_join("report.txt")
	h.check("可导出普通用户能读的文本报告", panel.export_report(text_path), OK)
	h.check("文本报告包含地图名", FileAccess.get_file_as_string(text_path).contains(data["id"]), true)
	h.check("整个跨图UI流程没有改变地图", Validation.read_map(path)["data"], JSON.parse_string(Model.stringify(data)))
	panel.free()


static func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child: Node in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


static func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(Model.stringify(data))
	file.close()


static func _remove_temporary(path: String, base: String) -> void:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	var root := ProjectSettings.globalize_path(base).simplify_path()
	if absolute != root and not absolute.begins_with(root + "/"):
		return
	var folder := DirAccess.open(path)
	if folder == null:
		return
	for filename: String in folder.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(filename)))
	for name: String in folder.get_directories():
		_remove_temporary(path.path_join(name), base)
	DirAccess.remove_absolute(absolute)
