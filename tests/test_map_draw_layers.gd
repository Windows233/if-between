## 独立物件绘制层与同层顺序：内存地图及真实MapView，不修改正式地图。
## 默认值覆盖旧地图与快照，显式绘制设置只改变贴图，不改变碰撞和交互。
## 可独立--script运行，也可由测试入口调用run(h)。
extends SceneTree

const TEXTURE := "res://art/props/gatehouse_desk.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var h := TestHarness.new()
	h.setup(root)
	run(h)
	quit(0 if h.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("物件绘制层与同层顺序")
	_test_layers(h)
	_test_order(h)
	_test_parts(h)
	_test_variants_and_reload(h)
	_test_school_gate_fountain_sign(h)
	_test_library_blood_layer(h)
	_test_validation(h)


static func _actor(id: String, layer: String = "", order: int = 0) -> Dictionary:
	return {"id": id, "rect": [50, 40, 80, 60], "sprite": TEXTURE,
		"draw_layer": layer, "draw_order": order, "decor": true,
		"reach_local": [-5, 42, 90, 35], "collision": [[5, 30, 70, 20]]}


static func _map(actors: Array) -> Dictionary:
	return {"id": "draw_layers", "size": [400, 300], "actors": actors,
		"overlay": "res://art/map/library_wall.png"}


static func _view(h: TestHarness, definition: MapDef) -> MapView:
	var view := MapView.new()
	h.root.add_child(view)
	view.build(definition)
	return view


static func _node(view: MapView, id: StringName) -> Sprite2D:
	return view.get("_actor_variant_nodes").get(id) as Sprite2D


static func _sprites(view: MapView) -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	for child: Node in view.get("_built").get_children():
		if child is Sprite2D and child.name != "Overlay" and child.name != "Background":
			result.append(child)
	return result


static func _ids(actors: Array[MapDef.Actor]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for actor: MapDef.Actor in actors:
		ids.append(actor.id)
	return ids


static func _test_layers(h: TestHarness) -> void:
	var actors: Array = []
	for layer: String in ["back", "auto", "map_under_player", "front", "map_top_under_player", "above_overlay"]:
		actors.append(_actor(layer, layer))
	var definition := MapDef.from_dictionary(_map(actors))
	h.check("六种绘制层定义合法", definition.validate(), [])
	var view := _view(h, definition)
	for player_y: float in [0.0, 999.0]:
		view.set_player_y(player_y)
		h.check("普通后层不因角色站位改变 %.0f" % player_y, _node(view, &"back").z_index, MapView.PROP_Z)
		h.check("自动层仍按遮挡基线切换 %.0f" % player_y, _node(view, &"auto").z_index,
			MapView.COVER_Z if player_y < definition.actors[1].effective_cover_y() else MapView.PROP_Z)
		h.check("底图上方层在角色下方且不随站位改变 %.0f" % player_y,
			_node(view, &"map_under_player").z_index, MapView.MAP_UNDER_PLAYER_Z)
		h.check("底图上方层不会盖住角色 %.0f" % player_y,
			_node(view, &"map_under_player").z_index < 10, true)
		h.check("底图上方层仍低于整张前景遮挡图 %.0f" % player_y,
			_node(view, &"map_under_player").z_index < view.overlay_node().z_index, true)
		h.check("地图上方层高于整张前景遮挡图 %.0f" % player_y,
			_node(view, &"map_top_under_player").z_index > view.overlay_node().z_index, true)
		h.check("地图上方层低于贴片范围内角色 %.0f" % player_y,
			_node(view, &"map_top_under_player").z_index < MapView.PLAYER_OVER_MAP_TOP_Z, true)
		h.check("角色前层仍低于整张前景 %.0f" % player_y,
			_node(view, &"front").z_index < view.overlay_node().z_index, true)
		h.check("前景之上可覆盖整张前景 %.0f" % player_y,
			_node(view, &"above_overlay").z_index > view.overlay_node().z_index, true)
	h.check("只有自动层参与按站位遮挡", view.cover_count(), 1)
	var top_actor := definition.actors[definition.actors.size() - 2]
	h.check("角色进入地图贴片区域时位于贴片前方",
		view.player_z_at(top_actor.rect.get_center()), MapView.PLAYER_OVER_MAP_TOP_Z)
	h.check("角色离开地图贴片区域后恢复正常遮挡",
		view.player_z_at(Vector2(390, 290)), MapView.PLAYER_Z)
	view.free()
	# 旧地图及旧快照不含新字段，必须精确保留over/cover的原行为。
	var legacy: Array = []
	for id: String in ["plain", "cover", "over"]:
		var raw := _actor(id)
		raw.erase("draw_layer")
		raw.erase("draw_order")
		if id != "plain":
			raw[id] = true
		legacy.append(raw)
	definition = MapDef.from_dictionary(_map(legacy))
	h.check("旧格式地图与快照仍合法", definition.validate(), [])
	var expected := ["back", "auto", "front"]
	for index: int in definition.actors.size():
		h.check("旧格式默认绘制层 %d" % index, definition.actors[index].visual_layers(),
			PackedStringArray([expected[index]]))
		h.check("旧格式默认同层顺序 %d" % index, definition.actors[index].draw_order, 0)


static func _test_order(h: TestHarness) -> void:
	var definition := MapDef.from_dictionary(_map([
		_actor("first", "back", 3), _actor("rear", "back", -5),
		_actor("second", "back", 3), _actor("top", "back", 1000000)]))
	var original := _ids(definition.actors)
	var ordered := MapDef.ordered_actors(definition.actors)
	h.check("绘制顺序升序且相同值保留原次序", _ids(ordered), [&"rear", &"first", &"second", &"top"])
	h.check("排序不改源地图物件次序", _ids(definition.actors), original)
	var view := _view(h, definition)
	var previous := -1
	for id: StringName in _ids(ordered):
		var node := _node(view, id)
		h.check("实际渲染树遵循同层顺序 " + str(id), node.get_index() > previous, true)
		previous = node.get_index()
		h.check("再大的同层顺序也不越过角色层 " + str(id), node.z_index, MapView.PROP_Z)
	view.free()
	var empty: Array[MapDef.Actor] = []
	h.check("空物件列表排序安全", MapDef.ordered_actors(empty), empty)


static func _test_parts(h: TestHarness) -> void:
	var raw := _actor("parts", "above_overlay", 17)
	raw["quarter_turns"] = 1
	raw["flip_h"] = true
	raw["visual_parts"] = [
		{"id": "rear", "sprite": TEXTURE, "rect": [-10, 5, 60, 20], "layer": "back"},
		{"id": "body", "sprite": TEXTURE, "rect": [0, 0, 80, 50], "layer": "auto"},
		{"id": "front", "sprite": TEXTURE, "rect": [10, 50, 60, 10], "layer": "front"}]
	var definition := MapDef.from_dictionary(_map([raw]))
	var actor := definition.actors[0]
	var collisions := actor.collision_rects()
	var reach := actor.reach
	h.check("多部件旋转图层定义合法", definition.validate(), [])
	h.check("整件设置显式覆盖所有部件", actor.visual_layers(),
		PackedStringArray(["above_overlay", "above_overlay", "above_overlay"]))
	var view := _view(h, definition)
	var sprites := _sprites(view)
	h.check("旋转多部件数量保持", sprites.size(), 3)
	for index: int in sprites.size():
		h.check("旋转部件覆盖前景 %d" % index, sprites[index].z_index, MapView.ABOVE_OVERLAY_Z)
		h.check("层设置不改变旋转翻转变换 %d" % index, sprites[index].transform,
			actor.visual_texture_transform(index, sprites[index].texture.get_size()))
	h.check("整件层覆盖不登记自动遮挡", view.cover_count(), 0)
	actor.draw_layer = ""
	view.build(definition)
	sprites = _sprites(view)
	h.check("清空整件覆盖后恢复各部件原层", actor.visual_layers(), PackedStringArray(["back", "auto", "front"]))
	h.check("继承部件自动遮挡恢复", view.cover_count(), 1)
	h.check("部件前层没有跑到前景之上", sprites[2].z_index, MapView.OVER_Z)
	h.check("层切换不改变碰撞", actor.collision_rects(), collisions)
	h.check("层切换不改变交互", actor.reach, reach)
	view.free()


static func _test_variants_and_reload(h: TestHarness) -> void:
	var raw := _actor("variant", "above_overlay", 27)
	raw["sprite_variants"] = {"open": "res://art/props/desk.png"}
	var original := _map([raw])
	var reloaded: Variant = JSON.parse_string(JSON.stringify(original))
	var definition := MapDef.from_dictionary(reloaded)
	var actor := definition.actors[0]
	h.check("JSON往返保留绘制层", actor.draw_layer, "above_overlay")
	h.check("JSON往返保留同层顺序", actor.draw_order, 27)
	var view := _view(h, definition)
	var node := _node(view, &"variant")
	var before_index := node.get_index()
	h.check("覆盖前景的物件仍能切贴图变体", view.set_actor_sprite_variant(&"variant", &"open"), true)
	h.check("换贴图后绘制层保持", node.z_index, MapView.ABOVE_OVERLAY_Z)
	h.check("换贴图后同层顺序保持", node.get_index(), before_index)
	h.check("换贴图后仍是原节点", _node(view, &"variant"), node)
	view.free()


static func _test_school_gate_fountain_sign(h: TestHarness) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/school_gate.json"))
	h.check("校门地图可读取遮挡回归数据", parsed is Dictionary, true)
	if not parsed is Dictionary:
		return
	var definition := MapDef.from_dictionary(parsed)
	var fountain: MapDef.Actor = null
	var sign: MapDef.Actor = null
	for actor: MapDef.Actor in definition.actors:
		if actor.id == &"sg_fountain":
			fountain = actor
		if actor.sprite.contains("sculpture_inscription"):
			sign = actor
	h.check("校门喷泉存在", fountain != null, true)
	h.check("喷泉铭牌贴图存在", sign != null, true)
	if fountain == null or sign == null:
		return
	h.check("喷泉铭牌跟随角色脚底自动遮挡", sign.visual_layers(), PackedStringArray(["auto"]))
	h.check("喷泉铭牌与喷泉共用遮挡基线", sign.effective_cover_y(), fountain.effective_cover_y())
	h.check("喷泉铭牌绘制在喷泉前方", sign.draw_order > fountain.draw_order, true)
	var view := _view(h, definition)
	var sign_node := _node(view, sign.id)
	var fountain_node := _node(view, fountain.id)
	h.check("校门地图不靠整张前景遮挡", view.overlay_node(), null)
	for player_y: float in [fountain.effective_cover_y() - 1.0, fountain.effective_cover_y() + 1.0]:
		view.set_player_y(player_y)
		var expected_z := MapView.COVER_Z if player_y < fountain.effective_cover_y() else MapView.PROP_Z
		h.check("角色在喷泉后方时铭牌跟随自动切层 %.1f" % player_y, sign_node.z_index, expected_z)
		h.check("角色在喷泉前方时喷泉跟随自动切层 %.1f" % player_y, fountain_node.z_index, expected_z)
	h.check("同层自动遮挡下铭牌绘制晚于喷泉", sign_node.get_index() > fountain_node.get_index(), true)
	view.free()


static func _test_library_blood_layer(h: TestHarness) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/library.json"))
	h.check("图书馆地图可读取血迹图层", parsed is Dictionary, true)
	if not parsed is Dictionary:
		return
	var definition := MapDef.from_dictionary(parsed)
	for actor: MapDef.Actor in definition.actors:
		if actor.id != &"library_blood_visual":
			continue
		h.check("入口血迹采用地图上方角色前方层", actor.visual_layers(), PackedStringArray(["map_top_under_player"]))
		var view := _view(h, definition)
		var node := _node(view, actor.id)
		h.check("入口血迹绘制在整张前景遮挡图上", node.z_index, MapView.MAP_TOP_UNDER_PLAYER_Z)
		h.check("入口血迹位于正常角色绘制层上", node.z_index > MapView.PLAYER_Z, true)
		h.check("角色进入血迹区域时提升到血迹前方",
			view.player_z_at(actor.rect.get_center()), MapView.PLAYER_OVER_MAP_TOP_Z)
		view.free()
		return
	h.check("图书馆地图包含入口血迹", false, true)


static func _test_validation(h: TestHarness) -> void:
	for value: Variant in [null, true, 12, [], {}]:
		var raw := _actor("bad_layer")
		raw["draw_layer"] = value
		h.check("拒绝非字符串绘制层 " + var_to_str(value),
			not MapDef.from_dictionary(_map([raw])).validate().is_empty(), true)
	for value: String in ["foreground", "above", "FRONT"]:
		var raw := _actor("bad_layer", value)
		h.check("拒绝未知绘制层 " + value, not MapDef.from_dictionary(_map([raw])).validate().is_empty(), true)
	for value: Variant in [null, true, "2", 1.5, INF, NAN, 1.0e100, [], {}]:
		var raw := _actor("bad_order")
		raw["draw_order"] = value
		h.check("拒绝非法同层顺序 " + var_to_str(value),
			not MapDef.from_dictionary(_map([raw])).validate().is_empty(), true)
	for value: Variant in [-1000000, 0, 2.0, 1000000]:
		var raw := _actor("valid_order")
		raw["draw_order"] = value
		h.check("接受有限整数同层顺序 " + var_to_str(value),
			MapDef.from_dictionary(_map([raw])).validate(), [])
