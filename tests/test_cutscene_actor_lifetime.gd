## 实际补间下检查人物被回溯/替换后的异步收尾，以及倒架前并行追赶完成。
## 不用instant跳过等待，检查协程确实返回而不只检查最终画面标记。
extends RefCounted

class TrackingCutscene extends Cutscene:
	var moving := 0
	func _npc_move(step: StageStep) -> void:
		moving += 1
		await super._npc_move(step)
		moving -= 1


static func run(h: TestHarness) -> void:
	h.section("演出角色释放与倒架异步衔接")
	for kind: String in ["normal","fade","library"]:
		await _test_removed_actor(h,kind)
	await _test_cancel_player_walk(h)
	await _test_fall_waits_for_c(h)


static func _test_removed_actor(h: TestHarness, kind: String) -> void:
	var main := h.new_main()
	main.enter_map(&"library",&"from_school_gate")
	var target := preload("res://scenes/library_staging.gd").point(main.current_map,"barrier_c")
	var actor: Node2D = main.cutscene.add_actor("c","res://art/npc/c",target+Vector2(0,-6),45,12,"down")
	var data := {"do":"npc_move","id":"c","to":[target.x,target.y],"time":0.18}
	if kind == "fade":
		data["fade"] = true
	if kind == "library":
		data["library_role"] = "barrier_c"
	var finished: Array[bool] = [false]
	_finish_move(main.cutscene,StageStep.from_dictionary(data),finished)
	await h.root.get_tree().create_timer(0.08).timeout
	main.cutscene.cancel()
	var replacement: Node2D = main.cutscene.add_actor("c","res://art/npc/c",target,45,12,"down")
	await h.root.get_tree().create_timer(0.3).timeout
	h.check(kind+"旧角色已释放",is_instance_valid(actor),false)
	h.check(kind+"取消移动后协程安全结束",finished[0],true)
	h.check(kind+"旧移动不影响新C位置",replacement.position,target)
	h.check(kind+"旧移动不改变新C站姿",(replacement as AnimatedSprite2D).animation,&"idle_down")
	main.queue_free()
	await h.root.get_tree().process_frame


static func _finish_move(scene: Cutscene, step: StageStep, finished: Array[bool]) -> void:
	await scene._npc_move(step)
	finished[0] = true


static func _test_cancel_player_walk(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library",&"from_school_gate")
	main.set_process(false)
	main.player.set_physics_process(false)
	var start: Vector2 = main.player.position
	var route: Array[Vector2] = [start+Vector2.RIGHT*8,start+Vector2(8,8)]
	var finished: Array[bool] = [false]
	_finish_player_walk(main.cutscene,route,finished)
	await h.root.get_tree().create_timer(0.04).timeout
	main.cutscene.cancel()
	main.player.set_physics_process(false)
	main.player.facing = Vector2.UP
	main.player.play_animation(true)
	await h.root.get_tree().create_timer(0.25).timeout
	h.check("取消主角演出行走后协程返回",finished[0],true)
	h.check_float("旧行走不继续第二段路径",main.player.position.y,start.y)
	h.check("旧行走不覆盖新朝向",main.player.facing,Vector2.UP)
	h.check("旧行走收尾不停止新动作",main.player.get_node("Body").animation,&"walk_up")
	main.queue_free()
	await h.root.get_tree().process_frame


static func _finish_player_walk(scene: Cutscene, route: Array[Vector2], finished: Array[bool]) -> void:
	await scene._walk_player(route,0.18)
	finished[0] = true


static func _test_fall_waits_for_c(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library",&"from_school_gate")
	main.cutscene.cancel()
	var scene := TrackingCutscene.new()
	scene.setup(main)
	main.cutscene = scene
	main.story.cutscene = scene
	main.flags.set_value(&"ch2/first_library_entry",true)
	main.flags.set_value(&"ch2/personal/rewound",true)
	var staging := preload("res://scenes/library_shelf_fall.gd").positions(main.current_map)
	main.player.position = staging["player"]
	var carpet := preload("res://scenes/library_staging.gd").point(main.current_map,"carpet_c")
	scene.add_actor("c","res://art/npc/c",carpet,45,12,"down")
	main.start_story(&"ch2_library_cat",&"crowbar_used")
	var moving_when_fall := -1
	var deadline := Time.get_ticks_msec()+8000
	while Time.get_ticks_msec() < deadline:
		await h.root.get_tree().process_frame
		if main.dialogue.is_open():
			main.dialogue.skip()
		if moving_when_fall < 0 and scene.history().has("map_actor_animation"):
			moving_when_fall = scene.moving
		if main.escape_session.active:
			break
	h.check("倒架前C追赶协程已结束",moving_when_fall,0)
	h.check("倒架后没有悬空人物移动",scene.moving,0)
	h.check("回溯后倒架完成标记",main.flags.get_value(&"ch2/library/shelf_fallen"),true)
	h.check("倒架后可继续逃跑",main.escape_session.active,true)
	h.check("倒架后C仍有效",is_instance_valid(scene._actor("c")),true)
	main.escape_session.cancel()
	main.story.cancel()
	main.queue_free()
	await h.root.get_tree().process_frame
