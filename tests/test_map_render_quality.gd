## 世界贴图的采样链回归：正式地图、主角全动画、演出人物与编辑器试走。
##
## 只读地图与原始帧图；检查最终继承的最近邻采样及原有坐标、45 像素标尺。
##
## 测试入口调用 run(h)。不改变项目默认过滤，不影响对话美术和其他界面。
extends RefCounted

const TextureSource := preload("res://scenes/map_texture_source.gd")


static func run(h: TestHarness) -> void:
	h.section("地图与角色像素采样")
	_check_atlas_sources(h)
	var main := h.new_main()
	_check_ui_defaults(h, main)
	var files := DirAccess.get_files_at(DataLoader.MAP_DIR)
	files.sort()
	var count := 0
	for filename: String in files:
		if not filename.ends_with(".json"):
			continue
		var id := StringName(filename.get_basename())
		var definition := DataLoader.load_map(id)
		h.check("%s 采样检查读取地图" % id, definition != null, true)
		if definition == null:
			continue
		count += 1
		var source := _geometry(definition)
		var spawn: StringName = definition.spawns.keys()[0] if not definition.spawns.is_empty() else &"default"
		main.enter_map(id, spawn)
		h.check("%s 采样不改变地图几何" % id, _geometry(main.current_map), source)
		h.check("%s 采样不改变出生点" % id, main.player.position, definition.spawn_point(spawn))
		h.check("%s 地图保持原坐标变换" % id, main.map_view.transform, Transform2D.IDENTITY)
		h.check("%s 地图根固定最近邻" % id, main.map_view.texture_filter,
			CanvasItem.TEXTURE_FILTER_NEAREST)
		_check_world_textures(h, main.map_view._built, str(id))
		var background := main.map_view._built.get_node_or_null("Background") as Sprite2D
		if background != null:
			h.check("%s 高清背景保留地图宽高" % id,
				(background.texture.get_size() * background.scale).is_equal_approx(Vector2(definition.size)), true)
			h.check("%s 高清背景保留地图原点" % id, background.position, Vector2.ZERO)
		h.check("%s 主角根固定最近邻" % id, main.player.texture_filter,
			CanvasItem.TEXTURE_FILTER_NEAREST)
		if definition.kind != MapDef.Kind.ROOM:
			continue
		_check_world_textures(h, main.player, "%s 主角" % id)
		_check_player_frames(h, main.player, main.camera.zoom, str(id))
		h.check("%s 演出世界固定最近邻" % id, main.stage_view.texture_filter,
			CanvasItem.TEXTURE_FILTER_NEAREST)
		var at: Vector2 = main.player.position + Vector2(24.0, 0.0)
		for recipe: Dictionary in [
			{"id": "animated", "sprite": "res://art/npc/a", "pose": "side"},
			{"id": "static", "sprite": "res://art/portrait/elder.png", "pose": ""},
		]:
			var actor: Node2D = main.cutscene.add_actor(str(recipe.id), str(recipe.sprite),
				at, 45.0, 9, str(recipe.pose))
			h.check("%s %s 演出贴图创建成功" % [id, recipe.id], actor != null, true)
			if actor != null:
				h.check("%s %s 演出脚底原坐标" % [id, recipe.id], actor.position, at)
		_check_world_textures(h, main.stage_view, "%s 演出" % id)
	h.check("采样回归覆盖正式地图", count > 0, true)
	main.queue_free()
	_check_editor_preview(h)


## UI 的 CanvasLayer 截断世界采样继承；使用临时子节点，不依赖立绘内部层级。
static func _check_ui_defaults(h: TestHarness, main: Node2D) -> void:
	h.check("游戏总根不强制像素采样", main.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE)
	var viewport := h.root as Viewport
	if viewport != null:
		h.check("UI视口默认采样仍为线性", viewport.canvas_item_default_texture_filter,
			Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
	var ui_canvas: CanvasLayer = main.dialogue
	h.check("对话界面保持独立画布", ui_canvas != null, true)
	var probe := TextureRect.new()
	ui_canvas.add_child(probe)
	h.check("对话画布子节点保持默认继承", probe.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE)
	h.check("对话画布不会继承地图或角色的最近邻", _effective_filter(probe),
		CanvasItem.TEXTURE_FILTER_PARENT_NODE)
	probe.free()


## 与引擎规则一致，遇到显式采样值即停止向父 CanvasItem 继承。
static func _effective_filter(item: CanvasItem) -> int:
	var current: Node = item
	while current != null:
		if current is CanvasLayer or current is Viewport:
			break
		if current is CanvasItem:
			var canvas := current as CanvasItem
			if canvas.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
				return canvas.texture_filter
		current = current.get_parent()
	return CanvasItem.TEXTURE_FILTER_PARENT_NODE


static func _check_world_textures(h: TestHarness, node: Node, label: String) -> void:
	if node.is_queued_for_deletion():
		return
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	var has_texture := false
	if node is Sprite2D:
		has_texture = (node as Sprite2D).texture != null
	elif node is AnimatedSprite2D:
		has_texture = (node as AnimatedSprite2D).sprite_frames != null
	elif node is TextureRect:
		has_texture = (node as TextureRect).texture != null
	if has_texture:
		h.check("%s %s 的最终采样为最近邻" % [label, node.name],
			_effective_filter(node as CanvasItem), CanvasItem.TEXTURE_FILTER_NEAREST)
	for child: Node in node.get_children():
		_check_world_textures(h, child, label)


static func _check_player_frames(h: TestHarness, player: Player, zoom: Vector2, label: String) -> void:
	var body := player.get_node("Body") as AnimatedSprite2D
	for animation: StringName in body.sprite_frames.get_animation_names():
		for frame: int in range(body.sprite_frames.get_frame_count(animation)):
			var texture := body.sprite_frames.get_frame_texture(animation, frame)
			h.check_float("%s %s/%d 保留45像素标尺" % [label, animation, frame],
				texture.get_height() * body.global_scale.y * zoom.y, 45.0)
			h.check("%s %s/%d 使用高清原帧" % [label, animation, frame], texture.get_height() > 45, true)


static func _geometry(definition: MapDef) -> Dictionary:
	var actors: Array = []
	for actor: MapDef.Actor in definition.actors:
		actors.append([actor.id, actor.rect, actor.reach, actor.collision_rects(), actor.effective_cover_y()])
	var portals: Array = []
	for portal: MapDef.Portal in definition.portals:
		portals.append([portal.id, portal.rect, portal.target_map, portal.target_spawn])
	return {"size": definition.size, "walls": definition.walls.duplicate(),
		"spawns": definition.spawns.duplicate(), "actors": actors, "portals": portals}


static func _check_editor_preview(h: TestHarness) -> void:
	var preview_script: Script = load("res://addons/if_map_editor/map_object_preview.gd")
	for id: String in ["desk_shop", "market"]:
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://data/maps/%s.json" % id))
		var panel: Control = preview_script.create_panel(source)
		h.root.add_child(panel)
		panel.auto_step = false
		h.check("%s 工具预览地图继承最近邻初始化" % id, panel.view.texture_filter,
			CanvasItem.TEXTURE_FILTER_NEAREST)
		h.check("%s 工具预览主角继承最近邻初始化" % id, panel.player.texture_filter,
			CanvasItem.TEXTURE_FILTER_NEAREST)
		_check_world_textures(h, panel.view._built, "%s 工具预览地图" % id)
		_check_world_textures(h, panel.player, "%s 工具预览主角" % id)
		panel.free()


static func _check_atlas_sources(h: TestHarness) -> void:
	var unrelated: Texture2D = load("res://art/player/down1.png")
	h.check("未标定纹理不被替换", TextureSource.resolve("res://art/player/down1.png", unrelated), unrelated)
	h.check("空纹理不生成缓存替代物", TextureSource.resolve("res://missing.png", null), null)
	var wrong_size := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	for path: String in TextureSource.MANIFEST:
		var entry: Dictionary = TextureSource.MANIFEST[path]
		h.check("%s 原尺寸变化时保留传入纹理" % path, TextureSource.resolve(path, wrong_size), wrong_size)
		var original: Texture2D = load(path)
		var resolved := TextureSource.resolve(path, original)
		h.check("%s 使用高清区域" % path, resolved is AtlasTexture, true)
		if not (resolved is AtlasTexture):
			continue
		var atlas := resolved as AtlasTexture
		h.check("%s 原图裁切框精确" % path, atlas.region, Rect2(entry.region))
		h.check("%s 高清区域保留真实大小" % path, atlas.get_size(), Vector2(entry.region.size))
		h.check("%s 高清图尺寸受校验" % path, atlas.atlas.get_size(), Vector2(entry.source_size))
		h.check("%s 裁切边缘不串色" % path, atlas.filter_clip, true)
		h.check("%s 成功区域复用同一缓存" % path, TextureSource.resolve(path, original), resolved)
		h.check("%s 已解析纹理不二次放大" % path, TextureSource.resolve(path, resolved), resolved)
	var test_path: String = TextureSource.MANIFEST.keys()[0]
	var test_entry: Dictionary = TextureSource.MANIFEST[test_path].duplicate(true)
	var cache_size: int = TextureSource._cache.size()
	test_entry["source_path"] = "res://art/map/missing_high_source.png"
	h.check("高清源缺失安全回退", TextureSource._load_source(test_entry), null)
	test_entry = TextureSource.MANIFEST[test_path].duplicate(true)
	test_entry["source_size"] = Vector2i.ONE
	h.check("高清源尺寸不符安全回退", TextureSource._load_source(test_entry), null)
	test_entry = TextureSource.MANIFEST[test_path].duplicate(true)
	test_entry["region"] = Rect2i(Vector2i(-1, 0), Vector2i(4, 4))
	h.check("高清源区域越界安全回退", TextureSource._load_source(test_entry), null)
	h.check("失败解析不污染成功缓存", TextureSource._cache.size(), cache_size)
	_check_atlas_geometry(h, test_path)


static func _check_atlas_geometry(h: TestHarness, path: String) -> void:
	var definition := MapDef.from_dictionary({"id": "atlas_geometry", "size": [320, 240],
		"overlay": path, "spawns": {"start": [160, 180]}})
	var view := MapView.new()
	h.root.add_child(view)
	view.build(definition)
	var overlay := view._built.get_node("Overlay") as Sprite2D
	h.check("前景层使用高清区域", overlay.texture is AtlasTexture, true)
	h.check("前景层仍保持整图原尺寸",
		(overlay.texture.get_size() * overlay.scale).is_equal_approx(Vector2(definition.size)), true)
	h.check("前景层仍保持原点", overlay.position, Vector2.ZERO)
	var rect := Rect2(40, 60, 70, 80)
	var prop := view._add_prop(path, rect, MapView.PROP_Z)
	h.check("高清物件保持原矩形位置", prop.position, rect.position)
	h.check("高清物件保持原矩形大小",
		(prop.texture.get_size() * prop.scale).is_equal_approx(rect.size), true)
	var original: Texture2D = load(path)
	for turns: int in [1, 3]:
		var actor := MapDef.Actor.new()
		actor.rect = rect
		actor.sprite = path
		actor.quarter_turns = turns
		actor.flip_h = turns == 1
		actor.flip_v = turns == 3
		var old_transform := actor.visual_texture_transform(0, original.get_size())
		view._add_actor(actor)
		var rendered := view._built.get_child(-1) as Sprite2D
		for uv: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
			var old_corner := old_transform * (original.get_size() * uv)
			var new_corner := rendered.transform * (rendered.texture.get_size() * uv)
			h.check("高清区域保留旋转翻转后的角点 %s/%s" % [turns, uv],
				new_corner.is_equal_approx(old_corner), true)
	view.free()
