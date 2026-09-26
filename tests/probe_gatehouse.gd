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
## 门洞里（portal [254,246,30,11]）；脚底到 y256 为止，下面是 #010815 空气墙。
const DOOR := Vector2(269, 252)


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	main.start_at_title = false
	main.skip_opening = true
	get_root().add_child(main)
	main.boot()
	await process_frame
	await physics_frame

	# 走**真实入口**：new_game → 调试分支进门卫室（含出生朝向），不绕行
	main.new_game()
	await process_frame
	await physics_frame
	main.player.pinned = true
	print("出生点：", main.player.global_position, "  朝向：", main.player.facing)
	_shot("gatehouse_spawn")

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
	var hit: bool = main.current_map.portal_at(DOOR, main.flags) != null
	print("portal_at 命中：%s" % hit)
	main.interact()
	await process_frame
	print("story 活跃：%s" % main.story.is_active())
	await create_timer(0.8).timeout
	await process_frame
	_shot("gatehouse_door")

	print("完成：user://shot_gatehouse_behind / _front / _door .png")
	quit(0)


func _shot(tag: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png("user://shot_%s.png" % tag)
