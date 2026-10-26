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
		h.check("C四帧行走："+direction, frames.get_frame_count(walk), 4)
		h.check("C独立站姿："+direction, frames.get_frame_count(idle), 1)
		var idle_texture := frames.get_frame_texture(idle,0)
		h.check("C站姿不误用迈步姿势："+direction, idle_texture.resource_path.ends_with("/idle_"+direction+".png"), true)
		h.check("C站姿精度匹配主角："+direction, idle_texture.get_size(), Vector2(258,360))
		var hashes := {}
		for index: int in 4:
			var texture := frames.get_frame_texture(walk,index)
			h.check("C行走画布匹配主角：%s%d" % [direction,index], texture.get_size(), Vector2(258,360))
			var image := texture.get_image()
			h.check("C行走脚底与画布底边对齐：%s%d" % [direction,index], image.get_used_rect().end.y, 360)
			hashes[hash(image.get_data())] = true
		h.check("C四帧实际内容不同："+direction, hashes.size(), 4)
		main.cutscene._walk_actor(actor,actor.position+Vector2.UP*10)
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
