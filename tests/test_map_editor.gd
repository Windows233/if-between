## 地图编辑器（`addons/if_map_editor`）的数据层，以及游戏侧对 `cover_y` 的支持。
##
## 编辑器是**编辑器插件**，本体没法在无头测试里点；能测、也必须测的是两件事：
## 1. `map_edit_model.gd` 的增删改与写回格式（写回要是「能对 diff」的）；
## 2. `MapDef.Actor.cover_y` 这个新字段被 `map_view` 认（游戏侧的行为）。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
class_name TestMapEditor
extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const CanvasScript := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const Kind := Model.Kind


static func run(h: TestHarness) -> void:
	test_list_and_load(h)
	test_wall_ops(h)
	test_portal_ops(h)
	test_cover_y_in_model(h)
	test_save_round_trip(h)
	test_copy_layout(h)
	test_visibility_gates_picking(h)
	test_map_view_honors_cover_y(h)


static func test_list_and_load(h: TestHarness) -> void:
	var ids := Model.list_maps()
	h.check("地图列表里有门卫室", ids.has("gatehouse"), true)
	h.check("地图列表里有委托屋", ids.has("desk_shop"), true)

	var m = Model.new()
	h.check("能载入门卫室", m.load_map("gatehouse"), true)
	# **不写死具体条目数** —— 地图内容是人一直在改的（策划会往里加物件），
	# 断言绑死数字只会让人白跑一趟测试。这里只盯「读得出来、形状对」。
	h.check("尺寸读出来了", m.map_size().x > 0.0 and m.map_size().y > 0.0, true)
	h.check("墙读得出来", m.count(Kind.WALL) > 0, true)
	h.check("传送点读得出来", m.count(Kind.PORTAL) >= 1, true)
	h.check("物件读得出来", m.count(Kind.ACTOR) >= 1, true)
	h.check("载入完不是脏的", m.dirty, false)
	h.check("不存在的图载不进来", m.load_map("no_such_map"), false)


static func test_wall_ops(h: TestHarness) -> void:
	var m = Model.new()
	m.load_map("gatehouse")
	var before := m.count(Kind.WALL)

	var index := m.add_rect(Kind.WALL, Rect2(10, 20, 30, 40))
	h.check("加了一条墙", m.count(Kind.WALL), before + 1)
	h.check("新墙的内容对", m.rect_of(Kind.WALL, index), Rect2(10, 20, 30, 40))
	h.check("改动之后是脏的", m.dirty, true)

	m.set_rect(Kind.WALL, index, Rect2(12, 22, 8, 9))
	h.check("改墙生效", m.rect_of(Kind.WALL, index), Rect2(12, 22, 8, 9))

	m.remove_at(Kind.WALL, index)
	h.check("删墙生效", m.count(Kind.WALL), before)


static func test_portal_ops(h: TestHarness) -> void:
	var m = Model.new()
	m.load_map("gatehouse")
	var before := m.count(Kind.PORTAL)

	var index := m.add_rect(Kind.PORTAL, Rect2(5, 6, 7, 8))
	h.check("加了一个传送区", m.count(Kind.PORTAL), before + 1)
	h.check("新传送区默认锁着（不通往任何地方）",
		bool((m.portals()[index] as Dictionary).get("locked", false)), true)
	h.check("新传送区带占位名", m.label_of(Kind.PORTAL, index), "新传送区")
	m.remove_at(Kind.PORTAL, index)
	h.check("删传送区生效", m.count(Kind.PORTAL), before)


## 遮挡基线：`cover_y` 的自动 / 手动 / 恢复。
##
## **用内存里造的数据，不读仓库里的地图文件** —— 地图内容是策划随时在改的
## （编辑器写回的就是这些数字），测试绑死在 207 这种具体值上，人家一拖基线
## 就红一片，白跑。
static func test_cover_y_in_model(h: TestHarness) -> void:
	var m = Model.new()
	# 物件 rect [10,20,30,40] → 底边 20+40 = 60
	m.data = {
		"size": [100, 100],
		"walls": [],
		"portals": [],
		"actors": [
			{"id": "a", "rect": [10, 20, 30, 40], "cover": true},
			{"id": "b", "rect": [50, 50, 10, 10]},
		],
	}
	h.check("写了 cover 的物件认得出来", m.is_cover_actor(0), true)
	h.check("没写 cover 的不算", m.is_cover_actor(1), false)
	h.check("没写 cover_y：基线=贴图框底边", m.actor_cover_y(0), 60.0)
	h.check("没写 cover_y：报告没有手动覆盖", m.has_cover_override(0), false)

	m.set_actor_cover_y(0, 25.0)
	h.check("写了 cover_y：基线改用手动值", m.actor_cover_y(0), 25.0)
	h.check("写了 cover_y：报告有手动覆盖", m.has_cover_override(0), true)
	h.check("手动值写进了数据（整数）", (m.actors()[0] as Dictionary)["cover_y"], 25)

	m.clear_actor_cover_y(0)
	h.check("恢复自动：基线回到贴图框底边", m.actor_cover_y(0), 60.0)
	h.check("恢复自动：不再报手动覆盖", m.has_cover_override(0), false)
	h.check("恢复自动：字段整个拿掉，不留 -1", (m.actors()[0] as Dictionary).has("cover_y"), false)


## 写回格式：**整数不能变成浮点**（96 不能写成 96.0）。
##
## 多人协作里这条是硬的：每次保存都把整片数字改一遍格式，diff 就没法看了。
## 这里比的是**小数点的个数和原文件一样** —— 不盯具体数字（那是人随时在改的），
## 只盯「没有凭空多出 `.0` 这种尾巴」。
static func test_save_round_trip(h: TestHarness) -> void:
	var m = Model.new()
	m.load_map("gatehouse")
	var original: Dictionary = m.data.duplicate(true)
	var before := FileAccess.get_file_as_string(m.path)

	var out := "user://__map_editor_roundtrip.json"
	h.check("能写出来", m.save_to(out), OK)

	var text := FileAccess.get_file_as_string(out)
	h.check("小数点个数没变多（没有 96.0 这类尾巴）",
		text.count("."), before.count("."))
	var back: Variant = JSON.parse_string(text)
	h.check("写回的文本还是合法 JSON", back is Dictionary, true)
	h.check("结构一模一样（键序与数值都没变）", h.same(back, original), true)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))


## 「复制布局到另一张图」（白天版 ↔ 夜间版那种同布置不同配色的图）。
##
## 测的是纯函数那一层：三张列表覆盖过去，**尺寸 / 背景 / 前景层不被动**，
## 出生点默认不动、勾了才动，而且拷的是深拷贝。
static func test_copy_layout(h: TestHarness) -> void:
	var src := {
		"size": [100, 80],
		"background": "res://art/map/a.png",
		"walls": [[1, 2, 3, 4]],
		"portals": [{"rect": [5, 6, 7, 8], "label": "门"}],
		"actors": [{"id": "d", "rect": [9, 10, 11, 12]}],
		"spawns": {"start": [1, 1]},
	}
	var dst := {
		"size": [200, 160],
		"background": "res://art/map/b.png",
		"overlay": "res://art/map/b_wall.png",
		"walls": [],
		"portals": [],
		"actors": [],
		"spawns": {"start": [9, 9]},
	}
	Model.copy_layout(src, dst)
	h.check("墙覆盖过去了", dst["walls"], [[1, 2, 3, 4]])
	h.check("传送区覆盖过去了", dst["portals"].size(), 1)
	h.check("物件覆盖过去了", dst["actors"].size(), 1)
	h.check("尺寸不动", dst["size"], [200, 160])
	h.check("背景不动", dst["background"], "res://art/map/b.png")
	h.check("前景层不动", dst.get("overlay", ""), "res://art/map/b_wall.png")
	h.check("出生点默认不动", dst["spawns"], {"start": [9, 9]})

	# 深拷贝：改了源，目标不该跟着变
	src["walls"][0][0] = 999
	h.check("拷的是深拷贝（改源不影响目标）", dst["walls"], [[1, 2, 3, 4]])

	Model.copy_layout(src, dst, true)
	h.check("勾了「连出生点一起」才复制出生点", dst["spawns"], {"start": [1, 1]})

	var m = Model.new()
	m.load_map("gatehouse")
	h.check("目标不存在时报一句人话", m.copy_layout_to("no_such_map") != "", true)
	h.check("目标就是自己时拒绝", m.copy_layout_to("gatehouse") != "", true)


## 显示开关**同时管能不能点中**。
##
## 一张图里物件压在碰撞块上是常事（委托屋的书桌、门卫室的桌子）。
## 物件开着的时候怎么点都是物件，底下那块墙永远点不到 ——
## 关掉「物件」就该能点中墙。地图也自己造，不读仓库文件。
static func test_visibility_gates_picking(h: TestHarness) -> void:
	var m = Model.new()
	m.data = {
		"size": [200, 200],
		"walls": [[50, 50, 60, 10]],
		"portals": [],
		"actors": [{"id": "table", "rect": [40, 40, 80, 40], "label": "台"}],
	}
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(400, 400)
	canvas.load_map(m, "", "", m.map_size())
	canvas.zoom = 1.0
	canvas.pan = Vector2.ZERO

	# 这个点同时在物件 [40..120, 40..80] 和墙 [50..110, 50..60] 里
	var probe := Vector2(60, 55)
	h.check("物件开着：点到的是物件", canvas._hit_item(probe), Vector2i(Kind.ACTOR, 0))

	canvas.sel_kind = Kind.ACTOR
	canvas.sel_index = 0
	canvas.set_layer_visible("show_actors", false)
	h.check("物件关掉：点到的是底下的墙", canvas._hit_item(probe).x, Kind.WALL)
	h.check("关掉那一类，挂在它上面的选中也一起收起来", canvas.sel_kind, -1)

	canvas.set_layer_visible("show_walls", false)
	h.check("墙也关掉：这一片就什么都点不中了", canvas._hit_item(probe), Vector2i(-1, -1))

	canvas.set_layer_visible("show_walls", true)
	h.check("再打开墙：又能点中了", canvas._hit_item(probe).x, Kind.WALL)
	canvas.free()


## 游戏侧：`cover_y` 写进地图数据之后，`map_view` 得认它。
##
## **不写死 207 这种值** —— 基线是策划会在编辑器里拖的东西。
## 这里先从地图数据里把「有效基线」算出来（和 `map_view` 同一套判据），
## 再拿基线南北各一个站位去验行为。
static func test_map_view_honors_cover_y(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"gatehouse", &"start")

	var def: MapDef = main.current_map
	var desk := -1
	for i in def.actors.size():
		if def.actors[i].cover:
			desk = i
			break
	h.check("门卫室里找得到一件遮挡物", desk >= 0, true)
	if desk < 0:
		main.queue_free()
		return
	h.check("map_view 登记了它", main.map_view.cover_count() >= 1, true)

	var rect: Rect2 = def.actors[desk].rect
	var baseline: float = rect.position.y + rect.size.y
	if def.actors[desk].cover_y >= 0.0:
		baseline = def.actors[desk].cover_y
	var mid_x := rect.position.x + rect.size.x * 0.5

	main.player.global_position = Vector2(mid_x, baseline - 30.0)
	main.update_cover()
	h.check("站在基线以北：物件盖住人",
		main.map_view.cover_z(0) > main.player.z_index, true)

	main.player.global_position = Vector2(mid_x, baseline + 30.0)
	main.update_cover()
	h.check("站在基线以南：人挡住物件",
		main.map_view.cover_z(0) < main.player.z_index, true)

	# 手动覆盖：把基线抬到 50，同一个站位该改判。
	# **不能靠 `enter_map` 再来一次** —— 那是从磁盘重读 JSON，内存里改的会被丢掉；
	# 直接让 `map_view` 按改过的 def 重建一遍。
	def.actors[desk].cover_y = 50.0
	main.map_view.build(def, main.flags)
	main.player.global_position = Vector2(mid_x, 150.0)
	main.update_cover()
	h.check("手动基线 50：同一个站位（y=150）改判成人挡住物件",
		main.map_view.cover_z(0) < main.player.z_index, true)

	main.queue_free()
