@tool
extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")

var directory := "res://data/map_objects"


func list_templates() -> Array[String]:
	var result: Array[String] = []
	var folder := DirAccess.open(directory)
	if folder != null:
		for filename: String in folder.get_files():
			if filename.ends_with(".json"):
				var name := filename.trim_suffix(".json")
				if not _load_actor(name).is_empty():
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
	item.erase("source_template")
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
	var item := _load_actor(name)
	if item.is_empty():
		return []
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
	var items: Array[Dictionary] = [item]
	return model.insert_actors(items, at)


func _load_actor(name: String) -> Dictionary:
	if not _valid_name(name):
		return {}
	var target := directory.path_join(name + ".json")
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error != OK and error != ERR_FILE_EOF:
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var content: Variant = parser.data
	if not content is Dictionary or not _valid_number(content.get("version")) \
			or content["version"] != 1:
		return {}
	if content.has("name") and (not content["name"] is String or not _valid_name(content["name"])):
		return {}
	var actor: Variant = content.get("actor")
	if not actor is Dictionary or not _valid_actor(actor):
		return {}
	return actor.duplicate(true)


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
