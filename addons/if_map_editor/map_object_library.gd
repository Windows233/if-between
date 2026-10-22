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
				result.append(filename.trim_suffix(".json"))
	result.sort()
	return result


func save_template(name: String, source: Dictionary) -> Error:
	if name.is_empty() or name != name.validate_filename() or name.contains(".."):
		return ERR_INVALID_PARAMETER
	var target := directory.path_join(name + ".json")
	if FileAccess.file_exists(target):
		return ERR_ALREADY_EXISTS
	var item := source.duplicate(true)
	var rect: Array = item.get("rect", [0, 0, 40, 40])
	var origin := Vector2(float(rect[0]), float(rect[1]))
	item["rect"] = [0, 0, rect[2], rect[3]]
	item.erase("source_template")
	if item.has("reach"):
		var reach: Array = item["reach"]
		item["reach_local"] = [float(reach[0]) - origin.x, float(reach[1]) - origin.y, reach[2], reach[3]]
		item.erase("reach")
	if item.has("cover_y"):
		var actor := MapDef._actor_from(source)
		item["sort_offset"] = actor.effective_cover_y() - actor.auto_cover_y()
		item.erase("cover_y")
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK:
		return error
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(Model.stringify({"version": 1, "name": name, "actor": item}))
	return OK


func instantiate(name: String, model, at: Vector2) -> Array[int]:
	if name != name.validate_filename() or name.contains(".."):
		return []
	var target := directory.path_join(name + ".json")
	if not FileAccess.file_exists(target):
		return []
	var content: Variant = JSON.parse_string(FileAccess.get_file_as_string(target))
	if not content is Dictionary or int(content.get("version", 0)) != 1:
		return []
	var actor: Variant = content.get("actor")
	if not actor is Dictionary or not actor.get("rect") is Array:
		return []
	var item: Dictionary = actor.duplicate(true)
	item["source_template"] = name
	var items: Array[Dictionary] = [item]
	return model.insert_actors(items, at)
