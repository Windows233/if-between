## 主角跨地图显示标尺：贴图、脚底碰撞、镜头边界与实际步速一起验证。
##
## 正式地图只读；出生点、物件与存档坐标均以当前数据为准，不固定内容坐标。
##
## 由测试入口的延迟阶段调用，根节点入树后再验证真实物理帧。
extends RefCounted


class TimingCutscene extends Cutscene:
	var spans: Array[float] = []

	func _move_to(node: Node2D, target: Vector2, time: float) -> void:
		spans.append(time)
		node.position = target

	func _footsteps_for(_seconds: float) -> void:
		pass


static func run(h: TestHarness) -> void:
	h.section("全场景统一主角标尺")
	_test_zoom_and_legacy(h)
	_test_all_maps(h)
	_test_head_anchor(h)
	_test_cutscene_speed(h)
	_test_npc_scale_and_restore(h)
	_test_save_roundtrip(h)
	await _test_physics_speed(h)


static func _test_zoom_and_legacy(h: TestHarness) -> void:
	var camera := GameCamera.new()
	h.root.add_child(camera)
	var view := GameCamera.view_size()
	var world := view * 8.0
	for ratio: float in [0.25, 0.5, 1.0, 2.0]:
		var label := "比例 %s" % ratio
		var expected_zoom := Vector2.ONE / ratio
		h.check(label + " 的房间镜头", GameCamera.room_zoom_for(ratio), expected_zoom)
		camera.follow(world * 0.5, world, false, ratio)
		h.check(label + " 的房间镜头不按整图适配", camera.zoom, expected_zoom)
		h.check(label + " 的中心跟随", camera.global_position, world * 0.5)
		camera.follow(-world, world, false, ratio)
		h.check(label + " 的左上边界", camera.global_position, view * ratio * 0.5)
		camera.follow(world * 2.0, world, false, ratio)
		h.check(label + " 的右下边界", camera.global_position, world - view * ratio * 0.5)
		camera.follow(Vector2.ZERO, view * ratio * 0.5, false, ratio)
		h.check(label + " 的小地图居中", camera.global_position, view * ratio * 0.25)
		camera.follow(world * 0.5, world, true, ratio)
		h.check(label + " 不影响大地图全景", camera.zoom, GameCamera.zoom_for(world, view))
	# 第四参数缺省的旧调用仍是 1:1，不能让现有调用者意外放大。
	camera.follow(world * 0.5, world)
	h.check("未传地图标尺时保留旧镜头", camera.zoom, Vector2.ONE)
	h.check("非法零比例不产生无限镜头", GameCamera.room_zoom_for(0.0), Vector2.ONE)
	h.check("非法负比例回退", GameCamera.room_zoom_for(-1.0), Vector2.ONE)
	camera.queue_free()


static func _map_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for filename: String in DirAccess.get_files_at(DataLoader.MAP_DIR):
		if filename.ends_with(".json"):
			ids.append(StringName(filename.get_basename()))
	ids.sort()
	return ids


static func _layout(definition: MapDef) -> Dictionary:
	var actors: Array = []
	for actor: MapDef.Actor in definition.actors:
		actors.append([actor.id, actor.rect, actor.reach, actor.collision_rects(),
			actor.effective_cover_y()])
	var portals: Array = []
	for portal: MapDef.Portal in definition.portals:
		portals.append([portal.id, portal.rect, portal.target_map, portal.target_spawn])
	return {"size": definition.size, "walls": definition.walls.duplicate(),
		"spawns": definition.spawns.duplicate(), "actors": actors, "portals": portals,
		"background": definition.background, "overlay": definition.overlay}


static func _test_all_maps(h: TestHarness) -> void:
	var main := h.new_main()
	var ids := _map_ids()
	h.check("自动枚举到正式地图", ids.is_empty(), false)
	var rooms := 0
	var overviews := 0
	for id: StringName in ids:
		var definition := DataLoader.load_map(id)
		h.check("%s 可读取" % id, definition != null, true)
		if definition == null:
			continue
		var before := _layout(definition)
		var spawn: StringName = definition.spawns.keys()[0] if not definition.spawns.is_empty() else &"default"
		main.enter_map(id, spawn)
		h.check("%s 实际切图成功" % id, main.current_map.id, id)
		h.check("%s 运行时保留地图布局和原坐标" % id, _layout(main.current_map), before)
		h.check("%s 出生点保留原坐标" % id, main.player.global_position, definition.spawn_point(spawn))
		h.check("%s 地图节点不叠加缩放" % id, main.map_view.scale, Vector2.ONE)
		var ratio := definition.player_scale
		h.check("%s 主角保留地图坐标比例" % id, main.player.scale, Vector2.ONE * ratio)
		if definition.kind == MapDef.Kind.OVERWORLD:
			overviews += 1
			h.check("%s 大地图隐藏主角" % id, main.player.visible, false)
			h.check("%s 大地图完整展示" % id, main.camera.zoom,
				GameCamera.zoom_for(Vector2(definition.size), GameCamera.view_size()))
			continue
		rooms += 1
		h.check("%s 走动场景显示主角" % id, main.player.visible, true)
		h.check("%s 主角屏幕高度标尺" % id, Player.DISPLAY_HEIGHT, 45.0)
		h.check("%s 使用地图标尺对应镜头" % id, main.camera.zoom, GameCamera.room_zoom_for(ratio))
		_check_body(h, main.player, main.camera.zoom, str(id))
		# 连续重算必须稳定，不能从上一帧的缩放视口来回推导。
		var old_zoom: Vector2 = main.camera.zoom
		for frame: int in range(3):
			main.update_camera()
		h.check("%s 连续帧镜头稳定" % id, main.camera.zoom, old_zoom)
		var world := Vector2(definition.size)
		var half: Vector2 = GameCamera.view_size() / main.camera.zoom * 0.5
		main.camera_focus = -world
		main.update_camera()
		h.check("%s 剧情焦点左上夹边" % id, main.camera.global_position,
			Vector2(minf(half.x, world.x * 0.5), minf(half.y, world.y * 0.5)))
		main.camera_focus = world * 2.0
		main.update_camera()
		h.check("%s 剧情焦点右下夹边" % id, main.camera.global_position,
			Vector2(maxf(world.x - half.x, world.x * 0.5), maxf(world.y - half.y, world.y * 0.5)))
		main.camera_focus = null
	h.check("走动地图得到覆盖", rooms > 0, true)
	h.check("大地图得到覆盖", overviews > 0, true)
	main.queue_free()


static func _check_body(h: TestHarness, player: Player, zoom: Vector2, label: String) -> void:
	var sprite := player.get_node_or_null("Body") as AnimatedSprite2D
	h.check(label + " 使用正式主角帧图", sprite != null, true)
	if sprite != null:
		for animation: StringName in sprite.sprite_frames.get_animation_names():
			for frame: int in range(sprite.sprite_frames.get_frame_count(animation)):
				var texture := sprite.sprite_frames.get_frame_texture(animation, frame)
				h.check_float("%s %s/%d 实际贴图屏幕高度" % [label, animation, frame],
					texture.get_size().y * sprite.global_scale.y * zoom.y, 45.0)
	var collision := player.get_child(0) as CollisionShape2D
	h.check(label + " 使用正式脚底碰撞", collision != null, true)
	if collision != null:
		var shape := collision.shape as RectangleShape2D
		h.check(label + " 屏幕碰撞为 16×16", shape.size * collision.global_scale * zoom, Vector2(16, 16))
		h.check_float(label + " 碰撞底边仍贴脚底",
			(collision.position.y + shape.size.y * 0.5) * player.scale.y * zoom.y, 0.0)
	h.check_float(label + " 屏幕步速为 96", player.movement_speed() * zoom.x, 96.0)


static func _test_head_anchor(h: TestHarness) -> void:
	var main := h.new_main()
	var player: Player = main.player
	main.current_map.player_scale = 0.5
	player.scale = Vector2.ONE * 0.5
	var target: Vector2 = main.current_map.spawn_point(main.current_spawn)
	main.cutscene.instant = true
	main.cutscene._place_player(StageStep.from_dictionary({"do": "place_player",
		"anchor": "head", "at": [target.x, target.y], "pin": true}))
	var zoom: Vector2 = main.camera.zoom
	var head := player.global_position + player.head_offset()
	h.check_float("半比例主角头中心保留剧情 x 坐标", head.x, target.x)
	h.check_float("半比例主角头中心保留剧情 y 坐标", head.y, target.y)
	h.check_float("半比例头到脚屏幕距离不漂移", -player.head_offset().y * zoom.y,
		Player.DISPLAY_HEIGHT * Player.HEAD_RATIO)
	h.check_float("半比例脚底按原地图坐标补偿", player.global_position.y - target.y,
		Player.DISPLAY_HEIGHT * Player.HEAD_RATIO * 0.5)
	_check_body(h, player, zoom, "半比例头锚点")
	main.queue_free()


static func _test_cutscene_speed(h: TestHarness) -> void:
	var main := h.new_main()
	var scene := TimingCutscene.new()
	scene.setup(main)
	for ratio: float in [0.25, 0.5, 1.0, 2.0]:
		main.player.scale = Vector2.ONE * ratio
		main.player.global_position = Vector2.ZERO
		var route: Array[Vector2] = [Vector2(24.0, 0.0) * ratio, Vector2(24.0, 24.0) * ratio]
		scene.spans.clear()
		scene._walk_player(route, 0.0)
		h.check("比例 %s 默认演出跟随屏幕步速" % ratio, scene.spans, [0.25, 0.25])
		h.check("比例 %s 演出终点保留世界坐标" % ratio, main.player.global_position, route.back())
		main.player.global_position = Vector2.ZERO
		scene.spans.clear()
		scene._walk_player(route, 2.0)
		h.check("比例 %s 保留剧本显式用时" % ratio, scene.spans, [1.0, 1.0])
	main.queue_free()


static func _test_npc_scale_and_restore(h: TestHarness) -> void:
	var main := h.new_main()
	var scene: Cutscene = main.cutscene
	var fixtures := [
		{"id": "static", "sprite": "res://art/portrait/elder.png", "height": 42.0},
		{"id": "c", "sprite": "res://art/npc/c", "height": 45.0, "requested_height": 32.0},
		{"id": "b", "sprite": "res://art/npc/b", "height": 45.0, "requested_height": 42.0},
		{"id": "elder", "sprite": "res://art/npc/elder", "height": 45.0},
	]
	for ratio: float in [0.5, 1.0, 2.0]:
		scene.clear_actors()
		main.current_map.player_scale = ratio
		main.player.scale = Vector2.ONE * ratio
		main.update_camera()
		var zoom: Vector2 = main.camera.zoom
		for fixture: Dictionary in fixtures:
			var at: Vector2 = main.current_map.spawn_point(main.current_spawn)
			var actor := scene.add_actor(str(fixture.id), str(fixture.sprite), at, float(fixture.get("requested_height", fixture.height)))
			h.check("比例 %s %s 创建成功" % [ratio, fixture.id], actor != null, true)
			if actor == null:
				continue
			h.check("比例 %s %s 类型正确" % [ratio, fixture.id],
				actor is Sprite2D if fixture.id == "static" else actor is AnimatedSprite2D, true)
			_check_npc(h, actor, zoom, float(fixture.height), "比例 %s %s" % [ratio, fixture.id])
		# snapshot 的 height 是原始标称高度；连续读写不得把地图系数积累进去。
		for cycle: int in range(3):
			var snapshot := scene.snapshot_actors()
			h.check("比例 %s 第 %d 次快照人数" % [ratio, cycle], snapshot.size(), fixtures.size())
			for fixture: Dictionary in fixtures:
				var entry := _actor_entry(snapshot, str(fixture.id))
				h.check("比例 %s 第 %d 次 %s 快照保留标称高度" % [ratio, cycle, fixture.id],
					entry.get("height"), fixture.height)
			scene.clear_actors()
			scene.restore_actors(snapshot)
			for fixture: Dictionary in fixtures:
				var restored := scene._actor(str(fixture.id))
				h.check("比例 %s 第 %d 次 %s 恢复" % [ratio, cycle, fixture.id], restored != null, true)
				if restored != null:
					_check_npc(h, restored, zoom, float(fixture.height),
						"比例 %s 第 %d 次恢复 %s" % [ratio, cycle, fixture.id])
	# 旧存档同样只有 recipe height，没有比例字段；在新标尺下仍只应用一次。
	scene.clear_actors()
	main.current_map.player_scale = 0.5
	main.player.scale = Vector2.ONE * 0.5
	main.update_camera()
	var legacy: Array = [{"id": "legacy", "sprite": "res://art/portrait/elder.png",
		"at": [100.0, 120.0], "height": 42.0, "z": 9, "pose": "", "talk": ""}]
	scene.restore_actors(legacy)
	var old_actor := scene._actor("legacy")
	h.check("原格式 NPC 快照恢复成功", old_actor != null, true)
	if old_actor != null:
		_check_npc(h, old_actor, main.camera.zoom, 42.0, "原格式 NPC 快照")
		h.check("旧 NPC 脚底坐标保持不变", old_actor.global_position, Vector2(100, 120))
	main.queue_free()


static func _actor_entry(entries: Array, id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


static func _check_npc(h: TestHarness, actor: Node2D, zoom: Vector2,
		height: float, label: String) -> void:
	var picture := Vector2.ZERO
	if actor is Sprite2D:
		picture = (actor as Sprite2D).texture.get_size()
	elif actor is AnimatedSprite2D:
		var animated := actor as AnimatedSprite2D
		picture = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame).get_size()
	var projected := picture * actor.global_scale * zoom
	h.check_float(label + " 实际贴图屏幕高度", projected.y, height)
	h.check_float(label + " 相对主角显示比例", projected.y / Player.DISPLAY_HEIGHT, height / 45.0)
	var body := actor.get_node_or_null("Body") as StaticBody2D
	h.check(label + " 有脚底实体", body != null, true)
	if body == null:
		return
	var collision := body.get_child(0) as CollisionShape2D
	var shape := collision.shape as RectangleShape2D
	var feet := shape.size * collision.global_scale * zoom
	h.check_float(label + " 脚底实体屏幕高度固定 8", feet.y, 8.0)
	h.check_float(label + " 脚底实体两侧合计收窄 4", feet.x, maxf(projected.x - 4.0, 1.0))
	h.check_float(label + " 实体底边保持脚底锚点",
		(collision.global_position.y - actor.global_position.y) * zoom.y + feet.y * 0.5, 0.0)


static func _test_save_roundtrip(h: TestHarness) -> void:
	var definition: MapDef = null
	for id: StringName in _map_ids():
		var candidate := DataLoader.load_map(id)
		if candidate.kind == MapDef.Kind.ROOM and not is_equal_approx(candidate.player_scale, 1.0):
			definition = candidate
			break
	h.check("存读覆盖真实非 1 比例地图", definition != null, true)
	if definition == null:
		return
	const SLOT := 2
	var path := SaveStore.path_for(SLOT)
	var existed := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()
	var main := h.new_main()
	var spawn: StringName = definition.spawns.keys()[0] if not definition.spawns.is_empty() else &"default"
	main.enter_map(definition.id, spawn)
	var position: Vector2 = definition.spawn_point(spawn) + Vector2(1, 2)
	main.player.global_position = position
	main.player.facing = Vector2.LEFT
	h.check("非 1 比例地图可存档", main.save_game(SLOT), true)
	var saved := SaveStore.read(SLOT)
	h.check("存档保留地图原生位置", saved.player_position, position)
	main.enter_map(&"overworld", &"default")
	h.check("从大地图读回缩放场景", main.load_game(SLOT), true)
	main.update_camera()
	h.check("读档恢复原坐标", main.player.global_position, position)
	h.check("读档恢复朝向", main.player.facing, Vector2.LEFT)
	h.check("读档恢复地图比例", main.player.scale, Vector2.ONE * definition.player_scale)
	_check_body(h, main.player, main.camera.zoom, "读档后")
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	else:
		SaveStore.delete(SLOT)
	main.queue_free()


static func _test_physics_speed(h: TestHarness) -> void:
	var player := Player.create()
	# 远离正式地图物理体，只测移动规则；屏幕距离与真实经过的物理帧对照。
	h.root.add_child(player)
	var tree := h.root.get_tree()
	for ratio: float in [0.25, 0.5, 1.0, 2.0]:
		player.scale = Vector2.ONE * ratio
		player.global_position = Vector2(100000, 100000)
		player.walk_path.clear()
		player.walk_path.append(player.global_position + Vector2(1000.0 * ratio, 0.0))
		player.set_physics_process(true)
		await tree.physics_frame
		var start := player.global_position
		var ticks := Engine.get_physics_frames()
		for frame: int in range(6):
			await tree.physics_frame
		player.set_physics_process(false)
		var elapsed := float(Engine.get_physics_frames() - ticks) / float(Engine.physics_ticks_per_second)
		var zoom := GameCamera.room_zoom_for(ratio)
		h.check_float("比例 %s 实际物理速度" % ratio, player.velocity.x * zoom.x, 96.0)
		h.check_float("比例 %s 物理帧屏幕位移" % ratio,
			(player.global_position.x - start.x) * zoom.x, 96.0 * elapsed, 0.1)
		h.check_float("比例 %s 物理移动没有竖向漂移" % ratio, player.global_position.y, start.y)
	player.queue_free()
