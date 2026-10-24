## 多段贴图的运行时回归：共享矩形、真实遮挡、旋转翻转、旧图兼容和数据校验。
##
## 使用内存地图和真实 MapView，所有部件保留同一 Actor 的碰撞与交互，不改正式地图。
##
## 由测试入口 preload 本脚本后调用 run(h)；不新增全局测试类，也不依赖地图插件。
extends RefCounted


static func fixture() -> Dictionary:
	var texture := "res://art/props/gatehouse_desk.png"
	return {"id": "visual_parts", "size": [400, 300], "actors": [{
		"id": "desk", "rect": [60, 40, 80, 60], "sprite": texture,
		"cover": true, "collision": [[5, 30, 70, 20]], "sort_offset": 3,
		"reach_local": [-6, 42, 92, 36], "line": "test",
		"visual_parts": [
			{"id": "rear", "sprite": texture, "rect": [-10, 5, 60, 20], "layer": "back"},
			{"id": "body", "sprite": texture, "rect": [0, 0, 80, 50], "layer": "auto", "sort_offset": -3},
			{"id": "canopy", "sprite": texture, "rect": [5, -15, 70, 35], "layer": "auto", "sort_offset": 17},
			{"id": "front", "sprite": texture, "rect": [10, 50, 60, 10], "layer": "front"}]}]}


static func run(h: TestHarness) -> void:
	test_parts(h)
	test_sprite_variants(h)
	test_cover(h)
	test_texture_geometry(h)
	test_legacy(h)
	test_validation(h)
	test_trigger_integration(h)


static func test_parts(h: TestHarness) -> void:
	var definition := MapDef.from_dictionary(fixture())
	var actor: MapDef.Actor = definition.actors[0]
	h.check("parts 数据合法", definition.validate(), [])
	h.check("parts 不复制 Actor", definition.actors.size(), 1)
	h.check("parts 不复制交互", actor.interactions.size(), 1)
	h.check("parts 保留同一局部碰撞", actor.collision_rects(), [Rect2(65, 70, 70, 20)])
	h.check("parts 保留同一局部交互", actor.reach, Rect2(54, 82, 92, 36))
	h.check("parts 交互仍返回原 Actor", definition.actor_near(Vector2(90, 100), 1) == actor, true)
	h.check("parts 世界矩形只平移一次", actor.world_visual_rects(), [
		Rect2(50, 45, 60, 20), Rect2(60, 40, 80, 50),
		Rect2(65, 25, 70, 35), Rect2(70, 90, 60, 10)])
	h.check("parts 层级可供 canvas 复用", actor.visual_layers(),
		PackedStringArray(["back", "auto", "auto", "front"]))
	h.check("parts 分别采用有效基线加偏移", actor.visual_cover_ys(),
		PackedFloat64Array([73, 70, 90, 73]))
	var view := MapView.new()
	h.root.add_child(view)
	view.build(definition)
	h.check("真实 MapView 只画 parts，不叠旧 sprite", _sprites(view).size(), 4)
	var body := view.get("_built").get_node("Actors") as StaticBody2D
	h.check("parts 只建一个 Actor 碰撞", body.get_child_count(), 1)
	view.free()


static func test_sprite_variants(h: TestHarness) -> void:
	var raw := fixture()
	raw["actors"][0].erase("visual_parts")
	raw["actors"][0]["sprite_variants"] = {
		"closed": "res://art/props/gatehouse_desk.png",
		"open": "res://art/props/desk.png"}
	raw["actors"][0]["sprite_variant"] = "closed"
	var definition := MapDef.from_dictionary(raw)
	var actor: MapDef.Actor = definition.actors[0]
	h.check("贴图变体数据合法", definition.validate(), [])
	h.check("默认变体解析", actor.visual_sprites(), PackedStringArray(["res://art/props/gatehouse_desk.png"]))
	var view := MapView.new()
	h.root.add_child(view)
	view.build(definition)
	h.check("MapView 按 Actor ID 切换贴图", view.set_actor_sprite_variant(&"desk", &"open"), true)
	h.check("成功切换后记录当前变体", actor.sprite_variant, "open")
	h.check("MapView 拒绝不存在的变体", view.set_actor_sprite_variant(&"desk", &"missing"), false)
	h.check("无效请求不改变当前变体", actor.sprite_variant, "open")
	h.check("MapView 切回基础贴图", view.set_actor_sprite_variant(&"desk", &""), true)
	h.check("基础贴图状态为空变体", actor.sprite_variant, "")
	view.free()


static func test_cover(h: TestHarness) -> void:
	var definition := MapDef.from_dictionary(fixture())
	var actor: MapDef.Actor = definition.actors[0]
	actor.cover = false
	actor.over = true
	var view := MapView.new()
	h.root.add_child(view)
	view.build(definition)
	var sprites := _sprites(view)
	h.check("parts 的 auto 独立于旧 cover/over 开关", view.cover_count(), 2)
	for player_y: float in [69.0, 70.0, 80.0, 90.0, 91.0]:
		view.set_player_y(player_y)
		h.check("back 始终在玩家后 %.0f" % player_y, sprites[0].z_index, MapView.PROP_Z)
		h.check("front 始终在玩家前 %.0f" % player_y, sprites[3].z_index, MapView.OVER_Z)
		h.check("body 实际遮挡 %.0f" % player_y, view.cover_z(0),
			MapView.COVER_Z if player_y < 70.0 else MapView.PROP_Z)
		h.check("canopy 实际遮挡 %.0f" % player_y, view.cover_z(1),
			MapView.COVER_Z if player_y < 90.0 else MapView.PROP_Z)
	actor.cover_y = 100.0
	view.build(definition)
	view.set_player_y(110.0)
	h.check("手动基线仍加每段偏移 body", view.cover_z(0), MapView.PROP_Z)
	h.check("手动基线仍加每段偏移 canopy", view.cover_z(1), MapView.COVER_Z)
	view.free()


static func test_texture_geometry(h: TestHarness) -> void:
	for turns: int in 4:
		for horizontal: bool in [false, true]:
			for vertical: bool in [false, true]:
				var raw := fixture()
				raw["actors"][0]["quarter_turns"] = turns
				raw["actors"][0]["flip_h"] = horizontal
				raw["actors"][0]["flip_v"] = vertical
				var definition := MapDef.from_dictionary(raw)
				var actor: MapDef.Actor = definition.actors[0]
				var view := MapView.new()
				h.root.add_child(view)
				view.build(definition)
				var sprites := _sprites(view)
				h.check("旋转翻转不重复烘焙碰撞", actor.collision_rects(), [Rect2(65, 70, 70, 20)])
				h.check("旋转翻转不重复烘焙交互", actor.reach, Rect2(54, 82, 92, 36))
				for index: int in sprites.size():
					_check_sprite_geometry(h, sprites[index], actor.world_visual_rects()[index],
						turns, horizontal, vertical)
				view.free()


static func _check_sprite_geometry(h: TestHarness, sprite: Sprite2D, world_rect: Rect2,
		turns: int, horizontal: bool, vertical: bool) -> void:
	var texture_size := sprite.texture.get_size()
	var label := "纹理 q%d h%s v%s" % [turns, horizontal, vertical]
	h.check("%s 保持原始纹理像素坐标" % label, sprite.get_rect(), Rect2(Vector2.ZERO, texture_size))
	h.check("%s 绕目标矩形中心旋转" % label,
		(sprite.transform * (texture_size * 0.5)).is_equal_approx(world_rect.get_center()), true)
	for corner: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
		var flipped := Vector2(1.0 - corner.x if horizontal else corner.x,
			1.0 - corner.y if vertical else corner.y)
		var oriented := flipped
		match turns:
			1: oriented = Vector2(1.0 - flipped.y, flipped.x)
			2: oriented = Vector2.ONE - flipped
			3: oriented = Vector2(flipped.y, 1.0 - flipped.x)
		var actual := sprite.transform * (corner * texture_size)
		var expected := world_rect.position + oriented * world_rect.size
		h.check("%s 角点 %s 的纹理方向和 AABB" % [label, corner], actual.is_equal_approx(expected), true)


static func test_legacy(h: TestHarness) -> void:
	for explicit_empty: bool in [false, true]:
		var raw := fixture()
		if explicit_empty:
			raw["actors"][0]["visual_parts"] = []
		else:
			raw["actors"][0].erase("visual_parts")
		var definition := MapDef.from_dictionary(raw)
		var actor: MapDef.Actor = definition.actors[0]
		var view := MapView.new()
		h.root.add_child(view)
		view.build(definition)
		var sprites := _sprites(view)
		h.check("旧字段和显式空 parts 都只画旧 sprite", sprites.size(), 1)
		h.check("旧图默认没有旋转翻转", [actor.quarter_turns, actor.flip_h, actor.flip_v], [0, false, false])
		h.check("旧 sprite 坐标保持原样", sprites[0].position, actor.rect.position)
		_check_sprite_geometry(h, sprites[0], actor.rect, 0, false, false)
		h.check("旧 cover 保留动态遮挡", view.cover_count(), 1)
		view.set_player_y(72.0)
		h.check("旧 cover 玩家后方", view.cover_z(0), MapView.COVER_Z)
		view.set_player_y(73.0)
		h.check("旧 cover 玩家前方", view.cover_z(0), MapView.PROP_Z)
		view.free()
		for turns: int in 4:
			actor.quarter_turns = turns
			actor.flip_h = true
			actor.flip_v = true
			view = MapView.new()
			h.root.add_child(view)
			view.build(definition)
			_check_sprite_geometry(h, _sprites(view)[0], actor.rect, turns, true, true)
			view.free()


static func test_validation(h: TestHarness) -> void:
	var variants := fixture()
	variants["actors"][0].erase("visual_parts")
	variants["actors"][0]["sprite_variants"] = {"closed": "res://art/props/gatehouse_desk.png"}
	variants["actors"][0]["sprite_variant"] = "missing"
	h.check("不存在的默认贴图变体被校验", not MapDef.from_dictionary(variants).validate().is_empty(), true)
	variants["actors"][0]["sprite_variant"] = "closed"
	variants["actors"][0]["visual_parts"] = [{"id": "part", "sprite": "res://art/props/gatehouse_desk.png",
		"rect": [0, 0, 10, 10], "layer": "auto"}]
	h.check("贴图变体不能和多部件绘制混用", not MapDef.from_dictionary(variants).validate().is_empty(), true)
	var bad_parts: Array = [null, {}, [null], [4], [{"sprite": 7}],
		[{"sprite": "x", "rect": [0, 0, 3, 4], "layer": "side"}],
		[{"sprite": "x", "rect": [0, 0, 3, 4]}]]
	for value: Variant in bad_parts:
		var raw := fixture()
		raw["actors"][0]["visual_parts"] = value
		h.check("无效 parts 容器或必填字段被校验", not MapDef.from_dictionary(raw).validate().is_empty(), true)
	for field: String in ["sprite", "rect", "layer"]:
		var raw := fixture()
		raw["actors"][0]["visual_parts"][0].erase(field)
		h.check("parts 缺少 %s 被校验" % field, not MapDef.from_dictionary(raw).validate().is_empty(), true)
	for patch: Dictionary in [{"rect": [0, 0, 0, 3]}, {"rect": [0, 0, 4]},
			{"rect": [0, INF, 4, 3]}, {"rect": [0, 0, NAN, 3]},
			{"rect": [true, 0, 4, 3]}, {"sort_offset": INF}, {"sort_offset": true}, {"id": 4}]:
		var raw := fixture()
		raw["actors"][0]["visual_parts"][0].merge(patch, true)
		h.check("parts 无效几何或字段类型被校验", not MapDef.from_dictionary(raw).validate().is_empty(), true)
	for patch: Dictionary in [{"quarter_turns": -1}, {"quarter_turns": 4},
			{"quarter_turns": 1.5}, {"quarter_turns": true}, {"quarter_turns": INF},
			{"flip_h": 1}, {"flip_v": null}, {"rect": [0, INF, 4, 3]},
			{"cover_y": NAN}, {"sort_offset": INF}]:
		var raw := fixture()
		raw["actors"][0].merge(patch, true)
		h.check("Actor 无效旋转翻转或非有限值被校验", not MapDef.from_dictionary(raw).validate().is_empty(), true)
	var raw := fixture()
	raw["actors"][0]["visual_parts"][1]["id"] = "rear"
	h.check("重复部件 id 被校验", not MapDef.from_dictionary(raw).validate().is_empty(), true)
	raw = fixture()
	for part: Dictionary in raw["actors"][0]["visual_parts"]:
		part.erase("id")
	h.check("可选部件 id 可全部省略", MapDef.from_dictionary(raw).validate(), [])
	raw = fixture()
	raw["actors"][0]["cover"] = false
	raw["actors"][0]["collision"] = []
	h.check("auto 部件仍要求有效排序碰撞箱", not MapDef.from_dictionary(raw).validate().is_empty(), true)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(fixture()))
	parsed["actors"][0]["quarter_turns"] = 1.0
	h.check("Godot JSON 数字类型允许整数旋转", MapDef.from_dictionary(parsed).validate(), [])


static func test_trigger_integration(h: TestHarness) -> void:
	var raw := fixture()
	raw["triggers"] = [{"id": "entry", "rect": [10, 10, 20, 20], "event": "test",
		"mode": "enter", "enabled": true, "once": false}]
	var definition := MapDef.from_dictionary(raw)
	h.check("MapDef 暴露触发器预加载 API", definition.triggers[0] is MapDef.Trigger, true)
	h.check("MapDef 解析触发区", definition.triggers[0].id, &"entry")
	h.check("MapDef 合并合法触发器校验", definition.validate(), [])
	raw["triggers"].append(raw["triggers"][0].duplicate(true))
	h.check("MapDef 校验重复触发区 id", not MapDef.from_dictionary(raw).validate().is_empty(), true)
	for value: Variant in [null, {}, [null], [{"id": "bad", "rect": [0, 0, 0, 4]}]]:
		raw["triggers"] = value
		h.check("MapDef 并入触发区形状校验", not MapDef.from_dictionary(raw).validate().is_empty(), true)


static func _sprites(view: MapView) -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	var built := view.get("_built") as Node2D
	for child: Node in built.get_children():
		if child is Sprite2D:
			result.append(child)
	return result
