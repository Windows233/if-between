@tool
extends RefCounted


static func find_group(data: Dictionary, group_id: String) -> Dictionary:
	for group: Variant in data.get("editor_groups", []):
		if group is Dictionary and str(group.get("id", "")) == group_id:
			return group
	return {}


static func descendants(data: Dictionary, group_id: String, visited := {}) -> Array[String]:
	var result: Array[String] = []
	if visited.has(group_id):
		return result
	visited[group_id] = true
	var group := find_group(data, group_id)
	for member: Variant in group.get("members", []):
		if not result.has(str(member)):
			result.append(str(member))
	for child: Variant in data.get("editor_groups", []):
		if child is Dictionary and str(child.get("parent", "")) == group_id:
			for member: String in descendants(data, str(child.get("id", "")), visited):
				if not result.has(member):
					result.append(member)
	return result


static func parent_of_actor(data: Dictionary, actor_id: String) -> String:
	for group: Variant in data.get("editor_groups", []):
		if group is Dictionary and group.get("members", []).has(actor_id):
			return str(group.get("id", ""))
	return ""


static func top_group(data: Dictionary, group_id: String) -> String:
	var seen := {}
	var current := group_id
	while not current.is_empty() and not seen.has(current):
		seen[current] = true
		var parent := str(find_group(data, current).get("parent", ""))
		if parent.is_empty() or find_group(data, parent).is_empty():
			return current
		current = parent
	return group_id


static func reparent(data: Dictionary, kind: String, identity: String, parent_id: String) -> bool:
	if not parent_id.is_empty() and find_group(data, parent_id).is_empty():
		return false
	if kind == "group":
		var group := find_group(data, identity)
		if group.is_empty() or identity == parent_id:
			return false
		var cursor := parent_id
		var seen := {}
		while not cursor.is_empty():
			if cursor == identity or seen.has(cursor):
				return false
			seen[cursor] = true
			cursor = str(find_group(data, cursor).get("parent", ""))
		if parent_id.is_empty():
			group.erase("parent")
		else:
			group["parent"] = parent_id
	elif kind == "actor":
		var exists := false
		for actor: Variant in data.get("actors", []):
			exists = exists or (actor is Dictionary and str(actor.get("id", "")) == identity)
		if not exists:
			return false
		for group: Variant in data.get("editor_groups", []):
			if group is Dictionary:
				var members: Array = group.get("members", []).duplicate()
				members.erase(identity)
				group["members"] = members
		if not parent_id.is_empty():
			var target := find_group(data, parent_id)
			var members: Array = target.get("members", []).duplicate()
			members.append(identity)
			target["members"] = members
	else:
		return false
	return true


static func repair_parents(data: Dictionary) -> void:
	for group: Variant in data.get("editor_groups", []):
		if group is Dictionary and not str(group.get("parent", "")).is_empty() \
				and find_group(data, str(group["parent"])).is_empty():
			group.erase("parent")


static func reorder(data: Dictionary, key: String, before_key: String, after := false) -> bool:
	if key.is_empty() or key == before_key:
		return false
	var order: Array = data.get("editor_tree_order", []).duplicate()
	for group: Variant in data.get("editor_groups", []):
		if group is Dictionary and not order.has("group:" + str(group.get("id", ""))):
			order.append("group:" + str(group.get("id", "")))
	for actor: Variant in data.get("actors", []):
		if actor is Dictionary and not order.has("actor:" + str(actor.get("id", ""))):
			order.append("actor:" + str(actor.get("id", "")))
	if not order.has(key) or (not before_key.is_empty() and not order.has(before_key)):
		return false
	order.erase(key)
	order.insert(order.find(before_key) + (1 if after else 0) if not before_key.is_empty() else order.size(), key)
	data["editor_tree_order"] = order
	return true


static func errors(data: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var ids := {}
	var owners := {}
	var actors := {}
	for actor: Variant in data.get("actors", []):
		if actor is Dictionary:
			actors[str(actor.get("id", ""))] = true
	for group: Variant in data.get("editor_groups", []):
		if not group is Dictionary:
			result.append("编组必须是对象")
			continue
		var identity := str(group.get("id", ""))
		if identity.is_empty() or ids.has(identity):
			result.append("编组 ID 为空或重复：" + identity)
		ids[identity] = true
		if not group.get("members", []) is Array:
			result.append("编组成员必须是数组：" + identity)
			continue
		for member: Variant in group.get("members", []):
			if not actors.has(str(member)):
				result.append("编组引用不存在的物件：" + str(member))
			if owners.has(str(member)):
				result.append("物件属于多个编组：" + str(member))
			owners[str(member)] = identity
	for group: Variant in data.get("editor_groups", []):
		if not group is Dictionary:
			continue
		var visited := {}
		var cursor := str(group.get("id", ""))
		while not cursor.is_empty():
			if visited.has(cursor):
				result.append("嵌套编组存在循环：" + cursor)
				break
			visited[cursor] = true
			var current := find_group(data, cursor)
			if current.is_empty():
				result.append("父编组不存在：" + cursor)
				break
			cursor = str(current.get("parent", ""))
	return result
