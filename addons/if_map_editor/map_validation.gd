## 地图审阅的只读校验器，返回可定位的问题与导航连通分量。
## 先检查原始 JSON 形状，再调用 MapDef；坏数据不会进入不安全的数值转换。
## context.maps/events 可注入跨图快照及事件目录；资源定位保留 kind/index/field。
@tool
extends RefCounted

const Library := preload("res://addons/if_map_editor/map_object_library.gd")
const Transfer := preload("res://addons/if_map_editor/map_geometry_transfer.gd")
const MAX_NAV_CELLS := 300000


## 返回 {map_id, source, issues, errors, warnings, can_save, navigation}。
## context.maps 为 {地图ID: 原始字典}；events 为 {事件ID: 字典或 true}。
static func validate(data: Variant, context: Dictionary = {}, library: Variant = null) -> Dictionary:
	var issues := geometry_issues(data)
	var map_id := str(data.get("id", "")) if data is Dictionary else ""
	var navigation: Dictionary = {}
	if issues.is_empty():
		var definition := MapDef.from_dictionary(data)
		for message: String in definition.validate():
			issues.append(issue("error", message, "map", -1, "", map_id))
		var spawn_index := 0
		for name: String in definition.spawns:
			var point: Vector2 = definition.spawns[name]
			if point.x < 0 or point.y < 0 or point.x > definition.size.x or point.y > definition.size.y:
				issues.append(issue("error", "出生点落在地图外。", "spawn", spawn_index, name, map_id))
			spawn_index += 1
		_check_resources(data, issues, "map", -1, map_id)
		var object_library: Variant = library if library != null else Library.new()
		for kind: String in ["actor", "portal", "trigger"]:
			var collection: Array = data.get({"actor": "actors", "portal": "portals", "trigger": "triggers"}[kind], [])
			var seen: Dictionary = {}
			for index: int in collection.size():
				var item: Dictionary = collection[index]
				var identity := str(item.get("id", ""))
				if identity.strip_edges().is_empty():
					if kind != "portal":
						issues.append(issue("error", "ID 缺失或重复：%s" % identity, kind, index, "id", map_id))
				elif seen.has(identity):
					issues.append(issue("error", "ID 缺失或重复：%s" % identity, kind, index, "id", map_id))
				else:
					seen[identity] = true
				_check_resources(item, issues, kind, index, map_id)
				_check_event(item, "event", context, issues, kind, index, map_id)
				for action_index: int in item.get("actions", []).size():
					_check_event(item["actions"][action_index], "event", context, issues,
						kind, index, map_id, "actions.%d.event" % action_index)
				if kind == "actor":
					_check_template(item, index, map_id, object_library, issues)
				elif kind == "trigger":
					_check_trigger(item, index, map_id, issues)
		_check_portals(data, context, issues)
		if definition.validate().is_empty():
			navigation = _navigation(definition, issues)
	var report := summarize(issues)
	report.merge({"map_id": map_id, "source": data.duplicate(true) if data is Dictionary
		and Transfer._json_value(data) else {}, "navigation": navigation})
	return report


## 可复用的原始数据闸门；通过后可安全交给 MapDef 和单物件迁移器。
static func geometry_issues(data: Variant) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if not data is Dictionary or not Transfer._json_value(data):
		issues.append(issue("error", "地图必须是有限、无环且深度不超过 64 的 JSON 字典。"))
		return issues
	var map_id := str(data.get("id", ""))
	if not data.get("id") is String or map_id.strip_edges().is_empty():
		issues.append(issue("error", "地图缺少有效 ID。", "map", -1, "id", map_id))
	if not Transfer._vector(data.get("size")) or data["size"][0] <= 0 or data["size"][1] <= 0:
		issues.append(issue("error", "地图尺寸无效。", "map", -1, "size", map_id))
	for field: String in ["player_scale"]:
		if data.has(field) and not Transfer._number(data[field]):
			issues.append(issue("error", "地图数值无效。", "map", -1, field, map_id))
	for field: String in ["background", "overlay", "music", "footstep", "kind"]:
		if data.has(field) and not data[field] is String:
			issues.append(issue("error", "地图字段必须是文本。", "map", -1, field, map_id))
	for field: String in ["walls", "actors", "portals", "triggers"]:
		if not data.get(field, []) is Array:
			issues.append(issue("error", "集合必须是数组。", "map", -1, field, map_id))
			continue
		for index: int in data.get(field, []).size():
			var value: Variant = data[field][index]
			var kind := {"walls": "wall", "actors": "actor", "portals": "portal", "triggers": "trigger"}[field] as String
			if field == "walls":
				if not Transfer._rect(value):
					issues.append(issue("error", "墙矩形无效。", kind, index, "rect", map_id))
			elif not value is Dictionary:
				issues.append(issue("error", "条目必须是属性字典。", kind, index, "", map_id))
			else:
				_check_item_shape(value, kind, index, map_id, issues)
	if not data.get("spawns", {}) is Dictionary:
		issues.append(issue("error", "出生点必须是字典。", "map", -1, "spawns", map_id))
	else:
		var index := 0
		for name: String in data.get("spawns", {}):
			if name.strip_edges().is_empty() or not Transfer._vector(data["spawns"][name]):
				issues.append(issue("error", "出生点名字或坐标无效。", "spawn", index, name, map_id))
			index += 1
	return issues


static func _check_item_shape(item: Dictionary, kind: String, index: int, map_id: String,
		issues: Array[Dictionary]) -> void:
	for field: String in ["rect", "reach", "reach_local"]:
		var required: bool = field == "rect"
		if (required or item.has(field)) and not Transfer._rect(item.get(field)):
			issues.append(issue("error", "矩形无效。", kind, index, field, map_id))
	if item.has("collision"):
		if not item["collision"] is Array:
			issues.append(issue("error", "局部碰撞必须是数组。", kind, index, "collision", map_id))
		else:
			for shape: Variant in item["collision"]:
				if not Transfer._rect(shape):
					issues.append(issue("error", "局部碰撞矩形无效。", kind, index, "collision", map_id))
	for field: String in ["solid", "person", "cover", "over", "decor", "locked", "auto_menu", "enabled", "once"]:
		if item.has(field) and not item[field] is bool:
			issues.append(issue("error", "开关必须是布尔值。", kind, index, field, map_id))
	for field: String in ["sort_collider", "sort_offset", "cover_y"]:
		if item.has(field) and (not Transfer._number(item[field]) or (field == "sort_collider"
				and float(item[field]) != floor(float(item[field])))):
			issues.append(issue("error", "排序数值无效。", kind, index, field, map_id))
	for field: String in ["id", "sprite", "event", "to", "spawn", "source_template", "action"]:
		if item.has(field) and not item[field] is String:
			issues.append(issue("error", "字段必须是文本。", kind, index, field, map_id))
	for field: String in ["talk", "actions"]:
		if item.has(field) and not item[field] is Array:
			issues.append(issue("error", "交互字段必须是数组。", kind, index, field, map_id))
		elif field == "actions":
			for action: Variant in item.get(field, []):
				if not action is Dictionary or (action.has("talk") and not _valid_talk(action["talk"])):
					issues.append(issue("error", "交互动作无效。", kind, index, field, map_id))
	if item.has("talk") and not _valid_talk(item["talk"]):
		issues.append(issue("error", "对话字段或数值无效。", kind, index, "talk", map_id))


static func _valid_talk(raw: Variant) -> bool:
	if not raw is Array:
		return false
	for line: Variant in raw:
		if not line is Dictionary:
			return false
		for field: String in ["size_delta", "shake"]:
			if line.has(field) and not Transfer._number(line[field]):
				return false
	return true


static func _check_resources(item: Dictionary, issues: Array[Dictionary], kind: String,
		index: int, map_id: String) -> void:
	for field: String in ["background", "overlay", "music", "footstep", "sprite"]:
		if item.has(field) and not str(item[field]).is_empty() and (
				not str(item[field]).begins_with("res://") or not FileAccess.file_exists(item[field])):
			var problem := issue("error", "缺少资源：%s" % item[field], kind, index, field, map_id)
			problem["resource"] = str(item[field])
			issues.append(problem)
	var parts: Variant = item.get("visual_parts", [])
	if parts is Array:
		for part_index: int in parts.size():
			if not parts[part_index] is Dictionary:
				continue
			var sprite := str(parts[part_index].get("sprite", ""))
			if not sprite.is_empty() and (not sprite.begins_with("res://") or not FileAccess.file_exists(sprite)):
				var problem := issue("error", "缺少部件资源：%s" % sprite, kind, index,
					"visual_parts.%d.sprite" % part_index, map_id)
				problem["resource"] = sprite
				issues.append(problem)


static func _check_event(item: Dictionary, field: String, context: Dictionary,
		issues: Array[Dictionary], kind: String, index: int, map_id: String, location := "event") -> void:
	if not item.has(field):
		return
	var identity: Variant = item[field]
	if identity is String and identity.is_empty() and kind != "trigger":
		return
	var content: Variant = null
	if identity is String and valid_id(identity):
		if context.get("events") is Dictionary:
			content = context["events"].get(identity)
		else:
			content = read_map("res://data/events/%s.json" % identity).get("data")
	var valid: bool = content is bool and content == true
	if content is Dictionary:
		valid = _valid_event(content, identity)
	if not valid:
		var problem := issue("error", "事件不存在或无效：%s" % str(identity), kind, index, location, map_id)
		problem["resource"] = "res://data/events/%s.json" % str(identity)
		issues.append(problem)


static func _valid_event(content: Dictionary, identity: String) -> bool:
	if not Transfer._json_value(content) or content.get("id") != identity \
			or not content.get("nodes") is Array or content["nodes"].is_empty():
		return false
	var identities: Dictionary = {}
	for node: Variant in content["nodes"]:
		if not node is Dictionary or not node.get("id") is String \
				or node["id"].is_empty() or identities.has(node["id"]):
			return false
		identities[node["id"]] = true
		if node.has("talk") and not _valid_talk(node["talk"]):
			return false
	if content.has("entry") and not str(content["entry"]).is_empty() and not identities.has(content["entry"]):
		return false
	for node: Dictionary in content["nodes"]:
		if node.has("next") and not str(node["next"]).is_empty() and not identities.has(node["next"]):
			return false
	return true


static func _check_template(item: Dictionary, index: int, map_id: String, library: Variant,
		issues: Array[Dictionary]) -> void:
	var actor := MapDef._actor_from(item)
	if actor.has_local_collision and actor.cover and not actor.over \
			and (actor.sort_collider < 0 or actor.sort_collider >= actor.collisions.size()):
		issues.append(issue("error", "物件缺少有效排序参考碰撞箱。", "actor", index, "sort_collider", map_id))
	if item.has("reach") and item.has("reach_local"):
		issues.append(issue("warning", "reach 被 reach_local 覆盖，请确认交互范围。", "actor", index, "reach_local", map_id))
	if item.has("cover_y") and item.has("sort_offset"):
		issues.append(issue("warning", "cover_y 会覆盖自动基线和 sort_offset。", "actor", index, "cover_y", map_id))
	if not item.has("source_template"):
		return
	var template: Dictionary = {}
	if library is Object and library.has_method("resolve_template"):
		var resolved: Dictionary = library.resolve_template(str(item["source_template"]))
		if resolved.get("ok", false):
			template = resolved.get("actor", {})
	elif library is Object and library.has_method("_load_actor"):
		template = library._load_actor(str(item["source_template"]))
	if template.is_empty():
		issues.append(issue("error", "source_template 缺失或模板无效：%s" % item["source_template"],
			"actor", index, "source_template", map_id))
		return
	for field: String in ["sprite", "collision", "reach_local", "sort_collider", "sort_offset", "solid", "cover", "over"]:
		if item.get(field) != template.get(field):
			issues.append(issue("warning", "实例覆盖模板字段：%s，请确认差异。" % field, "actor", index, field, map_id))
	if item["rect"].slice(2) != template["rect"].slice(2):
		issues.append(issue("warning", "实例尺寸覆盖模板尺寸。", "actor", index, "rect", map_id))
	if library is Object and library.has_method("inspect_instance"):
		var inspection: Dictionary = library.inspect_instance(item)
		if not inspection.get("snapshot_valid", false):
			var severity := "error" if item.has("source_template_defaults") or item.has("source_template_version") else "warning"
			issues.append(issue(severity, "实例的模板跟踪快照缺失或无效，请审阅模板来源。", "actor", index, "source_template_defaults", map_id))
		elif inspection.get("update_available", false):
			issues.append(issue("warning", "模板已有更新，实例尚未确认同步。", "actor", index, "source_template_version", map_id))


static func _check_trigger(item: Dictionary, index: int, map_id: String, issues: Array[Dictionary]) -> void:
	if not item.has("event"):
		issues.append(issue("error", "触发区域必须绑定已有事件。", "trigger", index, "event", map_id))
	if not item.get("mode", "enter") in ["enter_map", "enter", "interact", "click"]:
		issues.append(issue("error", "触发模式无效。", "trigger", index, "mode", map_id))
	for field: String in ["condition", "if"]:
		if item.has(field) and item[field] != null and not _valid_condition(item[field]):
			issues.append(issue("error", "触发条件结构无效。", "trigger", index, field, map_id))


static func _valid_condition(raw: Variant, depth := 0) -> bool:
	if not raw is Dictionary or depth > 32:
		return false
	var count := 0
	for field: String in ["all", "any", "not", "exists", "var"]:
		count += int(raw.has(field))
	if count != 1:
		return false
	for field: String in ["all", "any"]:
		if raw.has(field):
			if not raw[field] is Array:
				return false
			for child: Variant in raw[field]:
				if not _valid_condition(child, depth + 1):
					return false
			return true
	if raw.has("not"):
		return _valid_condition(raw["not"], depth + 1)
	var identity: Variant = raw.get("exists", raw.get("var"))
	return identity is String and not identity.strip_edges().is_empty() and (raw.has("exists")
		or (raw.has("value") and raw.get("op", "==") in ["==", "=", "eq", "!=", "<>", "ne", ">", "gt", ">=", "ge", "<", "lt", "<=", "le"]))


static func _check_portals(data: Dictionary, context: Dictionary, issues: Array[Dictionary]) -> void:
	var map_id: String = data["id"]
	for index: int in data.get("portals", []).size():
		var portal: Dictionary = data["portals"][index]
		if portal.get("locked", false) or not str(portal.get("event", "")).is_empty() or portal.get("action", "") == "overworld":
			continue
		var target_id := str(portal.get("to", ""))
		var target: Variant = null
		if target_id == map_id:
			target = data
		elif context.get("maps") is Dictionary and context["maps"].has(target_id):
			target = context["maps"][target_id]
		elif valid_id(target_id):
			target = read_map("res://data/maps/%s.json" % target_id).get("data")
		if not target is Dictionary or target.get("id") != target_id or not geometry_issues(target).is_empty():
			issues.append(issue("error", "传送目标地图不存在或无效：%s" % target_id, "portal", index, "to", map_id))
		elif not target.get("spawns") is Dictionary or not target["spawns"].has(portal.get("spawn", "")):
			issues.append(issue("error", "目标地图缺少出生点：%s" % portal.get("spawn", ""), "portal", index, "spawn", map_id))


static func _navigation(definition: MapDef, issues: Array[Dictionary]) -> Dictionary:
	var result := {"complete": true, "components": [], "spawn_components": {},
		"spawn_region_count": 0, "unseeded_components": [], "portal_components": {}, "cells": 0}
	if definition.kind == MapDef.Kind.OVERWORLD:
		return result
	var bounds := WalkGrid.bounds(definition)
	var first := Vector2i(ceil(bounds.position.x / WalkGrid.STEP), ceil(bounds.position.y / WalkGrid.STEP))
	var last := Vector2i(ceil(bounds.end.x / WalkGrid.STEP), ceil(bounds.end.y / WalkGrid.STEP))
	if float(last.x - first.x) * float(last.y - first.y) > MAX_NAV_CELLS:
		issues.append(issue("warning", "地图过大，未完成导航校验。", "map", -1, "size", str(definition.id)))
		result["complete"] = false
		return result
	var cells: Dictionary = {}
	for row: int in range(first.y, last.y):
		for column: int in range(first.x, last.x):
			var key := Vector2i(column, row)
			if WalkGrid.is_free(definition, Vector2(key) * WalkGrid.STEP):
				cells[key] = -1
	for origin: Vector2i in cells:
		if cells[origin] != -1:
			continue
		var component: int = result["components"].size()
		var queue: Array[Vector2i] = [origin]
		cells[origin] = component
		var cursor := 0
		while cursor < queue.size():
			var point := queue[cursor]
			cursor += 1
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor := point + offset
				if cells.get(neighbor, -2) == -1:
					cells[neighbor] = component
					queue.append(neighbor)
		result["components"].append({"id": component, "cells": queue.size()})
	result["cells"] = cells.size()
	var spawn_index := 0
	var spawn_regions: Array[int] = []
	for name: String in definition.spawns:
		var point: Vector2 = definition.spawns[name]
		var component: int = cells.get(WalkGrid.key(point), -1)
		result["spawn_components"][name] = component
		if not WalkGrid.is_free(definition, point) or component < 0:
			issues.append(issue("error", "出生点被阻挡或无法进入导航格：%s" % name,
				"spawn", spawn_index, name, str(definition.id)))
		elif not spawn_regions.has(component):
			spawn_regions.append(component)
		spawn_index += 1
	# 地图边缘、空心家具内部等也可能站得下脚底框；分量多不等于实际路线被切断。
	# 保留全域统计，按有效出生点区分需要确认的入口断路与仅供参考的独立空地。
	result["spawn_region_count"] = spawn_regions.size()
	for component: Dictionary in result["components"]:
		if not spawn_regions.has(int(component["id"])):
			result["unseeded_components"].append(component["id"])
	if result["components"].size() > 1:
		if spawn_regions.size() == 1:
			issues.append(issue("info", "检测到 %d 个可站立区域；出生点均在同一区域，另有 %d 处未放置出生点的独立空地。" % [
				result["components"].size(), result["unseeded_components"].size()],
				"map", -1, "navigation", str(definition.id)))
		elif spawn_regions.is_empty():
			issues.append(issue("warning", "导航分成 %d 个区域，但没有有效出生点可核对通路。" % result["components"].size(),
				"map", -1, "navigation", str(definition.id)))
		else:
			issues.append(issue("warning", "出生点分布在 %d 个互不连通的可走区域，请核对入口与出口路线。" % spawn_regions.size(),
				"map", -1, "navigation", str(definition.id)))
	for index: int in definition.portals.size():
		var portal := definition.portals[index]
		if portal.outcome == MapDef.Portal.Outcome.NONE:
			continue
		var reachable_components: Array[int] = []
		for key: Vector2i in cells:
			if portal.rect.has_point(Vector2(key) * WalkGrid.STEP) and not reachable_components.has(cells[key]):
				reachable_components.append(cells[key])
		result["portal_components"][str(index)] = reachable_components
		for name: String in result["spawn_components"]:
			if not reachable_components.has(result["spawn_components"][name]):
				issues.append(issue("warning", "从出生点 %s 无法到达此出口。" % name,
					"portal", index, "rect", str(definition.id)))
	return result


## 结构化定位字段固定；resource 等附加字段由具体校验器补充。
static func issue(severity: String, message: String, kind := "map", index := -1,
		field := "", map_id := "") -> Dictionary:
	return {"severity": severity, "message": message, "kind": kind, "index": index,
		"field": field, "map_id": map_id}


## errors 阻止保存；warnings 必须显式确认；info 保留在审阅结果，不触发保存弹窗。
static func summarize(issues: Array[Dictionary]) -> Dictionary:
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []
	var infos: Array[Dictionary] = []
	for problem: Dictionary in issues:
		if problem.get("severity") == "error":
			errors.append(problem.duplicate(true))
		elif problem.get("severity") == "info":
			infos.append(problem.duplicate(true))
		else:
			warnings.append(problem.duplicate(true))
	return {"issues": issues.duplicate(true), "errors": errors, "warnings": warnings, "infos": infos,
		"can_save": errors.is_empty(), "ok": errors.is_empty()}


## 只读 JSON，用于地图、事件和 manifest；不修改模型、草稿或正式文件。
static func read_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "path": path, "data": null, "text": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "path": path, "data": null, "text": ""}
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	var data: Variant = JSON.parse_string(text)
	return {"ok": data is Dictionary and (error == OK or error == ERR_FILE_EOF),
		"path": path, "data": data, "text": text}


static func valid_id(identity: String) -> bool:
	if identity.is_empty():
		return false
	for character: String in identity:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true
