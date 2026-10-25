## 世界像素标尺与人物环境融合的行为回归。
##
## 合成明暗背景只写 user://；检查跨地图、移动、NPC、编辑器及自定义材质。
## GPU 实际取样、透明边界及图集串色另由 probe_world_look.gd 检查。
extends RefCounted

const Look := preload("res://scenes/world_look.gd")
const Preview := preload("res://addons/if_map_editor/map_object_preview.gd")


static func run(h: TestHarness) -> void:
	h.section("人物与环境统一表现")
	var main := h.new_main()
	main.enter_map(&"dead_alley", &"from_overworld")
	var body := main.player.get_node("Body") as AnimatedSprite2D
	var material := body.material as ShaderMaterial
	h.check("主角启用独立环境材质", material != null, true)
	if material == null:
		main.queue_free()
		return
	var original_position: Vector2 = main.player.position
	var original_scale: Vector2 = main.player.scale
	var environment := body.get_node("Environment")
	h.check("人物接触阴影位于人物之后", environment.show_behind_parent, true)
	h.check_float("阴影保持统一逻辑宽度", environment.global_scale.x / original_scale.x, 1.0)
	h.check("暗场人物适度压亮", float(material.get_shader_parameter("exposure")) < 1.0, true)
	h.check("暗场人物不过暗", float(material.get_shader_parameter("exposure")) >= 0.76, true)
	var actor: Node2D = main.cutscene.add_actor("look_test", "res://art/npc/a", original_position, 45)
	h.check("演出人物复用环境处理", actor.get_node_or_null("Environment") != null, true)
	h.check("不同人物使用独立材质", actor.material != material, true)
	h.check_float("主角和NPC像素基格一致", actor.material.get_shader_parameter("cell_size"),
		material.get_shader_parameter("cell_size"))
	main.player.configure_environment(main.current_map)
	h.check("重复配置只保留一个环境节点", body.get_child_count(), 1)
	h.check("滤镜保留人物位置", main.player.position, original_position)
	h.check("滤镜保留人物标尺", main.player.scale, original_scale)
	var custom := CanvasItemMaterial.new()
	body.material = custom
	main.player.configure_environment(main.current_map)
	h.check("显式自定义材质不被覆盖", body.material, custom)
	h.check("自定义材质不残留自动阴影", body.get_node_or_null("Environment"), null)
	main.queue_free()
	_check_terrain(h)
	_check_original_style(h)
	_check_lighting(h)
	_check_preview(h)


static func _check_terrain(h: TestHarness) -> void:
	for ratio: float in [0.25, 0.5, 1.0, 2.0]:
		var definition := MapDef.new()
		definition.player_scale = ratio
		var sprite := Sprite2D.new()
		sprite.texture = load("res://art/player/down1.png")
		sprite.rotation = 0.3
		sprite.scale = Vector2(-0.5, 0.75)
		var original := sprite.transform
		Look.style_map(sprite, definition)
		h.check_float("标尺%s投影后地图颗粒恒为0.25" % ratio,
			sprite.material.get_shader_parameter("cell_size") / ratio, 0.25)
		h.check("标尺%s不改变旋转翻转" % ratio, sprite.transform, original)
		var custom := CanvasItemMaterial.new()
		sprite.material = custom
		Look.style_map(sprite, definition)
		h.check("地图预设材质保留", sprite.material, custom)
		sprite.free()


static func _check_original_style(h: TestHarness) -> void:
	var source := preload("res://scenes/map_texture_source.gd")
	var path := "res://art/background/chapter2_dead_alley.png"
	var original: Texture2D = load(path)
	var resolved := source.resolve(path, original)
	h.check("后巷撤下改变色调的重绘替换", source.PIXEL_REPAINTS.has(path), false)
	h.check("后巷直接保留原画资源", resolved, original)
	var changed := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	h.check("用户换了不同尺寸原图时保留其纹理", source.resolve(path, changed), changed)
	var missing := {"source_path": "res://art/background/missing_pixel_repaint.png"}
	h.check("像素重绘缺失时可回退", source._load_source(missing), null)
	var canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd").new()
	h.check("编辑画布保留原画", canvas._load_tex(path), original)
	canvas.free()
	var main := h.new_main()
	main.enter_map(&"dead_alley", &"from_overworld")
	var background := main.map_view._built.get_node("Background") as Sprite2D
	h.check("游戏背景保留原画", background.texture, original)
	h.check("显示整理保留地图世界范围", background.texture.get_size() * background.scale, Vector2(main.current_map.size))
	h.check("后巷原画启用有限边缘整理", float(background.material.get_shader_parameter("detail_strength")) > 0.0, true)
	h.check("主角不套背景边缘整理", Look._make_material(load("res://art/player/down1.png"), 1.0).get_shader_parameter("detail_strength"), 0.0)
	h.check("其他地图不套背景边缘整理", Look._make_material(load(source.MARKET_DAY), 1.0).get_shader_parameter("detail_strength"), 0.0)
	var sample := Look._background_sample(path)
	var expected := resolved.get_image()
	expected.resize(sample.get_width(), sample.get_height(), Image.INTERPOLATE_LANCZOS)
	h.check("人物环境色继续来自原画", sample.get_data(), expected.get_data())
	main.queue_free()


static func _check_lighting(h: TestHarness) -> void:
	var dir := "user://look_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for entry: Array in [["dark", Color(0.05, 0.08, 0.14)], ["bright", Color(0.85, 0.75, 0.6)]]:
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		image.fill(entry[1])
		image.save_png(dir.path_join(str(entry[0]) + ".png"))
	var definition := MapDef.new()
	definition.size = Vector2i(320, 180)
	# user:// PNG 未导入，因此将合成缩略图注入采样缓存，运行时路径仍只读正式资源。
	definition.background = DataLoader.load_map(&"bedroom").background
	var saved: Variant = Look._samples.get(definition.background)
	var colors: Array[Vector3] = []
	var exposures: Array[float] = []
	for name: String in ["dark", "bright"]:
		Look._samples[definition.background] = Image.load_from_file(dir.path_join(name + ".png"))
		var player := Player.create()
		h.root.add_child(player)
		player.configure_environment(definition)
		var body := player.get_node("Body")
		colors.append(body.material.get_shader_parameter("ambient"))
		exposures.append(body.material.get_shader_parameter("exposure"))
		player.free()
	h.check("暗背景中的人物曝光低于亮背景", exposures[0] < exposures[1], true)
	h.check("冷背景染冷色", colors[0].z > colors[0].x, true)
	h.check("暖背景染暖色", colors[1].x > colors[1].z, true)
	if saved == null:
		Look._samples.erase(definition.background)
	else:
		Look._samples[definition.background] = saved
	for name: String in ["dark", "bright"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(name + ".png")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


static func _check_preview(h: TestHarness) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/dead_alley.json"))
	var panel: Control = Preview.create_panel(data)
	h.root.add_child(panel)
	panel.auto_step = false
	var body: AnimatedSprite2D = panel.player.get_node("Body")
	h.check("试走主角环境节点存在", body.get_node_or_null("Environment") != null, true)
	h.check_float("试走背景颗粒与游戏一致",
		panel.view._built.get_node("Background").material.get_shader_parameter("cell_size"),
		Look.PIXEL * panel.definition.player_scale)
	h.check_float("试走人物颗粒与游戏一致", body.material.get_shader_parameter("cell_size"),
		Look.PIXEL * panel.definition.player_scale)
	panel.free()
