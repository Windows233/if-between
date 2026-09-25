## 探针：量每个传送区「框里有几行站得住」。
##
## 为什么单开一条：传送区是照示意图上的色块提的，而色块常常**紧贴着墙底**
##（台阶的上半段、门洞正下方那块垫子）。脚底方块 16 像素高、**只往上伸**，
## 所以紧贴墙底那一段**一行都站不住** —— 玩家走上去踩不到，
## 手感就是「这扇门坏了」。肉眼看数据看不出来，只能量。
##
## 集市那张 2026-09-24 实测：4 个口里有 2 个（西侧石阶、大宅正门）
## 框里一行都没有，都往下铺过才修好。
##
## **不是自动测试的一部分**（`run_tests.gd` 不调它）—— 自动测试里
## `test_walkable.gd` 已经拿同一条判据（≥ 4 行）守着了，这条是拿来查数的：
##   <godot> --headless --path <项目> --script res://tests/probe_portal_depth.gd -- <地图 id>
extends SceneTree


func _initialize() -> void:
	var args := PackedStringArray(OS.get_cmdline_user_args())
	var map_id := StringName(args[0]) if args.size() > 0 else &"market"
	var def := DataLoader.load_map(map_id)
	if def == null:
		print("读不到地图：", map_id)
		quit()
		return

	print("%s（%s）传送区 %d 处" % [def.id, def.size, def.portals.size()])
	for portal: MapDef.Portal in def.portals:
		var rect := portal.rect
		var rows := ""
		var count := 0
		# 框里能站的行
		for y: int in range(int(rect.position.y), int(rect.end.y)):
			for x: int in range(int(rect.position.x), int(rect.end.x) + 1):
				if WalkGrid.is_free(def, Vector2(x, y)):
					rows += "%d " % y
					count += 1
					break
		# 框外上下一带（要往下铺多少，看这个）
		var around := ""
		for y: int in range(int(rect.position.y) - 20, int(rect.end.y) + 30):
			for x: int in range(int(rect.position.x), int(rect.end.x) + 1):
				if WalkGrid.is_free(def, Vector2(x, y)):
					around += "%d " % y
					break

		var verdict := "够" if count >= 4 else "**站不进去，要往外铺**"
		print("")
		print("「%s」 %s   %s" % [portal.label, rect, verdict])
		print("   框里能站的行走（%d 行）：%s" % [count, rows if rows != "" else "（一行都没有）"])
		print("   框外上下一带：%s" % around)
	quit()
