## 第二次背刺后的可控逃离。两段地图共用追踪、自动隐蔽和进门判定。
## 追兵沿可走路径和玩家实际足迹移动；暂停、失焦和界面打开时停止计时。
## 缺少推倒/翻越动作时复用现有 C 行走帧和横放书架，不冒充最终美术。
class_name Ch2EscapeSession
extends Node

const EXIT_MARGIN := 40.0

signal resolved(success: bool)

var main: Variant
var active := false
var phase := ""
var _chaser: Node2D
var _trail: Array[Vector2] = []
var _hold := 0.0
var _base_alpha := 1.0
var _hud: CanvasLayer
var _label: Label
var _focused := true
var _auto_stealth_pending := false
var _stealth_dialogue_open := false
var _chaser_was_playing := false


func setup(host: Variant) -> void:
	main = host
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 100


func can_move_player() -> bool:
	return active and _focused and not _stealth_dialogue_open


func run(part: String) -> bool:
	if not begin(part):
		return false
	return await resolved


func begin(part: String) -> bool:
	if active or main == null or main.current_map == null:
		return false
	var expected := &"library" if part == "library" else &"school_gate"
	if part not in ["library", "gate"] or main.current_map.id != expected:
		return false
	if main.object_preview != null:
		main.object_preview.clear()
	if part == "library":
		# 对话节点写入倒架标记后不会自动重建地图；开跑前落实贴图和物理障碍。
		main.refresh_scene()
	phase = part
	_auto_stealth_pending = part == "gate" \
		and main.flags.get_value(&"ch2/personal/stealth_available") == true \
		and main.flags.get_value(&"ch2/personal/stealth_started") != true
	_base_alpha = main.player.modulate.a
	main.player.walk_path.clear()
	main.walk_and_use = false
	_trail.clear()
	var origin: Vector2 = main.player.global_position
	var preferred: Vector2 = preload("res://scenes/library_shelf_fall.gd").positions(main.current_map)["c"] if part == "library" else origin + Vector2(0, -28)
	var initial := WalkGrid.path_to(main.current_map, preferred, origin)
	if initial.is_empty() or initial[-1].distance_to(origin) > 3.0:
		# 地图被编辑后仍从可达位置出场，不能穿墙向玩家直线靠拢。
		for offset: Vector2 in [Vector2.UP * 28, Vector2.RIGHT * 28, Vector2.DOWN * 28, Vector2.LEFT * 28]:
			preferred = origin + offset
			if not WalkGrid.is_free(main.current_map, preferred):
				continue
			initial = WalkGrid.path_to(main.current_map, preferred, origin)
			if not initial.is_empty() and initial[-1].distance_to(origin) <= 3.0:
				break
	if initial.is_empty() or initial[-1].distance_to(origin) > 3.0:
		return false
	preferred = initial[0]
	_trail.assign(initial)
	_chaser = main.cutscene.add_actor("c", "res://art/npc/c", preferred,
		Player.DISPLAY_HEIGHT, 9, "idle_down")
	if _chaser == null:
		return false
	# 追逐使用距离判定，不再让 NPC 自带静态脚底挡住玩家。
	for body: Node in _chaser.get_children():
		if body is CollisionObject2D:
			body.collision_layer = 0
	_hold = 2.8 if part == "library" and main.flags.get_value(&"ch2/library/shelf_fallen") == true else 0.8
	active = true
	_show_hud()
	_refresh_stealth()
	main.update_player_control()
	return true


func handle_input(event: InputEvent) -> void:
	if not active or not _focused or _stealth_dialogue_open or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match InputUtil.keycode_of(key):
		KEY_F:
			activate_stealth()
		KEY_E, KEY_SPACE:
			try_exit()


func activate_stealth() -> bool:
	if not active or phase != "gate" \
			or main.flags.get_value(&"ch2/personal/stealth_available") != true:
		return false
	main.flags.set_value(&"ch2/personal/stealth_started", true)
	_refresh_stealth()
	return true


func try_exit() -> bool:
	if not active or _stealth_dialogue_open:
		return false
	if not _at_escape_exit():
		return false
	if phase == "gate":
		if not ItemTable.has(main.flags, &"key"):
			_label.text = "教学楼门锁着。需要先取得教室钥匙。"
			return false
	_finish(true)
	return true


func _at_escape_exit() -> bool:
	var portal_id: StringName = &"to_school_gate" if phase == "library" else &"to_classroom"
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.id != portal_id:
			continue
		var margin: float = EXIT_MARGIN * main.current_map.player_scale
		return portal.rect.grow(margin).has_point(main.player.global_position)
	return false


func cancel() -> void:
	_finish(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
	else:
		return
	if active and main != null:
		main.update_player_control()


func _process(delta: float) -> void:
	if not active or not _focused or _stealth_dialogue_open or not is_instance_valid(_chaser):
		return
	if main.ui_host.is_busy() or main.fade.is_busy():
		return
	var player_at: Vector2 = main.player.global_position
	if _trail.is_empty() or _trail[-1].distance_to(player_at) >= 0.8:
		_trail.append(player_at)
	if _hold > 0.0:
		_hold -= delta
		return
	if _auto_stealth_pending:
		_begin_stealth_reaction()
		return
	var stealth: bool = main.flags.get_value(&"ch2/personal/stealth_started") == true
	var budget: float = main.player.movement_speed() * (0.76 if stealth else 1.06) * minf(delta, 0.1)
	var direction := Vector2.ZERO
	while budget > 0.0 and not _trail.is_empty():
		var gap := _trail[0] - _chaser.global_position
		if gap.length() < 0.05:
			_trail.pop_front()
			continue
		direction = gap.normalized()
		var step := minf(budget, gap.length())
		_chaser.global_position += direction * step
		budget -= step
	_animate_chaser(direction)
	if main.camera != null:
		main.camera.zoom = Vector2.ONE / main.current_map.player_scale * 1.06
		if _chaser.global_position.distance_to(player_at) < 28.0 * main.current_map.player_scale:
			main.camera.shake(0.45, 0.1)
	# 还需沿路径追上，不能隔墙或隔书架抓到主角。
	if _trail.size() <= 3 and _chaser.global_position.distance_to(player_at) < 7.0 * main.current_map.player_scale:
		_finish(false)


## 校门追逐开始后自动触发一次；只暂停追逐世界，让下方对话框正常打字和翻页。
func _begin_stealth_reaction() -> void:
	_auto_stealth_pending = false
	if not activate_stealth():
		return
	_stealth_dialogue_open = true
	if _chaser is AnimatedSprite2D:
		_chaser_was_playing = _chaser.is_playing()
		_chaser.pause()
	if is_instance_valid(_hud):
		_hud.visible = false
	if main.camera != null:
		main.camera.clear_shake()
	main.dialogue.finished.connect(_end_stealth_reaction, CONNECT_ONE_SHOT)
	main.dialogue.play(Dialogue.from_array([{
		"speaker": "我",
		"text": "（居然夜幕之泪\n还有这种效果。）",
		"side": "left",
		"portrait": "protagonist/thinking",
	}]))
	main.update_player_control()


func _end_stealth_reaction() -> void:
	_stealth_dialogue_open = false
	if not active:
		return
	if is_instance_valid(_chaser) and _chaser is AnimatedSprite2D and _chaser_was_playing:
		_chaser.play()
	if is_instance_valid(_hud):
		_hud.visible = true
	main.update_player_control()


func _animate_chaser(direction: Vector2) -> void:
	if not (_chaser is AnimatedSprite2D) or direction == Vector2.ZERO:
		return
	var sprite := _chaser as AnimatedSprite2D
	var suffix := "side" if absf(direction.x) > absf(direction.y) else ("up" if direction.y < 0 else "down")
	var animation := StringName("walk_" + suffix)
	if sprite.sprite_frames.has_animation(animation):
		sprite.play(animation)
		sprite.flip_h = direction.x > 0 if suffix == "side" else false


func _show_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 18
	add_child(_hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 24)
	_hud.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 7)
	_label.custom_minimum_size.x = 292
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_label)
	_refresh_stealth()


func _refresh_stealth() -> void:
	var stealth: bool = main.flags.get_value(&"ch2/personal/stealth_started") == true
	main.player.modulate.a = _base_alpha * (0.45 if stealth else 1.0)
	if _label != null:
		var route := "向下逃到图书馆门口，靠近按 E / 空格" if phase == "library" else "绕过喷泉，向左上教学楼门逃跑，靠近按 E / 空格"
		var controls := "\nWASD 移动 · ESC 暂停"
		_label.text = route + controls + ("\n隐蔽已开启（决策币仍会暴露方向）" if stealth else "")


func _finish(success: bool) -> void:
	if not active:
		return
	active = false
	_auto_stealth_pending = false
	if _stealth_dialogue_open:
		_stealth_dialogue_open = false
		if main.dialogue.finished.is_connected(_end_stealth_reaction):
			main.dialogue.finished.disconnect(_end_stealth_reaction)
		main.dialogue.close()
	main.player.modulate.a = _base_alpha
	main.player.walk_path.clear()
	main.player.velocity = Vector2.ZERO
	main.walk_and_use = false
	if is_instance_valid(_chaser):
		main.cutscene._drop_actor("c")
	_chaser = null
	if is_instance_valid(_hud):
		_hud.queue_free()
	_hud = null
	_label = null
	if main.camera != null:
		main.camera.clear_shake()
		main.update_camera()
	main.update_player_control()
	resolved.emit(success)
