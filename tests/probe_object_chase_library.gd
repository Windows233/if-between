## 真窗口复现物件近景、追逐猫与未调查离馆后C恢复；截图供视觉复核。
## godot --path . --script res://tests/probe_object_chase_library.gd
extends SceneTree

var main: Node2D
var output := "user://bugfix_object_chase_library"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	root.add_child(main)
	main.boot()
	main.debug_start_map = ""
	main.enter_map(&"desk_shop", &"start")
	for actor: MapDef.Actor in main.current_map.actors:
		if actor.id == &"desk":
			main.begin_interaction(actor)
			break
	await _capture("01_object")
	main.stage_overlay.show_image("res://art/props/ch2_blackboard.png", 0.0)
	await _capture("02_story_object")
	main.stage_overlay.hide_image(0.0)
	main.enter_map(&"school_gate", &"near_classroom")
	main.flags.set_value(&"ch2/diary_read", true)
	main.flags.set_value(&"ch2/teamed_c", true)
	main.flags.set_value(&"ch2/gate_entry_seen", true)
	ItemTable.add(main.flags, &"charm")
	main.chase_session.begin()
	main.chase_session._trail.append(main.player.global_position - Vector2(40, 0))
	main.chase_session._trail.append(main.player.global_position)
	await _capture("03_chase")
	main.chase_session.cancel()
	main.cutscene.instant = true
	main.start_story(&"ch2_diary", &"library_enter")
	main.enter_map(&"school_gate", &"from_library")
	main.enter_map(&"library", &"from_school_gate")
	await _capture("04_library_return")
	print("[三项修复真窗口截图] " + ProjectSettings.globalize_path(output))
	quit(0)


func _capture(filename: String) -> void:
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(filename + ".png"))
