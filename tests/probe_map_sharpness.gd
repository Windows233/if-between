## 最终窗口分辨率的地图清晰度诊断：直接读取正式根窗口的 GPU 渲染纹理。
##
## 不走 320×180 SubViewport，也不修改生产配置。窗口保持不获焦点、屏幕外和最小化；
## APPDATA 必须隔离为 if-between-map-sharpness-*，不读取或改写玩家设置与存档。
##
## <godot> --path <项目> --script res://tests/probe_map_sharpness.gd --
##   --sharpness-output=<绝对目录> --sharpness-maps=classroom,market,desk_shop --mode=after
## 必须使用真实 GPU 驱动；输出 1280×720 整帧、原尺寸裁片、nearest 放大图和 JSON。
## before 是在当前素材上强制恢复旧 LINEAR 采样的重现；after 使用未经探针改动的生产采样。
extends SceneTree

const FINAL_SIZE := Vector2i(1280, 720)
const FILTER_NAMES := ["inherit", "nearest", "linear", "nearest_mipmap", "linear_mipmap",
	"nearest_mipmap_anisotropic", "linear_mipmap_anisotropic"]
const VIEWPORT_FILTER_NAMES := ["nearest", "linear", "linear_mipmap", "nearest_mipmap", "inherit"]

var _h := TestHarness.new()
var _main: Node2D
var _output := "user://map_sharpness_probe"
var _maps: Array[StringName] = [&"classroom", &"market", &"desk_shop"]
var _mode := "after"


func _initialize() -> void:
	root.unfocusable = true
	root.position = Vector2i(-20000, -20000)
	root.mode = Window.MODE_MINIMIZED
	call_deferred("_run")


func _run() -> void:
	_h.setup(root)
	var appdata := OS.get_environment("APPDATA").replace("\\", "/").trim_suffix("/")
	_h.check("使用隔离 APPDATA", appdata.get_file().begins_with("if-between-map-sharpness-"), true)
	_h.check("使用真实图形驱动", DisplayServer.get_name() != "headless", true)
	if _h.failed > 0:
		_h.report()
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--sharpness-output="):
			_output = argument.trim_prefix("--sharpness-output=")
		elif argument.begins_with("--sharpness-maps="):
			_maps.clear()
			var requested := argument.trim_prefix("--sharpness-maps=")
			if requested == "all":
				for filename: String in DirAccess.get_files_at(DataLoader.MAP_DIR):
					if filename.ends_with(".json"):
						_maps.append(StringName(filename.get_basename()))
				_maps.sort()
			else:
				for id: String in requested.split(",", false):
					_maps.append(StringName(id))
		elif argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
	_h.check("采样模式有效", _mode in ["before", "after"], true)
	if _h.failed > 0:
		_h.report()
		quit(1)
		return
	_h.check("创建输出目录", DirAccess.make_dir_recursive_absolute(_output), OK)
	var settings := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
	settings.store_string(JSON.stringify({"display": "window", "window_size": "1280x720",
		"music_volume": 0.0, "sfx_volume": 0.0}))
	settings.close()
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	_main.start_at_title = false
	_main.debug_start_map = ""
	_main.free_roam_after_ending = false
	root.add_child(_main)
	_main.boot()
	_main.set_process(false)
	_main.set_process_unhandled_input(false)
	root.size = FINAL_SIZE
	root.position = Vector2i(-20000, -20000)
	root.mode = Window.MODE_MINIMIZED
	# 最小化窗口不交换桌面缓冲；仍强制更新正式根 viewport 的渲染目标。
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	var audit: Array[Dictionary] = []
	for id: StringName in _maps:
		var definition := DataLoader.load_map(id)
		_h.check("%s 正式地图可读取" % id, definition != null, true)
		if definition == null:
			continue
		var spawn: StringName = &"start"
		if not definition.spawns.has(spawn) and not definition.spawns.is_empty():
			spawn = definition.spawns.keys()[0]
		_main.enter_map(id, spawn)
		_main.player.pinned = true
		_main.update_player_control()
		_main.player.play_animation(false)
		_main.fade.fade_to(0.0, 0.0)
		_main.stage_curtain.snap_up()
		if _mode == "before":
			# 仅重现旧采样；素材仍来自当前工作树，不冒充旧版本完整画面。
			root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
			_main.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
			_inherit_world_filter(_main.map_view)
			_inherit_world_filter(_main.player)
			_inherit_world_filter(_main.stage_view)
		for frame: int in range(5):
			await process_frame
			_main.update_camera()
		RenderingServer.force_draw(false)
		var image := root.get_texture().get_image()
		_h.check("%s 最终窗口纹理非空" % id, image != null and not image.is_empty(), true)
		if image == null or image.is_empty():
			continue
		_h.check("%s 最终 GPU 帧为 1280×720" % id, image.get_size(), FINAL_SIZE)
		_h.check("%s 最终帧非单色" % id, _color_count(image) > 12, true)
		var full_path := _output.path_join("%s_final_1280x720.png" % id)
		_h.check("%s 保存最终画面" % id, image.save_png(full_path), OK)
		var body := _main.player.get_node("Body") as AnimatedSprite2D
		var background := _main.map_view.find_child("Background", true, false) as Sprite2D
		var texture := body.sprite_frames.get_frame_texture(body.animation, body.frame)
		var physical := root.get_stretch_transform() * body.get_global_transform_with_canvas()
		var top := physical * body.offset
		var bottom := physical * (body.offset + Vector2(0.0, texture.get_height()))
		var room := definition.kind == MapDef.Kind.ROOM
		_h.check("%s 主角可见性正确" % id, _main.player.visible, room)
		if room:
			_h.check_float("%s 主角最终显示高 180 物理像素" % id, top.distance_to(bottom), 180.0, 0.01)
		var character_center := (top + bottom) * 0.5 + physical.basis_xform(Vector2(texture.get_width() * 0.5, 0.0))
		var actor_region := _crop(image, character_center, Vector2i(192, 240), "%s_character" % id)
		var map_region := _crop(image, Vector2(image.get_width() * 0.25, image.get_height() * 0.35),
			Vector2i(256, 256), "%s_map" % id)
		var entry := {"map": str(id), "spawn": str(spawn), "mode": _mode,
			"filter_replay": _mode == "before",
			"map_size": _pair(Vector2(definition.size)), "map_scale": definition.player_scale,
			"camera_zoom": _pair(_main.camera.zoom), "camera": _pair(_main.camera.global_position),
			"player_world_position": _pair(_main.player.global_position),
			"render_texture_size": _pair(Vector2(image.get_size())),
			"character_physical_height": top.distance_to(bottom), "character_visible": _main.player.visible,
			"character_crop": actor_region, "map_crop": map_region,
			"frame": full_path, "player_texture": _sprite_info(body),
			"background_texture": _sprite_info(background) if background != null else {},
			"world_textures": _world_texture_audit(),
			"viewport": _viewport_info()}
		audit.append(entry)
		print("MAP_SHARPNESS %s render=%s mode=%s stretch=%s background=%s character=%s" % [
			id, image.get_size(), root.content_scale_mode, root.get_stretch_transform().get_scale(),
			entry.background_texture, entry.player_texture])
	var report := FileAccess.open(_output.path_join("sharpness_audit.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"display": DisplayServer.get_name(), "mode": _mode,
		"filter_replay": _mode == "before",
		"mode_note": "before replays legacy LINEAR filtering using current assets" if _mode == "before" else "after captures unmodified production filtering",
		"adapter": RenderingServer.get_video_adapter_name(), "viewport": _viewport_info(),
		"maps": audit, "passed": _h.passed, "failed": _h.failed}, "\t"))
	report.close()
	_main.queue_free()
	await process_frame
	quit(0 if _h.report() else 1)


func _viewport_info() -> Dictionary:
	return {"window_size": _pair(Vector2(root.size)),
		"visible_rect": _pair(root.get_visible_rect().size),
		"render_texture_size": _pair(root.get_texture().get_size()),
		"content_scale_size": _pair(Vector2(root.content_scale_size)),
		"content_scale_mode": root.content_scale_mode,
		"content_scale_factor": root.content_scale_factor,
		"default_texture_filter": root.canvas_item_default_texture_filter,
		"stretch_transform": _transform(root.get_stretch_transform()),
		"canvas_transform": _transform(root.canvas_transform),
		"final_transform": _transform(root.get_final_transform()),
		"project_stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode"),
		"project_default_filter": ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"),
		"renderer": RenderingServer.get_current_rendering_method()}


func _sprite_info(item: Node2D) -> Dictionary:
	var texture: Texture2D
	if item is Sprite2D:
		texture = (item as Sprite2D).texture
	elif item is AnimatedSprite2D:
		var animated := item as AnimatedSprite2D
		texture = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
	else:
		return {}
	var physical := root.get_stretch_transform() * item.get_global_transform_with_canvas()
	var physical_pixel := Vector2(physical.x.length(), physical.y.length())
	var filter: int = item.texture_filter
	var viewport_filter: int = root.canvas_item_default_texture_filter
	var effective := {"enum": viewport_filter, "name": VIEWPORT_FILTER_NAMES[viewport_filter],
		"source": "viewport"}
	var ancestor: Node = item
	while ancestor is CanvasItem:
		var own_filter: int = (ancestor as CanvasItem).texture_filter
		if own_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			effective = {"enum": own_filter, "name": FILTER_NAMES[own_filter], "source": str(ancestor.get_path())}
			break
		ancestor = ancestor.get_parent()
	var source := {"path": texture.resource_path}
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		source = {"path": atlas.atlas.resource_path, "kind": "atlas",
			"region": [atlas.region.position.x, atlas.region.position.y, atlas.region.size.x, atlas.region.size.y],
			"atlas_full_size": _pair(atlas.atlas.get_size())}
	return {"source": texture.resource_path, "source_details": source,
		"node": str(item.get_path()), "visible": item.is_visible_in_tree(),
		"source_size": _pair(texture.get_size()),
		"world_display_size": _pair(texture.get_size() * item.global_scale),
		"local_scale": _pair(item.scale), "global_scale": _pair(item.global_scale),
		"source_pixel_to_physical": _pair(physical_pixel),
		"source_pixels_per_screen_pixel_1280": _pair(Vector2.ONE / physical_pixel),
		"source_pixels_per_screen_pixel_1920": _pair(Vector2.ONE / (physical_pixel * 1.5)),
		"declared_filter": filter, "declared_filter_name": FILTER_NAMES[filter],
		"effective_filter": effective, "physical_transform": _transform(physical)}


func _world_texture_audit() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for branch: Node in [_main.map_view, _main.player, _main.stage_view]:
		_collect_textures(branch, out)
	return out


func _collect_textures(node: Node, out: Array[Dictionary]) -> void:
	if node is Sprite2D or node is AnimatedSprite2D:
		out.append(_sprite_info(node as Node2D))
	for child: Node in node.get_children():
		_collect_textures(child, out)


func _inherit_world_filter(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	for child: Node in node.get_children():
		_inherit_world_filter(child)


func _crop(image: Image, center: Vector2, size: Vector2i, stem: String) -> Dictionary:
	var origin := Vector2i(center) - size / 2
	origin.x = clampi(origin.x, 0, image.get_width() - size.x)
	origin.y = clampi(origin.y, 0, image.get_height() - size.y)
	var area := Rect2i(origin, size)
	var crop := image.get_region(area)
	var raw := _output.path_join(stem + "_crop.png")
	_h.check(stem + " 保存原始裁片", crop.save_png(raw), OK)
	crop.resize(size.x * 3, size.y * 3, Image.INTERPOLATE_NEAREST)
	var enlarged := _output.path_join(stem + "_crop_nearest3x.png")
	_h.check(stem + " 保存 nearest 放大裁片", crop.save_png(enlarged), OK)
	return {"rect": [origin.x, origin.y, size.x, size.y], "raw": raw, "nearest3x": enlarged}


func _pair(value: Vector2) -> Array:
	return [value.x, value.y]


func _transform(value: Transform2D) -> Dictionary:
	return {"x": _pair(value.x), "y": _pair(value.y), "origin": _pair(value.origin)}


func _color_count(image: Image) -> int:
	var colors: Dictionary = {}
	for column: int in range(24):
		for row: int in range(16):
			colors[image.get_pixel(column * image.get_width() / 24, row * image.get_height() / 16)] = true
	return colors.size()
