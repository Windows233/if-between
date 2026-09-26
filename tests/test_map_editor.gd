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
const Kind := Model.Kind


static func run(h: TestHarness) -> void:
	test_list_and_load(h)
	test_wall_ops(h)
	test_portal_ops(h)
	test_cover_y_in_model(h)
	test_save_round_trip(h)
	test_map_view_honors_cover_y(h)


static func test_list_and_load(h: TestHarness) -> void:
	var ids := Model.list_maps()
	h.check("地图列表里有门卫室", ids.has("gatehouse"), true)
	h.check("地图列表里有委托屋", ids.has("desk_shop"), true)

	var m = Model.new()
	h.check("能载入门卫室", m.load_map("gatehouse"), true)
	h.check("门卫室的尺寸读出来了", m.map_size(), Vector2(384, 307))
	h.check("门卫室有一件物件（桌子）", m.count(Kind.ACTOR), 2)
	h.check("门卫室有一个传送点（门）", m.count(Kind.PORTAL), 1)
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


static func test_cover_y_in_model(h: TestHarness) -> void:
	var m = Model.new()
	m.load_map("gatehouse")
	var desk := -1
	for i in m.count(Kind.ACTOR):
		if m.is_cover_actor(i):
			desk = i
	h.check("门卫室的桌子是遮挡物", desk >= 0, true)
	if desk < 0:
		return

	h.check("没写 cover_y 时：基线=贴图框底边", m.actor_cover_y(desk), 207.0)
	h.check("没写 cover_y 时：报告没有手动覆盖", m.has_cover_override(desk), false)

	m.set_actor_cover_y(desk, 100.0)
	h.check("写了 cover_y：基线改用手动值", m.actor_cover_y(desk), 100.0)
	h.check("写了 cover_y：报告有手动覆盖", m.has_cover_override(desk), true)

	m.clear_actor_cover_y(desk)
	h.check("恢复自动：基线回到贴图框底边", m.actor_cover_y(desk), 207.0)
	h.check("恢复自动：不再报手动覆盖", m.has_cover_override(desk), false)


## 写回格式：**整数不能变成浮点**（96 不能写成 96.0）。
##
## 多人协作里这条是硬的：每次保存都把整片数字改一遍格式，diff 就没法看了。
## 所以这个用例盯的是文本层面的两件事：结构不变、没有 `.0`。
static func test_save_round_trip(h: TestHarness) -> void:
	var m = Model.new()
	m.load_map("gatehouse")
	var original: Dictionary = m.data.duplicate(true)

	var out := "user://__map_editor_roundtrip.json"
	h.check("能写出来", m.save_to(out), OK)

	var text := FileAccess.get_file_as_string(out)
	h.check("写回的文本里没有浮点尾巴（96.0 这类）", text.contains(".0"), false)
	var back: Variant = JSON.parse_string(text)
	h.check("写回的文本还是合法 JSON", back is Dictionary, true)
	h.check("结构一模一样（键序与数值都没变）", h.same(back, original), true)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))


## 游戏侧：`cover_y` 写进地图数据之后，`map_view` 得认它。
static func test_map_view_honors_cover_y(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"gatehouse", &"start")
	h.check("门卫室有一件遮挡物", main.map_view.cover_count(), 1)

	main.player.global_position = Vector2(130, 150)
	main.update_cover()
	h.check("自动基线（贴图底边 207）：人在后面，物件盖住人",
		main.map_view.cover_z(0) > main.player.z_index, true)

	# 手动把基线抬到 100：同一个站位就该改判。
	# **不能靠 `enter_map` 再来一次** —— 那是从磁盘重读 JSON，内存里改的会被丢掉；
	# 直接让 `map_view` 按改过的 def 重建一遍。
	var desk := -1
	for i in main.current_map.actors.size():
		if main.current_map.actors[i].cover:
			desk = i
	h.check("地图里找得到那件遮挡物", desk >= 0, true)
	if desk < 0:
		main.queue_free()
		return
	main.current_map.actors[desk].cover_y = 100.0
	main.map_view.build(main.current_map, main.flags)
	main.player.global_position = Vector2(130, 150)
	main.update_cover()
	h.check("手动基线 100：同一站位改判成人挡住物件",
		main.map_view.cover_z(0) < main.player.z_index, true)

	main.queue_free()
