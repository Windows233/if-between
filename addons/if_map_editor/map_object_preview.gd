## 将未保存的布局放进独立视口，供编辑器内试走。
##
## 工具子类让运行时的绘制和移动方法也能在编辑器执行；物理世界独立。
##
## 保持运行时脚本不变，新增预览节点必须归属本窗口，关闭时一起释放。
@tool
extends Window

const MainScript := preload("res://scenes/main.gd")


class PreviewMapView:
	extends MapView


class PreviewPlayer:
	extends Player

	func _init() -> void:
		name = "Player"
		z_index = 10
		var collision := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = FOOT_SIZE
		collision.shape = box
		collision.position = Vector2(0.0, FOOT_OFFSET)
		add_child(collision)
		var frames := build_frames()
		if frames != null:
			_sprite = AnimatedSprite2D.new()
			_sprite.name = "Body"
			_sprite.sprite_frames = frames
			_sprite.centered = false
			var first := frames.get_frame_texture(&"idle_down", 0)
			var frame_size := first.get_size() if first != null else BODY_SIZE
			_sprite.scale = Vector2.ONE * DISPLAY_HEIGHT / maxf(frame_size.y, 1.0)
			_sprite.offset = Vector2(-frame_size.x * 0.5, -frame_size.y)
			add_child(_sprite)
			play_animation(false)
			return
		var body := Polygon2D.new()
		var half_width := BODY_SIZE.x * 0.5
		body.polygon = PackedVector2Array([
			Vector2(-half_width, -BODY_SIZE.y), Vector2(half_width, -BODY_SIZE.y),
			Vector2(half_width, 0.0), Vector2(-half_width, 0.0),
		])
		body.color = BODY_COLOR
		add_child(body)


class PreviewRanges:
	extends Node2D

	var definition: MapDef
	var collision_shapes: Array[CollisionShape2D] = []

	func _draw() -> void:
		for collision: CollisionShape2D in collision_shapes:
			var box := collision.shape as RectangleShape2D
			if box == null:
				continue
			var rect := collision.global_transform * Rect2(-box.size * 0.5, box.size)
			draw_rect(rect, Color(0.1, 0.85, 0.9, 0.12))
			draw_rect(rect, Color(0.1, 0.85, 0.9, 0.8), false, 1.0)
		for actor: MapDef.Actor in definition.active_actors(null):
			if not actor.decor:
				draw_rect(actor.reach, Color(1.0, 0.8, 0.2, 0.7), false, 1.0)


var definition: MapDef
var view: MapView
var player: Player
var _hint: Label
var _range_toggle: CheckBox
var _ranges: PreviewRanges
var _pressed := false


## 从当前内存中的地图数据构造预览；不读取或保存正式地图。
func configure(data: Dictionary) -> void:
	definition = MapDef.from_dictionary(data)
	title = "场景试走：%s" % definition.id
	size = Vector2i(1100, 720)
	close_requested.connect(queue_free)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	_hint = Label.new()
	_hint.text = "WASD / 方向键试走；空格检查交互目标。使用当前未保存布局，不执行剧情。"
	layout.add_child(_hint)
	_range_toggle = CheckBox.new()
	_range_toggle.text = "显示碰撞/交互区"
	_range_toggle.tooltip_text = "青色：实体碰撞；黄色：交互框，交互还受距离与朝向限制。"
	_range_toggle.focus_mode = Control.FOCUS_NONE
	_range_toggle.toggled.connect(_set_ranges_visible)
	layout.add_child(_range_toggle)
	var display := SubViewportContainer.new()
	display.stretch = true
	display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(display)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1100, 680)
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	display.add_child(viewport)
	view = PreviewMapView.new()
	viewport.add_child(view)
	view.build(definition)
	player = PreviewPlayer.new()
	player.scale = Vector2.ONE * definition.player_scale
	viewport.add_child(player)
	player.set_physics_process(false)
	player.position = definition.spawn_point(&"start")
	if not definition.spawns.is_empty():
		player.position = definition.spawns.values()[0]
	_ranges = PreviewRanges.new()
	_ranges.definition = definition
	_ranges.z_index = 100
	_collect_collision_shapes(view)
	_collect_collision_shapes(player)
	viewport.add_child(_ranges)
	_ranges.hide()
	var camera := Camera2D.new()
	camera.position = Vector2(definition.size) * 0.5
	var fit := minf(1060.0 / definition.size.x, 640.0 / definition.size.y)
	camera.zoom = Vector2.ONE * fit
	viewport.add_child(camera)


func _physics_process(delta: float) -> void:
	if player == null or not visible or not has_focus():
		return
	player._physics_process(delta)
	view.set_player_y(player.global_position.y)
	if is_instance_valid(_ranges) and _ranges.visible:
		_ranges.queue_redraw()
	var pressed := Input.is_physical_key_pressed(KEY_SPACE)
	if pressed and not _pressed:
		var actor := definition.actor_near(player.global_position, MainScript.INTERACT_RANGE, null, player.facing)
		_hint.text = "交互目标：%s [%s]（仅检查，不执行剧情）" % [actor.label, actor.id] if actor != null else "当前位置和朝向没有可交互目标。"
	_pressed = pressed


func _collect_collision_shapes(node: Node) -> void:
	if node is CollisionShape2D:
		var collision := node as CollisionShape2D
		collision.hide()
		_ranges.collision_shapes.append(collision)
	for child: Node in node.get_children():
		_collect_collision_shapes(child)


func _set_ranges_visible(enabled: bool) -> void:
	if is_instance_valid(_ranges):
		_ranges.visible = enabled
		_ranges.queue_redraw()
