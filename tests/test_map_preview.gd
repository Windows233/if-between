## 布局试走的定向测试，也可通过 --script 独立运行。
##
## 同时检查普通 SceneTree 和 --editor 下的工具脚本行为。
##
## 父测试入口可调用 run(harness)。独立运行还验证逐帧运动与关闭清理。
## --preview-shot=<绝对路径> 可保存视口截图；--preview-map=gatehouse 可选正式地图。
## --preview-initialize-only 在 _initialize 中只验未入树的结构，复现全量入口的时序。
@tool
extends SceneTree

const Preview := preload("res://addons/if_map_editor/map_object_preview.gd")


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--preview-initialize-only"):
		var harness := TestHarness.new()
		harness.setup(root)
		print("MAP_PREVIEW_INIT root_inside_tree=%s" % root.is_inside_tree())
		run(harness)
		quit(0 if harness.report() else 1)
		return
	call_deferred("_run")


static func run(harness: TestHarness) -> void:
	var properties: Dictionary = {}
	for property: Dictionary in ClassDB.class_get_property_list(&"SubViewport"):
		properties[property.name] = property
	harness.check("SubViewport没有own_world_2d布尔字段", properties.has("own_world_2d"), false)
	harness.check("SubViewport的world_2d接受World2D", properties.get("world_2d", {}).get("class_name"), &"World2D")
	var data := fixture()
	var source := JSON.stringify(data)
	var preview := Preview.new()
	harness.root.add_child(preview)
	preview.configure(data)
	harness.check("布局快照不修改源数据", JSON.stringify(data), source)
	harness.check("预览保持当前未保存地图ID", preview.definition.id, &"unsaved_preview")
	harness.check("预览地图使用工具脚本", preview.view.get_script().is_tool(), true)
	harness.check("预览角色使用工具脚本", preview.player.get_script().is_tool(), true)
	harness.check("预览复用运行时地图类型", preview.view is MapView, true)
	harness.check("预览复用运行时角色类型", preview.player is Player, true)
	harness.check("窗口定义物理帧回调", preview.has_method("_physics_process"), true)
	harness.check("角色由窗口单次驱动", preview.player.is_physics_processing(), false)
	var viewport := preview.view.get_parent() as SubViewport
	harness.check("绘制挂在SubViewport下", viewport != null, true)
	if viewport == null:
		preview.free()
		return
	harness.check("角色与地图共享预览视口", preview.player.get_parent(), viewport)
	harness.check("预览创建独立World2D", viewport.world_2d is World2D, true)
	var parent_viewport := harness.root as Viewport
	var parent_world: World2D = parent_viewport.world_2d if parent_viewport != null else null
	harness.check("预览物理空间不使用父视口", viewport.world_2d == parent_world, false)
	harness.check("预览视口持续渲染", viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	var built := preview.view.get_node("Built")
	var background := built.get_node_or_null("Background") as Sprite2D
	harness.check("背景构造成原生贴图节点", background != null, true)
	if background != null:
		harness.check("背景有可渲染纹理", background.texture != null, true)
	var walls := built.get_node_or_null("Walls") as StaticBody2D
	var actors := built.get_node_or_null("Actors") as StaticBody2D
	harness.check("地图墙与四周边界生成实体", walls != null and walls.get_child_count() == preview.definition.walls.size() + 4, true)
	harness.check("物件局部碰撞生成实体", actors != null and actors.get_child_count() == 1, true)
	if actors != null and actors.get_child_count() == 1:
		var shape := actors.get_child(0) as CollisionShape2D
		harness.check("局部碰撞正确换算到世界位置", shape.position, Vector2(144, 112))
		harness.check("局部碰撞保留尺寸", (shape.shape as RectangleShape2D).size, Vector2(64, 32))
	harness.check("物件贴图参与遮挡排序", preview.view.cover_count(), 1)
	preview.view.set_player_y(80)
	harness.check("人在桌后时桌子位于角色之前", preview.view.cover_z(0), MapView.COVER_Z)
	preview.view.set_player_y(160)
	harness.check("人在桌前时桌子位于角色之后", preview.view.cover_z(0), MapView.PROP_Z)
	harness.check("角色使用快照出生点", preview.player.position, Vector2(48, 112))
	harness.check("角色保留快照缩放", preview.player.scale, Vector2.ONE * preview.definition.player_scale)
	var foot := preview.player.get_child(0) as CollisionShape2D
	harness.check("角色脚底实体尺寸复用运行时常量", (foot.shape as RectangleShape2D).size, Player.FOOT_SIZE)
	harness.check("角色脚底偏移复用运行时常量", foot.position, Vector2(0, Player.FOOT_OFFSET))
	harness.check("预览范围开关默认关闭", preview._range_toggle.button_pressed, false)
	harness.check("预览范围覆盖层默认隐藏", preview._ranges.visible, false)
	harness.check("范围覆盖层收集地图、物件与角色碰撞", preview._ranges.collision_shapes.size(), 7)
	for collision: CollisionShape2D in preview._ranges.collision_shapes:
		harness.check("编辑器原生青色碰撞绘制被隐藏", collision.visible, false)
		harness.check("隐藏碰撞图形不禁用实体", collision.disabled, false)
	preview._range_toggle.button_pressed = true
	harness.check("开关能显示碰撞与交互覆盖层", preview._ranges.visible, true)
	preview._range_toggle.button_pressed = false
	harness.check("开关能恢复正常试走画面", preview._ranges.visible, false)
	var body := preview.player.get_node_or_null("Body") as AnimatedSprite2D
	harness.check("角色构造成原生动画节点", body != null, true)
	if body != null:
		harness.check("角色有站立动画和真实纹理", body.sprite_frames.get_frame_texture(&"idle_down", 0) != null, true)
		preview.player.facing = Vector2.RIGHT
		preview.player.play_animation(true)
		harness.check("工具角色可调用继承的动画方法", body.animation, &"walk_side")
		harness.check("向右移动时翻转角色", body.flip_h, true)
	var other := Preview.new()
	harness.root.add_child(other)
	other.configure(fixture())
	var other_viewport := other.view.get_parent() as SubViewport
	harness.check("两个预览的World2D互不串用", other_viewport.world_2d == viewport.world_2d, false)
	var map_reference: WeakRef = weakref(preview.view)
	var player_reference: WeakRef = weakref(preview.player)
	var world_reference: WeakRef = weakref(viewport.world_2d)
	preview.close_requested.emit()
	harness.check("关闭信号会排队释放窗口", preview.is_queued_for_deletion(), true)
	preview.free()
	other.free()
	harness.check("释放窗口清理地图节点", map_reference.get_ref(), null)
	harness.check("释放窗口清理角色节点", player_reference.get_ref(), null)
	harness.check("释放窗口清理独立World2D", world_reference.get_ref(), null)


static func fixture() -> Dictionary:
	return {"id": "unsaved_preview", "name": "未保存的预览", "size": [320, 240],
		"background": "res://art/props/gatehouse_desk.png", "player_scale": 1.0,
		"spawns": {"start": [48, 112]}, "walls": [[240, 0, 16, 240]],
		"actors": [{"id": "preview_desk", "label": "书桌", "rect": [112, 64, 64, 64],
			"sprite": "res://art/props/gatehouse_desk.png", "cover": true,
			"collision": [[0, 32, 64, 32]], "reach_local": [-16, 32, 96, 64]}]}


func _run() -> void:
	print("MAP_PREVIEW engine=%s editor=%s display=%s" % [
		Engine.get_version_info().string, Engine.is_editor_hint(), DisplayServer.get_name()])
	if Engine.is_editor_hint():
		await process_frame
		await process_frame
		while EditorInterface.get_resource_filesystem().is_scanning():
			await process_frame
	root.size = Vector2i(1280, 800)
	root.gui_embed_subwindows = true
	var harness := TestHarness.new()
	harness.setup(root)
	run(harness)
	print("MAP_PREVIEW_STRUCTURE passed=%d failed=%d" % [harness.passed, harness.failed])
	await _test_movement(harness)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-shot="):
			await _render_probe(harness, argument.trim_prefix("--preview-shot="))
	await process_frame
	quit(0 if harness.report() else 1)


func _test_movement(harness: TestHarness) -> void:
	var preview := Preview.new()
	root.add_child(preview)
	preview.configure(fixture())
	preview.show()
	preview.set_physics_process(false)
	await physics_frame
	await physics_frame
	preview.player.walk_path = [Vector2(200, 112)]
	var start := preview.player.position
	await physics_frame
	preview.player._physics_process(1.0 / Engine.physics_ticks_per_second)
	harness.check_float("每个物理帧只移动一次", preview.player.position.x - start.x,
		Player.SPEED / Engine.physics_ticks_per_second, 0.01)
	for frame: int in range(79):
		await physics_frame
		preview.player._physics_process(1.0 / Engine.physics_ticks_per_second)
		preview.view.set_player_y(preview.player.position.y)
	harness.check("继承的移动方法实际改变角色位置", preview.player.position.x > start.x + 20.0, true)
	harness.check("角色受物件局部碰撞阻挡", preview.player.position.x <= 112.0 - Player.FOOT_SIZE.x * 0.5 + 0.1, true)
	harness.check("行走时播放侧面动画", preview.player._sprite.animation, &"walk_side")
	preview.player.position = Vector2(200, 180)
	await physics_frame
	preview.player.walk_path = [Vector2(300, 180)]
	for frame: int in range(40):
		await physics_frame
		preview.player._physics_process(1.0 / Engine.physics_ticks_per_second)
	harness.check("角色能在空地行走", preview.player.position.x > 210.0, true)
	harness.check("角色受地图墙阻挡", preview.player.position.x <= 240.0 - Player.FOOT_SIZE.x * 0.5 + 0.1, true)
	var reference: WeakRef = weakref(preview)
	var world_reference: WeakRef = weakref(preview.view.get_viewport().find_world_2d())
	preview.close_requested.emit()
	await process_frame
	await process_frame
	harness.check("关闭事件后窗口在帧末释放", reference.get_ref(), null)
	harness.check("关闭事件后物理世界在帧末释放", world_reference.get_ref(), null)


func _render_probe(harness: TestHarness, output: String) -> void:
	harness.check("渲染探针使用图形驱动", DisplayServer.get_name() != "headless", true)
	if DisplayServer.get_name() == "headless":
		return
	var data := fixture()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-map="):
			var map_id := argument.trim_prefix("--preview-map=")
			data = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % map_id))
	var preview := Preview.new()
	root.add_child(preview)
	preview.configure(data)
	preview.popup_centered()
	for frame: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := preview.view.get_viewport().get_texture().get_image()
	harness.check("渲染视口输出非空图像", image != null and not image.is_empty(), true)
	if image != null and not image.is_empty():
		var colors: Dictionary = {}
		for column: int in range(16):
			for row: int in range(12):
				colors[image.get_pixel(column * image.get_width() / 16, row * image.get_height() / 12)] = true
		harness.check("渲染图像不是单色黑屏", colors.size() > 8, true)
		harness.check("预览截图保存成功", image.save_png(output), OK)
		print("MAP_PREVIEW_RENDER map=%s size=%s colors=%d screenshot=%s" % [
			preview.definition.id, image.get_size(), colors.size(), output])
	preview.close_requested.emit()
	await process_frame
