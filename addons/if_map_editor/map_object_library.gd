@tool
extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const SOURCE_FIELDS := ["source_template", "source_template_version",
	"source_template_defaults", "source_template_preserved_fields"]

var directory := "res://data/map_objects"


func list_templates(category := "", tags: Array = [], query := "") -> Array[String]:
	var result: Array[String] = []
	var folder := DirAccess.open(directory)
	if folder != null:
		for filename: String in folder.get_files():
			if filename.ends_with(".json"):
				var name := filename.trim_suffix(".json")
				var resolved := resolve_template(name)
				if resolved["ok"] and _matches_template(name, resolved, category, tags, query):
					result.append(name)
	result.sort()
	return result


func save_template(name: String, source: Dictionary) -> Error:
	if not _valid_name(name):
		return ERR_INVALID_PARAMETER
	if not _valid_actor(source):
		return ERR_INVALID_DATA
	var item := source.duplicate(true)
	var rect: Array = item["rect"]
	var origin := Vector2(float(rect[0]), float(rect[1]))
	item["rect"] = [0, 0, rect[2], rect[3]]
	for field: String in SOURCE_FIELDS:
		item.erase(field)
	if item.has("reach"):
		if not item.has("reach_local"):
			var reach: Array = item["reach"]
			item["reach_local"] = [float(reach[0]) - origin.x, float(reach[1]) - origin.y,
				reach[2], reach[3]]
		item.erase("reach")
	if item.has("cover_y"):
		var actor := MapDef._actor_from(source)
		item["sort_offset"] = actor.effective_cover_y() - actor.auto_cover_y()
		item.erase("cover_y")
	if not _valid_actor(item):
		return ERR_INVALID_DATA
	var target := ProjectSettings.globalize_path(directory.path_join(name + ".json"))
	if _path_exists(target):
		return ERR_ALREADY_EXISTS
	var ancestor := target.get_base_dir()
	while not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor):
			return ERR_CANT_CREATE
		var parent := ancestor.get_base_dir()
		if parent == ancestor:
			break
		ancestor = parent
	var error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if error != OK:
		return error
	var pending := target + ".pending"
	error = DirAccess.make_dir_absolute(pending)
	if error != OK:
		return error
	var temporary := pending.path_join("template.json")
	error = _write_template_file(temporary, JSON.stringify({"version": 1, "name": name,
		"actor": item}, "  "))
	if error == OK:
		if _path_exists(target):
			error = ERR_ALREADY_EXISTS
		else:
			error = DirAccess.rename_absolute(temporary, target)
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	DirAccess.remove_absolute(pending)
	return error


func instantiate(name: String, model, at: Vector2) -> Array[int]:
	if not model is Model or not at.is_finite():
		return []
	var resolved := resolve_template(name)
	if not resolved["ok"]:
		return []
	var item: Dictionary = resolved["actor"].duplicate(true)
	for field: String in ["rect", "reach"]:
		if item.has(field):
			var rect := MapDef._to_rect(item[field])
			rect.position += at
			for value: float in [rect.position.x, rect.position.y, rect.size.x, rect.size.y]:
				if not _valid_integer(round(value)):
					return []
	var placed := item.duplicate(true)
	model._shift_actor(placed, at)
	if not _valid_actor(placed):
		return []
	item["source_template"] = name
	item["source_template_version"] = resolved["version"]
	item["source_template_defaults"] = _relative_actor(item)
	var items: Array[Dictionary] = [item]
	return model.insert_actors(items, at)


func _load_actor(name: String) -> Dictionary:
	var resolved := resolve_template(name)
	return resolved["actor"].duplicate(true) if resolved["ok"] else {}


func resolve_template(name: String) -> Dictionary:
	return _resolve_template(name, [], {})


func resolve(name: String) -> Dictionary:
	return resolve_template(name)


func create_template(name: String, source: Dictionary, parent := "", metadata: Dictionary = {}) -> Error:
	if not _valid_name(name):
		return ERR_INVALID_PARAMETER
	var document := {"version": 2, "template_version": 1, "name": name,
		"extends": parent, "metadata": metadata.duplicate(true), "actor": source.duplicate(true)}
	return _save_v2(name, document)


func update_template(name: String, source: Dictionary, expected_version: int,
		parent: Variant = null, metadata: Variant = null) -> Error:
	var previous := _read_document(name)
	if not previous["ok"]:
		return previous["error"]
	var resolved := resolve_template(name)
	if not resolved["ok"]:
		return resolved["error"]
	if resolved["version"] != expected_version:
		return ERR_BUSY
	var document: Dictionary = previous["document"].duplicate(true)
	document["version"] = 2
	document["template_version"] = expected_version + 1
	document["actor"] = source.duplicate(true)
	if parent != null:
		document["extends"] = parent
	if metadata != null:
		document["metadata"] = _copy_value(metadata)
	return _save_v2(name, document, previous["text"])


func preview_template_update(name: String, source: Dictionary, parent := "",
		metadata: Dictionary = {}) -> Dictionary:
	var previous := _read_document(name)
	var resolved := resolve_template(name)
	if not previous["ok"]:
		return previous
	if not resolved["ok"]:
		return resolved
	if not _valid_actor(source):
		return _failure(ERR_INVALID_DATA, "当前物件属性无效，不能写为模板默认。")
	var actor := _normalize_template_actor(source)
	actor["id"] = resolved["actor"]["id"]
	if not parent.is_empty():
		var inherited := resolve_template(parent)
		if not inherited["ok"]:
			return inherited
		actor = _defaults_delta(_normalize_template_actor(inherited["actor"]), actor)
	var document: Dictionary = previous["document"].duplicate(true)
	document["version"] = 2
	document["template_version"] = int(resolved["version"]) + 1
	document["extends"] = parent
	document["metadata"] = metadata.duplicate(true)
	document["actor"] = actor
	var replacements := {name: document}
	var candidate := _resolve_template(name, [], replacements)
	if not candidate["ok"]:
		return candidate
	var impacts := _template_impacts(name, replacements)
	if not impacts["ok"]:
		return impacts
	return {"ok": true, "error": OK, "name": name, "source": source.duplicate(true),
		"parent": parent, "metadata": metadata.duplicate(true), "document": document,
		"before_text": previous["text"], "before_signature": resolved["signature"],
		"expected_version": resolved["version"], "target_version": candidate["version"],
		"changes": _template_changes(previous["document"], resolved, document, candidate),
		"affected_templates": impacts["templates"]}


func confirm_template_update(preview: Dictionary, confirmed := false) -> Error:
	if not confirmed:
		return ERR_UNAUTHORIZED
	if not preview.get("ok", false) or not preview.get("name") is String \
			or not preview.get("source") is Dictionary or not preview.get("parent") is String \
			or not preview.get("metadata") is Dictionary:
		return ERR_INVALID_PARAMETER
	var fresh := preview_template_update(preview["name"], preview["source"], preview["parent"], preview["metadata"])
	if not fresh["ok"] or not _same_value(fresh, preview):
		return ERR_BUSY
	return _save_v2(fresh["name"], fresh["document"], fresh["before_text"])


func inspect_instance(source: Variant, actor_index := -1) -> Dictionary:
	var item := _instance_dict(source, actor_index)
	if item.is_empty():
		return _failure(ERR_INVALID_PARAMETER, "未选择有效物件。")
	var name := str(item.get("source_template", ""))
	var resolved := resolve_template(name)
	var result := {"ok": resolved["ok"], "error": resolved["error"],
		"message": resolved.get("message", ""), "name": name, "fields": {},
		"overrides": [], "snapshot_valid": false, "update_available": false,
		"instance_version": item.get("source_template_version", 0),
		"template_version": resolved.get("version", 0),
		"template_format_version": resolved.get("format_version", 0),
		"metadata": resolved.get("metadata", {}), "chain": resolved.get("chain", []),
		"parent": resolved.get("parent", "")}
	var current := _relative_actor(item)
	var valid := _has_snapshot(item)
	result["snapshot_valid"] = valid
	var baseline: Dictionary = item.get("source_template_defaults", {}) if valid else {}
	var latest: Dictionary = _relative_actor(resolved["actor"]) if resolved["ok"] else {}
	var preserved: Array = item.get("source_template_preserved_fields", []) if valid else []
	for field: String in _field_names(current, baseline, latest):
		var state := "unknown"
		if valid:
			state = "preserved" if field in preserved else (
				"default" if _same_field(current, baseline, field) else "overridden")
			if state != "default":
				result["overrides"].append(field)
		result["fields"][field] = {"state": state, "present": current.has(field),
			"value": _copy_value(current.get(field)), "default_present": latest.has(field),
			"default": _copy_value(latest.get(field))}
	if not valid:
		result["message"] += " 缺少可信默认快照，覆盖状态未知。先预览并确认建立安全基线；现有字段均保留为覆盖，再按需恢复默认。"
	elif resolved["ok"]:
		result["update_available"] = item["source_template_version"] != resolved["version"] \
			or not _equal_defaults(baseline, latest)
	return result


func preview_instance_update(source: Variant, actor_index := -1) -> Dictionary:
	return _preview_instance(source, actor_index, "update", [])


func preview_restore_defaults(source: Variant, fields: Array = [], actor_index := -1) -> Dictionary:
	return _preview_instance(source, actor_index, "restore", fields)


func preview_adopt_instance(source: Variant, actor_index := -1) -> Dictionary:
	return _preview_instance(source, actor_index, "adopt", [])


func preview_updates(model, indices: Array) -> Dictionary:
	if not model is Model or indices.is_empty():
		return _failure(ERR_INVALID_PARAMETER, "请选择需要更新的实例。")
	var updates: Array[Dictionary] = []
	var seen: Array[int] = []
	for requested: Variant in indices:
		if not _valid_integer(requested) or requested < 0:
			return _failure(ERR_INVALID_PARAMETER, "实例索引无效。")
		var actor_index := int(requested)
		if actor_index in seen:
			continue
		seen.append(actor_index)
		var preview := preview_instance_update(model, actor_index)
		if not preview["ok"]:
			return preview
		updates.append(preview)
	return {"ok": true, "error": OK, "updates": updates}


func confirm_instance_update(model, actor_index: int, preview: Dictionary,
		confirmed := false, record_history := true) -> Error:
	var entry := preview.duplicate(true)
	entry["index"] = actor_index
	return confirm_updates(model, {"ok": true, "updates": [entry]}, confirmed, record_history)


func confirm_updates(model, batch: Dictionary, confirmed := false, record_history := true) -> Error:
	if not confirmed:
		return ERR_UNAUTHORIZED
	if not model is Model or not batch.get("ok", false) or not batch.get("updates") is Array \
			or batch["updates"].is_empty():
		return ERR_INVALID_PARAMETER
	var checked: Array[Dictionary] = []
	var indices: Array[int] = []
	for entry: Variant in batch["updates"]:
		if not entry is Dictionary or not _valid_integer(entry.get("index")):
			return ERR_INVALID_PARAMETER
		var actor_index := int(entry["index"])
		if actor_index in indices:
			return ERR_INVALID_PARAMETER
		indices.append(actor_index)
		if not entry.get("ok", false) or not entry.get("before") is Dictionary \
				or not _same_value(model.actor_dict(actor_index), entry["before"]):
			return ERR_BUSY
		var fields: Array[String] = []
		if not entry.get("restore_fields", []) is Array:
			return ERR_INVALID_PARAMETER
		for field: Variant in entry.get("restore_fields", []):
			if not field is String:
				return ERR_INVALID_PARAMETER
			fields.append(field)
		var fresh := _preview_instance(model, actor_index, str(entry.get("mode", "")), fields)
		if not fresh["ok"] or fresh.get("signature") != entry.get("signature") \
				or not _same_value(fresh.get("after", {}), entry.get("after", {})):
			return ERR_BUSY
		checked.append(fresh)
	if record_history:
		model.record_history()
	for entry: Dictionary in checked:
		var actor_index := int(entry["index"])
		var before: Dictionary = entry["before"]
		var after: Dictionary = entry["after"]
		for field: String in before:
			if not after.has(field):
				model.erase_actor_field(actor_index, field)
		for field: String in after:
			if not _same_field(before, after, field):
				model.set_actor_field(actor_index, field, _copy_value(after[field]))
	if record_history:
		model.record_history()
	return OK


func _preview_instance(source: Variant, actor_index: int, mode: String, fields: Array) -> Dictionary:
	var item := _instance_dict(source, actor_index)
	if item.is_empty() or not _valid_actor(item) or mode not in ["update", "restore", "adopt"]:
		return _failure(ERR_INVALID_PARAMETER, "物件或操作无效。")
	var name := str(item.get("source_template", ""))
	var resolved := resolve_template(name)
	if not resolved["ok"]:
		return resolved
	var valid := _has_snapshot(item)
	if not valid and mode != "adopt":
		return _failure(ERR_UNCONFIGURED, "旧实例缺少可信默认快照；请先预览并确认建立安全基线，再按需恢复默认字段。")
	var baseline: Dictionary = item["source_template_defaults"] if valid else {}
	var latest := _relative_actor(resolved["actor"])
	var current := _relative_actor(item)
	var preserved: Array = item.get("source_template_preserved_fields", []).duplicate() if valid else []
	var merged := current.duplicate(true)
	var restore_fields: Array[String] = []
	for field: Variant in fields:
		if not field is String:
			return _failure(ERR_INVALID_PARAMETER, "恢复字段名必须为文本。")
		restore_fields.append(field)
	if mode == "adopt":
		if valid:
			return _failure(ERR_ALREADY_IN_USE, "此实例已有默认快照，请使用预览更新。")
		preserved = _field_names(current, latest)
	elif mode == "update":
		merged = _merge_instance(baseline, current, latest)
		for field: String in preserved:
			_assign_field(merged, current, field)
		for field: String in _field_names(baseline, current):
			if not _same_field(baseline, current, field) and _same_field(merged, latest, field) \
					and field not in preserved:
				preserved.append(field)
	else:
		if restore_fields.is_empty():
			restore_fields = _field_names(baseline, latest)
		for field: String in restore_fields:
			if field == "id" or field in SOURCE_FIELDS:
				return _failure(ERR_INVALID_PARAMETER, "实例 ID 与来源元数据不能恢复为模板字段。")
			_assign_field(merged, latest, field)
			preserved.erase(field)
	var after := _world_actor(merged, item)
	for field: String in SOURCE_FIELDS:
		after.erase(field)
	after["source_template"] = name
	after["source_template_version"] = resolved["version"] if mode != "restore" else item["source_template_version"]
	after["source_template_defaults"] = latest.duplicate(true) if mode != "restore" else baseline.duplicate(true)
	if mode == "restore":
		for field: String in restore_fields:
			_assign_field(after["source_template_defaults"], latest, field)
		if _equal_defaults(after["source_template_defaults"], latest):
			after["source_template_version"] = resolved["version"]
	if not preserved.is_empty():
		after["source_template_preserved_fields"] = preserved
	if not _valid_actor(after) or not _valid_actor(after["source_template_defaults"]):
		return _failure(ERR_INVALID_DATA, "保留覆盖后的组合无效；请检查碰撞、排序引用和交互字段。")
	var changes: Array[String] = []
	for field: String in _field_names(current, _relative_actor(after)):
		if not _same_field(current, _relative_actor(after), field):
			changes.append(field)
	return {"ok": true, "error": OK, "mode": mode, "index": actor_index,
		"before": item.duplicate(true), "after": after, "changes": changes,
		"restore_fields": fields.duplicate(), "signature": resolved["signature"],
		"name": name, "target_version": resolved["version"], "preserved_fields": preserved.duplicate(),
		"message": "仅建立来源快照；全部现有字段保留为覆盖。" if mode == "adopt" else "确认后应用，保留实例 ID 和位置。"}


func _read_document(name: String) -> Dictionary:
	if not _valid_name(name):
		return _failure(ERR_INVALID_PARAMETER, "模板名称无效。")
	var file := FileAccess.open(directory.path_join(name + ".json"), FileAccess.READ)
	if file == null:
		return _failure(FileAccess.get_open_error(), "模板不存在或无法读取：" + name)
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error != OK and error != ERR_FILE_EOF:
		return _failure(error, "模板读取失败：" + name)
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return _failure(ERR_PARSE_ERROR, "模板 JSON 损坏：" + name)
	return {"ok": true, "error": OK, "document": parser.data, "text": text}


func _resolve_template(name: String, visiting: Array, replacements: Dictionary) -> Dictionary:
	if not _valid_name(name):
		return _failure(ERR_INVALID_PARAMETER, "模板名称无效：" + name)
	if name in visiting or visiting.size() >= 64:
		return _failure(ERR_CYCLIC_LINK, "模板循环继承或继承过深：" + str(visiting + [name]))
	var loaded := {"ok": true, "document": replacements.get(name), "text": ""}
	if not replacements.has(name):
		loaded = _read_document(name)
	if not loaded["ok"]:
		return loaded
	var document: Dictionary = loaded["document"]
	if not _valid_json(document) or not _valid_number(document.get("version")) \
			or (document["version"] != 1 and document["version"] != 2) or not document.get("actor") is Dictionary:
		return _failure(ERR_INVALID_DATA, "模板格式无效：" + name)
	if document.has("name") and (not document["name"] is String or not _valid_name(document["name"])):
		return _failure(ERR_INVALID_DATA, "模板展示名无效：" + name)
	var actor: Dictionary = document["actor"].duplicate(true)
	var revision := 1
	var metadata: Dictionary = {}
	var chain: Array = []
	var signature := str(loaded["text"])
	if document["version"] == 2:
		if not _valid_integer(document.get("template_version")) or document["template_version"] < 1 \
				or not document.get("extends", "") is String or not _valid_metadata(document.get("metadata", {})):
			return _failure(ERR_INVALID_DATA, "v2 模板版本、父模板或分类标签无效：" + name)
		revision = int(document["template_version"])
		var parent: String = document.get("extends", "")
		if not parent.is_empty():
			var inherited := _resolve_template(parent, visiting + [name], replacements)
			if not inherited["ok"]:
				inherited["message"] = name + " → " + str(inherited.get("message", ""))
				return inherited
			actor = _merge_defaults(_normalize_template_actor(inherited["actor"]), actor)
			metadata = inherited["metadata"].duplicate(true)
			chain = inherited["chain"].duplicate(true)
			signature += str(inherited["signature"])
		metadata.merge(document.get("metadata", {}), true)
	if not _valid_actor(actor):
		return _failure(ERR_INVALID_DATA, "模板合并后的物件无效：" + name)
	if document["version"] == 2:
		actor = _normalize_template_actor(actor)
		if not _valid_actor(actor):
			return _failure(ERR_INVALID_DATA, "模板局部坐标规范化失败：" + name)
	for field: String in SOURCE_FIELDS:
		actor.erase(field)
	chain.append({"name": name, "version": revision})
	return {"ok": true, "error": OK, "actor": actor, "version": revision,
		"format_version": int(document["version"]), "metadata": metadata, "chain": chain,
		"parent": document.get("extends", "") if document["version"] == 2 else "",
		"signature": signature.sha256_text()}


func _save_v2(name: String, document: Dictionary, previous: Variant = null) -> Error:
	var replacements := {name: document}
	var resolved := _resolve_template(name, [], replacements)
	if not resolved["ok"]:
		return resolved["error"]
	var original: Dictionary = document["actor"]
	var normalized := _relative_actor(resolved["actor"])
	if original.has("reach"):
		var converted := _normalize_template_actor(resolved["actor"])
		normalized = converted
		original.erase("reach")
		original["reach_local"] = normalized["reach_local"]
	if original.has("cover_y"):
		normalized = _normalize_template_actor(resolved["actor"])
		original.erase("cover_y")
		original["sort_offset"] = normalized["sort_offset"]
	for field: String in SOURCE_FIELDS:
		original.erase(field)
	if original.has("rect"):
		original["rect"] = normalized["rect"]
	resolved = _resolve_template(name, [], replacements)
	if not resolved["ok"]:
		return resolved["error"]
	var impacts := _template_impacts(name, replacements)
	if not impacts["ok"]:
		return impacts["error"]
	return _publish_document(name, JSON.stringify(document, "  "), previous)


func _template_impacts(name: String, replacements: Dictionary) -> Dictionary:
	var templates: Array[Dictionary] = []
	for existing: String in list_templates():
		var before := resolve_template(existing)
		var depends := existing == name
		for ancestor: Dictionary in before["chain"]:
			if ancestor["name"] == name:
				depends = true
		if not depends:
			continue
		var after := _resolve_template(existing, [], replacements)
		if not after["ok"]:
			return _failure(after["error"], "更新将使子模板失效：" + existing + "；" + str(after.get("message", "")))
		templates.append({"name": existing, "before_signature": before["signature"],
			"changes": _template_changes({}, before, {}, after)})
	return {"ok": true, "error": OK, "templates": templates}


func _template_changes(before_document: Dictionary, before: Dictionary,
		after_document: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for field: String in _field_names(before["actor"], after["actor"]):
		_append_template_change(changes, "默认." + field, before["actor"], after["actor"], field)
	for field: String in _all_keys(before["metadata"], after["metadata"], {}):
		_append_template_change(changes, "元数据." + field, before["metadata"], after["metadata"], field)
	if not before_document.is_empty():
		_append_template_change(changes, "父模板", {"extends": before_document.get("extends", "")},
			{"extends": after_document.get("extends", "")}, "extends")
	return changes


func _append_template_change(changes: Array[Dictionary], path: String,
		before: Dictionary, after: Dictionary, field: String) -> void:
	if not _same_field(before, after, field):
		changes.append({"path": path, "before_present": before.has(field), "before": _copy_value(before.get(field)),
			"after_present": after.has(field), "after": _copy_value(after.get(field))})


func _defaults_delta(parent: Dictionary, desired: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	for field: String in desired:
		if _same_field(parent, desired, field):
			continue
		if parent.get(field) is Dictionary and desired[field] is Dictionary:
			delta[field] = _defaults_delta(parent[field], desired[field])
		else:
			delta[field] = _copy_value(desired[field])
	return delta


func _publish_document(name: String, text: String, previous: Variant) -> Error:
	var target := ProjectSettings.globalize_path(directory.path_join(name + ".json"))
	if previous == null and _path_exists(target):
		return ERR_ALREADY_EXISTS
	var ancestor := target.get_base_dir()
	while not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor):
			return ERR_CANT_CREATE
		var parent := ancestor.get_base_dir()
		if parent == ancestor:
			return ERR_CANT_CREATE
		ancestor = parent
	var error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if error != OK:
		return error
	var pending := target + ".pending"
	error = DirAccess.make_dir_absolute(pending)
	if error != OK:
		return error
	var temporary := pending.path_join("template.json")
	var backup := pending.path_join("original.json")
	error = _write_template_file(temporary, text)
	if error == OK:
		if previous == null:
			error = ERR_ALREADY_EXISTS if _path_exists(target) else DirAccess.rename_absolute(temporary, target)
		elif not FileAccess.file_exists(target) or FileAccess.get_file_as_string(target) != previous:
			error = ERR_BUSY
		else:
			error = DirAccess.rename_absolute(target, backup)
			if error == OK:
				error = ERR_BUSY if _path_exists(target) else DirAccess.rename_absolute(temporary, target)
				if error != OK and not _path_exists(target):
					DirAccess.rename_absolute(backup, target)
				elif error == OK:
					DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	if not FileAccess.file_exists(backup):
		DirAccess.remove_absolute(pending)
	return error


func _normalize_template_actor(source: Dictionary) -> Dictionary:
	var item := _relative_actor(source)
	if item.has("reach"):
		if not item.has("reach_local"):
			item["reach_local"] = item["reach"]
		item.erase("reach")
	if item.has("cover_y"):
		var actor := MapDef._actor_from(source)
		item["sort_offset"] = actor.effective_cover_y() - actor.auto_cover_y()
		item.erase("cover_y")
	return item


func _relative_actor(source: Dictionary) -> Dictionary:
	var item := source.duplicate(true)
	for field: String in SOURCE_FIELDS:
		item.erase(field)
	var rect: Variant = item.get("rect")
	if not _valid_rect(rect):
		return item
	item["rect"] = [0, 0, rect[2], rect[3]]
	if item.has("reach") and _valid_rect(item["reach"]):
		var reach: Array = item["reach"]
		item["reach"] = [reach[0] - rect[0], reach[1] - rect[1], reach[2], reach[3]]
	if _valid_number(item.get("cover_y")):
		item["cover_y"] = float(item["cover_y"]) - float(rect[1])
	return item


func _world_actor(defaults: Dictionary, source: Dictionary) -> Dictionary:
	var item := defaults.duplicate(true)
	var rect: Array = source["rect"]
	if not _valid_rect(item.get("rect")):
		return {}
	item["id"] = source["id"]
	item["rect"] = [rect[0], rect[1], item["rect"][2], item["rect"][3]]
	if item.has("reach") and _valid_rect(item["reach"]):
		var reach: Array = item["reach"]
		item["reach"] = [reach[0] + rect[0], reach[1] + rect[1], reach[2], reach[3]]
	if _valid_number(item.get("cover_y")):
		item["cover_y"] = float(item["cover_y"]) + float(rect[1])
	return item


func _merge_defaults(parent: Dictionary, child: Dictionary) -> Dictionary:
	var merged := parent.duplicate(true)
	for field: String in child:
		if merged.get(field) is Dictionary and child[field] is Dictionary:
			merged[field] = _merge_defaults(merged[field], child[field])
		else:
			merged[field] = _copy_value(child[field])
	return merged


func _merge_instance(baseline: Dictionary, current: Dictionary, latest: Dictionary) -> Dictionary:
	var merged := current.duplicate(true)
	for field: String in _all_keys(baseline, current, latest):
		if _same_field(baseline, current, field):
			_assign_field(merged, latest, field)
		elif baseline.get(field) is Dictionary and current.get(field) is Dictionary \
				and latest.get(field) is Dictionary:
			merged[field] = _merge_instance(baseline[field], current[field], latest[field])
	return merged


func _field_names(first: Dictionary, second: Dictionary, third: Dictionary = {}) -> Array[String]:
	var fields := _all_keys(first, second, third)
	fields.erase("id")
	for field: String in SOURCE_FIELDS:
		fields.erase(field)
	return fields


func _all_keys(first: Dictionary, second: Dictionary, third: Dictionary) -> Array[String]:
	var fields: Array[String] = []
	for source: Dictionary in [first, second, third]:
		for field: String in source:
			if field not in fields:
				fields.append(field)
	fields.sort()
	return fields


func _same_field(first: Dictionary, second: Dictionary, field: String) -> bool:
	return first.has(field) == second.has(field) and _same_value(first.get(field), second.get(field))


func _same_value(first: Variant, second: Variant, depth := 0) -> bool:
	if depth > 64:
		return false
	if _valid_number(first) and _valid_number(second):
		return first == second
	if first is Dictionary and second is Dictionary:
		if first.size() != second.size():
			return false
		for field: Variant in first:
			if not second.has(field) or not _same_value(first[field], second[field], depth + 1):
				return false
		return true
	if first is Array and second is Array:
		if first.size() != second.size():
			return false
		for offset: int in first.size():
			if not _same_value(first[offset], second[offset], depth + 1):
				return false
		return true
	return typeof(first) == typeof(second) and first == second


func _equal_defaults(first: Dictionary, second: Dictionary) -> bool:
	for field: String in _field_names(first, second):
		if not _same_field(first, second, field):
			return false
	return true


func _assign_field(target: Dictionary, source: Dictionary, field: String) -> void:
	if source.has(field):
		target[field] = _copy_value(source[field])
	else:
		target.erase(field)


func _copy_value(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


func _instance_dict(source: Variant, actor_index: int) -> Dictionary:
	if source is Dictionary:
		return source
	return source.actor_dict(actor_index) if source is Model else {}


func _has_snapshot(item: Dictionary) -> bool:
	if not _valid_integer(item.get("source_template_version")) or item["source_template_version"] < 1 \
			or not item.get("source_template_defaults") is Dictionary \
			or not _valid_actor(item["source_template_defaults"]) \
			or not item.get("source_template_preserved_fields", []) is Array:
		return false
	for field: Variant in item.get("source_template_preserved_fields", []):
		if not field is String or field == "id" or field in SOURCE_FIELDS:
			return false
	return true


func _valid_metadata(metadata: Variant) -> bool:
	if not metadata is Dictionary or not _valid_json(metadata) \
			or not metadata.get("category", "") is String or not metadata.get("tags", []) is Array:
		return false
	for tag: Variant in metadata.get("tags", []):
		if not tag is String:
			return false
	return true


func _matches_template(name: String, resolved: Dictionary, category: String, tags: Array, query: String) -> bool:
	var metadata: Dictionary = resolved["metadata"]
	if not category.is_empty() and metadata.get("category", "") != category:
		return false
	for tag: Variant in tags:
		if tag not in metadata.get("tags", []):
			return false
	var searchable := name + " " + str(metadata) + " " + str(resolved["actor"].get("label", ""))
	return query.strip_edges().is_empty() or searchable.to_lower().contains(query.strip_edges().to_lower())


func _failure(error: Error, message: String) -> Dictionary:
	return {"ok": false, "error": error, "message": message}


func _valid_actor(actor: Dictionary) -> bool:
	if not _valid_json(actor) or not _valid_rect(actor.get("rect")):
		return false
	if not actor.get("id") is String and not actor.get("id") is StringName:
		return false
	for field: String in ["label", "sprite", "line", "event", "source_template"]:
		if actor.has(field) and not actor[field] is String and not actor[field] is StringName:
			return false
	for field: String in ["solid", "cover", "over", "person", "decor", "auto_menu"]:
		if actor.has(field) and not actor[field] is bool:
			return false
	for field: String in ["reach", "reach_local"]:
		if actor.has(field) and not _valid_rect(actor[field]):
			return false
	if actor.has("collision"):
		if not actor["collision"] is Array:
			return false
		for shape: Variant in actor["collision"]:
			if not _valid_rect(shape):
				return false
	if actor.has("sort_collider") and not _valid_integer(actor["sort_collider"]):
		return false
	for field: String in ["sort_offset", "cover_y"]:
		if actor.has(field) and not _valid_number(actor[field]):
			return false
	if actor.has("talk") and not _valid_talk(actor["talk"]):
		return false
	if actor.has("actions"):
		if not actor["actions"] is Array:
			return false
		for action: Variant in actor["actions"]:
			if not action is Dictionary or (action.has("talk") and not _valid_talk(action["talk"])):
				return false
	var definition := MapDef.new()
	definition.id = &"map_template"
	var parsed := MapDef._actor_from(actor)
	definition.actors.append(parsed)
	if not definition.validate().is_empty() or not _finite_rect(parsed.reach) \
			or not is_finite(parsed.auto_cover_y()) or not is_finite(parsed.effective_cover_y()):
		return false
	for shape: Rect2 in parsed.collision_rects():
		if not _finite_rect(shape):
			return false
	return true


func _valid_talk(talk: Variant) -> bool:
	if not talk is Array:
		return false
	for line: Variant in talk:
		if not line is Dictionary:
			return false
		if line.has("size_delta") and not _valid_integer(line["size_delta"]):
			return false
		if line.has("shake") and not _valid_number(line["shake"]):
			return false
	return true


func _valid_rect(rect: Variant) -> bool:
	if not rect is Array or rect.size() != 4:
		return false
	for value: Variant in rect:
		if not _valid_number(value):
			return false
	var parsed := MapDef._to_rect(rect)
	return parsed.size.x > 0.0 and parsed.size.y > 0.0 and _finite_rect(parsed)


func _finite_rect(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.end.is_finite()


func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _valid_integer(value: Variant) -> bool:
	return _valid_number(value) and float(value) == floor(float(value)) \
		and float(value) >= -9223372036854775808.0 and float(value) < 9223372036854775808.0


func _valid_json(value: Variant, depth := 0) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is String or value is StringName:
		return true
	if value is int or value is float:
		return _valid_number(value)
	if value is Array:
		for item: Variant in value:
			if not _valid_json(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if (not key is String and not key is StringName) or not _valid_json(value[key], depth + 1):
				return false
		return true
	return false


func _valid_name(name: String) -> bool:
	if name.is_empty() or name != name.strip_edges() or name != name.validate_filename() \
			or name.contains("..") or name.ends_with("."):
		return false
	for index: int in name.length():
		if name.unicode_at(index) < 32:
			return false
	var stem := name.get_slice(".", 0).to_upper()
	return stem not in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4",
		"COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4",
		"LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]


func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


func _write_template_file(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error
