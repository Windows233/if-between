## 统一主角标尺的真实图形探针：逐图渲染、截图并记录画面坐标中的动画高度。
##
## 以独立 320×180 逻辑视口复用正式 Main/MapView/Player/Camera；根窗口不获焦点，
## 不发送桌面输入。启动时 APPDATA 目录名必须以 if-between-character-scale- 开头，
## 以免覆盖玩家的设置或存档；未使用隔离目录会立即退出，不启动游戏。
##
## <godot> --path <项目> --script res://tests/probe_character_scale.gd -- --scale-output=<目录>
## 需要 Windows 图形驱动，不能用 --headless；结果为逐图 PNG 与 scale_audit.json。
extends SceneTree

var _harness := TestHarness.new()
var _main: Node2D
var _viewport: SubViewport
var _output := "user://character_scale_probe"


func _initialize() -> void:
	root.unfocusable = true
	call_deferred("_run")


func _run() -> void:
	_harness.setup(root)
	_harness.check("探针使用真实图形驱动", DisplayServer.get_name() != "headless", true)
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var appdata := OS.get_environment("APPDATA").replace("\\", "/").trim_suffix("/")
	var isolated := appdata.get_file().begins_with("if-between-character-scale-")
	_harness.check("探针使用专属临时 APPDATA", isolated, true)
	if not isolated:
		_harness.report()
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scale-output="):
			_output = argument.trim_prefix("--scale-output=")
	_harness.check("创建探针结果目录", DirAccess.make_dir_recursive_absolute(_output), OK)
	# 隔离用户目录中的临时设置让 boot 保持窗口模式并静音；启动者负责 APPDATA 隔离。
	var settings := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
	settings.store_string(JSON.stringify({"display": "window", "window_size": "1280x720",
		"music_volume": 0.0, "sfx_volume": 0.0}))
	settings.close()
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(GameCamera.view_size())
	_viewport.world_2d = World2D.new()
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	_main.start_at_title = false
	_main.debug_start_map = ""
	_main.free_roam_after_ending = false
	_viewport.add_child(_main)
	_main.boot()
	_main.set_process(false)
	_main.set_process_unhandled_input(false)
	root.position = Vector2i(-20000, -20000)
	root.mode = Window.MODE_MINIMIZED
	var files := DirAccess.get_files_at("res://data/maps")
	files.sort()
	var audit: Array[Dictionary] = []
	for filename: String in files:
		if not filename.ends_with(".json"):
			continue
		var map_id := StringName(filename.get_basename())
		var definition := DataLoader.load_map(map_id)
		_harness.check("%s 正式地图可读取" % map_id, definition != null, true)
		if definition == null:
			continue
		var spawn: StringName = &"start"
		if not definition.spawns.has(spawn) and not definition.spawns.is_empty():
			spawn = definition.spawns.keys()[0]
		_main.enter_map(map_id, spawn)
		_main.player.pinned = true
		_main.update_player_control()
		_main.fade.fade_to(0.0, 0.0)
		_main.stage_curtain.snap_up()
		_main.player.play_animation(false)
		_main.update_camera()
		_main.update_cover()
		var camera_at_spawn: Vector2 = _main.camera.position
		for frame: int in range(5):
			await process_frame
			_main.update_camera()
		# 最小化的主窗口不触发自动交换帧；显式绘制独立视口，不向桌面交换缓冲。
		RenderingServer.force_draw(false)
		_harness.check("%s 镜头更新不震荡" % map_id, _main.camera.position, camera_at_spawn)
		var body := _main.player.get_node("Body") as AnimatedSprite2D
		var texture := body.sprite_frames.get_frame_texture(body.animation, 0)
		var screen_transform := body.get_global_transform_with_canvas()
		var top := screen_transform * body.offset
		var bottom := screen_transform * (body.offset + Vector2(0.0, texture.get_height()))
		var screen_height := top.distance_to(bottom)
		var room := definition.kind == MapDef.Kind.ROOM
		_harness.check("%s 主角可见性符合地图类型" % map_id, _main.player.visible, room)
		if room:
			_harness.check_float("%s 实际动画屏幕高度统一" % map_id,
				screen_height, Player.DISPLAY_HEIGHT, 0.001)
		var image := _viewport.get_texture().get_image()
		var shot := _output.path_join("%s_spawn.png" % map_id)
		_harness.check("%s 图形输出非空" % map_id, image != null and not image.is_empty(), true)
		if image != null and not image.is_empty():
			_harness.check("%s 画面非单色" % map_id, _sample_colors(image) > 8, true)
			_harness.check("%s 截图保存" % map_id, image.save_png(shot), OK)
		var entry := {"map": str(map_id), "kind": "room" if room else "overworld",
			"map_size": [definition.size.x, definition.size.y], "player_scale": definition.player_scale,
			"camera_zoom": [_main.camera.zoom.x, _main.camera.zoom.y],
			"screen_character_height": screen_height, "player_visible": _main.player.visible,
			"spawn": str(spawn), "position": [_main.player.position.x, _main.player.position.y],
			"camera": [camera_at_spawn.x, camera_at_spawn.y], "screenshot": shot}
		if room:
			var world_view: Vector2 = GameCamera.view_size() / _main.camera.zoom
			_main.player.position = Vector2(definition.size) - Vector2.ONE
			_main.update_camera()
			var expected: Vector2 = Vector2(definition.size) - world_view * 0.5
			if definition.size.x < world_view.x:
				expected.x = definition.size.x * 0.5
			if definition.size.y < world_view.y:
				expected.y = definition.size.y * 0.5
			_harness.check("%s 远端镜头正确夹边" % map_id, _main.camera.position, expected)
			entry["far_camera"] = [_main.camera.position.x, _main.camera.position.y]
		audit.append(entry)
		print("CHARACTER_SCALE map=%s s=%.3f zoom=%s height=%.3f visible=%s" % [
			map_id, definition.player_scale, _main.camera.zoom, screen_height, _main.player.visible])
	var report := FileAccess.open(_output.path_join("scale_audit.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"display": DisplayServer.get_name(),
		"viewport": [_viewport.size.x, _viewport.size.y], "passed": _harness.passed,
		"failed": _harness.failed, "maps": audit}, "\t"))
	report.close()
	_main.queue_free()
	await process_frame
	_viewport.queue_free()
	await process_frame
	quit(0 if _harness.report() else 1)


func _sample_colors(image: Image) -> int:
	var colors: Dictionary = {}
	for column: int in range(20):
		for row: int in range(12):
			colors[image.get_pixel(column * image.get_width() / 20,
				row * image.get_height() / 12)] = true
	return colors.size()
