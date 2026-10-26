## 侧走专用实机核验：重复追兵更新下帧推进、左右镜像、实际移动与八相位截图。
## 截图逐相位取自真实渲染器；原速/慢放动图由交付整理工具按步周期编排。
extends SceneTree

var main: Variant
var output := "user://c_side_walk"
var report: Dictionary = {"failures":[],"visited_frames":[],"left_motion":[],"right_motion":[]}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	_run.call_deferred()


func _run() -> void:
	main=load("res://scenes/main.tscn").instantiate()
	main.start_at_title=false
	root.add_child(main)
	main.boot()
	root.mode=Window.MODE_WINDOWED
	root.unfocusable=true
	root.size=Vector2i(1280,720)
	root.position=Vector2i(-20000,-20000)
	Engine.max_fps=60
	main.set_process(false)
	main.enter_map(&"school_gate",&"near_yard",true)
	main.cutscene.clear_actors()
	main.player.set_physics_process(false)
	main.player.visible=false
	main.camera.zoom=Vector2.ONE/main.current_map.player_scale
	main.camera.position=Vector2(195,160)
	var left:=main.cutscene.add_actor("c_left","res://art/npc/c",Vector2(175,170),45,12,"side") as AnimatedSprite2D
	var right:=main.cutscene.add_actor("c_right","res://art/npc/c",Vector2(215,170),45,12,"side") as AnimatedSprite2D
	main.cutscene._walk_actor(left,left.position+Vector2.LEFT*10)
	main.cutscene._walk_actor(right,right.position+Vector2.RIGHT*10)
	main.escape_session._chaser=left
	var visited: Dictionary={}
	# 重复 play(同一动画) 的运行时调用不能把帧不断退回第一张。
	for tick: int in 24:
		main.escape_session._animate_chaser(Vector2.LEFT)
		await create_timer(0.035).timeout
		visited[left.frame]=true
		if tick==12: await _shot("native_cycle")
	report.visited_frames=visited.keys()
	if visited.size()!=8: report.failures.append("实际播放没有经过全部8帧")
	if left.flip_h or not right.flip_h: report.failures.append("左右镜像错误")
	report["fps"]=left.sprite_frames.get_animation_speed(&"walk_side")
	left.pause()
	right.pause()
	for index: int in 8:
		left.frame=index
		right.frame=index
		await _shot("phase_%02d"%index)
	var done: Array[bool]=[false,false]
	_move("c_left",left.position-Vector2(35,0),done,0)
	_move("c_right",right.position+Vector2(35,0),done,1)
	for _tick: int in 40:
		await create_timer(0.03).timeout
		report.left_motion.append(left.position.x)
		report.right_motion.append(right.position.x)
		if done[0] and done[1]: break
	if not done[0] or not done[1]: report.failures.append("左右移动演出没有结束")
	if left.position.x>=175 or right.position.x<=215: report.failures.append("角色没有实际移动")
	if left.animation!=&"idle_side" or right.animation!=&"idle_side": report.failures.append("停下后没有恢复站姿")
	await _shot("motion_finish")
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("[C侧走GPU] ",JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit(0 if report.failures.is_empty() else 1)


func _move(id: String, target: Vector2, done: Array[bool], index: int) -> void:
	await main.cutscene._npc_move(StageStep.from_dictionary({"do":"npc_move","id":id,"to":[target.x,target.y],"time":1.0}))
	done[index]=true


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
