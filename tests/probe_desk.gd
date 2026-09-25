## 探针：推着角色去撞某件会挡人的家具，报出**实际**能站到哪儿、前后关系对不对。
##
## 为什么要真跑一遍：能站的位置是「脚底方块 + 实体块」算出来的，
## 手算很容易漏掉方块那 16 个像素的高度，或者把贴图的透明边当成实心。
## 这里让物理自己去撞，撞出来的是准的。
##
## 不是自动测试的一部分（`run_tests.gd` 不调它），改完碰撞箱手动跑一次：
##   <godot> --path <项目> --script res://tests/probe_desk.gd
extends SceneTree

## 从哪个方向推、起点放哪儿。x 取书桌正中。
const PROBE_X := 224.0
const FROM_NORTH := Vector2(PROBE_X, 118)
const FROM_SOUTH := Vector2(PROBE_X, 200)


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	main.start_at_title = false
	main.skip_opening = true
	get_root().add_child(main)
	main.boot()
	await process_frame
	await physics_frame

	main.enter_map(&"desk_shop", &"start")
	await process_frame
	main.player.pinned = true

	var desk := _rect_of(main, &"desk")
	print("书桌贴图 rect: ", desk)
	print("会挡人的实体块: ", _boxes_near(main, desk))
	print("脚底方块: %s，从原点往上伸 %.0f、往下伸 %.0f（原点在脚底，所以不对称）"
		% [Player.FOOT_SIZE,
		   Player.FOOT_SIZE.y * 0.5 - Player.FOOT_OFFSET,
		   Player.FOOT_SIZE.y * 0.5 + Player.FOOT_OFFSET])
	print("")

	var north := _push(main, FROM_NORTH, Vector2(0, 1), "从北边往南顶")
	var south := _push(main, FROM_SOUTH, Vector2(0, -1), "从南边往北顶")

	print("")
	print("桌椅前后能站到的两端：北 %s / 南 %s" % [north, south])
	for item: Dictionary in main.map_view._covers:
		var node: Node2D = item["node"]
		print("cover_y = %.1f" % float(item["cover_y"]))
		for spot: Array in [[north, "桌后"], [south, "桌前"]]:
			main.player.global_position = spot[0]
			main.update_cover()
			print("  %s z=%d（%s）"
				% [spot[1], node.z_index, "家具盖人" if node.z_index > 10 else "人盖家具"])
	quit()


## 把角色放过去，然后一点一点往某方向挪，撞住为止。
func _push(main: Node2D, from: Vector2, dir: Vector2, label: String) -> Vector2:
	main.player.global_position = from
	main.player.pinned = true
	var steps := 0
	while steps < 400:
		# 类型写死：`main` 声明成 Node2D，取到的都是 Variant，`:=` 推不出来
		var hit: Variant = main.player.move_and_collide(dir)
		if hit != null:
			break
		steps += 1
	var at: Vector2 = main.player.global_position
	print("%s：走了 %d 步，停在 %s" % [label, steps, at])
	return at


func _rect_of(main: Node2D, id: StringName) -> Rect2:
	for a: MapDef.Actor in main.current_map.actors:
		if a.id == id:
			return a.rect
	return Rect2()


## 跟这块家具重叠的实体块（书桌的挡人箱就在其中）。
func _boxes_near(main: Node2D, area: Rect2) -> String:
	var out: Array[String] = []
	for w: Rect2 in main.current_map.walls:
		if w.position.x < area.end.x and w.end.x > area.position.x \
				and w.position.y < area.end.y + 8.0 and w.end.y > area.position.y:
			out.append(str(w))
	return ", ".join(out)
