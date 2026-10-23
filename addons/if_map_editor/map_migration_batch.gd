## 显式墙归属计划的原子迁移，以及跨地图只读 manifest 审阅。
## 每个目标复用 MapGeometryTransfer.preview，在全部预检通过后组合独立副本。
## apply 只改当前模型并记录整步撤销；落盘必须经确认、重新校验与现有备份接口。
@tool
extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Transfer := preload("res://addons/if_map_editor/map_geometry_transfer.gd")
const Validation := preload("res://addons/if_map_editor/map_validation.gd")


## plan = [{actor_id: String, wall_indices: Array[int], preserve_baseline: bool}]。
## 返回 {ok, source, data, plan, diff, issues, errors, warnings}；墙索引始终指向 source。
static func preview(data: Variant, plan: Variant) -> Dictionary:
	var issues := Validation.geometry_issues(data)
	var result := {"ok": false, "source": {}, "data": {}, "plan": [], "diff": {}}
	if not issues.is_empty():
		result.merge(Validation.summarize(issues), true)
		return result
	var map_id: String = data["id"]
	for message: String in Transfer._validate_data(data):
		issues.append(Validation.issue("error", message, "map", -1, "", map_id))
	var entries := _preflight(data, plan, issues)
	if not Validation.summarize(issues)["ok"]:
		result.merge(Validation.summarize(issues), true)
		return result
	var candidate: Dictionary = data.duplicate(true)
	var removed: Array[int] = []
	var changes: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var actor_index: int = entry["actor_index"]
		var indices: Array[int] = []
		indices.assign(entry["wall_indices"])
		var single := Transfer.preview(data, actor_index, indices, entry["preserve_baseline"])
		for severity: String in ["errors", "warnings"]:
			for message: String in single[severity]:
				issues.append(Validation.issue("error" if severity == "errors" else "warning",
					message, "actor", actor_index, "collision", map_id))
		if not single["ok"]:
			continue
		candidate["actors"][actor_index] = single["data"]["actors"][actor_index].duplicate(true)
		removed.append_array(indices)
		changes.append({"actor_id": entry["actor_id"], "actor_index": actor_index,
			"wall_indices": indices.duplicate(), "preserve_baseline": entry["preserve_baseline"],
			"before": _actor_snapshot(data["actors"][actor_index]),
			"after": _actor_snapshot(candidate["actors"][actor_index])})
	if not Validation.summarize(issues)["ok"]:
		result.merge(Validation.summarize(issues), true)
		return result
	removed.sort()
	for offset: int in range(removed.size() - 1, -1, -1):
		candidate["walls"].remove_at(removed[offset])
	for message: String in Transfer._validate_data(candidate):
		issues.append(Validation.issue("error", message, "map", -1, "", map_id))
	result.merge(Validation.summarize(issues), true)
	if result["ok"]:
		result["source"] = data.duplicate(true)
		result["data"] = candidate
		result["plan"] = plan.duplicate(true)
		result["diff"] = {"before": {"walls": data.get("walls", []).duplicate(true)},
			"after": {"walls": candidate.get("walls", []).duplicate(true)}, "changes": changes}
	return result


static func _preflight(data: Dictionary, plan: Variant, issues: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var map_id: String = data["id"]
	if not plan is Array or plan.is_empty() or not Transfer._json_value(plan):
		issues.append(Validation.issue("error", "请明确提供非空迁移计划，不会自动猜测墙归属。", "map", -1, "plan", map_id))
		return result
	var owners: Dictionary = {}
	var targets: Dictionary = {}
	var actors: Dictionary = {}
	for index: int in data.get("actors", []).size():
		actors[str(data["actors"][index].get("id", ""))] = index
	for index: int in plan.size():
		var entry: Variant = plan[index]
		if not entry is Dictionary or not entry.get("actor_id") is String \
				or not entry.get("wall_indices") is Array or not entry.get("preserve_baseline") is bool:
			issues.append(Validation.issue("error", "计划必须包含 actor_id、wall_indices 和 preserve_baseline。", "map", index, "plan", map_id))
			continue
		var actor_id: String = entry["actor_id"]
		if not actors.has(actor_id) or targets.has(actor_id):
			issues.append(Validation.issue("error", "迁移目标缺失或重复重叠：%s" % actor_id, "map", index, "plan.actor_id", map_id))
			continue
		targets[actor_id] = true
		var indices: Array[int] = []
		if entry["wall_indices"].is_empty():
			issues.append(Validation.issue("error", "目标没有明确勾选墙，不会自动分配。", "actor", actors[actor_id], "wall_indices", map_id))
		for raw: Variant in entry["wall_indices"]:
			if not Transfer._number(raw) or float(raw) != floor(float(raw)) \
					or raw < 0 or raw >= data.get("walls", []).size():
				issues.append(Validation.issue("error", "墙索引无效或已过期。", "actor", actors[actor_id], "wall_indices", map_id))
				continue
			var wall_index := int(raw)
			if owners.has(wall_index):
				issues.append(Validation.issue("error", "墙 #%d 存在重复归属。" % wall_index, "wall", wall_index, "ownership", map_id))
			owners[wall_index] = actor_id
			indices.append(wall_index)
		result.append({"actor_id": actor_id, "actor_index": actors[actor_id],
			"wall_indices": indices, "preserve_baseline": entry["preserve_baseline"]})
	return result


## 成功时整批一笔撤销；拒绝过期、篡改或不属于当前地图的预览，失败不动任何模型状态。
static func apply(model: Variant, review: Dictionary, confirmed := false) -> bool:
	if not confirmed or not model is Model or review.get("ok") != true or not review.get("source") is Dictionary \
			or not review.get("data") is Dictionary or review["source"] != model.data \
			or model.map_id != str(model.data.get("id", "")):
		return false
	var checked := preview(model.data, review.get("plan"))
	if not checked["ok"] or checked["data"] != review["data"] or checked["diff"] != review.get("diff"):
		return false
	model.record_history()
	model.data = checked["data"].duplicate(true)
	model.dirty = true
	model.record_history()
	return true


## manifest = {maps: [{map_id, path?: JSON路径, source?: 预期快照, plan?: 显式计划}]}。
## 也可传 manifest 文件路径。只读所有地图，返回 {maps, issues, ok, can_save}，绝不落盘。
static func report_manifest(manifest: Variant, library: Variant = null) -> Dictionary:
	if manifest is String:
		manifest = Validation.read_map(manifest).get("data")
	var issues: Array[Dictionary] = []
	var maps: Array[Dictionary] = []
	if not manifest is Dictionary or not manifest.get("maps") is Array \
			or manifest["maps"].is_empty() or not Transfer._json_value(manifest):
		issues.append(Validation.issue("error", "manifest 必须含非空 maps 数组。", "map", -1, "manifest"))
	else:
		var identities: Dictionary = {}
		var paths: Dictionary = {}
		for entry: Variant in manifest["maps"]:
			var review := _read_entry(entry, identities, paths)
			maps.append(review)
			issues.append_array(review["issues"])
		var context := {"maps": {}}
		for review: Dictionary in maps:
			if review.get("data") is Dictionary:
				context["maps"][review["map_id"]] = review["data"]
		for review: Dictionary in maps:
			if not review.get("ok", false):
				continue
			var validation := Validation.validate(review["data"], context, library)
			review["validation"] = validation
			review["issues"].append_array(validation["issues"])
			for problem: Dictionary in review["issues"]:
				problem["path"] = review["path"]
			issues.append_array(validation["issues"])
			review["ok"] = validation["can_save"]
	var result := Validation.summarize(issues)
	result["maps"] = maps
	return result


static func _read_entry(entry: Variant, identities: Dictionary, paths: Dictionary) -> Dictionary:
	var issues: Array[Dictionary] = []
	var result := {"ok": false, "issues": issues}
	if not entry is Dictionary or not entry.get("map_id") is String \
			or not Validation.valid_id(entry["map_id"]) or (entry.has("path") and not entry["path"] is String):
		issues.append(Validation.issue("error", "manifest 地图条目或 ID 无效。", "map", -1, "manifest"))
		return result
	var map_id: String = entry["map_id"]
	var path: String = entry.get("path", "res://data/maps/%s.json" % map_id)
	var canonical := ProjectSettings.globalize_path(path).simplify_path().to_lower()
	result.merge({"map_id": map_id, "path": path})
	if identities.has(map_id) or paths.has(canonical):
		issues.append(Validation.issue("error", "manifest 地图或目标路径重复重叠。", "map", -1, "manifest", map_id))
		return result
	identities[map_id] = true
	paths[canonical] = true
	var snapshot := Validation.read_map(path)
	if not snapshot["ok"] or snapshot["data"].get("id") != map_id:
		issues.append(Validation.issue("error", "地图无法读取或 ID 与 manifest 不符。", "map", -1, "path", map_id))
		return result
	var source: Dictionary = snapshot["data"]
	issues.append_array(Validation.geometry_issues(source))
	if not issues.is_empty():
		return result
	if entry.has("source") and Model._normalize(entry["source"]) != Model._normalize(source):
		issues.append(Validation.issue("error", "地图已过期，请重新生成审阅报告。", "map", -1, "source", map_id))
		return result
	result.merge({"source": source.duplicate(true), "source_hash": snapshot["text"].sha256_text()})
	if entry.has("plan"):
		var migration := preview(source, entry["plan"])
		result["preview"] = migration
		issues.append_array(migration["issues"])
		if not migration["ok"]:
			return result
		result["data"] = migration["data"].duplicate(true)
		result["diff"] = migration["diff"].duplicate(true)
	else:
		result["data"] = source.duplicate(true)
		result["diff"] = {"before": {"walls": source.get("walls", []).duplicate(true)},
			"after": {"walls": source.get("walls", []).duplicate(true)}, "changes": []}
	result["ok"] = true
	return result


## 保存当前模型。review 可为 validate() 报告、manifest 单图项或完整报告。
## confirmed 与 warnings_acknowledged 由主界面确认；重验通过后调用 model.save_to() 生成备份。
static func save_current(model: Variant, review: Dictionary, confirmed := false,
		warnings_acknowledged := false, context: Dictionary = {}, library: Variant = null) -> Dictionary:
	if not confirmed:
		return _save_failure("必须先确认保存。", ERR_UNAUTHORIZED)
	if review.get("can_save", true) == false or review.get("ok", true) == false:
		return _save_failure("审阅报告含阻止保存的错误。", ERR_INVALID_DATA)
	if not model is Model or model.path.is_empty() or model.map_id != str(model.data.get("id", "")):
		return _save_failure("当前地图模型未配置。", ERR_UNCONFIGURED)
	var selected := review
	var validation_context := context.duplicate(true)
	if review.get("maps") is Array:
		selected = {}
		validation_context["maps"] = {}
		for item: Variant in review["maps"]:
			if item is Dictionary and item.get("data") is Dictionary:
				if not item.get("path") is String or not item.get("source_hash") is String:
					return _save_failure("跨图报告缺少磁盘快照，请重新审阅。", ERR_INVALID_DATA)
				var current := Validation.read_map(item["path"])
				if not current["ok"] or current["text"].sha256_text() != item["source_hash"]:
					return _save_failure("跨图报告中有地图已过期，请重新审阅。", ERR_INVALID_DATA)
				validation_context["maps"][item.get("map_id", "")] = item["data"]
				if item.get("map_id") == model.map_id:
					selected = item
	if selected.get("data", selected.get("source")) != model.data \
			or selected.get("path", model.path) != model.path:
		return _save_failure("模型或审阅报告已过期。", ERR_INVALID_DATA)
	var snapshot := Validation.read_map(model.path)
	if not snapshot["ok"]:
		return _save_failure("正式地图无法读取，不能安全备份。", ERR_FILE_CANT_READ)
	if selected.has("source_hash"):
		if snapshot["text"].sha256_text() != selected["source_hash"]:
			return _save_failure("磁盘地图已过期，请重新审阅。", ERR_INVALID_DATA)
	elif Model.stringify(snapshot["data"]) != model._saved_text:
		return _save_failure("磁盘地图已改变，请重新载入。", ERR_INVALID_DATA)
	var validation := Validation.validate(model.data, validation_context, library)
	if not validation["can_save"]:
		validation["error"] = ERR_INVALID_DATA
		return validation
	if (not validation["warnings"].is_empty() or not review.get("warnings", []).is_empty()) and not warnings_acknowledged:
		validation["ok"] = false
		validation["error"] = ERR_UNAUTHORIZED
		validation["message"] = "请先展示并确认所有警告。"
		return validation
	var error: Error = model.save_to()
	return {"ok": error == OK, "error": error, "validation": validation,
		"backup": model.last_backup_name, "message": "已保存。" if error == OK else "安全保存失败。"}


static func _save_failure(message: String, error: Error) -> Dictionary:
	return {"ok": false, "error": error, "message": message}


static func _actor_snapshot(raw: Dictionary) -> Dictionary:
	var actor := MapDef._actor_from(raw)
	var world: Array = []
	for shape: Rect2 in actor.collision_rects():
		world.append(Transfer._array_rect(shape))
	return {"collision": raw.get("collision", []).duplicate(true), "has_local_collision": actor.has_local_collision,
		"world_collision": world, "reach": Transfer._array_rect(actor.reach),
		"reach_local": raw.get("reach_local"), "cover": actor.cover,
		"cover_y": actor.effective_cover_y(), "sort_collider": actor.sort_collider,
		"sort_offset": actor.sort_offset, "manual_cover_y": raw.get("cover_y")}
