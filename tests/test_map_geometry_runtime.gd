## 地图物件的游戏运行时回归：局部碰撞、交互范围与遮挡基线。
##
## 使用内存地图和正式 MapView，不依赖地图编辑器或修改地图数据。
##
## 由游戏测试入口调用 run(h)，需要 main 已整合物件几何的运行时支持。
class_name TestMapGeometryRuntime
extends RefCounted


static func fixture() -> Dictionary:
	return {"id": "geometry_runtime", "size": [400, 300], "walls": [], "actors": [{
		"id": "desk", "rect": [60, 40, 80, 60], "label": "书桌", "cover": true,
		"sprite": "res://art/props/gatehouse_desk.png", "collision": [[5, 30, 70, 20]],
		"reach_local": [-6, 42, 92, 36], "sort_collider": 0, "event": "gatehouse_door"}]}


static func run(h: TestHarness) -> void:
	test_geometry(h)
	test_sorting(h)
	test_runtime(h)
	test_cover_y_runtime(h)
	test_legacy(h)
	test_collision_override(h)


static func test_geometry(h: TestHarness) -> void:
	var definition := MapDef.from_dictionary(fixture())
	var desk: MapDef.Actor = definition.actors[0]
	h.check("局部碰撞字段被识别", desk.has_local_collision, true)
	h.check("解析保留局部碰撞坐标", desk.collisions, [Rect2(5, 30, 70, 20)])
	h.check("局部碰撞转换到地图坐标", desk.collision_rects(), [Rect2(65, 70, 70, 20)])
	h.check("局部交互范围转换到地图坐标", desk.reach, Rect2(54, 82, 92, 36))
	h.check("排序参考框解析", desk.sort_collider, 0)
	h.check("排序偏移默认为零", desk.sort_offset, 0.0)
	h.check("物件几何通过数据层校验", definition.validate(), [])
	var raw := fixture()
	raw["actors"][0]["reach"] = [1, 2, 3, 4]
	var with_legacy_reach := MapDef.from_dictionary(raw)
	h.check("reach_local 优先于旧绝对交互框", with_legacy_reach.actors[0].reach,
		Rect2(54, 82, 92, 36))
	raw["actors"][0]["rect"] = [90, 90, 80, 60]
	var moved := MapDef.from_dictionary(raw)
	h.check("物件移动后局部碰撞跟随", moved.actors[0].collision_rects(),
		[Rect2(95, 120, 70, 20)])
	h.check("物件移动后局部交互跟随", moved.actors[0].reach, Rect2(84, 132, 92, 36))
	h.check("物件移动后自动基线跟随", moved.actors[0].effective_cover_y(), 120.0)
	desk.sort_collider = 4
	h.check("无效排序参考框被校验拒绝", definition.validate().is_empty(), false)
	desk.sort_collider = 0
	desk.collisions[0] = Rect2(5, 30, 0, 20)
	h.check("零宽局部碰撞被校验拒绝", definition.validate().is_empty(), false)


static func test_sorting(h: TestHarness) -> void:
	var raw := fixture()
	raw["actors"][0]["collision"].append([-10, 10, 8, 12])
	raw["actors"][0]["sort_collider"] = 1
	raw["actors"][0]["sort_offset"] = -4
	var definition := MapDef.from_dictionary(raw)
	var desk: MapDef.Actor = definition.actors[0]
	h.check("多个局部碰撞都转换到地图坐标", desk.collision_rects(),
		[Rect2(65, 70, 70, 20), Rect2(50, 50, 8, 12)])
	h.check("参考碰撞框索引从数据解析", desk.sort_collider, 1)
	h.check("自动遮挡取指定碰撞框上缘", desk.auto_cover_y(), 50.0)
	h.check("排序偏移从数据解析", desk.sort_offset, -4.0)
	h.check("偏移叠加到自动上缘", desk.effective_cover_y(), 46.0)
	raw["actors"][0]["cover_y"] = 88
	var manual := MapDef.from_dictionary(raw)
	h.check("旧手动 cover_y 优先于自动基线和偏移", manual.actors[0].effective_cover_y(), 88.0)
	manual.actors[0].cover_y = 0.0
	h.check("零值 cover_y 也是有效手动覆盖", manual.actors[0].effective_cover_y(), 0.0)
	manual.actors[0].cover_y = -1.0
	h.check("清除手动覆盖后恢复上缘加偏移", manual.actors[0].effective_cover_y(), 46.0)


static func test_runtime(h: TestHarness) -> void:
	var raw := fixture()
	raw["actors"][0]["collision"].append([-10, 10, 8, 12])
	var definition := MapDef.from_dictionary(raw)
	var view := MapView.new()
	h.root.add_child(view)
	view.build(definition)
	var boxes := _physical_boxes(h, view)
	h.check("实际物理节点使用所有局部框而非整张贴图", boxes,
		[Rect2(65, 70, 70, 20), Rect2(50, 50, 8, 12)])
	var points: Array[Vector2] = [Vector2(90, 80), Vector2(90, 60), Vector2(53, 60),
		Vector2(150, 80), Vector2(90, 110), Vector2(90, 70)]
	var expected_free: Array[bool] = [false, true, false, true, true, true]
	var expected_landing: Array[bool] = [false, true, false, true, true, false]
	for index: int in points.size():
		var point: Vector2 = points[index]
		h.check("物理脚底与碰撞框相交判定 %s" % point,
			_physical_is_free(boxes, point), expected_free[index])
		h.check("WalkGrid 与实际物理框一致 %s" % point,
			WalkGrid.is_free(definition, point), expected_free[index])
		h.check("局部碰撞的导航落点余量 %s" % point,
			WalkGrid.has_landing_room(definition, point), expected_landing[index])
	view.queue_free()


static func test_cover_y_runtime(h: TestHarness) -> void:
	var definition := MapDef.from_dictionary(fixture())
	var desk: MapDef.Actor = definition.actors[0]
	var view := MapView.new()
	h.root.add_child(view)
	view.build(definition)
	h.check("局部碰撞物件登记遮挡", view.cover_count(), 1)
	_check_cover(h, view, "自动碰撞上缘", 70.0)
	desk.sort_offset = -4.0
	view.build(definition)
	_check_cover(h, view, "自动上缘加偏移", 66.0)
	view.set_player_y(60.0)
	h.check("手调前同一站位被物件遮挡", view.cover_z(0) > 10, true)
	desk.cover_y = 50.0
	view.build(definition)
	view.set_player_y(60.0)
	h.check("重建后手动 cover_y 改变同一站位的遮挡", view.cover_z(0) < 10, true)
	_check_cover(h, view, "手动 cover_y 覆盖偏移", 50.0)
	desk.cover_y = -1.0
	view.build(definition)
	_check_cover(h, view, "清除手动基线", 66.0)
	view.queue_free()


static func test_legacy(h: TestHarness) -> void:
	var raw := {"id": "legacy_geometry", "size": [400, 300], "walls": [], "actors": [
		{"id": "solid_desk", "rect": [60, 40, 80, 60], "solid": true, "cover": true,
			"sprite": "res://art/props/gatehouse_desk.png", "reach": [55, 90, 90, 30]},
		{"id": "person", "rect": [200, 40, 30, 40], "person": true}]}
	var definition := MapDef.from_dictionary(raw)
	var solid: MapDef.Actor = definition.actors[0]
	var person: MapDef.Actor = definition.actors[1]
	h.check("旧 solid 不误判为局部碰撞", solid.has_local_collision, false)
	h.check("旧 solid 保持整块碰撞", solid.collision_rects(), [Rect2(60, 40, 80, 60)])
	h.check("旧 reach 保持绝对坐标", solid.reach, Rect2(55, 90, 90, 30))
	h.check("旧物件自动基线保持贴图底边", solid.effective_cover_y(), 100.0)
	h.check("旧 person 不误判为局部碰撞", person.has_local_collision, false)
	h.check("旧 person 保持脚底窄条碰撞", person.collision_rects(), [Rect2(202, 72, 26, 8)])
	h.check("旧物件缺省交互框保持贴图范围", person.reach, person.rect)
	var view := MapView.new()
	h.root.add_child(view)
	view.build(definition)
	h.check("旧 solid/person 的实际物理节点保持兼容", _physical_boxes(h, view),
		[Rect2(60, 40, 80, 60), Rect2(202, 72, 26, 8)])
	h.check("旧 solid 导航仍挡住整块区域", WalkGrid.is_free(definition, Vector2(90, 60)), false)
	h.check("旧 solid 导航落点仍保留余量",
		WalkGrid.has_landing_room(definition, Vector2(149, 80)), false)
	_check_cover(h, view, "旧格式贴图底边", 100.0)
	solid.cover_y = 50.0
	view.build(definition)
	_check_cover(h, view, "旧格式手动基线", 50.0)
	view.queue_free()


static func test_collision_override(h: TestHarness) -> void:
	var raw := fixture()
	raw["actors"][0]["solid"] = true
	raw["actors"][0]["person"] = true
	var definition := MapDef.from_dictionary(raw)
	h.check("显式局部碰撞优先于 solid/person 回退", definition.actors[0].collision_rects(),
		[Rect2(65, 70, 70, 20)])
	h.check("局部框外仍可通过原 solid 贴图范围",
		WalkGrid.is_free(definition, Vector2(90, 60)), true)
	var view := MapView.new()
	h.root.add_child(view)
	view.build(definition)
	h.check("物理层同样优先采用显式局部碰撞", _physical_boxes(h, view),
		[Rect2(65, 70, 70, 20)])
	view.queue_free()
	raw["actors"][0]["collision"] = []
	raw["actors"][0]["cover"] = false
	var empty := MapDef.from_dictionary(raw)
	h.check("显式空碰撞仍与缺少字段区分", empty.actors[0].has_local_collision, true)
	h.check("显式空碰撞不恢复旧 solid/person 框", empty.actors[0].collision_rects(), [])
	h.check("空碰撞物件允许导航通过", WalkGrid.is_free(empty, Vector2(90, 80)), true)
	h.check("空碰撞物件允许导航落脚", WalkGrid.has_landing_room(empty, Vector2(90, 80)), true)
	h.check("无动态遮挡的空碰撞物件合法", empty.validate(), [])


static func _check_cover(h: TestHarness, view: MapView, label: String, baseline: float) -> void:
	view.set_player_y(baseline - 1.0)
	h.check("%s：北侧物件盖住角色" % label, view.cover_z(0) > 10, true)
	view.set_player_y(baseline + 1.0)
	h.check("%s：南侧角色盖住物件" % label, view.cover_z(0) < 10, true)


static func _physical_boxes(h: TestHarness, view: MapView) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var body := view.get_node_or_null("Built/Actors") as StaticBody2D
	h.check("物件物理碰撞体存在", body != null, true)
	if body == null:
		return result
	for child: Node in body.get_children():
		var collision := child as CollisionShape2D
		h.check("物件碰撞节点类型正确", collision != null, true)
		if collision == null:
			continue
		var box := collision.shape as RectangleShape2D
		h.check("物件物理碰撞使用矩形", box != null, true)
		if box != null:
			result.append(Rect2(collision.position - box.size * 0.5, box.size))
	return result


static func _physical_is_free(boxes: Array[Rect2], point: Vector2) -> bool:
	var foot := Rect2(point + Vector2(-Player.FOOT_SIZE.x * 0.5,
		Player.FOOT_OFFSET - Player.FOOT_SIZE.y * 0.5), Player.FOOT_SIZE)
	for box: Rect2 in boxes:
		if foot.intersects(box):
			return false
	return true
