## 真实 GPU 验证世界像素格、透明叠层及翻转图集边界，并保存编辑器试走画面。
##
## 独立 APPDATA 必须以 if-between-world-look- 开头；窗口隐藏且不抢焦点。
## godot --path . --script res://tests/probe_world_look.gd -- --output=<目录>
extends SceneTree

const Look := preload("res://scenes/world_look.gd")
const Preview := preload("res://addons/if_map_editor/map_object_preview.gd")
var _h := TestHarness.new()
var _output := "user://world_look_probe"


func _initialize() -> void:
	root.unfocusable = true
	root.position = Vector2i(-20000, -20000)
	root.mode = Window.MODE_MINIMIZED
	_run.call_deferred()


func _run() -> void:
	_h.setup(root)
	_h.check("探针使用隔离数据目录", OS.get_environment("APPDATA").replace("\\", "/").get_file().begins_with("if-between-world-look-"), true)
	_h.check("探针使用真实GPU", DisplayServer.get_name() != "headless", true)
	if _h.failed > 0:
		_h.report()
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(_output)
	root.size = Vector2i(256, 128)
	root.content_scale_size = root.size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	var texture_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in 64:
		for x: int in 64:
			texture_image.set_pixel(x, y, Color(float((x * 13 + y * 3) % 31) / 31.0,
				float((x * 5 + y * 17) % 29) / 29.0, 0.3))
	var texture := ImageTexture.create_from_image(texture_image)
	for ratio: float in [0.25, 0.5, 1.0, 2.0]:
		var definition := MapDef.new()
		definition.player_scale = ratio
		var container := Node2D.new()
		root.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * 4.0 / ratio)
		root.add_child(container)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2.ONE * ratio / 4.0
		sprite.position = Vector2.ONE * 2.0 * ratio
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		container.add_child(sprite)
		Look.style_map(sprite, definition)
		var frame := await _capture()
		var fine_details := true
		for y: int in range(64):
			for x: int in range(64):
				var actual := frame.get_pixel(x + 8, y + 8)
				var expected := texture_image.get_pixel(x, y)
				fine_details = fine_details and absf(actual.r - expected.r) <= 1.0 / 255.0 \
					and absf(actual.g - expected.g) <= 1.0 / 255.0
		_h.check("标尺%s GPU保留逐像素细节" % ratio, fine_details, true)
		# 同源半透明前景叠回底图必须逐像素无差，含透明边界。
		var overlay_image: Image = texture_image.duplicate()
		for y: int in 64:
			for x: int in range(32):
				var color := overlay_image.get_pixel(x, y)
				color.a = 0.0
				overlay_image.set_pixel(x, y, color)
		var overlay := Sprite2D.new()
		overlay.texture = ImageTexture.create_from_image(overlay_image)
		overlay.centered = false
		overlay.transform = sprite.transform
		overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		container.add_child(overlay)
		Look.style_map(overlay, definition)
		var composite := await _capture()
		_h.check("标尺%s透明前景与底图无接缝" % ratio,
			frame.get_region(Rect2i(8, 8, 64, 64)).get_data(), composite.get_region(Rect2i(8, 8, 64, 64)).get_data())
		# 图集一侧鲜绿作为串色哨兵，另一侧红色；翻转和旋转后仍不能采到绿边。
		var atlas_image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
		atlas_image.fill(Color.GREEN)
		atlas_image.fill_rect(Rect2i(0, 0, 32, 32), Color.RED)
		var atlas := AtlasTexture.new()
		atlas.atlas = ImageTexture.create_from_image(atlas_image)
		atlas.region = Rect2(0, 0, 32, 32)
		var prop := Sprite2D.new()
		prop.texture = atlas
		prop.scale = Vector2(-ratio / 4.0, ratio / 4.0)
		prop.position = Vector2(30, 12) * ratio
		prop.rotation = 0.25
		prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		container.add_child(prop)
		Look.style_map(prop, definition)
		var atlas_frame := await _capture()
		var red := 0
		var green := 0
		for y: int in range(24, 72):
			for x: int in range(96, 144):
				var color := atlas_frame.get_pixel(x, y)
				if color.r > 0.9 and color.g < 0.1:
					red += 1
				if color.g > 0.9 and color.r < 0.1:
					green += 1
		_h.check("标尺%s旋转翻转图集可见" % ratio, red > 500, true)
		_h.check("标尺%s图集无邻区绿边" % ratio, green, 0)
		container.free()
	# 人物染色要在 GPU 生效，节点原有的 modulate/alpha 也必须保留。
	root.canvas_transform = Transform2D.IDENTITY
	var blank := await _capture()
	var white := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var actor := Sprite2D.new()
	actor.texture = ImageTexture.create_from_image(white)
	actor.centered = false
	actor.material = Look._make_material(actor.texture, 1.0)
	actor.material.set_shader_parameter("actor", true)
	actor.material.set_shader_parameter("ambient", Vector3(0.8, 0.9, 1.0))
	actor.material.set_shader_parameter("exposure", 0.8)
	root.add_child(actor)
	var themed := (await _capture()).get_pixel(16, 16)
	_h.check("人物GPU色温有效", themed.b > themed.g and themed.g > themed.r, true)
	_h.check("人物GPU曝光有效", themed.b < 0.9, true)
	actor.modulate = Color(0.5, 0.5, 0.5, 1.0)
	var modulated := (await _capture()).get_pixel(16, 16)
	_h.check("人物保留演出modulate", modulated.r < themed.r * 0.7, true)
	actor.modulate = Color(1, 1, 1, 0)
	var faded := (await _capture()).get_pixel(16, 16)
	_h.check("人物完全淡出后无残留", faded, blank.get_pixel(16, 16))
	actor.free()
	# 背景细节整理不能给整张图调色：平坦区域逐色不变，边缘增强且保留 RGB 比例。
	var steps := Image.create(32, 16, false, Image.FORMAT_RGB8)
	steps.fill(Color(0.2, 0.3, 0.4))
	steps.fill_rect(Rect2i(16, 0, 16, 16), Color(0.1, 0.15, 0.2))
	var detail_sprite := Sprite2D.new()
	detail_sprite.texture = ImageTexture.create_from_image(steps)
	detail_sprite.centered = false
	detail_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	detail_sprite.material = Look._make_material(detail_sprite.texture, 1.0)
	root.add_child(detail_sprite)
	var unprocessed := await _capture()
	detail_sprite.material.set_shader_parameter("detail_strength", 0.6)
	var processed := await _capture()
	_h.check("边缘整理保留平坦区域原色", processed.get_pixel(8, 8), unprocessed.get_pixel(8, 8))
	_h.check("边缘整理强化已有明暗边界", processed.get_pixel(15, 8).b > unprocessed.get_pixel(15, 8).b
		and processed.get_pixel(16, 8).b < unprocessed.get_pixel(16, 8).b, true)
	var edge := processed.get_pixel(15, 8)
	var original_edge := unprocessed.get_pixel(15, 8)
	_h.check("边缘整理保留原色RGB比例", absf(edge.r / edge.b - original_edge.r / original_edge.b) < 0.015
		and absf(edge.g / edge.b - original_edge.g / original_edge.b) < 0.015, true)
	detail_sprite.free()
	# 真实编辑器独立物理视口，确认工具模式共用材质且最终画面非空。
	root.canvas_transform = Transform2D.IDENTITY
	root.size = Vector2i(1100, 720)
	root.content_scale_size = root.size
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/dead_alley.json"))
	var panel: Control = Preview.create_panel(data)
	root.add_child(panel)
	panel.size = Vector2(1100, 720)
	panel.auto_step = false
	var native_background := panel.view._built.get_node("Background") as Sprite2D
	_h.check("试走实际保留后巷原图", native_background.texture.resource_path, str(data.background))
	var preview_frame := await _capture()
	_h.check("试走截图保存", preview_frame.save_png(_output.path_join("dead_alley_preview.png")), OK)
	_h.check("试走背景可渲染", panel.view._built.get_node("Background").material is ShaderMaterial, true)
	_h.check("试走人物环境节点可运行", panel.player.get_node("Body/Environment").is_processing(), true)
	panel.set_options({"show_ranges": true})
	var collision_frame := await _capture()
	_h.check("重绘的现有碰撞/交互区截图保存", collision_frame.save_png(_output.path_join("dead_alley_collision_review.png")), OK)
	panel.player.position = Vector2(191, 65)
	panel.advance(0.0)
	var gate_frame := await _capture()
	_h.check("重绘铁门的现有碰撞/交互区截图保存", gate_frame.save_png(_output.path_join("dead_alley_gate_review.png")), OK)
	panel.free()
	var report := FileAccess.open(_output.path_join("gpu_report.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": _h.passed, "failed": _h.failed,
		"adapter": RenderingServer.get_video_adapter_name()}, "\t"))
	report.close()
	quit(0 if _h.report() else 1)


func _capture() -> Image:
	for i: int in 4:
		await process_frame
	RenderingServer.force_draw(false)
	return root.get_texture().get_image()
