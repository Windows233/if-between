## 连续实机动画演示：追逐姿势和雾流 → 图书馆倒架 → 恢复操作后跑向门口。
## 自动略过对白，仅缩短演示时长；不修改正式场景或存档。
## 运行时加 --fixed-fps 30 --write-movie <输出.avi> 录制，之后可转 MP4。
extends SceneTree

var main: Node2D
var cat_demo := false
var clock := 0.0
var start := Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func _process(delta: float) -> bool:
	if cat_demo:
		clock += delta
		main.chase_session._animate_mist(delta, Vector2.RIGHT)
		main.chase_session._mist_sprite.flip_h = false
		main.player.position = start + Vector2(sin(clock * 0.6) * 10.0, 0)
		main.chase_session._mist.position = main.player.position + Vector2(-32, 0)
		main.player.facing = Vector2.RIGHT
		main.player.play_animation(true)
	return false

func _run() -> void:
	root.size = Vector2i(960, 540)
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	root.add_child(main)
	main.boot()
	main.enter_map(&"school_gate", &"near_classroom", true)
	main.flags.set_value(&"ch2/diary_read", true)
	main.flags.set_value(&"ch2/teamed_c", true)
	ItemTable.add(main.flags, &"charm")
	main.chase_session.begin()
	main.chase_session.set_process(false)
	main.chase_session.set_physics_process(false)
	main.player.set_physics_process(false)
	main.toast.visible = false
	start = main.player.position + Vector2(25, 0)
	main.camera_focus = start + Vector2(-10, -8)
	cat_demo = true
	await create_timer(4.0).timeout
	cat_demo = false
	main.chase_session.cancel()
	main.enter_map(&"library", &"from_school_gate", true)
	main.player.position = Vector2(233, 258)
	main.camera_focus = Vector2(233, 215)
	ItemTable.add(main.flags, &"crowbar")
	main.toast.visible = false
	main.start_story(&"ch2_library_cat", &"crowbar_used")
	var elapsed := 0.0
	while elapsed < 12.0 and not main.escape_session.active:
		await process_frame
		elapsed += main.get_process_delta_time()
		if main.dialogue.is_open():
			main.dialogue.skip()
	assert(main.escape_session.active)
	main.escape_session._hold = 10.0
	var door := Vector2.ZERO
	for portal: MapDef.Portal in main.current_map.portals:
		if portal.id == &"to_school_gate":
			door = portal.rect.get_center()
	main.player.walk_path.assign(WalkGrid.path_to(main.current_map, main.player.position, door))
	await create_timer(2.0).timeout
	print("DEMO_COMPLETE cat -> shelf -> controllable escape")
	main.escape_session.cancel()
	main.queue_free()
	await process_frame
	quit()
