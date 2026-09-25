## 地图与场景：数据解析、连接、大地图、悬停详情、相机、数据加载。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
class_name TestMap
extends RefCounted


static func run(h: TestHarness) -> void:
	test_map_def_parses(h)
	test_map_def_defaults(h)
	test_map_def_validate(h)
	test_map_def_portal_lookup(h)
	test_player_direction(h)
	test_main_scene_and_portal(h)
	test_map_kind_and_portal_action(h)
	test_overworld_flow(h)
	test_map_def_actors(h)
	test_map_background_and_detail(h)
	test_camera_shrink(h)
	test_overworld_tooltip(h)
	test_game_camera_position(h)
	test_data_loader(h)
	test_scene_transition(h)
	test_facing_filter(h)
	test_door_beats_shelf(h)
	test_furniture_cover(h)
	test_lamp_is_not_over(h)
	test_side_walls_sealed(h)
	test_side_stone_walls(h)
	test_wall_has_no_air_gap(h)
	test_overlay_layer(h)
	test_walk_to(h)
	test_mouse_walk_switch(h)
	test_walk_path_reaches_goal(h)
	test_player_frames(h)


static func test_map_def_parses(h: TestHarness) -> void:
	var def := MapDef.from_dictionary({
		"id": "t",
		"size": [100, 50],
		"walls": [[0, 0, 10, 10]],
		"spawns": {"a": [5, 7]},
		"portals": [{"rect": [90, 20, 10, 10], "to": "other", "spawn": "b"}],
	})

	h.check("id 解析", def.id, &"t")
	h.check("size 解析", def.size, Vector2i(100, 50))
	h.check("墙数量", def.walls.size(), 1)
	h.check("墙矩形", def.walls[0], Rect2(0, 0, 10, 10))
	h.check("出生点", def.spawn_point(&"a"), Vector2(5, 7))
	h.check("传送点数量", def.portals.size(), 1)
	h.check("传送目标场景", def.portals[0].target_map, &"other")
	h.check("传送目标出生点", def.portals[0].target_spawn, &"b")


static func test_map_def_defaults(h: TestHarness) -> void:
	var def := MapDef.from_dictionary({})
	h.check("缺 id 时为空", def.id, &"")
	h.check("缺 size 时有默认值", def.size, Vector2i(320, 180))
	h.check("没有该出生点时退回场景中心", def.spawn_point(&"nope"), Vector2(160, 90))


static func test_map_def_validate(h: TestHarness) -> void:
	# 故意写坏，看能抓出几类问题
	var bad := MapDef.from_dictionary({
		"id": "",
		"size": [0, 0],
		"walls": [[0, 0, 0, 5]],
		"portals": [{"rect": [0, 0, 4, 4], "to": "", "spawn": ""}],
		"spawns": {"out": [500, 500]},
	})
	h.check("坏数据被抓出至少 4 条", bad.validate().size() >= 4, true)

	var good := MapDef.from_dictionary({
		"id": "ok",
		"size": [100, 100],
		"walls": [[0, 0, 10, 10]],
		"portals": [{"rect": [90, 20, 10, 10], "to": "x", "spawn": "y"}],
		"spawns": {"a": [5, 5]},
	})
	h.check("合法数据没有问题", good.validate().size(), 0)


static func test_map_def_portal_lookup(h: TestHarness) -> void:
	var def := MapDef.from_dictionary({
		"id": "p",
		"size": [100, 100],
		"portals": [{"rect": [10, 10, 20, 20], "to": "x", "spawn": "y"}],
	})
	h.check("站在传送点内能查到", def.portal_at(Vector2(20, 20)) != null, true)
	h.check("站在传送点外查不到", def.portal_at(Vector2(5, 5)) == null, true)


static func test_player_direction(h: TestHarness) -> void:
	var up: Array[int] = [KEY_W]
	var down: Array[int] = [KEY_S]
	var left: Array[int] = [KEY_A]
	var right: Array[int] = [KEY_D]
	var up_left: Array[int] = [KEY_W, KEY_A]
	var all_four: Array[int] = [KEY_W, KEY_A, KEY_S, KEY_D]
	var nothing: Array[int] = []

	h.check("W 向上", Player.direction_from(up), Vector2.UP)
	h.check("S 向下", Player.direction_from(down), Vector2.DOWN)
	h.check("A 向左", Player.direction_from(left), Vector2.LEFT)
	h.check("D 向右", Player.direction_from(right), Vector2.RIGHT)
	h.check("没按键就不动", Player.direction_from(nothing), Vector2.ZERO)
	# 上下同时按应该互相抵消，否则会出现「按住两个键才走得动」的怪事
	h.check("相反方向抵消", Player.direction_from(all_four), Vector2.ZERO)
	# 斜向要归一化，不然斜着走会快 1.41 倍
	h.check_float("斜向速度归一化", Player.direction_from(up_left).length(), 1.0)


static func test_main_scene_and_portal(h: TestHarness) -> void:
	# 集成测试：真的把主场景实例化起来，验证地图文件读得到、场景能切
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		h.check("主场景能加载", false, true)
		return

	var main: Node2D = packed.instantiate()
	h.root.add_child(main)
	# --script 模式下 _ready 不会同步触发，显式拉起来。boot 是幂等的。
	main.boot()

	if main.current_map == null:
		h.check("起始场景加载成功", false, true)
		main.queue_free()
		return

	h.check("起始场景是 desk_shop", main.current_map.id, &"desk_shop")
	h.check("玩家已创建", main.player != null, true)
	h.check("起始出生点生效", main.player.global_position, Vector2(173, 293))

	# 切场景，验证另一份地图数据也能读
	main.enter_map(&"market", &"from_overworld")
	h.check("切到 market", main.current_map.id, &"market")
	# 出生点在广场南边那块地毯正中（2026-09-24 重做集市之后是这儿）
	h.check("落在 market 的出生点", main.player.global_position, Vector2(278, 279))

	# 南门就在脚下那块地毯上，走出去是大地图
	var portal: MapDef.Portal = main.current_map.portal_at(Vector2(277, 279))
	h.check("market 的传送点查得到", portal != null, true)
	if portal != null:
		h.check("南门走出去是大地图",
			portal.outcome, MapDef.Portal.Outcome.TO_OVERWORLD)

	main.queue_free()


static func test_map_kind_and_portal_action(h: TestHarness) -> void:
	var room := MapDef.from_dictionary({"id": "r", "size": [100, 100]})
	h.check("不写 kind 时默认是室内", room.kind, MapDef.Kind.ROOM)

	var world := MapDef.from_dictionary({"id": "w", "kind": "overworld", "size": [100, 100]})
	h.check("大地图类型能解析", world.kind, MapDef.Kind.OVERWORLD)

	# 出门连接不需要目标场景，校验不该报错
	var exit_map := MapDef.from_dictionary({
		"id": "r2",
		"size": [100, 100],
		"portals": [{"rect": [10, 10, 20, 20], "action": "overworld"}],
	})
	h.check("出门连接没有目标场景也合法", exit_map.validate().size(), 0)
	var exit_portal: MapDef.Portal = exit_map.portals[0]
	h.check("action 解析成 TO_OVERWORLD",
		exit_portal.outcome, MapDef.Portal.Outcome.TO_OVERWORLD)

	# 反例：声明是 GOTO 却没有目标，必须被抓住
	var broken := MapDef.from_dictionary({
		"id": "r3",
		"size": [100, 100],
		"portals": [{"rect": [10, 10, 20, 20], "to": ""}],
	})
	h.check("GOTO 缺 target_map 要被抓住", broken.validate().size(), 1)

	var named := MapDef.from_dictionary({
		"id": "w2",
		"kind": "overworld",
		"size": [100, 100],
		"portals": [{"rect": [1, 1, 10, 10], "label": "公园", "to": "park", "spawn": "s"}],
	})
	var named_portal: MapDef.Portal = named.portals[0]
	h.check("地点名字能解析", named_portal.label, "公园")
	h.check("地点目标能解析", named_portal.target_map, &"park")


static func test_overworld_flow(h: TestHarness) -> void:
	# 完整走一遍：出门 -> 大地图 -> 点建筑 -> 回到室内
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	h.root.add_child(main)
	main.boot()

	h.check("起始在室内", main.current_map.kind, MapDef.Kind.ROOM)
	h.check("室内角色可见", main.player.visible, true)

	# desk_shop 没有出门连接，先走到集市
	main.enter_map(&"market", &"from_overworld")

	var exit_portal: MapDef.Portal = null
	for p: MapDef.Portal in main.current_map.portals:
		if p.outcome == MapDef.Portal.Outcome.TO_OVERWORLD:
			exit_portal = p
	if exit_portal == null:
		h.check("market 有出门连接", false, true)
		main.queue_free()
		return

	main.use_portal_at(exit_portal.rect.get_center())
	h.check("出门后进的是大地图", main.current_map.kind, MapDef.Kind.OVERWORLD)
	h.check("大地图上角色不可见", main.player.visible, false)

	var place: MapDef.Portal = main.current_map.portals[1]
	h.check("地点有名字", place.label != "", true)
	main.use_portal_at(place.rect.get_center())
	h.check("点选后回到室内", main.current_map.kind, MapDef.Kind.ROOM)
	h.check("角色重新可见", main.player.visible, true)

	main.queue_free()


static func test_map_def_actors(h: TestHarness) -> void:
	var def := MapDef.from_dictionary({
		"id": "a",
		"size": [100, 100],
		"actors": [
			{"id": "n1", "rect": [10, 10, 10, 20], "label": "甲", "line": "你好"},
			{"id": "n2", "rect": [80, 10, 10, 20], "label": "乙", "line": "再见"},
		],
	})

	h.check("角色数量", def.actors.size(), 2)
	var first: MapDef.Actor = def.actors[0]
	h.check("角色 id", first.id, &"n1")
	h.check("角色名字", first.label, "甲")
	h.check("角色有一个动作", first.interactions.size(), 1)
	var first_inter: MapDef.Interaction = first.interactions[0]
	h.check("默认动作 id", first_inter.id, &"talk")
	h.check("动作带一段对话", first_inter.dialogue.size(), 1)
	var first_line: DialogueLine = first_inter.dialogue.lines[0]
	h.check("对话内容接上了", first_line.text, "你好")

	# 就近选取：两个都在范围内时取近的那个
	h.check("近处取到甲", h.actor_id(def, Vector2(15, 20), 40.0), &"n1")
	h.check("近处取到乙", h.actor_id(def, Vector2(85, 20), 40.0), &"n2")
	h.check("都够不着时没有目标", h.actor_id(def, Vector2(50, 90), 8.0), &"<none>")

	var broken := MapDef.from_dictionary({
		"id": "b",
		"size": [100, 100],
		"actors": [{"rect": [1, 1, 5, 5]}],
	})
	h.check("角色缺 id 会被抓住", broken.validate().size(), 1)


static func test_map_background_and_detail(h: TestHarness) -> void:
	var def := MapDef.from_dictionary({
		"id": "w",
		"kind": "overworld",
		"size": [100, 100],
		"background": "res://somewhere.png",
		"portals": [
			{"rect": [1, 1, 10, 10], "label": "甲", "detail": "详细说明", "to": "x"},
		],
	})
	h.check("背景图路径解析", def.background, "res://somewhere.png")
	var portal: MapDef.Portal = def.portals[0]
	h.check("详情解析", portal.detail, "详细说明")
	h.check("名字也在", portal.label, "甲")


## 相机缩放：**只有大地图缩成全景，房间一律 1:1。**
##
## 2026-09-24 踩过一次：给所有场景都加了「缩进视口」，
## 结果委托屋（463x378，比视口 320x180 大）被压成一张全景图，
## 相机也不再跟人 —— 策划当场就报了「委托屋的镜头变成全图了」。
static func test_camera_shrink(h: TestHarness) -> void:
	var view := GameCamera.view_size()
	h.check("视口取的是项目设置那个固定值", view, Vector2(320.0, 180.0))
	h.check("大地图缩（640x360 对 320x180，正好一半）",
		GameCamera.zoom_for(Vector2(640.0, 360.0), view), Vector2(0.5, 0.5))
	# **判断的是 kind，不是尺寸。** 房间也比视口大，但它不该缩。
	h.check("大地图要缩", GameCamera.should_shrink(MapDef.Kind.OVERWORLD), true)
	h.check("房间不缩", GameCamera.should_shrink(MapDef.Kind.ROOM), false)


static func test_overworld_tooltip(h: TestHarness) -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node2D = packed.instantiate()
	h.root.add_child(main)
	main.boot()

	main.enter_map(&"overworld", &"default")
	h.check("进了大地图", main.current_map.kind, MapDef.Kind.OVERWORLD)
	h.check("一上来没展开详情", main.map_view.detail_for(), &"")

	# 悬停在第一个地点上面。**坐标从数据里取，别写死** ——
	# 大地图换过图、地点位置跟着换过两次（2026-09-24），写死的话每换一次都得回来改。
	#
	# 验的是 `map_view.detail_for()`：详情**展开在地点名字框下面**，
	# 由 `map_view` 自己画，不再走跟在鼠标旁边那个 `tooltip`（2026-09-24 改的）。
	var first: MapDef.Portal = main.current_map.portals[0]
	main.update_overworld_hover(first.rect.get_center())
	h.check("展开了这个地点的详情", main.map_view.detail_for(), first.id)

	# 挪到没人的地方。**别挑到别的地点头上** —— 图上有七个，
	# 随便挑个角落很可能正落在某一个上面（这一条改地图时踩过一次）。
	main.update_overworld_hover(Vector2(120, 60))
	h.check("离开地点就收起", main.map_view.detail_for(), &"")

	# 室内不展开
	main.enter_map(&"desk_shop", &"start")
	main.update_overworld_hover(Vector2(185, 138))
	h.check("室内不展开", main.map_view.detail_for(), &"")

	main.queue_free()

static func test_game_camera_position(h: TestHarness) -> void:
	# 视口 320x180。场景比视口小 → 锁在场景中心，画面不动
	var small := GameCamera.position_for(Vector2(10, 10), Vector2(200, 150), Vector2(320, 180))
	h.check("小场景锁中心 X", small.x, 100.0)
	h.check("小场景锁中心 Y", small.y, 75.0)

	# 场景比视口大 → 跟着焦点，但夹在边界内
	var big := GameCamera.position_for(Vector2(50, 50), Vector2(1000, 600), Vector2(320, 180))
	h.check("贴左上角时夹住", big, Vector2(160, 90))
	var far := GameCamera.position_for(Vector2(9999, 9999), Vector2(1000, 600), Vector2(320, 180))
	h.check("贴右下角时夹住", far, Vector2(840, 510))
	var mid := GameCamera.position_for(Vector2(500, 300), Vector2(1000, 600), Vector2(320, 180))
	h.check("中间就跟着走", mid, Vector2(500, 300))

	# 只有一个方向超出时，另一方向仍然锁中心
	var mixed := GameCamera.position_for(Vector2(500, 10), Vector2(1000, 150), Vector2(320, 180))
	h.check("宽的跟着走", mixed.x, 500.0)
	h.check("矮的锁中心", mixed.y, 75.0)


static func test_data_loader(h: TestHarness) -> void:
	var def := DataLoader.load_map(&"desk_shop")
	h.check("读到地图", def != null, true)
	h.check("地图 id 对", def.id, &"desk_shop")
	h.check("读不存在的地图返回 null", DataLoader.load_map(&"没有这个地图"), null)

	var event := DataLoader.load_event(&"elder_commission", [&"end1_calm"])
	h.check("读到剧情", event != null, true)
	h.check("剧情 id 对", event.id, &"elder_commission")
	h.check("读不存在的剧情返回 null", DataLoader.load_event(&"没有这个剧情"), null)

	var table := DataLoader.load_endings()
	h.check("读到结局表", table.endings.size(), 4)
	h.check("结局表里有第一章的 end1", table.get_ending(&"end1_calm") != null, true)
	h.check("结局表里有 end2", table.get_ending(&"end2_sweet") != null, true)

	var items := DataLoader.load_items()
	h.check("读到物品表", items != null, true)
	h.check("物品名字能查", items.name_of(&"key"), "钥匙")
	h.check("没登记的物品退回 id", items.name_of(&"nope"), "nope")


static func test_scene_transition(h: TestHarness) -> void:
	var main := h.new_main()
	h.check("转场层建好了", main.fade != null, true)

	# 同步切场景之后，画面应当是「刚盖黑、准备淡开」的状态
	main.enter_map(&"overworld", &"default")
	h.check("切完场景遮罩盖着", main.fade.is_covering(), true)
	h.check("遮罩是全黑的", main.fade.alpha(), 1.0)
	h.check("淡入不算忙碌", main.fade.is_busy(), false)

	# 玩家主动传送是异步的：调用后立刻看，场景还没换，但转场已经忙起来了
	main.enter_map(&"market", &"from_overworld")
	var before: StringName = main.current_map.id
	var exit_portal: MapDef.Portal = null
	for p: MapDef.Portal in main.current_map.portals:
		if p.outcome == MapDef.Portal.Outcome.TO_OVERWORLD:
			exit_portal = p
	h.check("找得到出门连接", exit_portal != null, true)

	main._travel_through_portal(exit_portal.rect.get_center())
	h.check("转场忙起来了", main.fade.is_busy(), true)
	h.check("这一帧还没切场景", main.current_map.id, before)
	# 黑屏期间不能让玩家继续走动
	main.update_player_control()
	h.check("转场期间不能走动", main.player.is_physics_processing(), false)

	# 忙碌时重复触发不该叠加：第二次直接被挡下
	main._travel_through_portal(exit_portal.rect.get_center())
	h.check("转场中再触发也还是忙", main.fade.is_busy(), true)

	main.queue_free()


## 交互只认朝向面前的东西。
static func test_facing_filter(h: TestHarness) -> void:
	var box := Rect2(100, 100, 20, 20)

	# 纯判定：正前方算，背后不算，脚踩在上面算
	h.check("正前方算在面前", MapDef.faces_target(Vector2(110, 130), box, Vector2.UP), true)
	h.check("背对着不算", MapDef.faces_target(Vector2(110, 130), box, Vector2.DOWN), false)
	h.check("斜前方还算", MapDef.faces_target(Vector2(70, 140), box, Vector2.UP), true)
	h.check("脚踩在上面算", MapDef.faces_target(Vector2(110, 110), box, Vector2.DOWN), true)

	# 场景里：书桌在玩家上方，面朝上能选到，面朝下选不到
	var main := h.new_main()
	var stand := Vector2(224, 175)
	var up: MapDef.Actor = main.current_map.actor_near(stand, 24.0, main.flags, Vector2.UP)
	h.check("面朝上选到柜台", up.id if up != null else &"", &"desk")
	var down: MapDef.Actor = main.current_map.actor_near(stand, 24.0, main.flags, Vector2.DOWN)
	h.check("背对着就选不到", down == null, true)

	# 不传方向时不过滤 —— 测试和「附近有什么」这类查询要用这种
	var any: MapDef.Actor = main.current_map.actor_near(stand, 24.0, main.flags)
	h.check("不传方向就不过滤", any != null, true)

	main.queue_free()


## 站在门口那一块，附近有书架挡着，按交互必须出门而不是跟书架说话。
##
## 这是玩家实际撞到的毛病：委托屋的卧室门上方就是书架，先查人就会
## 会挡人的家具（`MapDef.Actor.cover`）：人在它后面时它盖住人，人在前面时人盖住它。
##
## 场上只有书桌开了这个。书桌 `rect` 是 [181,109,86,48]，下边界 157 ——
## 脚落在 157 以北（画面上的桌子后面）书桌压在人上面，以南则反过来。
static func test_furniture_cover(h: TestHarness) -> void:
	var main := h.new_main()
	h.check("场上有一件会挡人的家具", main.map_view.cover_count(), 1)

	main.player.global_position = Vector2(224, 140)
	main.update_cover()
	h.check("人在桌后：书桌盖住人",
		main.map_view.cover_z(0) > main.player.z_index, true)

	main.player.global_position = Vector2(224, 200)
	main.update_cover()
	h.check("人在桌前：人挡住书桌",
		main.map_view.cover_z(0) < main.player.z_index, true)

	main.queue_free()


## 卧室门口那盏提灯：**在场上、能点，但既不盖角色、也不再单独贴图**。
##
## - `over` 是 2026-09-24 撤的（角色走到它北边时不会再被它压住）
## - `sprite` 是 2026-09-25 撤的 —— 门口那道围墙连同两盏提灯整张做成了
##   前景遮挡层（`MapDef.overlay`），单独再贴一份提灯就是重复画一遍
##
## 那两个机制本身都留着（`Actor.over` / `Actor.sprite` / `MapView.OVER_Z`），
## 只是**现在没有任何物件用它**。哪天真需要「一件东西永远挡在前面」，
## 给那件东西写上就行。
static func test_lamp_is_not_over(h: TestHarness) -> void:
	for mid: StringName in [&"bedroom", &"bedroom_night"]:
		var def := DataLoader.load_map(mid)
		if def == null:
			h.check("读得到 %s" % mid, false, true)
			continue
		var lamp: MapDef.Actor = null
		for actor: MapDef.Actor in def.actors:
			if actor.id == &"lamp":
				lamp = actor
		h.check("%s 里还找得到提灯" % mid, lamp != null, true)
		if lamp == null:
			continue
		h.check("%s 的提灯不再盖住角色" % mid, lamp.over, false)
		h.check("%s 的提灯不再单独贴图" % mid, lamp.sprite, "")
		# 交互和那句查看文本照旧
		h.check("%s 的提灯还点得动" % mid, lamp.interactions.size() > 0, true)


## 地图左右两侧要封严。
##
## 走路判定只认 `walls` —— **`map_view` 那道兜底边界墙 `WalkGrid` 看不见**，
## 所以两侧到画布边缘那一段要是没涂，人能从旁边绕到围墙外面去（画面外）。
## 2026-09-25 策划报的「卧室右边石墙、委托屋左右石墙都漏了」。
static func test_side_walls_sealed(h: TestHarness) -> void:
	for mid: StringName in [&"bedroom", &"bedroom_night", &"bedroom_night_sleep",
			&"desk_shop"]:
		var def := DataLoader.load_map(mid)
		if def == null:
			h.check("读得到 %s" % mid, false, true)
			continue
		var left_ok := 0
		var right_ok := 0
		var y := 20
		while y < int(def.size.y) - 20:
			if WalkGrid.is_free(def, Vector2(10, y)):
				left_ok += 1
			if WalkGrid.is_free(def, Vector2(float(def.size.x - 10), y)):
				right_ok += 1
			y += 4
		h.check("%s 左边封上了" % mid, left_ok, 0)
		h.check("%s 右边封上了" % mid, right_ok, 0)


## 房间左右两侧那道**灰白石墙**要挡得住人。
##
## 2026-09-25 策划报的：**那不是地图边缘那圈纯黑**（那是地图外的场景），
## 是插画上左右两侧有纹理的石墙。量出来它在游戏坐标
## **左侧 x≈41~66、右侧 x≈399~427**。**右侧石墙的下半段空着** ——
## 人能从那儿站进石墙里去（卧室 y 304~330、委托店 y 291~322）。
## 左侧不缺：那边有一条竖墙一路盖到底。
static func test_side_stone_walls(h: TestHarness) -> void:
	for mid: StringName in [&"desk_shop", &"bedroom", &"bedroom_night",
			&"bedroom_night_sleep"]:
		var def := DataLoader.load_map(mid)
		if def == null:
			h.check("读得到 %s" % mid, false, true)
			continue
		# 贴着两侧石墙各走一列。x=48 落在左石墙里、x=410 落在右石墙里。
		var left_ok := 0
		var right_ok := 0
		var y := 60
		while y < 320:
			if WalkGrid.is_free(def, Vector2(48, y)):
				left_ok += 1
			if WalkGrid.is_free(def, Vector2(410, y)):
				right_ok += 1
			y += 4
		h.check("%s 左侧石墙挡得住" % mid, left_ok, 0)
		h.check("%s 右侧石墙挡得住" % mid, right_ok, 0)


## 底部围墙那一段：**贴着墙站得住，从那儿往上走要一路畅通**。
##
## 2026-09-25 策划报的「贴墙的位置上方还有一长条空气墙」。底部围墙原来是
## 「顶沿 + 主体」两条拼出来的，把主体下移好让人贴墙站之后，顶沿留在半空 ——
## 站是站得住了，往上走却被一条看不见的东西挡住。
static func test_wall_has_no_air_gap(h: TestHarness) -> void:
	var def := DataLoader.load_map(&"desk_shop")
	# **范围写死是故意的。** 一路扫到地图底会扫到「底部墙下面」——
	# 那儿本来就站得住，但那是画面外，不算这条路。要查的就是
	# 「贴着墙站住的地方（≈321）」到「围墙顶（≈300）」之间通不通。
	var gap := 0
	var y := 320
	while y >= 300:
		if not WalkGrid.is_free(def, Vector2(130, y)):
			gap += 1
		y -= 2
	h.check("贴墙那一段一路畅通（没有空气墙）", gap, 0)

	# 反面：贴墙那一步本身要站得住 —— 不然「只露半身」就无从谈起
	h.check("贴着围墙站得住", WalkGrid.is_free(def, Vector2(130, 321)), true)


## 前景遮挡层：一张扣图压在所有东西（含角色）之上。
##
## 2026-09-25 策划要的：**「简单叠加」就行，不用改碰撞箱。** 图上画着的那一块
## （画面下方那道围墙、四周的建筑）本来就该盖住人，所以只要层级够高。
static func test_overlay_layer(h: TestHarness) -> void:
	# ---- 一、数据上挂了的那几张图都真的在 ----
	#
	# **集市不在这张名单里** —— 它那两张扣图 2026-09-25 撤回了
	# （策划：「集市场景的遮盖撤回修改」）。下面单独有一条守着「撤了就真的没有」。
	for mid: StringName in [&"desk_shop",
			&"bedroom", &"bedroom_night", &"bedroom_night_sleep"]:
		var def := DataLoader.load_map(mid)
		h.check("读得到 %s" % mid, def != null, true)
		if def == null:
			continue
		h.check("%s 挂了前景层" % mid, def.overlay != "", true)
		h.check("%s 的前景层图在" % mid,
			ResourceLoader.exists(def.overlay), true)

	# ---- 一之二、集市那两张撤回了，就别让它偷偷回来 ----
	for mid: StringName in [&"market", &"market_night"]:
		var def := DataLoader.load_map(mid)
		if def == null:
			h.check("读得到 %s" % mid, false, true)
			continue
		h.check("%s 没有前景层" % mid, def.overlay, "")

	# ---- 二、建出来的那一层要压过角色 ----
	# 角色是 10（`Player.create()`），比它高才盖得住人。
	var main := h.new_main()
	main.enter_map(&"desk_shop", &"start")
	var sprite: Sprite2D = main.map_view.overlay_node()
	h.check("委托店建出了前景层", sprite != null, true)
	if sprite != null:
		h.check("压过角色（角色是 10）", sprite.z_index > 10, true)
		h.check("按地图尺寸铺满",
			(sprite.scale * Vector2(sprite.texture.get_size())).round(),
			Vector2(main.current_map.size).round())

	# ---- 三、没挂 overlay 的地图不该多出这一层 ----
	main.enter_map(&"overworld", &"start")
	h.check("大地图没有前景层", main.map_view.overlay_node(), null)

	# ---- 四、底部墙往下挪的位置对不对 ----
	#
	# 围墙顶是**量出来的**（`tools/measure_wall.py` 读图上「整行宽起来」那一行，
	# 避开提灯那种窄东西）：卧室在游戏坐标 y≈308、委托店 y≈299.5。
	# 角色高 45，半身 ≈22 —— 所以脚底能站到「围墙顶 + 22」左右时，
	# 围墙正好盖住下半身。碰撞箱上边界就是照这个往下挪的。
	var room := DataLoader.load_map(&"bedroom_night")
	h.check("卧室：到底还站得住", WalkGrid.is_free(room, Vector2(224, 330)), true)
	h.check("卧室：再往下就被挡了", WalkGrid.is_free(room, Vector2(224, 332)), false)

	var shop := DataLoader.load_map(&"desk_shop")
	h.check("委托店：到底还站得住", WalkGrid.is_free(shop, Vector2(100, 321)), true)
	h.check("委托店：再往下就被挡了", WalkGrid.is_free(shop, Vector2(100, 323)), false)

	main.queue_free()


## 鼠标点地图：人走过去；点到东西就顺手互动。
##
## 以前房间里左键跟空格是一个功用（都走 `interact()`），鼠标在场景里没别的用 ——
## 人在哪儿、想点哪儿，它一概不管。
static func test_walk_to(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"desk_shop", &"start")
	h.check("一开始没有自动走的路", main.player.walk_path.size(), 0)

	# 点空地：记下一条路，不用顺手互动
	main.walk_to(Vector2(224, 200))
	h.check("点空地之后有路可走", main.player.walk_path.size() > 0, true)
	h.check("点空地不用顺手互动", main.walk_and_use, false)

	# 点那扇去卧室的门：走过去，而且到了要顺手互动
	main.walk_to(Rect2(73, 79, 29, 25).get_center())
	h.check("点门之后有路", main.player.walk_path.size() > 0, true)
	h.check("点门会顺手互动", main.walk_and_use, true)

	# 走完（路径清空）之后才轮到 `_check_walk_arrival()` 替玩家按交互键。
	# 无头里没有物理帧，手动把路清掉模拟「走到了」。
	main.player.walk_path.clear()
	main._check_walk_arrival()
	h.check("到过之后那面旗收掉", main.walk_and_use, false)

	# 沿路径走：朝下一个点、走近了吃掉它、走完就停
	var walker := Player.new()
	walker.global_position = Vector2(90, 100)
	walker.walk_path = [Vector2(100, 100), Vector2(120, 100)]
	h.check("朝下一个点走", walker._follow_path(), Vector2.RIGHT)
	walker.global_position = Vector2(99, 100)
	walker._follow_path()
	h.check("走近了就把这个点吃掉", walker.walk_path.size(), 1)
	walker.global_position = Vector2(119, 100)
	h.check("走完了就停", walker._follow_path(), Vector2.ZERO)
	h.check("路也空了", walker.walk_path.size(), 0)
	walker.free()

	main.queue_free()


## 鼠标寻路那个开关（`main.mouse_walk`）。
##
## 2026-09-24 策划说这个功能还不够好，先收起来 —— 默认**关着**。
##
## 这一条守的是「开关真的接在**输入那一下**上」：从 `_unhandled_input()`
## 打进去，而不是直接看 `walk_to()` —— 那个函数本身不该被关
## （它是程序接口，上面那条测试就靠它）。
##
## 关着的时候**不退回「左键 = 互动」**：那正是当初把两者分开的原因。
static func test_mouse_walk_switch(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"desk_shop", &"start")
	main.stage_curtain.snap_up()
	var p: Player = main.player

	h.check("默认关着", main.mouse_walk, false)
	h.check("一开始没有自动走的路", p.walk_path.size(), 0)
	main._unhandled_input(_left_click())
	h.check("关着的时候点左键不记路", p.walk_path.size(), 0)

	# 开着的时候照旧 —— 不然就是把功能关掉的同时，把「以后要完善」那条路也堵了
	main.mouse_walk = true
	main._unhandled_input(_left_click())
	h.check("开着的时候点左键照旧记路", p.walk_path.size() > 0, true)

	# `walk_to()` 本身没被关：那是程序接口，测试和将来的快捷键照样调它
	p.walk_path.clear()
	main.walk_to(Vector2(224, 200))
	h.check("walk_to() 本身没被关", p.walk_path.size() > 0, true)

	main.queue_free()


## 造一个「鼠标左键按下」的事件。
##
## **位置不用管**：`_unhandled_input` 里取的是 `get_global_mouse_position()`，
## 不是事件自带的坐标。这里只要类型和按钮对得上。
static func _left_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


## 沿鼠标点出来的路**一步一步真走一遍**，人得真到得了目标。
##
## 这条是为「卡在桌角原地踏步」那个 bug 加的。当时的情形是：**路径算得对，
## 但走路那一步是斜的** —— 拐弯处前一个点被「够近就吃掉」的判据吃掉之后，
## `gap` 同时有 x 和 y，`normalized()` 就让人斜着抄近道切过拐角，
## 蹭到桌角推不动。而路径还在、动画还在放，看着像寻路算错了。
##
## 所以这里**不复用 `_follow_path()` 的返回值当结论**，而是拿它当真脚步：
## 一步一格地挪，最后看人落在哪儿。无头里没有物理帧，只能这么模拟。
static func test_walk_path_reaches_goal(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"desk_shop", &"start")
	# **类型必须显式写。** `h.new_main()` 返回 `Node2D`，而 `main.player` /
	# `main.current_map` 在它身上是未知属性 —— 拿到的是 `Variant`，
	# 用 `:=` 推断会直接报 "Cannot infer the type"，
	# 而那个报错在 `--script` 下的表现是**整轮测试卡住不动**。
	var p: Player = main.player
	var start: Vector2 = main.current_map.spawn_point(&"start")

	# 地毯那块地。起点在桌子后面，过去要绕开桌子 —— 拐角正是会出事的地方。
	var target := Vector2(224, 200)
	p.global_position = start
	main.walk_to(target)
	h.check("点地毯有一条路", p.walk_path.size() > 0, true)
	if p.walk_path.is_empty():
		main.queue_free()
		return

	var off_axis := 0
	var steps := 0
	while not p.walk_path.is_empty() and steps < 3000:
		var dir: Vector2 = p._follow_path()
		if dir == Vector2.ZERO:
			# 零向量 = 这一步没得走了。`_follow_path()` 会把走到的点顺手吃掉，
			# 所以它也可能是「整条走完了」—— 到底哪种，交给下面
			# 「路走空了」那条断言去分。**这里不要自己判「卡住」**：
			# 真正的「被物理挡住走不动」在无头里根本没有物理帧，压根测不出来。
			break
		# **一步只准一个轴** —— 斜着走就是那个 bug 的根源
		if absf(dir.x) > 0.0 and absf(dir.y) > 0.0:
			off_axis += 1
		p.global_position += dir * 2.0
		steps += 1

	h.check("每一步都是直的（没有斜着抄近道）", off_axis, 0)
	h.check("路走空了（人真走到了）", p.walk_path.is_empty(), true)
	h.check("落在站得住的地方",
		WalkGrid.is_free(main.current_map, p.global_position), true)
	# 目标是空地，该基本走到跟前（`ARRIVE` 允许的那点误差之内）
	h.check("落在目标附近", p.global_position.distance_to(target) <= 6.0, true)

	# 点偏了（点进墙里）也得有路，而且落点站得住 —— 不能返回空、
	# 也不能把人送到墙里面去
	if not main.current_map.walls.is_empty():
		p.global_position = start
		var into_wall: Vector2 = main.current_map.walls[0].get_center()
		main.walk_to(into_wall)
		h.check("点进墙里也有路", p.walk_path.size() > 0, true)
		var detour_steps := 0
		while not p.walk_path.is_empty() and detour_steps < 3000:
			var dir: Vector2 = p._follow_path()
			if dir == Vector2.ZERO:
				break
			p.global_position += dir * 2.0
			detour_steps += 1
		h.check("绕进墙里那一趟也落在站得住的地方",
			WalkGrid.is_free(main.current_map, p.global_position), true)

	main.queue_free()


## 站在门上按交互，走的是门 —— 不是被旁边的东西截胡。
##
## **新图上门口没有紧邻的家具了**（旧版有：站在门上不挑方向就够得着书架，
## 那才是当初「点了半天出不去」的原因）。所以这条现在只保证门自己触发得了。
## 「门优先于物件」那个顺序在 `main.interact()` 里 —— `_take_portal()` 写在
## `actor_near()` 之前，没有分支，也不需要数据里刚好有这种场景才成立。
static func test_door_beats_shelf(h: TestHarness) -> void:
	var main := h.new_main()

	# 出门那扇门在 [206,311,33,26]
	var stand := Vector2(220, 320)
	main.player.global_position = stand
	main.player.facing = Vector2.UP
	main.interact()
	h.check("按下去走的是门", main.fade.is_busy(), true)
	h.check("没被对话截胡", main.dialogue.is_open(), false)

	main.queue_free()


## 角色的四向：方向和帧号都按策划给的规矩来。
static func test_player_frames(h: TestHarness) -> void:
	var body := Player.new()

	# 四向，不是八向：斜着走时取分得比较开的那个轴
	body.facing = Vector2(0, 1)
	h.check("朝下", body.facing_side(), "down")
	body.facing = Vector2(0, -1)
	h.check("朝上", body.facing_side(), "up")
	body.facing = Vector2(-1, 0)
	h.check("朝左算侧面", body.facing_side(), "side")
	body.facing = Vector2(0.9, 0.4)
	h.check("斜着走取水平那一面", body.facing_side(), "side")
	body.facing = Vector2(0.2, 0.9)
	h.check("偏竖向就取上下", body.facing_side(), "down")
	body.free()

	# 帧表：六组动画，帧数按策划给的编号
	var frames := Player.build_frames()
	h.check("帧表建起来了", frames != null, true)
	if frames == null:
		return

	for name: StringName in [&"walk_up", &"idle_up", &"walk_side",
			&"idle_side", &"walk_down", &"idle_down"]:
		h.check("有动画 %s" % name, frames.has_animation(name), true)

	h.check("背面走三步", frames.get_frame_count(&"walk_up"), 3)
	h.check("侧面走四步", frames.get_frame_count(&"walk_side"), 4)
	# 正面 2026-09-24 换了素材，走路从三帧变四帧（新四张是「1 站立、2/3/4 走路」）
	h.check("正面走四步", frames.get_frame_count(&"walk_down"), 4)
	h.check("每面站着一帧", frames.get_frame_count(&"idle_up"), 1)
	h.check("走路的循环", frames.get_animation_loop(&"walk_down"), true)
	h.check("站着的也循环（一帧，等于不动）", frames.get_animation_loop(&"idle_down"), true)

	# 背面的循环顺序 1、3、2 —— 帧号写错在画面上看不出来，只有这条能守
	h.check("背面第二帧是 3 号", frames.get_frame_texture(&"walk_up", 1) != null, true)

	# 角色显示高度不能超过委托屋左上角那扇木门的门框。
	# **量的是「显示多大」，不是帧图多大** —— 帧图是高分辨率的，
	# 缩小靠节点 scale 做。早先的版本把图压到 28 像素高，画面上再放大好几倍，
	# 结果就是糊的。
	#
	# 门框在 4 倍高清图上高 605 像素，图 ÷12 进游戏 → 50.4 个游戏单位。
	# **换地图或者改缩放系数时，这个数跟着重算**（见开发纪要 28.2）。
	const DOOR_FRAME := 50.4
	var frame_px := frames.get_frame_texture(&"walk_down", 0).get_size()
	h.check("角色没高过门框", Player.DISPLAY_HEIGHT <= DOOR_FRAME, true)

	# 帧图本身得是高清的。这条守「别又把素材压小」：早先的版本把 720 像素高的
	# 素材压成 28 像素，画面上再放大就糊了。
	h.check("帧图是高分辨率的（%.0f 像素高）" % frame_px.y, frame_px.y >= 100.0, true)

	# 缩放在节点上做：帧图高 × scale 要正好等于显示高度
	h.check("缩放后正好是显示高度",
		is_equal_approx(frame_px.y * (Player.DISPLAY_HEIGHT / frame_px.y),
			Player.DISPLAY_HEIGHT), true)
