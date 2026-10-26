## C 新素材与人形 NPC 统一尺寸：独立站姿、四步态、侧向朝向和旧存档迁移。
extends RefCounted


static func run(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"library", &"from_school_gate", true)
	var actor := main.cutscene.add_actor("c", "res://art/npc/c", Vector2(233,250), 32) as AnimatedSprite2D
	h.check("旧 C 32高度调用仍得到主角标尺", _height(actor,main.camera.zoom), Player.DISPLAY_HEIGHT)
	for direction: String in ["down", "up", "side"]:
		var idle := StringName("idle_"+direction)
		var walk := StringName("walk_"+direction)
		var frames: SpriteFrames = actor.sprite_frames
		var count := 8 if direction == "side" else 4
		h.check("C完整行走帧数："+direction, frames.get_frame_count(walk), count)
		h.check("C独立站姿："+direction, frames.get_frame_count(idle), 1)
		var idle_texture := frames.get_frame_texture(idle,0)
		h.check("C站姿不误用迈步姿势："+direction, idle_texture.resource_path.ends_with("/idle_"+direction+".png"), true)
		h.check("C站姿精度匹配主角："+direction, idle_texture.get_size(), Vector2(258,360))
		var hashes := {}
		for index: int in count:
			var texture := frames.get_frame_texture(walk,index)
			h.check("C行走画布匹配主角：%s%d" % [direction,index], texture.get_size(), Vector2(258,360))
			var image := texture.get_image()
			h.check("C行走脚底与画布底边对齐：%s%d" % [direction,index], image.get_used_rect().end.y, 360)
			hashes[hash(image.get_data())] = true
		h.check("C各步态实际内容不同："+direction, hashes.size(), count)
		main.cutscene._walk_actor(actor,actor.position+Vector2.UP*10)
	_check_side_gait(h,actor.sprite_frames)
	main.cutscene._walk_actor(actor,actor.position+Vector2.LEFT*10)
	h.check("C向左使用侧面", actor.animation, &"walk_side")
	h.check("C侧面原画向左，不翻面", actor.flip_h, false)
	main.cutscene._walk_actor(actor,actor.position+Vector2.RIGHT*10)
	h.check("C向右翻转侧面", actor.flip_h, true)
	main.cutscene._stop_actor(actor)
	h.check("C停下切独立侧面站姿", actor.animation, &"idle_side")
	main.cutscene._walk_actor(actor,actor.position+Vector2.UP*10)
	h.check("C向上切背面并清翻转", [actor.animation,actor.flip_h], [&"walk_up",false])
	var a := main.cutscene.add_actor("a","res://art/npc/a",Vector2(180,250),45,12,"crouch") as AnimatedSprite2D
	a.flip_h=true
	main.cutscene._walk_actor(a,a.position+Vector2.RIGHT*10)
	h.check("只有静态图的 A 保留蹲姿",a.animation,&"idle_crouch")
	h.check("缺少对应行走图时不改原翻面",a.flip_h,true)
	var at := actor.global_position
	var legacy: Array = [{"id":"old_c","sprite":"res://art/npc/c","height":32,"at":[at.x,at.y],"z":9,"pose":"down"}]
	main.cutscene.restore_actors(legacy)
	var restored: Node2D = main.cutscene._actor("old_c")
	h.check("旧存档 C 自动升级尺寸", _height(restored,main.camera.zoom), Player.DISPLAY_HEIGHT)
	h.check("旧存档 C 脚底坐标不变", restored.global_position,at)
	var snapshot: Array = main.cutscene.snapshot_actors()
	for entry: Dictionary in snapshot:
		if entry.id in ["c","old_c"]:
			h.check("快照保存统一高度，避免反复缩放："+str(entry.id),entry.height,Player.DISPLAY_HEIGHT)
	main.enter_map(&"school_yard",&"from_gate",true)
	var bound: AnimatedSprite2D = main.cutscene._actor("c")
	var binding := bound.get_node("RescueBinding") as Sprite2D
	h.check("新长方形 C 的束缚画布随之对齐", binding.texture.get_size()*binding.scale,Vector2(258,360))
	h.check("受困 C 与主角使用相同屏幕高度", _height(bound,main.camera.zoom), Player.DISPLAY_HEIGHT)
	main.queue_free()


static func _height(actor: Node2D, zoom: Vector2) -> float:
	var sprite := actor as AnimatedSprite2D
	return sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame).get_height()*sprite.global_scale.y*zoom.y


static func _check_side_gait(h: TestHarness, frames: SpriteFrames) -> void:
	h.check("八帧侧走保持半秒完整步周期", frames.get_animation_speed(&"walk_side"), 16.0)
	var contact_a := _boot_metrics(frames.get_frame_texture(&"walk_side",0).get_image())
	var passing_a := _boot_metrics(frames.get_frame_texture(&"walk_side",2).get_image())
	var contact_b := _boot_metrics(frames.get_frame_texture(&"walk_side",4).get_image())
	var passing_b := _boot_metrics(frames.get_frame_texture(&"walk_side",6).get_image())
	# 浅棕近侧靴是同一条腿：前半轮在前/左，后半轮在后/右。
	h.check("近侧脚在第一落脚相位领先",contact_a.x < 99.0,true)
	h.check("近侧脚在另一落脚相位已退到后方",contact_b.x > 159.0,true)
	h.check("近侧脚有完整前后行程，而非原地抖动",contact_b.x-contact_a.x > 80.0,true)
	h.check("经过相位两脚确实收拢：前半轮",passing_a.span < contact_a.span-40,true)
	h.check("经过相位两脚确实收拢：后半轮",passing_b.span < contact_b.span-40,true)
	h.check("近侧脚从支撑落地变为提膝抬起",passing_a.y-passing_b.y > 10.0,true)


static func _boot_metrics(image: Image) -> Dictionary:
	var sum_x := 0.0
	var sum_y := 0.0
	var count := 0
	var left := image.get_width()
	var right := 0
	for y: int in range(285,image.get_height()):
		for x: int in image.get_width():
			var color := image.get_pixel(x,y)
			if color.a < 0.5:
				continue
			left=mini(left,x)
			right=maxi(right,x)
			if color.r-color.g > 8.0/255.0 and color.g-color.b > 1.0/255.0 \
					and (color.r+color.g+color.b)/3.0 > 75.0/255.0:
				sum_x+=x
				sum_y+=y
				count+=1
	return {"x":sum_x/maxi(1,count),"y":sum_y/maxi(1,count),"span":right-left}
