## 将编辑师明确选中的地图墙归入物件，不猜测墙体所有权。
## 预览只生成副本；应用重新核对来源与计划，不保存文件或写撤销历史。
## 调用者负责隐藏/锁定权限、确认与整步撤销；运行时仍读取原地图格式。
extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


static func preview(data: Dictionary, actor_index: int, wall_indices: Array[int],
		preserve_sort: bool = true) -> Dictionary:
	var errors := _validate_data(data)
	var result := {"ok": false, "errors": errors, "warnings": [], "data": {},
		"source": {}, "actor_index": actor_index, "wall_indices": wall_indices.duplicate(),
		"preserve_sort": preserve_sort, "before_baseline": 0.0, "after_baseline": 0.0,
		"added_shapes": 0}
	if not errors.is_empty():
		return result
	if actor_index < 0 or actor_index >= data["actors"].size():
		errors.append("请先选择一个有效物件。")
		return result
	var selected: Dictionary = data["actors"][actor_index]
	if selected.get("person", false) or selected.get("over", false):
		errors.append("人物或固定前景物件不能接收地图墙，请由编辑师单独处理。")
	var condition: Variant = selected.get("if")
	if condition != null and (not condition is Dictionary or not condition.is_empty()):
		errors.append("带显示条件的物件不能接收始终生效的地图墙。")
	if wall_indices.is_empty():
		errors.append("请明确勾选要归入的地图墙，不会自动选择。")
	var seen: Dictionary = {}
	for wall_index: int in wall_indices:
		if wall_index < 0 or wall_index >= data.get("walls", []).size():
			errors.append("地图墙索引已失效：%d。" % wall_index)
		elif seen.has(wall_index):
			errors.append("地图墙不能重复选择：%d。" % wall_index)
		seen[wall_index] = true
	if not errors.is_empty():
		return result
	var indices: Array[int] = wall_indices.duplicate()
	indices.sort()
	var actor := MapDef._actor_from(selected)
	var candidate := data.duplicate(true)
	var target: Dictionary = candidate["actors"][actor_index]
	var shapes: Array = target.get("collision", []).duplicate(true)
	if not actor.has_local_collision:
		for world_shape: Rect2 in actor.collision_rects():
			var local_shape := Rect2(world_shape.position - actor.rect.position, world_shape.size)
			if Rect2(actor.rect.position + local_shape.position, local_shape.size) != world_shape:
				errors.append("已有物件碰撞坐标无法无损转换，请先调整坐标。")
			shapes.append(_array_rect(local_shape))
	var previous_count := shapes.size()
	var warnings: Array[String] = []
	for wall_index: int in indices:
		var world := MapDef._to_rect(data["walls"][wall_index])
		var local := Rect2(world.position - actor.rect.position, world.size)
		if Rect2(actor.rect.position + local.position, local.size) != world:
			errors.append("墙 #%d 的坐标精度无法无损转换，请先调整坐标。" % wall_index)
		shapes.append(_array_rect(local))
		if not actor.rect.intersects(world):
			warnings.append("墙 #%d 不与物件贴图范围重叠，请确认归属。" % wall_index)
	if not errors.is_empty():
		return result
	target["collision"] = shapes
	if not target.has("reach_local"):
		target["reach_local"] = _array_rect(Rect2(actor.reach.position - actor.rect.position, actor.reach.size))
	target.erase("reach")
	var reference := actor.sort_collider if actor.has_local_collision and previous_count > 0 else previous_count
	if reference < 0 or reference >= previous_count:
		reference = previous_count
	target["sort_collider"] = reference
	var before_baseline := actor.effective_cover_y()
	target.erase("cover_y")
	target.erase("sort_offset")
	if preserve_sort:
		target["sort_offset"] = before_baseline - MapDef._actor_from(target).auto_cover_y()
	for selected_index: int in range(indices.size() - 1, -1, -1):
		candidate["walls"].remove_at(indices[selected_index])
	var candidate_errors := _validate_data(candidate)
	if not candidate_errors.is_empty():
		errors.append_array(candidate_errors)
		return result
	var converted := MapDef._actor_from(target)
	var converted_shapes := converted.collision_rects()
	for selected_index: int in indices.size():
		if converted_shapes[previous_count + selected_index] != MapDef._to_rect(data["walls"][indices[selected_index]]):
			errors.append("归入后的世界碰撞坐标发生精度变化，请先调整坐标。")
			return result
	if converted.reach != actor.reach:
		errors.append("交互区坐标无法无损转换，请先调整坐标。")
		return result
	if preserve_sort and not is_equal_approx(converted.effective_cover_y(), before_baseline):
		errors.append("排序基线无法保持，请先检查坐标与手动偏移。")
		return result
	if not str(selected.get("sprite", "")).is_empty():
		warnings.append("归入后移动或复制物件会携带这些墙；请确认背景中没有重复烘焙的同一物件。")
	else:
		warnings.append("该物件没有独立贴图；归入碰撞不会从背景中拆出图像。")
	result.merge({"ok": true, "data": candidate, "source": data.duplicate(true),
		"wall_indices": indices, "before_baseline": before_baseline,
		"after_baseline": converted.effective_cover_y(), "added_shapes": indices.size(),
		"warnings": warnings}, true)
	return result


static func apply(model, plan: Dictionary) -> bool:
	if not model is Model or not plan.get("ok", false) is bool or plan.get("ok", false) != true:
		return false
	if not plan.get("source") is Dictionary or not plan.get("data") is Dictionary \
			or plan["source"] != model.data \
			or not plan.get("actor_index") is int or not plan.get("wall_indices") is Array \
			or not plan.get("preserve_sort") is bool:
		return false
	var indices: Array[int] = []
	for raw: Variant in plan["wall_indices"]:
		if not raw is int:
			return false
		indices.append(raw)
	var checked := preview(model.data, plan["actor_index"], indices, plan["preserve_sort"])
	if not checked["ok"] or checked["data"] != plan.get("data"):
		return false
	model.data = checked["data"].duplicate(true)
	model.dirty = true
	return true


static func _validate_data(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _json_value(data):
		errors.append("地图包含非有限数值、过深结构或非 JSON 数据。")
		return errors
	if not data.get("id") is String or str(data.get("id", "")).strip_edges().is_empty() \
			or not _vector(data.get("size")) or data["size"][0] <= 0 or data["size"][1] <= 0:
		errors.append("地图 ID 或尺寸无效。")
	for collection: String in ["walls", "actors", "portals"]:
		if not data.get(collection, null if collection == "actors" else []) is Array:
			errors.append("地图 %s 必须是数组。" % collection)
	if not errors.is_empty():
		return errors
	for wall: Variant in data.get("walls", []):
		if not _rect(wall):
			errors.append("地图墙必须是有效的 [x, y, 宽, 高]。")
	var identities: Dictionary = {}
	for raw: Variant in data.get("actors", []):
		if not raw is Dictionary:
			errors.append("地图物件必须是属性字典。")
			continue
		if not raw.get("id") is String or str(raw.get("id", "")).strip_edges().is_empty() \
				or identities.has(raw.get("id")):
			errors.append("物件 ID 必须有效且唯一。")
		identities[raw.get("id")] = true
		for field: String in ["rect", "reach", "reach_local"]:
			if (field == "rect" or raw.has(field)) and not _rect(raw.get(field)):
				errors.append("物件 %s 的 %s 矩形无效。" % [raw.get("id", ""), field])
		if raw.has("collision"):
			if not raw["collision"] is Array:
				errors.append("物件局部碰撞必须是数组。")
			else:
				for shape: Variant in raw["collision"]:
					if not _rect(shape):
						errors.append("物件局部碰撞矩形无效。")
		for flag: String in ["solid", "person", "over", "cover", "decor"]:
			if raw.has(flag) and not raw[flag] is bool:
				errors.append("物件 %s 必须是布尔值。" % flag)
		for field: String in ["sort_collider", "sort_offset", "cover_y"]:
			if raw.has(field) and (not _number(raw[field]) or (field == "sort_collider" \
					and float(raw[field]) != floor(float(raw[field])))):
				errors.append("物件 %s 数值无效。" % field)
	for portal: Variant in data.get("portals", []):
		if not portal is Dictionary or not _rect(portal.get("rect")):
			errors.append("地图传送区矩形无效。")
	if not data.get("spawns", {}) is Dictionary:
		errors.append("地图出生点必须是字典。")
	else:
		for point: Variant in data.get("spawns", {}).values():
			if not _vector(point):
				errors.append("地图出生点坐标无效。")
	if errors.is_empty():
		errors.append_array(MapDef.from_dictionary(data).validate())
	return errors


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 1000000.0


static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


static func _rect(value: Variant) -> bool:
	if not value is Array or value.size() != 4:
		return false
	for component: Variant in value:
		if not _number(component):
			return false
	return value[2] > 0 and value[3] > 0


static func _array_rect(value: Rect2) -> Array:
	var values: Array = []
	for component: float in [value.position.x, value.position.y, value.size.x, value.size.y]:
		values.append(int(component) if component == floor(component) else component)
	return values


static func _json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is String:
		return true
	if value is int or value is float:
		return is_finite(float(value))
	if value is Array:
		for item: Variant in value:
			if not _json_value(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _json_value(value[key], depth + 1):
				return false
		return true
	return false
