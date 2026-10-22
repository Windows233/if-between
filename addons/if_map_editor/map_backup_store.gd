extends RefCounted

const MAX_SNAPSHOTS_PER_MAP := 20

var directory := "user://map_editor_backups"


func create_snapshot(map_id: String, source_path: String) -> String:
	if not _valid_map_id(map_id) or not FileAccess.file_exists(source_path):
		return ""
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return ""
	var bytes := source.get_buffer(source.get_length())
	source.close()
	if bytes.is_empty():
		return ""
	var folder := ProjectSettings.globalize_path(directory.path_join(map_id))
	var make_dir_error := DirAccess.make_dir_recursive_absolute(folder)
	if make_dir_error != OK and not DirAccess.dir_exists_absolute(folder):
		return ""
	var name := _next_snapshot_name(map_id)
	var target_path := ProjectSettings.globalize_path(_snapshot_path(map_id, name))
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return ""
	target.store_buffer(bytes)
	var write_error := target.get_error()
	target.close()
	if write_error != OK:
		DirAccess.remove_absolute(target_path)
		return ""
	_prune(map_id)
	return name


func list_snapshots(map_id: String) -> Array[String]:
	var result: Array[String] = []
	if not _valid_map_id(map_id):
		return result
	var folder := directory.path_join(map_id)
	var dir := DirAccess.open(folder)
	if dir == null:
		return result
	for name: String in dir.get_files():
		if _valid_snapshot_name(name):
			result.append(name)
	result.sort()
	result.reverse()
	return result


func read_snapshot(map_id: String, name: String) -> Dictionary:
	if not _valid_map_id(map_id) or not _valid_snapshot_name(name):
		return {}
	var path := _snapshot_path(map_id, name)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or str(parsed.get("id", "")) != map_id:
		return {}
	return parsed


func _prune(map_id: String) -> void:
	var names := list_snapshots(map_id)
	while names.size() > MAX_SNAPSHOTS_PER_MAP:
		var oldest := names.pop_back()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_snapshot_path(map_id, oldest)))


func _next_snapshot_name(map_id: String) -> String:
	var date := Time.get_datetime_dict_from_system()
	var stem := "%04d%02d%02d_%02d%02d%02d_%d" % [date.year, date.month, date.day,
		date.hour, date.minute, date.second, Time.get_ticks_usec()]
	var name := stem + ".json"
	var suffix := 1
	while FileAccess.file_exists(_snapshot_path(map_id, name)):
		name = "%s_%d.json" % [stem, suffix]
		suffix += 1
	return name


func _snapshot_path(map_id: String, name: String) -> String:
	return directory.path_join(map_id).path_join(name)


func _valid_map_id(map_id: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]+$")
	return not map_id.is_empty() and pattern.search(map_id) != null


func _valid_snapshot_name(name: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^\\d{8}_\\d{6}_\\d+(_\\d+)?\\.json$")
	return pattern.search(name) != null
