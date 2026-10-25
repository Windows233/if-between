## 物件局部几何变换：围绕 Actor.rect 中心计算新的轴对齐包围盒。
##
## 贴图先局部翻转，再顺时针旋转 quarter_turns；子部件共用物件的方向。
##
## apply 通过 model setters 写入全部物件，只记录一次可撤销的操作。
@tool
extends RefCounted


static func apply(model, indices: Array[int], operation: String, value: Variant = null,
		record := true) -> bool:
	if model == null:
		return false
	var selected: Array[int] = model.expand_group_selection(indices)
	var targets: Array[Dictionary] = []
	var changed := false
	for index: int in selected:
		var source: Dictionary = model.actor_dict(index)
		var target := transformed_actor(source, operation, value)
		if target.is_empty():
			return false
		targets.append(target)
		changed = changed or target != source
	if not changed:
		return false
	if record:
		model.record_history()
	for offset in selected.size():
		write_actor(model, selected[offset], targets[offset])
	if record:
		model.record_history()
	return true


static func transformed_actor(source: Dictionary, operation: String,
		value: Variant = null) -> Dictionary:
	var basis := Transform2D.IDENTITY
	var turns := posmod(int(source.get("quarter_turns", 0)), 4)
	var flip_h := bool(source.get("flip_h", false))
	var flip_v := bool(source.get("flip_v", false))
	var offset_scale := 1.0
	match operation:
		"flip_h":
			basis.x = Vector2(-1, 0)
			turns = posmod(-turns, 4)
			flip_h = not flip_h
		"flip_v":
			basis.y = Vector2(0, -1)
			turns = posmod(-turns, 4)
			flip_v = not flip_v
		"rotate", "rotate_cw", "rotate_ccw":
			var delta := int(value) if value != null else (-1 if operation == "rotate_ccw" else 1)
			match posmod(delta, 4):
				1:
					basis.x = Vector2(0, 1)
					basis.y = Vector2(-1, 0)
				2:
					basis.x = Vector2(-1, 0)
					basis.y = Vector2(0, -1)
				3:
					basis.x = Vector2(0, -1)
					basis.y = Vector2(1, 0)
			turns = posmod(turns + delta, 4)
		"scale":
			var factor := Vector2.ONE
			if value is Vector2:
				factor = value
			elif value is float or value is int:
				factor = Vector2.ONE * float(value)
			else:
				return {}
			if not factor.is_finite() or factor.x <= 0.0 or factor.y <= 0.0:
				return {}
			basis.x.x = factor.x
			basis.y.y = factor.y
			offset_scale = factor.y
		_:
			return {}
	if basis == Transform2D.IDENTITY:
		return source.duplicate(true)
	var rect := rect_from(source.get("rect"))
	if not rect.has_area():
		return {}
	var center := rect.size * 0.5
	basis.origin = center - basis * center
	var bounds := transformed_rect(Rect2(Vector2.ZERO, rect.size), basis)
	var target_rect := Rect2(rect.position + bounds.position, bounds.size)
	basis.origin -= bounds.position
	var result := _geometry(source, basis, target_rect, offset_scale)
	if operation != "scale":
		result["quarter_turns"] = turns
		result["flip_h"] = flip_h
		result["flip_v"] = flip_v
	return result


static func resized_actor(source: Dictionary, target: Rect2) -> Dictionary:
	var rect := rect_from(source.get("rect"))
	if not rect.has_area() or not target.has_area() or not target.position.is_finite() \
			or not target.size.is_finite():
		return {}
	var factor := target.size / rect.size
	return _geometry(source, Transform2D(Vector2(factor.x, 0), Vector2(0, factor.y),
		Vector2.ZERO), target, factor.y)


static func write_actor(model, index: int, target: Dictionary) -> bool:
	var source: Dictionary = model.actor_dict(index)
	if source.is_empty() or target.is_empty() or source == target:
		return false
	for key: Variant in source.keys():
		if not target.has(key):
			model.erase_actor_field(index, str(key))
	for key: Variant in target:
		if not source.has(key) or source[key] != target[key]:
			model.set_actor_field(index, str(key), target[key])
	return true


static func _geometry(source: Dictionary, local: Transform2D, target: Rect2,
		offset_scale: float) -> Dictionary:
	var result := source.duplicate(true)
	result["rect"] = rect_array(target)
	var actor := MapDef._actor_from(source)
	if source.has("collision") or actor.solid or actor.person:
		var shapes: Array = []
		for shape: Rect2 in actor.collision_rects():
			shapes.append(rect_array(Rect2(shape.position - target.position, shape.size)))
		result["collision"] = shapes
	result["reach_local"] = rect_array(Rect2(actor.reach.position - target.position, actor.reach.size))
	result.erase("reach")
	var parts: Variant = source.get("visual_parts", [])
	if parts is Array and not parts.is_empty():
		var transformed_parts: Array = []
		for part: Variant in parts:
			if not part is Dictionary:
				transformed_parts.append(part)
				continue
			var item: Dictionary = part.duplicate(true)
			item["rect"] = rect_array(transformed_rect(rect_from(item.get("rect")), local))
			if item.has("sort_offset"):
				item["sort_offset"] = _number(float(item["sort_offset"]) * offset_scale)
			transformed_parts.append(item)
		result["visual_parts"] = transformed_parts
	if float(source.get("cover_y", -1.0)) >= 0.0:
		var automatic := MapDef._actor_from(source).auto_cover_y()
		result.erase("cover_y")
		result["sort_offset"] = _number((float(source["cover_y"]) - automatic) * offset_scale)
	elif source.has("sort_offset"):
		result["sort_offset"] = _number(float(source["sort_offset"]) * offset_scale)
	return result


static func transformed_rect(rect: Rect2, transform: Transform2D) -> Rect2:
	var first := transform * rect.position
	var low := first
	var high := first
	for point in [rect.position + Vector2(rect.size.x, 0), rect.end,
			rect.position + Vector2(0, rect.size.y)]:
		var mapped: Vector2 = transform * point
		low = low.min(mapped)
		high = high.max(mapped)
	return Rect2(low, high - low)


static func rect_from(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	if value is Array and value.size() == 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()


static func rect_array(rect: Rect2) -> Array:
	return [_number(rect.position.x), _number(rect.position.y), _number(rect.size.x), _number(rect.size.y)]


static func _number(value: float) -> Variant:
	if value == roundf(value):
		return int(value)
	return value


static func visual_transform(rect: Rect2, actor: Dictionary) -> Transform2D:
	var turns := posmod(int(actor.get("quarter_turns", 0)), 4)
	var dimensions := Vector2(rect.size.y, rect.size.x) if turns % 2 == 1 else rect.size
	var orientation := Transform2D(float(turns) * PI * 0.5, Vector2.ZERO)
	orientation.x *= -dimensions.x if bool(actor.get("flip_h", false)) else dimensions.x
	orientation.y *= -dimensions.y if bool(actor.get("flip_v", false)) else dimensions.y
	orientation.origin = rect.get_center()
	return orientation
