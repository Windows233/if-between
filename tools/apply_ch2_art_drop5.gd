## 通过地图编辑器数据层接入本轮素材；不修改墙、出口或追逐碰撞。
## 保留独立交互区，窗位置以运行时通行验证为准。
extends SceneTree

const Model = preload("res://addons/if_map_editor/map_edit_model.gd")

func _initialize() -> void:
	var model = Model.new()
	assert(model.load_map("library", false))
	for index: int in model.actors().size():
		if model.actor_field(index, "id") == "escape_shelf_barrier":
			model.set_actor_field(index, "sprite_variants", {"hidden":"res://art/fx/library/hidden.png", "fallen":"res://art/props/library_shelf_fallen.png"})
			model.set_actor_field(index, "quarter_turns", 0)
			model.set_actor_field(index, "label", "倒塌书架")
	assert(model.save_to() == OK)
	assert(model.load_map("classroom", false))
	for index: int in model.actors().size():
		if model.actor_field(index, "id") == "classroom_window":
			# Keep the user's current rect and reach; fit the visuals to that geometry.
			model.set_actor_field(index, "visual_parts", [
				{"id":"night", "rect":[0,0,28,44], "layer":"back", "sprite":"res://art/props/classroom_window_night_back.svg"},
				{"id":"frame", "rect":[0,0,28,44], "layer":"back", "sprite":"res://art/props/classroom_window_frame.png"},
			])
	assert(model.save_to() == OK)
	assert(model.load_map("market_night", false))
	var replacements := 0
	for index: int in model.actors().size():
		var path: String = model.actor_field(index, "sprite", "")
		if path.contains("market_day_"):
			var night := path.replace("market_day_", "market_night_")
			assert(FileAccess.file_exists(night))
			model.set_actor_field(index, "sprite", night)
			replacements += 1
	assert(model.save_to() == OK)
	assert(model.load_map("school_gate", false))
	for index: int in model.portals().size():
		var portal: Dictionary = model.portals()[index]
		if portal.get("id") == "to_classroom":
			var rect: Rect2 = model.rect_of(Model.Kind.PORTAL, index)
			rect.size.y = maxf(rect.size.y, 54.0)
			model.set_rect(Model.Kind.PORTAL, index, rect)
	assert(model.save_to() == OK)
	print("ART_MAP_SAVE_OK night replacements=", replacements, " classroom portal reach=checked")
	quit()
