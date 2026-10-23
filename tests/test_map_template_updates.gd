extends RefCounted

const Library := preload("res://addons/if_map_editor/map_object_library.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Inspector := preload("res://addons/if_map_editor/map_template_inspector.gd")


class PartialWriter:
	extends "res://addons/if_map_editor/map_object_library.gd"

	func _write_template_file(path: String, text: String) -> Error:
		var error := super._write_template_file(path, text.substr(0, 12))
		return ERR_FILE_CANT_WRITE if error == OK else error


class CompetingWriter:
	extends "res://addons/if_map_editor/map_object_library.gd"

	var target := ""

	func _write_template_file(path: String, text: String) -> Error:
		var error := super._write_template_file(path, text)
		return super._write_template_file(target, "competing edit") if error == OK else error


static func run(h: TestHarness) -> void:
	test_inheritance(h)
	test_updates(h)
	test_legacy(h)
	test_batch(h)
	test_writes(h)
	test_inspector(h)
	test_template_authoring(h)
	test_template_authoring_safety(h)


static func fixture() -> Dictionary:
	return {"id": "desk", "rect": [60, 40, 80, 60], "label": "书桌", "cover": true,
		"sprite": "res://art/props/gatehouse_desk.png", "collision": [[5, 30, 70, 20]],
		"reach_local": [-6, 42, 92, 36], "sort_collider": 0, "event": "gatehouse_door",
		"future": {"color": "oak", "count": 1}}


static func test_inheritance(h: TestHarness) -> void:
	var library = _library("inheritance")
	h.check("v2基础模板创建", library.create_template("desk", fixture(), "",
		{"category": "家具", "tags": ["室内", "木制"]}), OK)
	h.check("v2单继承允许部分默认", library.create_template("child", {"label": "窄桌",
		"future": {"child": true}, "collision": [[3, 20, 50, 20]]}, "desk"), OK)
	var resolved: Dictionary = library.resolve("child")
	h.check("v2格式与内容版本分开", [resolved.get("format_version"), resolved.get("version")], [2, 1])
	h.check("继承链按父到子排列", resolved.get("chain"), [{"name": "desk", "version": 1}, {"name": "child", "version": 1}])
	var actor: Dictionary = resolved.get("actor", {})
	h.check("子模板显式覆盖父字段", actor.get("label"), "窄桌")
	h.check("默认字典递归合并", actor.get("future"), {"color": "oak", "count": 1.0, "child": true})
	h.check("默认数组整体替换", actor.get("collision"), [[3.0, 20.0, 50.0, 20.0]])
	h.check("分类与标签继承筛选", library.list_templates("家具", ["木制"], "child"), ["child"])
	h.check("不匹配标签筛除", library.list_templates("家具", ["室外"]), [])
	var before := FileAccess.get_file_as_string(library.directory.path_join("desk.json"))
	h.check("更新拒绝形成继承循环", library.update_template("desk", fixture(), 1, "child"), ERR_CYCLIC_LINK)
	h.check("循环错误不改父文件", FileAccess.get_file_as_string(library.directory.path_join("desk.json")), before)
	h.check("缺失父模板不能保存", library.create_template("missing", {}, "absent") != OK, true)
	h.check("继承错误不产生文件", FileAccess.file_exists(library.directory.path_join("missing.json")), false)
	_write(library.directory.path_join("cycle_a.json"), JSON.stringify({"version": 2, "template_version": 1, "extends": "cycle_b", "actor": {}}))
	_write(library.directory.path_join("cycle_b.json"), JSON.stringify({"version": 2, "template_version": 1, "extends": "cycle_a", "actor": {}}))
	h.check("读取外部循环数据明确报错", library.resolve_template("cycle_a").get("error"), ERR_CYCLIC_LINK)
	_write(library.directory.path_join("multiple.json"), JSON.stringify({"version": 2, "template_version": 1, "extends": ["desk", "child"], "actor": {}}))
	h.check("拒绝多继承文档", library.resolve_template("multiple").get("ok"), false)
	var model = _model()
	var indices: Array[int] = library.instantiate("child", model, Vector2(200, 100))
	h.check("继承模板可以实例化", indices.size(), 1)
	var changed := fixture()
	changed["future"]["count"] = 2
	h.check("父模板显式更新", library.update_template("desk", changed, 1), OK)
	h.check("父版本变化触发子实例更新提示", library.inspect_instance(model, 0).get("update_available"), true)
	var preview: Dictionary = library.preview_instance_update(model, 0)
	h.check("子版本不变仍能合并父变化", preview.get("after", {}).get("future", {}).get("count"), 2)
	h.check("v2元数据不混进运行时物件", model.actor_dict(0).has("metadata"), false)
	var legacy := fixture()
	legacy.erase("reach_local")
	legacy["reach"] = [54, 82, 92, 36]
	legacy["cover_y"] = 88
	_write(library.directory.path_join("raw_v1.json"), JSON.stringify({"version": 1, "actor": legacy}))
	h.check("v2可继承含世界坐标的旧v1", library.create_template("legacy_child", {"rect": [0, 0, 100, 70]}, "raw_v1"), OK)
	resolved = library.resolve_template("legacy_child")
	h.check("继承时先将旧父几何归入局部坐标", resolved.get("actor", {}).get("reach_local"), [-6.0, 42.0, 92.0, 36.0])
	h.check("继承不把旧世界基线误当局部偏移", resolved.get("actor", {}).get("sort_offset"), 18.0)
	_cleanup(library.directory)


static func test_updates(h: TestHarness) -> void:
	var library = _library("updates")
	h.check("创建更新模板", library.create_template("desk", fixture()), OK)
	var model = _model()
	library.instantiate("desk", model, Vector2(200, 100))
	model.set_actor_field(0, "id", "local_desk")
	model.set_actor_field(0, "label", "本地书桌")
	model.set_actor_field(0, "future", {"color": "red", "count": 1})
	model.set_actor_field(0, "custom_local", {"keep": true})
	model.erase_actor_field(0, "event")
	model.reset_history()
	model.dirty = false
	var before := Model.stringify(model.data)
	var newer := fixture()
	newer["label"] = "本地书桌"
	newer["rect"] = [0, 0, 100, 70]
	newer["collision"] = [[5, 28, 75, 22]]
	newer["future"]["count"] = 2
	h.check("模板内容版本递增", library.update_template("desk", newer, 1), OK)
	var info: Dictionary = library.inspect_instance(model, 0)
	h.check("检查器明确标记覆盖", info["fields"]["label"]["state"], "overridden")
	h.check("删除模板字段也是覆盖", info["fields"]["event"]["state"], "overridden")
	var preview: Dictionary = library.preview_instance_update(model, 0)
	h.check("预览成功", preview.get("ok"), true)
	h.check("预览不改模型或脏标记", [Model.stringify(model.data), model.dirty], [before, false])
	var after: Dictionary = preview.get("after", {})
	h.check("更新保留ID位置并跟随默认尺寸", [after.get("id"), after.get("rect")], ["local_desk", [200, 100, 100.0, 70.0]])
	h.check("递归合并保留局部覆盖并更新其他默认", after.get("future"), {"color": "red", "count": 2.0})
	h.check("JSON数值类型差异不会误标默认字段覆盖", info["fields"]["rect"]["state"], "default")
	h.check("未覆盖的局部碰撞更新", after.get("collision"), [[5.0, 28.0, 75.0, 22.0]])
	h.check("删除与未知扩展字段保留", [after.has("event"), after.get("custom_local")], [false, {"keep": true}])
	h.check("未明确确认不能写模型", library.confirm_instance_update(model, 0, preview), ERR_UNAUTHORIZED)
	var tampered := preview.duplicate(true)
	tampered["after"]["id"] = "unsafe"
	h.check("不能篡改预览绕过身份保护", library.confirm_instance_update(model, 0, tampered, true), ERR_BUSY)
	h.check("明确确认更新", library.confirm_instance_update(model, 0, preview, true), OK)
	var applied := Model.stringify(model.data)
	h.check("更新版本与默认快照", model.actor_field(0, "source_template_version"), 2)
	h.check("更新可整步撤销", model.undo(), true)
	h.check("撤销连元数据一起恢复", Model.stringify(model.data), before)
	h.check("更新可整步重做", model.redo(), true)
	h.check("重做保持全部结果", Model.stringify(model.data), applied)
	newer["label"] = "第三版默认"
	h.check("第三版模板更新", library.update_template("desk", newer, 2), OK)
	preview = library.preview_instance_update(model, 0)
	h.check("曾被新默认追平的本地覆盖仍保留", preview.get("after", {}).get("label"), "本地书桌")
	h.check("确认第三版", library.confirm_instance_update(model, 0, preview, true), OK)
	preview = library.preview_restore_defaults(model, ["label"], 0)
	h.check("恢复字段也先预览", model.actor_field(0, "label"), "本地书桌")
	h.check("确认恢复指定字段", library.confirm_instance_update(model, 0, preview, true), OK)
	h.check("指定字段恢复当前默认", model.actor_field(0, "label"), "第三版默认")
	h.check("指定字段恢复清除覆盖状态", library.inspect_instance(model, 0)["fields"]["label"]["state"], "default")
	preview = library.preview_restore_defaults(model, [], 0)
	h.check("确认恢复全部模板默认", library.confirm_instance_update(model, 0, preview, true), OK)
	h.check("恢复全部重新建立已删除默认字段", model.actor_field(0, "event"), "gatehouse_door")
	h.check("恢复全部保留未知扩展", model.actor_field(0, "custom_local"), {"keep": true})
	h.check("恢复不能改实例ID", library.preview_restore_defaults(model, ["id"], 0).get("ok"), false)
	preview = library.preview_instance_update(model, 0)
	newer["label"] = "第四版默认"
	h.check("创建过期预览场景", library.update_template("desk", newer, 3), OK)
	h.check("模板变动后旧确认被拒绝", library.confirm_instance_update(model, 0, preview, true), ERR_BUSY)
	preview = library.preview_instance_update(model, 0)
	model.set_actor_field(0, "label", "预览后编辑")
	h.check("实例变动后旧确认被拒绝", library.confirm_instance_update(model, 0, preview, true), ERR_BUSY)
	model.set_actor_field(0, "sort_offset", 1.1)
	preview = library.preview_instance_update(model, 0)
	model.set_actor_field(0, "sort_offset", 1.2)
	h.check("小数变动也让预览过期", library.confirm_instance_update(model, 0, preview, true), ERR_BUSY)
	model.set_actor_field(0, "rect", [210, 110, 88, 66])
	preview = library.preview_instance_update(model, 0)
	h.check("本地尺寸覆盖和新位置保留", preview.get("after", {}).get("rect"), [210, 110, 88, 66])
	var unrecorded := Model.stringify(model.data)
	h.check("确认前先保留尚未记录的本地状态", library.confirm_instance_update(model, 0, preview, true), OK)
	h.check("撤销只撤模板动作", model.undo(), true)
	h.check("未记录的本地状态不会随模板更新撤销丢失", Model.stringify(model.data), unrecorded)
	_cleanup(library.directory)


static func test_legacy(h: TestHarness) -> void:
	var library = _library("legacy")
	h.check("旧保存API仍创建v1", library.save_template("desk", fixture()), OK)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(library.directory.path_join("desk.json")))
	h.check("旧API不偷改格式", document.get("version"), 1)
	var model = _model()
	library.instantiate("desk", model, Vector2(200, 100))
	h.check("v1新实例也记录可信快照", library.inspect_instance(model, 0).get("snapshot_valid"), true)
	for field: String in ["source_template_defaults", "source_template_version"]:
		model.erase_actor_field(0, field)
	model.set_actor_field(0, "unknown_extension", {"keep": true})
	var before := Model.stringify(model.data)
	h.check("旧source_template实例覆盖状态未知", library.inspect_instance(model, 0)["fields"]["label"]["state"], "unknown")
	h.check("旧实例不能猜成无覆盖更新", library.preview_instance_update(model, 0).get("error"), ERR_UNCONFIGURED)
	var preview: Dictionary = library.preview_adopt_instance(model, 0)
	h.check("安全接管也不静默改实例", Model.stringify(model.data), before)
	h.check("确认建立保守基线", library.confirm_instance_update(model, 0, preview, true), OK)
	h.check("旧值等于默认也保留为覆盖", library.inspect_instance(model, 0)["fields"]["label"]["state"], "preserved")
	var newer := fixture()
	newer["label"] = "新的模板默认"
	newer["solid"] = false
	h.check("旧v1显式迁移为v2版本更新", library.update_template("desk", newer, 1), OK)
	preview = library.preview_instance_update(model, 0)
	h.check("保守基线阻止覆盖旧本地字段", preview.get("after", {}).get("label"), "书桌")
	h.check("接管后新模板字段可继承", preview.get("after", {}).get("solid"), false)
	h.check("确认保守更新", library.confirm_instance_update(model, 0, preview, true), OK)
	preview = library.preview_restore_defaults(model, ["label"], 0)
	h.check("旧实例可显式恢复所选默认", library.confirm_instance_update(model, 0, preview, true), OK)
	h.check("恢复后字段使用新默认", model.actor_field(0, "label"), "新的模板默认")
	preview = library.preview_restore_defaults(model, [], 0)
	h.check("保守接管后可恢复全部模板字段", library.confirm_instance_update(model, 0, preview, true), OK)
	h.check("恢复全部也保留旧实例未知扩展", model.actor_field(0, "unknown_extension"), {"keep": true})
	model.set_actor_field(0, "source_template_defaults", "corrupt")
	h.check("损坏快照不被信任", library.inspect_instance(model, 0).get("snapshot_valid"), false)
	h.check("损坏快照继续阻止自动更新", library.preview_instance_update(model, 0).get("ok"), false)
	_cleanup(library.directory)


static func test_batch(h: TestHarness) -> void:
	var library = _library("batch")
	h.check("批量模板创建", library.create_template("desk", fixture()), OK)
	var model = _model()
	library.instantiate("desk", model, Vector2(100, 100))
	library.instantiate("desk", model, Vector2(250, 100))
	model.reset_history()
	model.dirty = false
	var before := Model.stringify(model.data)
	var newer := fixture()
	newer["label"] = "批量新默认"
	h.check("批量模板更新", library.update_template("desk", newer, 1), OK)
	var batch: Dictionary = library.preview_updates(model, [0, 1, 0])
	h.check("重复选择去重", batch.get("updates", []).size(), 2)
	h.check("批量预览不改数据", Model.stringify(model.data), before)
	model.set_actor_field(1, "line", "预览后修改")
	var stale := Model.stringify(model.data)
	h.check("批量任一实例过期则整体拒绝", library.confirm_updates(model, batch, true), ERR_BUSY)
	h.check("批量拒绝没有部分写入", Model.stringify(model.data), stale)
	model.erase_actor_field(1, "line")
	batch = library.preview_updates(model, [0, 1])
	h.check("批量确认成功", library.confirm_updates(model, batch, true), OK)
	h.check("两个实例均更新", [model.actor_field(0, "label"), model.actor_field(1, "label")], ["批量新默认", "批量新默认"])
	h.check("批量一次撤销", model.undo(), true)
	h.check("一次撤销恢复整个选择", Model.stringify(model.data), before)
	h.check("批量不产生第二个历史步", model.undo(), false)
	model.set_actor_field(1, "collision", [[0, 0, 20, 20], [20, 0, 20, 20]])
	model.set_actor_field(1, "sort_collider", 1)
	newer["collision"] = [[0, 0, 30, 30]]
	newer["sort_collider"] = 0
	h.check("构造字段依赖更新", library.update_template("desk", newer, 2), OK)
	h.check("覆盖碰撞与排序引用保持有效", library.preview_updates(model, [0, 1]).get("ok"), true)
	h.check("无效选择导致整体预览失败", library.preview_updates(model, [0, 9]).get("ok"), false)
	_cleanup(library.directory)


static func test_writes(h: TestHarness) -> void:
	var library = _library("writes")
	h.check("创建写入保护模板", library.create_template("desk", fixture()), OK)
	var target: String = library.directory.path_join("desk.json")
	var before := FileAccess.get_file_as_string(target)
	h.check("新API同名仍拒绝覆盖", library.create_template("desk", fixture()), ERR_ALREADY_EXISTS)
	h.check("旧save也不覆盖v2", library.save_template("desk", fixture()), ERR_ALREADY_EXISTS)
	h.check("必须指定正确的预期版本", library.update_template("desk", fixture(), 99), ERR_BUSY)
	var partial := PartialWriter.new()
	partial.directory = library.directory
	h.check("版本更新部分写入失败上报", partial.update_template("desk", fixture(), 1), ERR_FILE_CANT_WRITE)
	h.check("更新失败保留原文件字节", FileAccess.get_file_as_string(target), before)
	h.check("更新失败清理自己的暂存", DirAccess.dir_exists_absolute(target + ".pending"), false)
	var competing := CompetingWriter.new()
	competing.directory = library.directory
	competing.target = target
	h.check("发布前外部编辑触发冲突", competing.update_template("desk", fixture(), 1), ERR_BUSY)
	h.check("外部编辑的字节不能覆盖", FileAccess.get_file_as_string(target), "competing edit")
	h.check("损坏已有模板不能盲目升级", library.update_template("desk", fixture(), 1) != OK, true)
	h.check("损坏模板保留原字节", FileAccess.get_file_as_string(target), "competing edit")
	h.check("模板ID与路径仍校验", library.create_template("../escape", fixture()), ERR_INVALID_PARAMETER)
	h.check("无效元数据不写文件", library.create_template("bad_metadata", fixture(), "", {"tags": [1]}) != OK, true)
	_cleanup(library.directory)


static func test_inspector(h: TestHarness) -> void:
	var library = _library("inspector")
	h.check("面板模板创建", library.create_template("desk", fixture()), OK)
	var model = _model()
	library.instantiate("desk", model, Vector2(100, 100))
	library.instantiate("desk", model, Vector2(250, 100))
	model.reset_history()
	var before := Model.stringify(model.data)
	var newer := fixture()
	newer["label"] = "面板新默认"
	h.check("面板模板更新", library.update_template("desk", newer, 1), OK)
	var panel := Inspector.new()
	panel.configure(model, library, 0)
	panel.set_selection([0, 1])
	var signals := {"edited": 0, "rebuild": 0}
	panel.edited.connect(func():
		signals["edited"] += 1
		model.record_history())
	panel.rebuild_requested.connect(func(): signals["rebuild"] += 1)
	h.check("面板有明确确认按钮", (panel.get_node("ConfirmTemplateChanges") as Button).disabled, true)
	h.check("面板可预览选择批量", panel.prepare_update().get("updates", []).size(), 2)
	h.check("面板预览不发编辑信号", signals["edited"], 0)
	h.check("面板调用仍需明确确认", panel.confirm_preview(), ERR_UNAUTHORIZED)
	panel.prepare_update()
	h.check("面板确认成功", panel.confirm_preview(true), OK)
	h.check("批量只emit一次edited与rebuild", signals, {"edited": 1, "rebuild": 1})
	h.check("dock统一记录后可一次撤销", model.undo(), true)
	h.check("UI不自行拆分history", Model.stringify(model.data), before)
	h.check("UI没有额外历史记录", model.undo(), false)
	panel.free()
	_cleanup(library.directory)


static func test_template_authoring(h: TestHarness) -> void:
	var library = _library("template_authoring")
	h.check("模板编辑入口基础模板", library.create_template("parent", fixture(), "", {"category": "旧分类", "tags": ["旧标签"]}), OK)
	h.check("模板编辑入口实例源模板", library.create_template("desk", fixture()), OK)
	var model = _model()
	library.instantiate("desk", model, Vector2(100, 100))
	model.set_actor_field(0, "id", "map_specific_id")
	model.set_actor_field(0, "label", "当前实例属性")
	model.reset_history()
	model.dirty = false
	var before := Model.stringify(model.data)
	var panel := Inspector.new()
	panel.configure(model, library, 0)
	var signals := {"edited": 0, "rebuild": 0}
	panel.edited.connect(func(): signals["edited"] += 1)
	panel.rebuild_requested.connect(func(): signals["rebuild"] += 1)
	h.check("检查器可达模板更新按钮", panel.has_node("PreviewSourceTemplateUpdate"), true)
	h.check("源模板确认初始禁用", (panel.get_node("ConfirmSourceTemplateUpdate") as Button).disabled, true)
	var parent := panel.get_node("TemplateParent") as OptionButton
	for choice: int in parent.item_count:
		if parent.get_item_metadata(choice) == "parent":
			parent.select(choice)
	(panel.get_node("TemplateCategory") as LineEdit).text = "家具"
	(panel.get_node("TemplateTags") as LineEdit).text = "室内， 木制, 室内"
	var preview: Dictionary = panel.prepare_template_update()
	h.check("源模板编辑生成预览", preview.get("ok"), true)
	h.check("源模板预览列出父关系与分类标签差异", preview.get("changes", []).size() >= 4, true)
	h.check("源模板预览保持地图与dirty", [Model.stringify(model.data), model.dirty], [before, false])
	h.check("源模板预览尚未写入版本", library.resolve_template("desk").get("version"), 1)
	h.check("模板作者更新也必须明确确认", panel.confirm_source_template_update(), ERR_UNAUTHORIZED)
	h.check("确认通过检查器更新源模板", panel.confirm_source_template_update(true), OK)
	var resolved: Dictionary = library.resolve_template("desk")
	h.check("UI更新源模板的版本父关系", [resolved.get("version"), resolved.get("parent")], [2, "parent"])
	h.check("UI分类标签编辑去重并保存", resolved.get("metadata"), {"category": "家具", "tags": ["室内", "木制"]})
	h.check("UI使用当前物件属性作为模板默认", resolved.get("actor", {}).get("label"), "当前实例属性")
	h.check("模板ID不被地图实例ID替代", resolved.get("actor", {}).get("id"), "desk")
	h.check("更新模板不悄悄同步地图快照", model.actor_field(0, "source_template_version"), 1)
	h.check("模板资产更新不写地图数据或dirty", [Model.stringify(model.data), model.dirty], [before, false])
	h.check("模板资产只请求面板重建不发地图edited", signals, {"edited": 0, "rebuild": 1})
	h.check("模板资产不占地图撤销历史", model.undo(), false)
	var pending: Dictionary = panel.prepare_template_update()
	h.check("更新后仍可再次预览模板", pending.get("ok"), true)
	model.set_actor_field(0, "label", "预览后的新属性")
	h.check("物件属性变化阻止旧模板确认", panel.confirm_source_template_update(true), ERR_BUSY)
	h.check("被拒确认保持资产版本", library.resolve_template("desk").get("version"), 2)
	var newer := fixture()
	newer["future"]["count"] = 9
	h.check("父模板未来更新", library.update_template("parent", newer, 1), OK)
	h.check("UI建继承不会冻结未覆盖的父默认", library.resolve_template("desk").get("actor", {}).get("future", {}).get("count"), 9)
	panel.free()
	_cleanup(library.directory)


static func test_template_authoring_safety(h: TestHarness) -> void:
	var library = _library("authoring_safety")
	var source := fixture()
	source["collision"] = [[0, 0, 20, 20], [20, 0, 20, 20]]
	source["sort_collider"] = 0
	h.check("子模板依赖保护创建父模板", library.create_template("parent", source), OK)
	h.check("子模板依赖保护创建子模板", library.create_template("child", {"sort_collider": 1}, "parent"), OK)
	var newer := fixture()
	var before := FileAccess.get_file_as_string(library.directory.path_join("parent.json"))
	h.check("源模板预览拒绝破坏子模板排序引用", library.preview_template_update("parent", newer).get("ok"), false)
	h.check("直接版本API也保护子模板", library.update_template("parent", newer, 1) != OK, true)
	h.check("子模板验证失败不改资产字节", FileAccess.get_file_as_string(library.directory.path_join("parent.json")), before)
	source["label"] = "新的父默认"
	var preview: Dictionary = library.preview_template_update("parent", source)
	h.check("模板预览报告父与子影响", preview.get("affected_templates", []).size(), 2)
	h.check("模板预览拒绝不明确确认", library.confirm_template_update(preview), ERR_UNAUTHORIZED)
	var tampered := preview.duplicate(true)
	tampered["document"]["actor"]["id"] = "forged"
	h.check("模板确认拒绝篡改预览", library.confirm_template_update(tampered, true), ERR_BUSY)
	h.check("子模板更新使原预览过期", library.update_template("child", {"sort_collider": 1, "label": "子模板后改"}, 1), OK)
	h.check("子模板影响变化必须重做预览", library.confirm_template_update(preview, true), ERR_BUSY)
	preview = library.preview_template_update("parent", source)
	h.check("重新预览后明确确认模板", library.confirm_template_update(preview, true), OK)
	h.check("源模板更新确实增加版本", library.resolve_template("parent").get("version"), 2)
	h.check("源模板更新不会覆盖子模板默认", library.resolve_template("child").get("actor", {}).get("label"), "子模板后改")
	h.check("UI父选择不能形成循环", library.preview_template_update("parent", source, "child").get("error"), ERR_CYCLIC_LINK)
	_cleanup(library.directory)


static func _library(label: String):
	var library = Library.new()
	library.directory = "user://test_map_template_updates_%s_%d" % [label, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(library.directory))
	return library


static func _model():
	var model = Model.new()
	model.data = {"id": "template_updates_fixture", "size": [600, 400], "actors": []}
	model.reset_history()
	return model


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _cleanup(path: String) -> void:
	if not path.begins_with("user://test_map_template_updates_"):
		return
	var folder := DirAccess.open(path)
	if folder == null:
		return
	for filename: String in folder.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in folder.get_directories():
		_cleanup(path.path_join(child))
	DirAccess.remove_absolute(path)
