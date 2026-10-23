extends RefCounted


static func run(h: TestHarness) -> void:
	h.section("图书馆条件入口与往返")
	var gate := DataLoader.load_map(&"school_gate")
	var library := DataLoader.load_map(&"library")
	h.check("校门地图载入", gate != null, true)
	h.check("图书馆地图载入", library != null, true)
	if gate == null or library == null:
		return
	h.check("校门定义合法", gate.validate(), [])
	h.check("图书馆定义合法", library.validate(), [])
	var entry := _portal_to(gate, &"library")
	var exit_portal := _portal_to(library, &"school_gate")
	h.check("校门有且仅有一个图书馆直达入口", _portal_count(gate, &"library"), 1)
	h.check("图书馆有且仅有一个校门出口", _portal_count(library, &"school_gate"), 1)
	if entry == null or exit_portal == null:
		return
	_test_lock(h, gate, entry)
	_test_walkability(h, gate, library, entry, exit_portal)
	_test_round_trip(h, gate, library, entry, exit_portal)


static func _test_lock(h: TestHarness, gate: MapDef, entry: MapDef.Portal) -> void:
	var locked: MapDef.Portal = null
	for portal: MapDef.Portal in gate.portals:
		if portal.event_id == &"ch2_library_locked":
			locked = portal
	h.check("保留锁门剧情入口", locked != null, true)
	if locked == null:
		return
	h.check("锁门和开放入口使用同一触发区", locked.rect, entry.rect)
	h.check("开放入口有条件", entry.condition != null, true)
	h.check("锁门入口有条件", locked.condition != null, true)
	h.check("开放入口直接传送", entry.event_id, &"")
	for scenario: Dictionary in [
		{"name": "尚未开放", "set": false, "value": false, "open": false},
		{"name": "D3尚未完成", "set": true, "value": false, "open": false},
		{"name": "D3日记剧情后开放", "set": true, "value": true, "open": true},
	]:
		var flags := WorldState.new()
		if scenario["set"]:
			flags.set_value(&"ch2/library_open", scenario["value"])
		var available: Array[MapDef.Portal] = []
		for portal: MapDef.Portal in gate.active_portals(flags):
			if portal.rect == entry.rect:
				available.append(portal)
		var prefix: String = scenario["name"]
		h.check(prefix + "入口分流互斥且不缺失", available.size(), 1)
		h.check(prefix + "开放入口状态", entry.is_active(flags), scenario["open"])
		h.check(prefix + "锁门入口状态", locked.is_active(flags), not scenario["open"])
		var expected := entry if scenario["open"] else locked
		h.check(prefix + "命中相应入口", gate.portal_at(entry.rect.get_center(), flags), expected)
	var rescued := WorldState.new()
	rescued.set_value(&"ch2/rescued_c", true)
	h.check("救援成功不提前开放图书馆", entry.is_active(rescued), false)
	h.check("救援成功仍保留锁门提示", gate.portal_at(entry.rect.get_center(), rescued), locked)
	var event := DataLoader.load_event(&"ch2_library_locked")
	h.check("锁门剧情可载入", event != null, true)
	if event != null:
		h.check("锁门剧情合法", event.validate(), [])
		h.check("锁门剧情入口存在", event.entry_node() != null, true)
		if event.entry_node() != null:
			var raw: Dictionary = event.entry_node().stage[0].data
			h.check("未开放提示符合剧情修改1.0", raw.get("lines", [{}])[0].get("text", ""),
				"还没有到自习室开放的时间")


static func _test_walkability(h: TestHarness, gate: MapDef, library: MapDef,
		entry: MapDef.Portal, exit_portal: MapDef.Portal) -> void:
	h.check("进馆目标出生点存在", library.spawns.has(entry.target_spawn), true)
	h.check("返程目标为 from_library", exit_portal.target_spawn, &"from_library")
	h.check("校门返程出生点存在", gate.spawns.has(exit_portal.target_spawn), true)
	var library_spawn := library.spawn_point(entry.target_spawn)
	var gate_spawn := gate.spawn_point(exit_portal.target_spawn)
	h.check("进馆落点可站立且留有余量", WalkGrid.has_landing_room(library, library_spawn), true)
	h.check("返程落点可站立且留有余量", WalkGrid.has_landing_room(gate, gate_spawn), true)
	var library_reached := WalkGrid.reachable(library, library_spawn)
	var gate_reached := WalkGrid.reachable(gate, gate_spawn)
	var exit_stands := _standing_points(library, library_reached, exit_portal.rect)
	var entry_stands := _standing_points(gate, gate_reached, entry.rect)
	h.check("图书馆出口从出生点走得到且能停稳", not exit_stands.is_empty(), true)
	h.check("返回校门后仍走得到图书馆入口", not entry_stands.is_empty(), true)
	h.check("图书馆出口有足够站立深度", _row_count(exit_stands) >= 4, true)
	h.check("校门图书馆入口有足够站立深度", _row_count(entry_stands) >= 4, true)
	h.check("图书馆内能离开出生点向房间内行走",
		_interior_point(library, library_reached, library_spawn).distance_to(library_spawn)
			> WalkGrid.FOOT_UP * 2.0, true)
	var flags := WorldState.new()
	h.check("返程出口不依赖开放 flag", exit_portal.is_active(flags), true)
	flags.set_value(&"ch2/library_open", true)
	h.check("图书馆开放后返程出口仍然开放", exit_portal.is_active(flags), true)
	h.check("返程落点在地图内", Rect2(Vector2.ZERO, gate.size).has_point(gate_spawn), true)


static func _test_round_trip(h: TestHarness, gate: MapDef, library: MapDef,
		entry: MapDef.Portal, exit_portal: MapDef.Portal) -> void:
	var main := h.new_main()
	main.cutscene.instant = false
	main.enter_map(&"school_gate", exit_portal.target_spawn)
	main.flags.set_value(&"ch2/rescued_c", true)
	var entry_stands := _standing_points(gate,
		WalkGrid.reachable(gate, gate.spawn_point(exit_portal.target_spawn)), entry.rect)
	if entry_stands.is_empty():
		main.queue_free()
		return
	for closed_explicitly: bool in [false, true]:
		if closed_explicitly:
			main.flags.set_value(&"ch2/library_open", false)
		main.player.global_position = entry_stands[0]
		h.check("锁门实际交互被接管", main._take_portal(), true)
		h.check("锁门交互不离开校门", main.current_map.id, &"school_gate")
		h.check("锁门交互启动原剧情", main.story.event_id, &"ch2_library_locked")
		h.drain_dialogue(main.dialogue)
	main.cutscene.instant = true
	main.flags.set_value(&"ch2/library_open", true)
	h.check("开放后入口实际目标", main.portal_destination(entry_stands[0]),
		[&"library", entry.target_spawn])
	main.use_portal_at(entry_stands[0])
	h.check("通过校门入口实际进入图书馆", main.current_map.id, &"library")
	h.check("图书馆玩家可见", main.player.visible, true)
	h.check("进馆使用地图指定出生点", main.player.global_position, library.spawn_point(entry.target_spawn))
	var library_spawn := library.spawn_point(entry.target_spawn)
	var library_reached := WalkGrid.reachable(library, library_spawn)
	var inside := _interior_point(library, library_reached, library_spawn)
	var route_inside := WalkGrid.path_to(library, library_spawn, inside)
	h.check("进馆后有通往室内的行走路径", route_inside.size() > 1, true)
	var exit_stands := _standing_points(library, library_reached, exit_portal.rect)
	if exit_stands.is_empty():
		main.queue_free()
		return
	var route_back := WalkGrid.path_to(library, inside, exit_stands[0])
	h.check("室内游走后有返回出口的路径", route_back.size() > 1, true)
	for route: Array[Vector2] in [route_inside, route_back]:
		for point: Vector2 in route:
			main.player.global_position = point
		h.check("路径终点可站立", WalkGrid.is_free(library, main.player.global_position), true)
	h.check("返程实际目标", main.portal_destination(exit_stands[0]),
		[&"school_gate", exit_portal.target_spawn])
	main.use_portal_at(exit_stands[0])
	h.check("通过馆内出口实际回到校门", main.current_map.id, &"school_gate")
	h.check("返回校门使用 from_library 出生点", main.player.global_position,
		gate.spawn_point(exit_portal.target_spawn))
	h.check("往返保留图书馆开放 flag", main.flags.get_value(&"ch2/library_open"), true)
	main.use_portal_at(entry_stands[0])
	h.check("返回校门后可以再次进馆", main.current_map.id, &"library")
	main.queue_free()


static func _portal_to(definition: MapDef, target: StringName) -> MapDef.Portal:
	for portal: MapDef.Portal in definition.portals:
		if portal.target_map == target:
			return portal
	return null


static func _portal_count(definition: MapDef, target: StringName) -> int:
	var count := 0
	for portal: MapDef.Portal in definition.portals:
		if portal.target_map == target:
			count += 1
	return count


static func _standing_points(definition: MapDef, reached: Array[Vector2], area: Rect2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point: Vector2 in reached:
		if area.has_point(point) and WalkGrid.has_landing_room(definition, point):
			result.append(point)
	return result


static func _row_count(points: Array[Vector2]) -> int:
	var rows: Dictionary = {}
	for point: Vector2 in points:
		rows[point.y] = true
	return rows.size()


static func _interior_point(definition: MapDef, reached: Array[Vector2], spawn: Vector2) -> Vector2:
	var result := spawn
	for point: Vector2 in reached:
		if WalkGrid.has_landing_room(definition, point) \
				and point.distance_squared_to(spawn) > result.distance_squared_to(spawn):
			result = point
	return result
