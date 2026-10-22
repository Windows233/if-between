@tool
extends Window

const MainScript := preload("res://scenes/main.gd")

var definition: MapDef
var view: MapView
var player: Player
var _hint: Label
var _pressed := false


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
	var display := SubViewportContainer.new()
	display.stretch = true
	display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(display)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1100, 680)
	viewport.own_world_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	display.add_child(viewport)
	view = MapView.new()
	viewport.add_child(view)
	view.build(definition)
	player = Player.create()
	player.set_physics_process(false)
	player.scale = Vector2.ONE * definition.player_scale
	viewport.add_child(player)
	player.position = definition.spawn_point(&"start")
	if not definition.spawns.is_empty():
		player.position = definition.spawns.values()[0]
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
	var pressed := Input.is_physical_key_pressed(KEY_SPACE)
	if pressed and not _pressed:
		var actor := definition.actor_near(player.global_position, MainScript.INTERACT_RANGE, null, player.facing)
		_hint.text = "交互目标：%s [%s]（仅检查，不执行剧情）" % [actor.label, actor.id] if actor != null else "当前位置和朝向没有可交互目标。"
	_pressed = pressed
