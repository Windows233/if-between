extends SceneTree

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


func _initialize() -> void:
	var model = Model.new()
	if not model.load_map("library", false):
		quit(1)
		return
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://.godot/library_review/layout.json"))
	var original_path := "res://.godot/library_review/library_before_main.json"
	if not FileAccess.file_exists(original_path):
		if DirAccess.copy_absolute(model.path, original_path) != OK:
			quit(1)
			return
	var labels := {"library_altar": "陈设桌", "library_plant": "盆栽与烛台",
		"library_reading_desk": "阅览桌"}
	for raw: Dictionary in payload["actors"]:
		var index := -1
		for candidate: int in model.actors().size():
			if str(model.actor_field(candidate, "id")) == str(raw["id"]):
				index = candidate
				break
		if index < 0:
			index = model.add_actor()
			model.set_actor_field(index, "id", raw["id"])
			model.set_actor_field(index, "label", labels.get(raw["id"], "书柜"))
			model.set_actor_field(index, "decor", true)
		var rect: Array = raw["rect"]
		model.set_actor_field(index, "rect", rect.duplicate())
		model.set_actor_field(index, "sprite", raw["sprite"])
		model.erase_actor_field(index, "reach_local")
		model.erase_actor_field(index, "cover_y")
		var shape: Array = raw["collision_world"]
		model.set_actor_field(index, "cover", true)
		model.set_actor_field(index, "collision", [[shape[0] - rect[0], shape[1] - rect[1], shape[2], shape[3]]])
		model.set_actor_field(index, "sort_collider", 0)
		model.set_actor_field(index, "reach_local", [0, 0, rect[2], rect[3]])
	model.data["walls"] = []
	for raw: Array in payload["walls"]:
		model.add_rect(Model.Kind.WALL, Rect2(raw[0], raw[1], raw[2], raw[3]))
	model.set_overlay_path("res://art/map/library_wall.png")
	model.data["background"] = "res://art/map/library.png"
	for spawn_name: String in model.spawn_names():
		var point: Array = payload["spawn"]
		model.data["spawns"][spawn_name] = point.duplicate()
	model.mark_dirty()
	var problems: Array[String] = MapDef.from_dictionary(model.data).validate()
	if not problems.is_empty():
		push_error(str(problems))
		quit(1)
		return
	var status: Error = model.save_to()
	print("Library saved through optional MapEditModel: ", status, "; backup: ", original_path)
	quit(0 if status == OK else 1)
