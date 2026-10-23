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

	func clear() -> void:
		if is_instance_valid(_built):
			_built.free()
			_built = null
		super.clear()


class PreviewPlayer:
	extends Player

	func _init() -> void:
		name = "Player"
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	var flags: WorldState
	var collision_shapes: Array[CollisionShape2D] = []

	func _draw() -> void:
		for collision: CollisionShape2D in collision_shapes:
			var box := collision.shape as RectangleShape2D
			if box == null:
				continue
			var rect := collision.global_transform * Rect2(-box.size * 0.5, box.size)
			draw_rect(rect, Color(0.1, 0.85, 0.9, 0.12))
			draw_rect(rect, Color(0.1, 0.85, 0.9, 0.8), false, 1.0)
		for actor: MapDef.Actor in definition.active_actors(flags):
			if not actor.decor:
				draw_rect(actor.reach, Color(1.0, 0.8, 0.2, 0.7), false, 1.0)
		for portal: MapDef.Portal in definition.active_portals(flags):
			draw_rect(portal.rect, Color(0.5, 1.0, 0.5, 0.7), false, 1.0)


class PreviewPanel:
	extends VBoxContainer

	var definition: MapDef
	var view: MapView
	var player: Player
	var flags := WorldState.new()
	var options: Dictionary = {}
	var auto_step := true
	var blocked := false
	var _hint: Label
	var _warning: Label
	var _range_toggle: CheckBox
	var _ranges: PreviewRanges
	var _camera: Camera2D
	var _display: SubViewportContainer
	var _pressed := false
	var _source: Dictionary = {}

	func configure(data: Dictionary, settings: Dictionary = {}) -> void:
		_source = data.duplicate(true)
		definition = MapDef.from_dictionary(_source)
		if view == null:
			_build()
		(get_node("MapName") as Label).text = "%s [%s]" % [_source.get("name", definition.id), definition.id]
		options = {}
		set_options(settings, true)

	func _build() -> void:
		name = "MapPreview"
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		var caption := Label.new()
		caption.name = "MapName"
		caption.custom_minimum_size.x = 200
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.text = "%s [%s]" % [_source.get("name", definition.id), definition.id]
		add_child(caption)
		_hint = Label.new()
		_hint.custom_minimum_size.x = 200
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint.text = "WASD / 方向键试走；空格检查交互目标。使用未保存布局，仅检查，不执行剧情。"
		add_child(_hint)
		_warning = Label.new()
		_warning.custom_minimum_size.x = 200
		_warning.name = "BlockedWarning"
		_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_warning.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25))
		add_child(_warning)
		_range_toggle = CheckBox.new()
		_range_toggle.text = "显示碰撞/交互区"
		_range_toggle.tooltip_text = "青色：实体碰撞；黄色：交互框；绿色：连接。使用真实状态条件。"
		_range_toggle.focus_mode = Control.FOCUS_NONE
		_range_toggle.toggled.connect(_set_ranges_visible)
		add_child(_range_toggle)
		_display = SubViewportContainer.new()
		_display.stretch = true
		_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(_display)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1100, 680)
		viewport.world_2d = World2D.new()
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_display.add_child(viewport)
		view = PreviewMapView.new()
		viewport.add_child(view)
		player = PreviewPlayer.new()
		viewport.add_child(player)
		player.set_physics_process(false)
		_ranges = PreviewRanges.new()
		_ranges.z_index = 100
		viewport.add_child(_ranges)
		_ranges.hide()
		_camera = Camera2D.new()
		viewport.add_child(_camera)
		_display.resized.connect(_fit_camera)

	func set_options(settings: Dictionary, reset_spawn := false) -> void:
		var previous_spawn: String = str(options.get("spawn", ""))
		options.merge(settings.duplicate(true), true)
		flags = WorldState.new()
		var values: Variant = options.get("flags", {})
		if values is Dictionary:
			for key: Variant in values:
				flags.set_value(StringName(str(key)), values[key])
		view.build(definition, flags)
		player.scale = Vector2.ONE * definition.player_scale
		player.visible = definition.kind == MapDef.Kind.ROOM
		if reset_spawn or (settings.has("spawn") and str(settings.spawn) != previous_spawn):
			var spawn := StringName(str(options.get("spawn", "start")))
			if not definition.spawns.has(spawn) and not definition.spawns.is_empty():
				spawn = definition.spawns.keys()[0]
			player.position = definition.spawn_point(spawn)
		player.walk_path.clear()
		player.velocity = Vector2.ZERO
		_ranges.definition = definition
		_ranges.flags = flags
		_ranges.collision_shapes.clear()
		_collect_collision_shapes(view)
		_collect_collision_shapes(player)
		_range_toggle.set_pressed_no_signal(bool(options.get("show_ranges", _range_toggle.button_pressed)))
		_set_ranges_visible(_range_toggle.button_pressed)
		_fit_camera()
		view.set_player_y(player.position.y)
		_update_blocked()
		_pressed = false
		if bool(options.get("read_only", false)):
			_hint.text = "只读比较；显示真实条件、碰撞与交互区，不执行移动或剧情。"
		else:
			_hint.text = "WASD / 方向键试走；空格检查交互目标。使用未保存布局，仅检查，不执行剧情。"

	func _fit_camera() -> void:
		if _camera == null:
			return
		var available := _display.size if _display.size.x > 1.0 and _display.size.y > 1.0 else Vector2(1060, 640)
		if definition.kind == MapDef.Kind.OVERWORLD:
			_camera.zoom = GameCamera.zoom_for(Vector2(definition.size), available)
			_camera.position = Vector2(definition.size) * 0.5
			return
		# 试走与游戏共用人物标尺；面板大小只决定统一的显示倍率，不再按各图适配全图。
		var logical_view := GameCamera.view_size()
		var fit := minf(available.x / logical_view.x, available.y / logical_view.y)
		_camera.zoom = GameCamera.room_zoom_for(definition.player_scale) * fit
		_camera.position = GameCamera.position_for(player.position,
			Vector2(definition.size), available / _camera.zoom)

	func _update_blocked() -> void:
		blocked = false
		if definition.kind == MapDef.Kind.ROOM:
			var foot := player.get_child(0) as CollisionShape2D
			var shape := foot.shape as RectangleShape2D
			var footprint := foot.global_transform * Rect2(-shape.size * 0.5, shape.size)
			for collision: CollisionShape2D in _ranges.collision_shapes:
				if collision.get_parent() == player or collision.disabled:
					continue
				var box := collision.shape as RectangleShape2D
				if box != null and footprint.intersects(collision.global_transform * Rect2(-box.size * 0.5, box.size)):
					blocked = true
					break
		_warning.text = "警告：当前状态的碰撞挡住了角色。保留原位置；请调整状态或选择其他出生点。" if blocked else ""
		_warning.visible = blocked

	func inspect_interaction() -> String:
		var actor := definition.actor_near(player.global_position, MainScript.INTERACT_RANGE, flags, player.facing)
		if actor != null:
			_hint.text = "交互目标：%s [%s]（仅检查，不执行剧情）" % [actor.label, actor.id]
		else:
			var portal := definition.portal_at(player.global_position, flags)
			if portal != null:
				var locked := not portal.blocked_by.is_empty() and bool(flags.get_value(StringName(portal.blocked_by), false))
				_hint.text = "连接：%s [%s]%s（仅检查，不传送、不执行剧情）" % [
					portal.label, portal.id, "；门禁：" + portal.blocked_text if locked else ""]
			else:
				_hint.text = "当前位置和朝向没有可交互目标。"
		return _hint.text

	func advance(delta: float) -> void:
		if player == null or not is_visible_in_tree() or not get_window().has_focus():
			return
		if bool(options.get("read_only", false)) or definition.kind != MapDef.Kind.ROOM:
			return
		_update_blocked()
		if not blocked:
			player._physics_process(delta)
		_fit_camera()
		view.set_player_y(player.global_position.y)
		if _ranges.visible:
			_ranges.queue_redraw()
		var pressed := Input.is_physical_key_pressed(KEY_SPACE)
		if pressed and not _pressed:
			inspect_interaction()
		_pressed = pressed

	func _physics_process(delta: float) -> void:
		if auto_step:
			advance(delta)

	func _collect_collision_shapes(node: Node) -> void:
		if node is CollisionShape2D:
			var collision := node as CollisionShape2D
			collision.hide()
			_ranges.collision_shapes.append(collision)
		for child: Node in node.get_children():
			_collect_collision_shapes(child)

	func _set_ranges_visible(enabled: bool) -> void:
		options["show_ranges"] = enabled
		if is_instance_valid(_ranges):
			_ranges.visible = enabled
			_ranges.queue_redraw()


var definition: MapDef
var view: MapView
var player: Player
var _hint: Label
var _range_toggle: CheckBox
var _ranges: PreviewRanges
var _pressed := false
var panel: PreviewPanel
var flags: WorldState
var options: Dictionary = {}


## 从当前内存中的地图数据构造预览；不读取或保存正式地图。
func configure(data: Dictionary, settings: Dictionary = {}) -> void:
	if panel == null:
		panel = PreviewPanel.new()
		panel.auto_step = false
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(panel)
		size = Vector2i(1100, 720)
		close_requested.connect(queue_free)
	panel.configure(data, settings)
	_sync_panel()
	title = "场景试走：%s" % definition.id


func set_options(settings: Dictionary) -> void:
	panel.set_options(settings)
	_sync_panel()


func _sync_panel() -> void:
	definition = panel.definition
	view = panel.view
	player = panel.player
	flags = panel.flags
	options = panel.options
	_hint = panel._hint
	_range_toggle = panel._range_toggle
	_ranges = panel._ranges


static func create_panel(data: Dictionary, settings: Dictionary = {}) -> PreviewPanel:
	var result := PreviewPanel.new()
	result.configure(data, settings)
	return result


static func create_comparison(data: Dictionary, other_data: Dictionary,
		settings: Dictionary = {}, other_settings: Dictionary = {}) -> HSplitContainer:
	var split := HSplitContainer.new()
	split.name = "MapComparison"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_options := settings.duplicate(true)
	var right_options := other_settings.duplicate(true)
	left_options["read_only"] = true
	right_options["read_only"] = true
	split.add_child(create_panel(data, left_options))
	split.add_child(create_panel(other_data, right_options))
	return split


func _physics_process(delta: float) -> void:
	if panel != null and visible and has_focus():
		panel.advance(delta)


func _collect_collision_shapes(node: Node) -> void:
	panel._collect_collision_shapes(node)


func _set_ranges_visible(enabled: bool) -> void:
	panel._set_ranges_visible(enabled)
