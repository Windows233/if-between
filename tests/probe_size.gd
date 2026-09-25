## 一次性探针：把「角色在屏幕上到底被画成多少像素」问清楚。
##
## 尺寸不对、画面发糊这类事，光看代码看不出来 —— 帧图多大、引擎拿到的贴图多大、
## 画面最终缩放是多少、精灵最后占多少屏幕像素，几样一起打出来才能定论。
##
## 用法：
##     godot --path . --script res://tests/probe_size.gd          # 真窗口
##     godot --headless --path . --script res://tests/probe_size.gd
extends SceneTree


func _initialize() -> void:
	var frames := Player.build_frames()
	if frames == null:
		print("[探针] 帧表建不起来")
		quit(1)
		return

	var texture := frames.get_frame_texture(&"idle_down", 0)
	print("[探针] 帧贴图 idle_down#0 = %s" % texture.get_size())

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	root.add_child(main)
	main.start_at_title = false
	main.boot()
	main.enter_map(&"desk_shop", &"start")

	print("[探针] 视口 = %s" % root.get_visible_rect().size)
	print("[探针] 窗口 = %s" % Vector2(DisplayServer.window_get_size()))

	# 画面最终变换的缩放 = 「逻辑像素 -> 屏幕像素」的倍数。
	# 大于 1 说明画面是按窗口分辨率画的（canvas_items 拉伸，放大时不会糊）；
	# 等于 1 则说明是先画在小视口上、再整块放大 —— 那样糊是必然的。
	var final_scale: Vector2 = root.get_final_transform().get_scale()
	print("[探针] 最终缩放 = %s（屏幕像素 / 逻辑像素）" % final_scale)

	var box := main.player.get_node_or_null("Body") as AnimatedSprite2D
	if box == null:
		print("[探针] 没找到 Body")
	else:
		var size := box.sprite_frames.get_frame_texture(box.animation, 0).get_size()
		print("[探针] 当前动画 %s，帧图原生 %s，节点缩放 %.4f"
			% [box.animation, size, box.scale.x])
		var drawn: Vector2 = size * box.scale * final_scale
		print("[探针] 屏幕上占 %.0f x %.0f 像素" % [drawn.x, drawn.y])
		var ratio := drawn.y / maxf(size.y, 1.0)
		if ratio > 1.0:
			print("[探针] 相对帧图放大 %.2f 倍 —— 大于 1 就会糊" % ratio)
		else:
			print("[探针] 相对帧图缩到 %.2f —— 缩小是清晰的" % ratio)

	quit(0)
