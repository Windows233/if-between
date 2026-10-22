## 在真实插件控件中演练手动选墙、预览、确认与撤销，不保存正式地图。
## 同时比对迁移前后由 MapView 构建的实际碰撞节点与遮挡层级。
## 可用 IF_MAP_EDITOR_SCREENSHOT_DIR 保存渲染窗口截图；无头模式跳过截图。
extends SceneTree

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


func _initialize() -> void:
	create_timer(35.0).timeout.connect(func() -> void:
		push_error("地图墙归入探针超时。")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	var dock: Control = Dock.new()
	dock._editor_state_path = "user://transfer_probe_scene_state.cfg"
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var source_path := "res://data/maps/gatehouse.json"
	var source_hash := FileAccess.get_sha256(source_path)
	var map_index: int = Model.list_maps().find("gatehouse")
	assert(map_index >= 0)
	dock._map_picker.select(map_index)
	dock._load_selected()
	var indices: Array[int] = [0]
	dock.canvas.select_actors(indices)
	dock._refresh_selection()
	await process_frame
	var original: Dictionary = dock.model.data.duplicate(true)
	assert(not dock.model.dirty)
	assert(dock._transfer_button.visible and not dock._transfer_button.disabled)
	dock._transfer_button.pressed.emit()
	await process_frame
	var dialog = dock._transfer_dialog
	assert(dialog.visible and dialog.selected_wall_indices().is_empty())
	assert(dialog.size.x <= 1280 and dialog.size.y <= 800)
	print("首次打开归入助手尺寸 %s" % dialog.size)
	assert(dialog.get_ok_button().disabled)
	assert(dock.model.data == original and not dock.model.dirty)
	var wall_item: TreeItem = dialog._wall_list.get_root().get_first_child()
	while wall_item != null and int(wall_item.get_metadata(0)) != 5:
		wall_item = wall_item.get_next()
	assert(wall_item != null)
	wall_item.set_checked(0, true)
	dialog._wall_list.item_edited.emit()
	await process_frame
	assert(dialog._plan["ok"] and not dialog.get_ok_button().disabled)
	assert(dialog._plan["before_baseline"] == 165.0)
	assert(dialog._plan["after_baseline"] == 165.0)
	assert(dialog.size.x <= 1280 and dialog.size.y <= 800)
	await _capture("transfer-1280.png")
	root.size = Vector2i(1024, 768)
	root.content_scale_size = Vector2i(1024, 768)
	await process_frame
	dialog.open_for_viewport()
	await process_frame
	assert(dialog.size.x <= 1024 and dialog.size.y <= 768)
	assert(dialog._wall_list.size.y >= 80 and dialog._preview.size.y >= 64)
	print("归入助手尺寸 %s；旧墙列表 %s；差异预览 %s" % [
		dialog.size, dialog._wall_list.size, dialog._preview.size])
	await _capture("transfer-1024.png")
	dialog.get_ok_button().pressed.emit()
	await process_frame
	assert(not dialog.visible)
	assert(dock.model.count(Model.Kind.WALL) == original["walls"].size() - 1)
	assert(dock.model.actor_field(0, "collision") == [[0, 12, 76, 40]])
	assert(dock.model.actor_cover_y(0) == 165.0 and dock.model.dirty)
	assert(dock.canvas.selected_actors() == indices)
	var converted: Dictionary = dock.model.data.duplicate(true)
	await _runtime_equivalence(original, converted)
	await _capture("transfer-result-1024.png")
	dock._object_command("undo")
	assert(dock.model.data == original and not dock.model.dirty)
	dock._object_command("redo")
	assert(dock.model.data == converted and dock.model.dirty)
	dock._object_command("undo")
	assert(FileAccess.get_sha256(source_path) == source_hash)
	print("地图墙归入探针通过：门卫室墙 #5 手动归入桌子、差异预览、确认、整步撤销重做；源文件未改。")
	dock.queue_free()
	await process_frame
	quit(0)


func _runtime_equivalence(original: Dictionary, converted: Dictionary) -> void:
	var before := MapView.new()
	var after := MapView.new()
	root.add_child(before)
	root.add_child(after)
	before.build(MapDef.from_dictionary(original))
	after.build(MapDef.from_dictionary(converted))
	await physics_frame
	var original_shapes: Array[String] = []
	var converted_shapes: Array[String] = []
	_collect_shapes(before, original_shapes)
	_collect_shapes(after, converted_shapes)
	original_shapes.sort()
	converted_shapes.sort()
	assert(not original_shapes.is_empty() and original_shapes == converted_shapes)
	for player_y: float in [164.0, 166.0]:
		before.set_player_y(player_y)
		after.set_player_y(player_y)
		assert(before.cover_z(0) == after.cover_z(0))
	print("MapView 实际碰撞节点几何一致（%d 个），桌前/桌后遮挡层级一致。" % original_shapes.size())
	before.queue_free()
	after.queue_free()
	await process_frame


func _collect_shapes(node: Node, shapes: Array[String]) -> void:
	if node is CollisionShape2D and node.shape is RectangleShape2D:
		shapes.append(str(Rect2(node.global_position - node.shape.size * 0.5, node.shape.size)))
	for child: Node in node.get_children():
		_collect_shapes(child, shapes)


func _capture(filename: String) -> void:
	var directory := OS.get_environment("IF_MAP_EDITOR_SCREENSHOT_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var image := root.get_texture().get_image()
	assert(not image.is_empty() and image.save_png(directory.path_join(filename)) == OK)
