## 统一世界层像素颗粒，并用脚边背景的低频颜色让人物融入环境。
##
## 只改变显示材质和接触阴影，不修改素材、地图布局、人物尺寸、碰撞或 UI。
## 背景缩略采样按资源缓存；人物每 0.12 秒更新一次，低通滤波避免移动时闪色。
##
## 游戏与编辑器试走共用本类。预置材质保持原样；每个人物拥有独立材质实例。
@tool
extends Node2D

## 背景和人物统一用细基格；阴影的尺寸与阶梯密度独立于细节设置。
const PIXEL := 0.25
const SHADOW_PIXEL := 0.5
const PIXEL_SHADER := preload("res://scenes/world_pixel.gdshader")
static var _samples: Dictionary = {}

var _sprite: Node2D
var _definition: MapDef
var _image: Image
var _material: ShaderMaterial
var _elapsed := 0.0
var _tint := Vector3.ONE
var _exposure := 1.0


static func style_map(node: Node, definition: MapDef) -> void:
	if node is Sprite2D and node.material == null:
		var sprite := node as Sprite2D
		var material := _make_material(sprite.texture, definition.player_scale)
		sprite.material = material
	for child: Node in node.get_children():
		style_map(child, definition)


static func style_actor(sprite: Node2D, definition: MapDef) -> void:
	var old := sprite.get_node_or_null("Environment")
	if old != null:
		sprite.remove_child(old)
		old.queue_free()
	if sprite.material != null and sprite.get_meta("world_look_material", null) != sprite.material:
		return
	var texture: Texture2D
	if sprite is AnimatedSprite2D:
		texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	elif sprite is Sprite2D:
		texture = sprite.texture
	if texture == null:
		return
	var look := load("res://scenes/world_look.gd").new() as Node2D
	look.name = "Environment"
	look._sprite = sprite
	look._definition = definition
	look._image = _background_sample(definition.background)
	look._material = _make_material(texture, definition.player_scale)
	look._material.set_shader_parameter("actor", true)
	# 背景与人物共用细基格，保留原画描边、五官和场景纹理。
	look._material.set_shader_parameter("cell_size", PIXEL * definition.player_scale)
	look._material.set_shader_parameter("saturation", 0.88)
	sprite.material = look._material
	sprite.set_meta("world_look_material", look._material)
	sprite.add_child(look)
	look.show_behind_parent = true
	look._update_environment(1.0)


static func _make_material(texture: Texture2D, map_scale: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PIXEL_SHADER
	material.set_shader_parameter("cell_size", PIXEL * map_scale)
	if texture is AtlasTexture:
		var size: Vector2 = texture.atlas.get_size()
		var region: Rect2 = texture.region
		material.set_shader_parameter("uv_bounds", Vector4(region.position.x / size.x,
			region.position.y / size.y, region.end.x / size.x, region.end.y / size.y))
	return material


static func _background_sample(path: String) -> Image:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _samples.has(path):
		return _samples[path]
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	image.resize(96, maxi(1, roundi(96.0 * image.get_height() / image.get_width())), Image.INTERPOLATE_LANCZOS)
	_samples[path] = image
	return image


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.12:
		return
	_update_environment(1.0 - exp(-_elapsed * 5.0))
	_elapsed = 0.0


func _update_environment(weight: float) -> void:
	# 阴影按统一逻辑尺寸绘制，抵消高清人物贴图自身的缩放。
	scale = Vector2.ONE * _definition.player_scale / _sprite.global_scale.abs()
	var color := Color(0.5, 0.5, 0.5)
	if _image != null:
		var uv := _sprite.global_position / Vector2(_definition.size)
		var center := Vector2i(uv * Vector2(_image.get_size()))
		color = Color(0, 0, 0)
		# 取脚边一片区域的均值，不追逐单块砖、草叶或灯芯的高频颜色。
		for y: int in range(-2, 3):
			for x: int in range(-2, 3):
				color += _image.get_pixel(clampi(center.x + x, 0, _image.get_width() - 1),
					clampi(center.y + y, 0, _image.get_height() - 1)) / 25.0
	var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	var neutral := maxf(luma, 0.04)
	var target := Vector3(clampf(color.r / neutral, 0.65, 1.35),
		clampf(color.g / neutral, 0.65, 1.35), clampf(color.b / neutral, 0.65, 1.35))
	_tint = _tint.lerp(Vector3.ONE.lerp(target, 0.28), weight)
	_exposure = lerpf(_exposure, clampf(0.72 + sqrt(luma) * 0.38, 0.76, 1.0), weight)
	_material.set_shader_parameter("ambient", _tint)
	_material.set_shader_parameter("exposure", _exposure)
	queue_redraw()


func _draw() -> void:
	# 像素阶梯椭圆，落在鞋底下方；随人物淡出并参与原有遮挡。
	for y: int in range(-5, 6):
		for x: int in range(-16, 17):
			var distance := pow(float(x) / 16.0, 2.0) + pow(float(y) / 5.0, 2.0)
			if distance < 1.0:
				draw_rect(Rect2(Vector2(x, y) * SHADOW_PIXEL + Vector2(0.0, -0.5), Vector2.ONE * SHADOW_PIXEL),
					Color(0.025, 0.02, 0.035, (1.0 - distance) * 0.32))
