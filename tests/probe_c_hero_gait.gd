## 将主角和C放在同一地图、同样帧序下渲染，供左右步态对比。
## 实时部分检查两套动画速度、同步帧推进及追兵重复更新不会退回首帧。
## 逐帧截图仅用于复现8FPS正常播放；不修改游戏地图或人物配置。
extends SceneTree

var main: Variant
var output := "user://c_hero_gait"
var report: Dictionary = {"failures":[], "native_frames":[]}

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
	main.player.position=Vector2(175,170)
	main.camera.zoom=Vector2.ONE/main.current_map.player_scale
	main.camera.position=Vector2(195,160)
	var hero:=main.player.get_node("Body") as AnimatedSprite2D
	var c:=main.cutscene.add_actor("c", "res://art/npc/c", Vector2(215,170),45,12,"side") as AnimatedSprite2D
	main.player.facing=Vector2.LEFT
	main.player.play_animation(true)
	main.cutscene._walk_actor(c,c.position+Vector2.LEFT*10)
	hero.set_frame_and_progress(0,0)
	c.set_frame_and_progress(0,0)
	main.escape_session._chaser=c
	var visited: Dictionary={}
	for _tick: int in 24:
		main.escape_session._animate_chaser(Vector2.LEFT)
		await create_timer(0.035).timeout
		visited[c.frame]=true
		report.native_frames.append([hero.frame,c.frame])
		if hero.frame!=c.frame: report.failures.append("主角与C帧序没有同步")
	report["hero_fps"]=hero.sprite_frames.get_animation_speed(&"walk_side")
	report["c_fps"]=c.sprite_frames.get_animation_speed(&"walk_side")
	if report.hero_fps!=report.c_fps: report.failures.append("播放速度不同")
	if visited.size()!=4: report.failures.append("持续追兵更新下没有播放全部四帧")
	for facing: Vector2 in [Vector2.LEFT, Vector2.RIGHT]:
		var direction: String="left" if facing.x<0 else "right"
		main.player.facing=facing
		main.player.play_animation(true)
		main.cutscene._walk_actor(c,c.position+facing*10)
		if hero.flip_h!=c.flip_h: report.failures.append("主角与C朝向不同")
		hero.pause()
		c.pause()
		for index: int in 4:
			hero.frame=index
			c.frame=index
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("%s_%02d.png"%[direction,index]))
	main.player.play_animation(false)
	main.cutscene._stop_actor(c)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("idle.png"))
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("[主角C同款步态GPU] ",JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit(0 if report.failures.is_empty() else 1)
