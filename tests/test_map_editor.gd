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
	test_spawns_in_model(h)
	test_actor_fields_in_model(h)
	test_asset_lists(h)
	test_reference_checks(h)
	test_import_prop(h)
	test_overlay_in_model(h)
	test_overlay_picking(h)
	test_draft_cache(h)
	test_foot_box(h)
	test_save_round_trip(h)
	test_copy_layout(h)
	test_visibility_gates_picking(h)
	test_spawn_picking(h)
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


## 出生点（`spawns`）：它不是矩形，是个坐标。
##
## 数据层把它包成「以点为中心的 6×6 方块」，好让画布那套选中/拖动照用；
## 但位置语义永远是那个点 —— 这个用例专门把这个包装盯住。
## **出生点只管位置，不管朝向**（朝向由剧情 `place_player` 或上一张地图带过来）。
static func test_spawns_in_model(h: TestHarness) -> void:
	var m = Model.new()
	m.data = {
		"size": [100, 80],
		"walls": [], "portals": [], "actors": [],
		"spawns": {"start": [10, 20]},
	}

	h.check("出生点数", m.count(Kind.SPAWN), 1)
	h.check("出生点名字", m.spawn_names()[0], "start")
	h.check("出生点坐标", m.spawn_point(0), Vector2(10, 20))
	h.check("读到的是以点为中心的 6×6 方块", m.rect_of(Kind.SPAWN, 0), Rect2(7, 17, 6, 6))

	m.set_spawn_point(0, Vector2(30, 40))
	h.check("改坐标生效", m.spawn_point(0), Vector2(30, 40))
	h.check("存进去的是整数", (m.spawns()["start"] as Array)[0], 30)

	var index := m.add_spawn("from_overworld")
	h.check("加了一个出生点", m.count(Kind.SPAWN), 2)
	h.check("新出生点默认在地图正中", m.spawn_point(index), Vector2(50, 40))
	h.check("重名不给加", m.add_spawn("start"), -1)
	h.check("空名字不给加", m.add_spawn("   "), -1)

	m.set_rect(Kind.SPAWN, index, Rect2(60, 70, 6, 6))
	h.check("按矩形拖（取中心）也对", m.spawn_point(index), Vector2(63, 73))

	m.remove_at(Kind.SPAWN, index)
	h.check("删出生点", m.count(Kind.SPAWN), 1)
	h.check("删的是对的那个", m.spawn_names()[0], "start")


## 出生点压在墙/物件上时也得选得中（它只有 6×6），关掉那层就落到下面的东西上。
static func test_spawn_picking(h: TestHarness) -> void:
	var m = Model.new()
	m.data = {
		"size": [200, 200],
		"walls": [[50, 50, 60, 10]],
		"portals": [], "actors": [],
		"spawns": {"start": [60, 55]},
	}
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(400, 400)
	canvas.load_map(m, "", "", m.map_size())
	canvas.zoom = 1.0
	canvas.pan = Vector2.ZERO

	h.check("出生点压在墙上：先选中出生点",
		canvas._hit_item(Vector2(60, 55)), Vector2i(Kind.SPAWN, 0))
	canvas.set_layer_visible("show_spawns", false)
	h.check("关掉出生点层：落到下面的墙", canvas._hit_item(Vector2(60, 55)).x, Kind.WALL)
	canvas.set_layer_visible("show_spawns", true)
	h.check("再打开：又能选中出生点", canvas._hit_item(Vector2(60, 55)).x, Kind.SPAWN)
	canvas.free()


## 物件字段与互动内容（编辑器里「物件属性」那块的数据层）。
##
## 两条硬要求：
## 1. **认不得的字段一个字都不能丢** —— 所有写入都是就地改某个键，不重建字典；
## 2. 互动写法四种互斥（`line` / `talk` / `event` / `actions`），`actor_form()` 要判对。
static func test_actor_fields_in_model(h: TestHarness) -> void:
	var m = Model.new()
	m.data = {
		"size": [100, 100],
		"walls": [], "portals": [],
		"actors": [
			{"id": "a", "label": "甲", "rect": [10, 10, 20, 20], "line": "一句话",
				"future_key": 7},
			{"id": "b", "rect": [40, 40, 20, 20], "talk": [
				{"speaker": "我", "text": "喂", "side": "right",
					"portrait": "protagonist/reading", "size_delta": 2, "shake": 0.5}]},
			{"id": "c", "rect": [70, 70, 20, 20], "event": "ch1_sleep"},
			{"id": "d", "rect": [80, 80, 20, 20], "decor": true},
		],
	}

	h.check("读得到 id", m.actor_field(0, "id"), "a")
	h.check("读得到名字", m.actor_field(0, "label"), "甲")
	m.set_actor_field(0, "label", "乙")
	h.check("改名字生效", m.actor_field(0, "label"), "乙")
	h.check("改完标了脏", m.dirty, true)
	h.check("**认不得的字段原样留着**", m.actor_field(0, "future_key"), 7)

	h.check("写法判定：单句旁白", m.actor_form(0), "line")
	h.check("写法判定：多句对话", m.actor_form(1), "talk")
	h.check("写法判定：剧情事件", m.actor_form(2), "event")
	h.check("写法判定：纯装饰", m.actor_form(3), "decor")

	# 改对话行（面板就是这么改的：拿数组就地写）
	var talk := m.actor_talk(1)
	h.check("对话行数", talk.size(), 1)
	(talk[0] as Dictionary)["text"] = "喂喂"
	h.check("改对话文本生效", m.actor_talk(1)[0]["text"], "喂喂")
	h.check("同行的 size_delta 没被碰", m.actor_talk(1)[0]["size_delta"], 2)
	h.check("同行的 shake 没被碰", m.actor_talk(1)[0]["shake"], 0.5)

	m.actor_talk(1).append({"text": "第二句"})
	h.check("加一句", m.actor_talk(1).size(), 2)
	m.actor_talk(1).remove_at(1)
	h.check("删一句", m.actor_talk(1).size(), 1)

	var before := m.count(Kind.ACTOR)
	var index := m.add_actor()
	h.check("加了一件物件", m.count(Kind.ACTOR), before + 1)
	h.check("新物件默认落在地图正中（40×40）",
		m.rect_of(Kind.ACTOR, index), Rect2(30, 30, 40, 40))
	h.check("新物件有 id 和名字", m.actor_field(index, "id") != "", true)
	var index2 := m.add_actor()
	h.check("连加两件，id 不重名",
		m.actor_field(index, "id") != m.actor_field(index2, "id"), true)
	h.check("新物件还没写互动（判成 none）", m.actor_form(index), "none")


## 「选贴图 / 选立绘」那两个下拉的候选来源。
static func test_asset_lists(h: TestHarness) -> void:
	var m = Model.new()
	var props := m.prop_files()
	h.check("art/props 里能找到图", props.size() > 0, true)
	h.check("贴图路径是 res:// 开头", props[0].begins_with("res://art/props/"), true)

	var portraits := m.portrait_names()
	h.check("立绘列表里有主角表情（含子目录）",
		portraits.has("protagonist/reading"), true)
	h.check("立绘名不带 .png", portraits[0].ends_with(".png"), false)

	h.check("剧情文件列表非空", m.event_ids().size() > 0, true)


## 删东西之前的「关联检查」—— 删掉就断了入口，而这类错误 `check_data` 查不出来
## （它只查「引用存在不存在」，查不出「本来该有个人来触发」）。
static func test_reference_checks(h: TestHarness) -> void:
	var m = Model.new()
	m.data = {
		"size": [100, 100], "walls": [],
		"portals": [
			{"rect": [1, 1, 2, 2], "to": "overworld", "label": "门"},
			{"rect": [3, 3, 2, 2], "label": "锁着的", "locked": true},
		],
		"actors": [
			{"id": "bed", "rect": [10, 10, 20, 20], "event": "ch1_sleep"},
			{"id": "plain", "rect": [40, 40, 20, 20], "line": "一句话"},
			{"id": "menu", "rect": [60, 60, 20, 20], "actions": [
				{"id": "a", "label": "看看", "talk": [{"text": "看"}]},
				{"id": "b", "label": "睡下", "event": "ch1_sleep", "once": true},
			]},
			{"id": "cond", "rect": [70, 70, 20, 20], "line": "x",
				"if": {"var": "gate/slept_once", "op": "==", "value": true},
				"set": {"item/key": 1}},
		],
	}

	h.check("挂事件的物件：报出事件名", m.actor_references(0).size(), 1)
	h.check("挂事件的物件：算「有剧情」", m.actor_has_story(0), true)
	h.check("只有一句旁白的：没有关联", m.actor_references(1).size(), 0)
	h.check("只有一句旁白的：不算「有剧情」", m.actor_has_story(1), false)

	var menu_refs := m.actor_references(2)
	h.check("动作菜单：只报挂了事件的那一项", menu_refs.size(), 1)
	h.check("动作菜单：那一项还标出「只演一次」", str(menu_refs[0]).contains("只演一次"), true)
	h.check("动作菜单：算「有剧情」", m.actor_has_story(2), true)

	var cond_refs := m.actor_references(3)
	h.check("有 if 条件要报出来", cond_refs.size(), 2)
	h.check("有 set 状态要报出来", str(cond_refs[1]).contains("item/key"), true)

	h.check("传送点连着别的地图要报出来", m.portal_references(0).size(), 1)
	h.check("锁着的传送点也要说一声", m.portal_references(1).size(), 1)


## 导入图片做遮挡片：拷进 props 目录 + 名字收拾干净 + 重名不覆盖。
static func test_import_prop(h: TestHarness) -> void:
	var m = Model.new()
	var src := "user://__editor_import_test.png"
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	img.save_png(src)
	h.check("测试用的小图造出来了", FileAccess.file_exists(src), true)

	var out_dir := "user://__editor_props"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var path := m.import_image(src, out_dir)
	h.check("导进了目标目录", path.begins_with(out_dir + "/"), true)
	h.check("文件真的在", FileAccess.file_exists(path), true)

	# 重名不覆盖，往后加 _2
	var again := m.import_image(src, out_dir)
	h.check("重名不覆盖（换了个名字）", again != path, true)

	# 名字收拾：大写变小写、空格变下划线
	var odd := "user://__Editor Odd-Name!.png"
	var img2 := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img2.fill(Color(0, 1, 0, 1))
	img2.save_png(odd)
	var cleaned := m.import_image(odd, out_dir)
	h.check("名字收拾成小写下划线（去符号、去首尾下划线）",
		cleaned.get_file(), "editor_odd_name.png")

	h.check("不是 png 的不收", m.import_image(src.get_basename() + ".txt", out_dir), "")
	h.check("找不到的路径不收", m.import_image("user://__nope.png", out_dir), "")

	# 建遮挡物件：贴图 + 默认勾上「会挡人」
	var index := m.add_actor_with_sprite(path, true)
	h.check("物件贴图指向导入的那张图", m.actor_field(index, "sprite"), path)
	h.check("导入建的物件默认会挡人", bool(m.actor_field(index, "cover", false)), true)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(src))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(odd))
	var dir := DirAccess.open(out_dir)
	if dir != null:
		for name in dir.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(out_dir + "/" + name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out_dir))


## 前景层（`overlay`）：一条路径、整张拉伸，所以**没有位置/尺寸**可改。
## 但它要能选中、能换图、能清掉。
static func test_overlay_in_model(h: TestHarness) -> void:
	var m = Model.new()
	m.data = {"size": [100, 80], "walls": [], "portals": [], "actors": [], "spawns": {}}
	h.check("没设前景层时：不算有一件", m.count(Kind.OVERLAY), 0)

	m.set_overlay_path("res://art/map/some_wall.png")
	h.check("设了前景层：算一件", m.count(Kind.OVERLAY), 1)
	h.check("读得到路径", m.overlay_path(), "res://art/map/some_wall.png")
	h.check("名字是「前景层」", m.label_of(Kind.OVERLAY, 0), "前景层")
	h.check("兜底矩形是整张地图", m.rect_of(Kind.OVERLAY, 0), Rect2(0, 0, 100, 80))

	m.dirty = false
	m.set_rect(Kind.OVERLAY, 0, Rect2(5, 5, 10, 10))
	h.check("拖它不产生改动（没有位置可存）", m.dirty, false)
	h.check("路径也没被改", m.overlay_path(), "res://art/map/some_wall.png")

	m.remove_at(Kind.OVERLAY, 0)
	h.check("删/清掉之后就不算了", m.count(Kind.OVERLAY), 0)
	h.check("数据里那条也没了", m.data.has("overlay"), false)


## 前景层要能像别的层一样点中；关掉那层就点不中。
static func test_overlay_picking(h: TestHarness) -> void:
	var overlay_path := "res://art/map/gatehouse_wall.png"
	if not ResourceLoader.exists(overlay_path):
		h.check("门卫室前景层图在（测试前提）", false, true)
		return
	var m = Model.new()
	m.data = {
		"size": [384, 307], "walls": [], "portals": [], "actors": [], "spawns": {},
		"overlay": overlay_path,
	}
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(800, 600)
	canvas.load_map(m, "", overlay_path, m.map_size())
	canvas.zoom = 1.0
	canvas.pan = Vector2.ZERO

	var band: Rect2 = canvas.overlay_game_rect()
	h.check("算得出前景层实际范围", band.size.x > 0.0 and band.size.y > 0.0, true)
	h.check("那块范围在地图下半部（下围墙）", band.position.y > m.map_size().y * 0.5, true)

	var middle: Vector2 = band.position + band.size * 0.5
	h.check("点在前景层上：选中它", canvas._hit_item(middle), Vector2i(Kind.OVERLAY, 0))
	canvas.set_layer_visible("show_overlay", false)
	h.check("关掉前景层：点不中了", canvas._hit_item(middle), Vector2i(-1, -1))
	canvas.free()


## 草稿缓存：**没保存就切地图不该丢进度**。
##
## 切走时把改动写进 `user://` 的草稿目录，切回来优先吃草稿；
## 存进仓库、或者显式丢弃，草稿才消失。
static func test_draft_cache(h: TestHarness) -> void:
	var m = Model.new()
	m.draft_dir = "user://__editor_draft_test"
	_clear_dir(m.draft_dir)

	m.load_map("gatehouse", false)
	var base_walls: int = m.count(Kind.WALL)
	m.add_rect(Kind.WALL, Rect2(1, 2, 3, 4))
	h.check("改完是脏的", m.dirty, true)
	m.stash_draft()
	h.check("草稿写出来了", m.draft_exists("gatehouse"), true)
	h.check("草稿带写盘时间", m.draft_time("gatehouse") != "", true)
	h.check("草稿列表里有它", m.draft_ids().has("gatehouse"), true)

	m.load_map("desk_shop", false)
	h.check("切到别的图：读的是文件不是草稿", m.from_draft, false)
	m.load_map("gatehouse")
	h.check("切回来：吃的是草稿", m.from_draft, true)
	h.check("草稿里那条墙还在", m.count(Kind.WALL), base_walls + 1)
	h.check("吃草稿时算「有未保存改动」", m.dirty, true)

	var out := "user://__editor_draft_test_out.json"
	h.check("能保存到别处", m.save_to(out), OK)
	h.check("存到别处不算「保存了这张图」，草稿留着", m.draft_exists("gatehouse"), true)
	# 存回**它自己的路径**才算保存。把 path 指到临时文件，别真去动仓库里的图。
	m.path = out
	h.check("存回自己的路径", m.save_to(), OK)
	h.check("保存之后草稿清掉（不然下次吃回旧的）", m.draft_exists("gatehouse"), false)

	m.add_rect(Kind.WALL, Rect2(5, 5, 5, 5))
	m.stash_draft()
	h.check("又存了一次草稿", m.draft_exists("gatehouse"), true)
	m.drop_draft("gatehouse")
	h.check("显式丢弃：没了", m.draft_exists("gatehouse"), false)
	m.load_map("gatehouse")
	h.check("丢弃之后读的是文件版本", m.from_draft, false)
	h.check("临时加的那条墙不在了", m.count(Kind.WALL), base_walls)

	_clear_dir(m.draft_dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))


static func _clear_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + "/" + name))


## 测试工具：鼠标处的**主角碰撞箱**（脚底那个 16×16 方块）。
##
## 两件事必须跟真机一致：**几何**（以落点为底向上伸 16、左右各 8，和 `WalkGrid`
## 同一份常量）和**判据**（直接调 `WalkGrid.is_free`，不另写一份）。
static func test_foot_box(h: TestHarness) -> void:
	var m = Model.new()
	m.data = {
		"size": [400, 400],
		"walls": [[90, 180, 40, 40]],
		"portals": [], "actors": [], "spawns": {},
	}
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(600, 600)
	canvas.load_map(m, "", "", m.map_size())
	canvas.zoom = 1.0
	canvas.pan = Vector2.ZERO

	h.check("脚底框的几何：底边就是落点、往上伸 16",
		canvas.foot_rect_at(Vector2(100, 200)), Rect2(92, 184, 16, 16))
	h.check("踩在墙里：站不住", canvas.foot_is_free(Vector2(100, 200)), false)
	h.check("空地：站得住", canvas.foot_is_free(Vector2(300, 300)), true)
	h.check("墙正上方（脚在墙顶之上）：站得住",
		canvas.foot_is_free(Vector2(100, 170)), true)

	# 改数据之后判据要跟着变（缓存的 MapDef 得作废）
	m.walls().clear()
	canvas.invalidate_def()
	h.check("把墙删了之后：原来站不住的地方站得住了",
		canvas.foot_is_free(Vector2(100, 200)), true)
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
