## 真实渲染核查 C 精度、全 NPC 标尺、束缚、旧存档和四方向动画。
## --out=输出目录；可选 --old=旧C原帧，用于前后对照，不修改正式地图。
extends SceneTree

var main: Variant
var output := "user://c_sprite_probe"
var old_path := ""
var report: Dictionary = {"failures":[],"actors":[]}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
		if arg.begins_with("--old="): old_path=arg.trim_prefix("--old=")
	DirAccess.make_dir_recursive_absolute(output)
	_run.call_deferred()


func _run() -> void:
	main=load("res://scenes/main.tscn").instantiate()
	main.start_at_title=false
	main.debug_start_map=""
	root.add_child(main)
	main.boot()
	root.mode=Window.MODE_WINDOWED
	root.unfocusable=true
	root.size=Vector2i(1280,720)
	root.position=Vector2i(-20000,-20000)
	main.set_process(false)
	main.enter_map(&"school_gate",&"near_yard",true)
	main.cutscene.clear_actors()
	main.player.set_physics_process(false)
	main.player.global_position=Vector2(130,170)
	main.camera.zoom=Vector2.ONE/main.current_map.player_scale
	main.camera.position=Vector2(185,160)
	for entry: Array in [["a",157.5,45],["b",185,42],["c",212.5,32],["elder",240,45]]:
		var actor: AnimatedSprite2D=main.cutscene.add_actor(entry[0],"res://art/npc/"+entry[0],Vector2(entry[1],170),entry[2],12,"side" if entry[0]=="a" else "down")
		_label(entry[0],actor.position+Vector2(0,4))
		_measure(actor,entry[0],main.camera.zoom)
	_label("主角",main.player.position+Vector2(0,4))
	await create_timer(0.4).timeout
	await _shot("01_all_npcs_equal_scale")
	main.cutscene.clear_actors()
	_clear_labels()
	main.player.global_position=Vector2(212.5,170)
	var c: AnimatedSprite2D=main.cutscene.add_actor("c","res://art/npc/c",Vector2(185,170),32,12,"down")
	if old_path!="":
		var image:=Image.load_from_file(old_path)
		var old:=Sprite2D.new()
		old.name="OldCComparison"
		old.texture=ImageTexture.create_from_image(image)
		old.centered=false
		old.position=Vector2(157.5,170)
		old.offset=Vector2(-image.get_width()*.5,-image.get_height())
		old.scale=Vector2.ONE*32.0*main.current_map.player_scale/image.get_height()
		old.z_index=12
		old.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		main.stage_view.add_child(old)
		preload("res://scenes/world_look.gd").style_actor(old,main.current_map)
		_label("旧 C",old.position+Vector2(0,4))
	_label("新 C",c.position+Vector2(0,4))
	_label("主角",main.player.position+Vector2(0,4))
	await _shot("02_old_new_protagonist")
	if old_path!="":
		main.stage_view.get_node("OldCComparison").queue_free()
	_clear_labels()
	main.player.global_position=Vector2(175,170)
	c.position=Vector2(202.5,170)
	var hero:=main.player.get_node("Body") as AnimatedSprite2D
	var sample:=0
	for direction: Vector2 in [Vector2.DOWN,Vector2.UP,Vector2.LEFT,Vector2.RIGHT]:
		main.cutscene._walk_actor(c,c.position+direction*10)
		main.player.facing=direction
		main.player.play_animation(true)
		for _frame: int in 8:
			await create_timer(0.125).timeout
			await _shot("animation_%02d"%sample)
			sample+=1
		main.cutscene._stop_actor(c)
	hero.play(&"idle_down")
	for map_id: StringName in [&"school_yard",&"school_gate",&"shop"]:
		main.flags.set_value(&"ch2/c_at_school_gate",true)
		main.flags.set_value(&"quest_cat",true)
		main.flags.set_value(&"ch2/rescued_c",map_id!=&"school_yard")
		main.enter_map(map_id,&"from_gate" if map_id==&"school_yard" else (&"near_classroom" if map_id==&"school_gate" else &"from_market"),true)
		main.player.set_physics_process(false)
		if map_id==&"shop":
			main.player.global_position=Vector2(160,126)
		else:
			var actual: AnimatedSprite2D=main.cutscene._actor("c")
			main.player.global_position=actual.position-Vector2(35,0)*main.current_map.player_scale
			_measure(actual,str(map_id),Vector2.ONE/main.current_map.player_scale)
			if map_id==&"school_yard":
				var binding:=actual.get_node("RescueBinding") as Sprite2D
				report["binding_canvas"]=str(binding.texture.get_size()*binding.scale)
		main.update_camera()
		await create_timer(0.2).timeout
		await _shot("03_"+str(map_id))
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("[C素材GPU] ",JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit(0 if report.failures.is_empty() else 1)


func _measure(actor: AnimatedSprite2D,id: String,zoom: Vector2) -> void:
	var size:=actor.sprite_frames.get_frame_texture(actor.animation,actor.frame).get_size()
	var height:=size.y*actor.global_scale.y*zoom.y
	report.actors.append({"id":id,"frame":str(size),"screen_height":height})
	if not is_equal_approx(height,Player.DISPLAY_HEIGHT): report.failures.append(id+"高度未统一")


func _label(text: String,at: Vector2) -> void:
	var label:=Label.new()
	label.add_to_group("probe_c_labels")
	label.text=text
	label.scale=Vector2.ONE*main.current_map.player_scale
	label.position=at-Vector2(20,0)*main.current_map.player_scale
	label.custom_minimum_size.x=40
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",7)
	label.z_index=50
	main.stage_view.add_child(label)


func _clear_labels() -> void:
	for node: Node in get_nodes_in_group("probe_c_labels"):
		node.queue_free()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
