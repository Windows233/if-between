extends RefCounted

const Library := preload("res://addons/if_map_editor/map_object_library.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


class PartialWriter:
	extends "res://addons/if_map_editor/map_object_library.gd"

	func _write_template_file(path: String, text: String) -> Error:
		var error := super._write_template_file(path, text.substr(0, 16))
		return ERR_FILE_CANT_WRITE if error == OK else error


class CompetingWriter:
	extends "res://addons/if_map_editor/map_object_library.gd"

	var competing_target := ""

	func _write_template_file(path: String, text: String) -> Error:
		var error := super._write_template_file(path, text)
		if error != OK:
			return error
		return super._write_template_file(competing_target, "another writer")


static func run(h: TestHarness) -> void:
	test_round_trip(h)
	test_legacy_geometry(h)
	test_invalid_actors(h)
	test_invalid_documents(h)
	test_names(h)
	test_failed_saves(h)
	test_failed_placement(h)


static func fixture() -> Dictionary:
	return {"id": "desk", "rect": [60, 40, 80, 60], "label": "书桌", "cover": true,
		"sprite": "res://art/props/gatehouse_desk.png", "collision": [[5, 30, 70, 20]],
		"reach_local": [-6, 42, 92, 36], "sort_collider": 0, "event": "gatehouse_door"}


static func test_round_trip(h: TestHarness) -> void:
	var library = _library("round_trip")
	var source := fixture()
	source["source_template"] = "previous_template"
	var before := Model.stringify(source)
	h.check("合法局部负坐标与排序引用0可以保存", library.save_template("desk", source), OK)
	h.check("保存模板不修改源物件", Model.stringify(source), before)
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(library.directory.path_join("desk.json")))
	h.check("模板仍使用version1", document.get("version"), 1)
	var stored: Dictionary = document.get("actor", {})
	h.check("模板保存时归零贴图原点", stored.get("rect"), [0.0, 0.0, 80.0, 60.0])
	h.check("模板保留合法负局部交互坐标", stored.get("reach_local"), [-6.0, 42.0, 92.0, 36.0])
	h.check("模板快照不保留源模板标记", stored.has("source_template"), false)
	h.check("模板列表只展示有效快照", library.list_templates(), ["desk"])
	var model = _model()
	var selection: Array[int] = library.instantiate("desk", model, Vector2(200, 100))
	h.check("模板实例化生成一个物件", selection.size(), 1)
	if selection.size() == 1:
		var item: Dictionary = model.actor_dict(selection[0])
		var actor := MapDef._actor_from(item)
		h.check("模板实例ID避开地图已有ID", actor.id, &"desk_2")
		h.check("模板实例贴图落在指定位置", actor.rect, Rect2(200, 100, 80, 60))
		h.check("模板实例碰撞随位置换算", actor.collision_rects(), [Rect2(205, 130, 70, 20)])
		h.check("模板实例按碰撞上边缘排序", actor.effective_cover_y(), 130.0)
		h.check("模板实例保持事件入口", actor.interactions[0].event_id, &"gatehouse_door")
		h.check("source_template仍标识所放置快照", item.get("source_template"), "desk")
		h.check("成功放置才标脏", model.dirty, true)
		DirAccess.remove_absolute(library.directory.path_join("desk.json"))
		h.check("移除模板文件不影响已生成物件", MapDef.from_dictionary(model.data).validate(), [])
		h.check("已生成实例不依赖模板文件加载", MapDef._actor_from(item).effective_cover_y(), 130.0)
	_cleanup(library.directory)


static func test_legacy_geometry(h: TestHarness) -> void:
	var library = _library("legacy")
	var source := fixture()
	source.erase("reach_local")
	source["reach"] = [54, 82, 92, 36]
	source["cover_y"] = 88
	source["sort_offset"] = 99
	h.check("合法旧reach和cover_y可以保存", library.save_template("legacy", source), OK)
	var normalized: Dictionary = library._load_actor("legacy")
	h.check("旧世界交互范围转换为局部范围", normalized.get("reach_local"), [-6.0, 42.0, 92.0, 36.0])
	h.check("旧世界交互字段在快照中移除", normalized.has("reach"), false)
	h.check("旧基线转为相对碰撞上边缘的偏移", normalized.get("sort_offset"), 18.0)
	h.check("旧绝对基线在快照中移除", normalized.has("cover_y"), false)
	var model = _model()
	var selection: Array[int] = library.instantiate("legacy", model, Vector2(200, 100))
	h.check("规范化旧模板能实例化", selection.size(), 1)
	if selection.size() == 1:
		var actor := MapDef._actor_from(model.actor_dict(selection[0]))
		h.check("旧交互范围移动后正确", actor.reach, Rect2(194, 142, 92, 36))
		h.check("旧手动排序偏移移动后正确", actor.effective_cover_y(), 148.0)
	source["cover_y"] = -1
	source["sort_offset"] = -4
	h.check("旧cover_y自动哨兵可保存", library.save_template("automatic", source), OK)
	h.check("自动哨兵保留已有排序偏移", library._load_actor("automatic").get("sort_offset"), -4.0)
	source["reach_local"] = [-9, 20, 60, 35]
	h.check("局部与旧reach共存仍可保存", library.save_template("local_wins", source), OK)
	h.check("局部交互按MapDef语义优先于旧reach", library._load_actor("local_wins").get("reach_local"), [-9.0, 20.0, 60.0, 35.0])
	source.erase("collision")
	source.erase("reach_local")
	source.erase("sort_collider")
	source["cover_y"] = 108
	h.check("无局部碰撞的旧模板仍可保存", library.save_template("legacy_bottom", source), OK)
	h.check("旧贴图底边基线规范为相对偏移", library._load_actor("legacy_bottom").get("sort_offset"), 8.0)
	source["collision"] = []
	source["over"] = true
	h.check("永久前景允许空局部碰撞沿用MapDef语义", library.save_template("foreground", source), OK)
	_cleanup(library.directory)


static func test_invalid_actors(h: TestHarness) -> void:
	var library = _library("invalid_actors")
	var cases: Array[Dictionary] = []
	var bad_rects: Array = [null, "rect", [], [0, 1, 2], [0, 1, 2, 3, 4],
		[{}, 0, 20, 20], ["0", 0, 20, 20], [false, 0, 20, 20],
		[0, 0, 0, 20], [0, 0, 20, -1]]
	for field: String in ["rect", "reach", "reach_local"]:
		for index: int in bad_rects.size():
			_add_case(cases, "%s非法矩形%d" % [field, index], {field: bad_rects[index]})
	for value: Variant in [null, {}, "collision", [[0, 0, 1]], [[0, 0, 20, 0]], [[0, 0, "20", 20]]]:
		_add_case(cases, "非法局部碰撞%d" % cases.size(), {"collision": value})
	for value: Variant in [null, {}, "0", false, 0.5, -1, 1]:
		_add_case(cases, "非法排序引用%d" % cases.size(), {"sort_collider": value})
	_add_case(cases, "空碰撞无排序参考", {"collision": []})
	_add_case(cases, "缺少物件ID", {"id": ""})
	_add_case(cases, "非文本物件ID", {"id": {}})
	_add_case(cases, "错误旧基线类型", {"cover_y": {}})
	_add_case(cases, "错误排序偏移类型", {"sort_offset": []})
	_add_case(cases, "错误对话数值不能进入MapDef", {"talk": [{"size_delta": {}}]})
	_add_case(cases, "错误动作对话数值不能进入MapDef", {"actions": [{"talk": [{"shake": []}]}]})
	var model = _model()
	for index: int in cases.size():
		var entry: Dictionary = cases[index]
		var name := "bad_%d" % index
		var actor: Dictionary = entry["actor"]
		h.check("保存拒绝" + entry["label"], library.save_template(name, actor), ERR_INVALID_DATA)
		h.check("拒绝保存不留目标文件" + name, FileAccess.file_exists(library.directory.path_join(name + ".json")), false)
		h.check("拒绝保存不留暂存目录" + name, DirAccess.dir_exists_absolute(library.directory.path_join(name + ".json.pending")), false)
		_write(library.directory.path_join(name + ".json"), JSON.stringify({"version": 1, "actor": actor}))
		_check_rejected(h, library, model, name, index % 2 == 0)
	for rect: Array in [[INF, 0, 20, 20], [0, 0, NAN, 20]]:
		var actor := fixture()
		actor["rect"] = rect
		h.check("保存拒绝非有限矩形数值", library.save_template("nonfinite", actor), ERR_INVALID_DATA)
		h.check("非有限矩形拒绝后不留文件", FileAccess.file_exists(library.directory.path_join("nonfinite.json")), false)
	h.check("损坏物件不会列为可用模板", library.list_templates(), [])
	_cleanup(library.directory)


static func test_invalid_documents(h: TestHarness) -> void:
	var library = _library("documents")
	var documents: Array[String] = ["", "{", "{\"version\":1,\"actor\":", "null", "[]", "1"]
	for version: Variant in [null, false, true, "1", [], {}, 0, 2, 1.5]:
		documents.append(JSON.stringify({"version": version, "actor": fixture()}))
	documents.append(JSON.stringify({"actor": fixture()}))
	documents.append(JSON.stringify({"version": 1}))
	documents.append(JSON.stringify({"version": 1, "actor": []}))
	for name: Variant in [null, [], "", "../desk", "desk."]:
		documents.append(JSON.stringify({"version": 1, "name": name, "actor": fixture()}))
	var model = _model()
	for index: int in documents.size():
		var name := "document_%d" % index
		_write(library.directory.path_join(name + ".json"), documents[index])
		_check_rejected(h, library, model, name, index % 2 == 1)
	_check_rejected(h, library, model, "missing", false)
	h.check("错误JSON和版本不会进入模板列表", library.list_templates(), [])
	_write(library.directory.path_join("old_v1.json"), JSON.stringify({"version": 1, "actor": fixture()}))
	var selection: Array[int] = library.instantiate("old_v1", model, Vector2.ZERO)
	h.check("旧version1未写展示名仍可实例化", selection.size(), 1)
	_cleanup(library.directory)


static func test_names(h: TestHarness) -> void:
	var library = _library("names")
	var model = _model()
	for name: String in ["", " ", "../desk", "a/b", "a\\b", "..", "desk..old", "desk.",
		"desk ", " desk", "a?b", "a\nb", "CON", "nul", "COM1.txt", "lpt9"]:
		h.check("保存拒绝非法模板名" + name, library.save_template(name, fixture()), ERR_INVALID_PARAMETER)
		_check_rejected(h, library, model, name, false)
	h.check("合法中文模板名称可保存", library.save_template("书桌（旧式）", fixture()), OK)
	h.check("合法中文模板能列出", library.list_templates(), ["书桌（旧式）"])
	_cleanup(library.directory)


static func test_failed_saves(h: TestHarness) -> void:
	var library = _library("failed_saves")
	var target: String = library.directory.path_join("desk.json")
	_write(target, "existing corrupt snapshot")
	h.check("同名损坏文件也不覆盖", library.save_template("desk", fixture()), ERR_ALREADY_EXISTS)
	h.check("保存失败保留原文件字节", FileAccess.get_file_as_string(target), "existing corrupt snapshot")
	DirAccess.make_dir_absolute(library.directory.path_join("directory.json"))
	h.check("同名目录不可覆盖", library.save_template("directory", fixture()), ERR_ALREADY_EXISTS)
	var partial := PartialWriter.new()
	partial.directory = library.directory
	h.check("部分写入错误向调用者报告", partial.save_template("partial", fixture()), ERR_FILE_CANT_WRITE)
	h.check("部分写入失败无目标文件", FileAccess.file_exists(library.directory.path_join("partial.json")), false)
	h.check("部分写入失败清理暂存目录", DirAccess.dir_exists_absolute(library.directory.path_join("partial.json.pending")), false)
	var competing := CompetingWriter.new()
	competing.directory = library.directory
	competing.competing_target = library.directory.path_join("competing.json")
	h.check("发布前出现同名文件时拒绝覆盖", competing.save_template("competing", fixture()), ERR_ALREADY_EXISTS)
	h.check("保留竞争写入者的完整文件", FileAccess.get_file_as_string(competing.competing_target), "another writer")
	h.check("发布冲突清理本次暂存目录", DirAccess.dir_exists_absolute(library.directory.path_join("competing.json.pending")), false)
	var pending: String = library.directory.path_join("busy.json.pending")
	DirAccess.make_dir_absolute(pending)
	_write(pending.path_join("owner.txt"), "other save")
	h.check("其他保存持有暂存目录时拒绝写入", library.save_template("busy", fixture()) != OK, true)
	h.check("失败不删除其他保存的暂存数据", FileAccess.get_file_as_string(pending.path_join("owner.txt")), "other save")
	var blocked = Library.new()
	blocked.directory = target.path_join("child")
	h.check("模板目录父路径是文件时正常报错", blocked.save_template("blocked", fixture()) != OK, true)
	h.check("目录失败不修改已有父文件", FileAccess.get_file_as_string(target), "existing corrupt snapshot")
	_cleanup(library.directory)


static func test_failed_placement(h: TestHarness) -> void:
	var library = _library("placement")
	h.check("创建放置失败测试的合法模板", library.save_template("desk", fixture()), OK)
	var model = _model()
	var before := Model.stringify(model.data)
	for offset: Vector2 in [Vector2(INF, 0), Vector2(0, NAN), Vector2(0, -INF)]:
		h.check("无效落点不会生成物件", library.instantiate("desk", model, offset), [])
		h.check("无效落点不改地图", Model.stringify(model.data), before)
		h.check("无效落点不标脏", model.dirty, false)
	var distant_reach := fixture()
	distant_reach["reach_local"] = [2e38, 0, 20, 20]
	_write(library.directory.path_join("overflow.json"), JSON.stringify({"version": 1, "actor": distant_reach}))
	h.check("超出数据层整数坐标范围时拒绝放置", library.instantiate("overflow", model, Vector2(2e38, 0)), [])
	h.check("整数坐标越界不改地图内容", Model.stringify(model.data), before)
	h.check("整数坐标越界不改dirty", model.dirty, false)
	h.check("空model正常返回失败", library.instantiate("desk", null, Vector2.ZERO), [])
	h.check("错误model类型正常返回失败", library.instantiate("desk", RefCounted.new(), Vector2.ZERO), [])
	_cleanup(library.directory)


static func _add_case(cases: Array[Dictionary], label: String, changes: Dictionary) -> void:
	var actor := fixture()
	actor.merge(changes, true)
	cases.append({"label": label, "actor": actor})


static func _check_rejected(h: TestHarness, library, model, name: String, dirty: bool) -> void:
	model.dirty = dirty
	var before := Model.stringify(model.data)
	h.check("实例化拒绝坏模板" + name, library.instantiate(name, model, Vector2(100, 80)), [])
	h.check("实例化失败地图内容不变" + name, Model.stringify(model.data), before)
	h.check("实例化失败dirty保持原值" + name, model.dirty, dirty)


static func _library(label: String):
	var library = Library.new()
	library.directory = "user://test_map_templates_%s_%d" % [label, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(library.directory))
	return library


static func _model():
	var model = Model.new()
	model.map_id = "template_fixture"
	model.data = {"id": "template_fixture", "size": [400, 300], "actors": [fixture()]}
	model.reset_history()
	return model


static func _write(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error


static func _cleanup(path: String) -> void:
	var folder := DirAccess.open(path)
	if folder == null:
		return
	for filename: String in folder.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in folder.get_directories():
		_cleanup(path.path_join(child))
	DirAccess.remove_absolute(path)
