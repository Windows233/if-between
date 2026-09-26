## 探针：门卫室桌子遮挡的**实拍**验证。
##
## 测试只能验「数据对不对」（cover_z、rect），验不了「画出来是什么样」。
## 这个探针把人分别放到桌后、桌前、门洞里，各拍一张真窗口的实拍：
##   <godot> --path <项目> --script res://tests/probe_gatehouse.gd
## 出图 user://shot_gatehouse_*.png，也就是
##   %APPDATA%\Godot\app_userdata\IF：如果之间\shot_gatehouse_*.png
##
## 不是自动测试的一部分（`run_tests.gd` 不调它）。**必须开真窗口**，
## 无头模式用 dummy 渲染器，截出来是空的。
extends SceneTree

## 桌后：碰撞块（y=164 起）之前、贴着后沿的站位，脚部被桌面后沿挡住。
const BEHIND := Vector2(130, 158)
const FRONT := Vector2(130, 215)
## 门洞下方的过道里（portal [250,265,42,42]，她画的蓝框位置）。
const DOOR := Vector2(269, 278)


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	main.start_at_title = false
	main.skip_opening = true
	get_root().add_child(main)
	main.boot()
	await process_frame
	await physics_frame

	main.enter_map(&"gatehouse", &"start")
	await process_frame
	await physics_frame
	main.player.pinned = true

	var count: int = main.map_view.cover_count()
	print("cover 物件数：%d" % count)

	main.player.global_position = BEHIND
	main.update_cover()
	await process_frame
	await physics_frame
	await create_timer(0.4).timeout
	if count > 0:
		print("站桌后 cover_z = %d（角色 z=10，大于即在人上）" % main.map_view.cover_z(0))
	_shot("gatehouse_behind")

	main.player.global_position = FRONT
	main.update_cover()
	await process_frame
	await physics_frame
	await create_timer(0.4).timeout
	if count > 0:
		print("站桌前 cover_z = %d（小于 10 即在人下）" % main.map_view.cover_z(0))
	_shot("gatehouse_front")

	# 门：站进门洞按交互，应该弹「出不去」的那行字
	main.player.global_position = DOOR
	main.update_cover()
	await physics_frame
	main.interact()
	await create_timer(0.8).timeout
	await process_frame
	_shot("gatehouse_door")

	print("完成：user://shot_gatehouse_behind / _front / _door .png")
	quit(0)


func _shot(tag: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png("user://shot_%s.png" % tag)
