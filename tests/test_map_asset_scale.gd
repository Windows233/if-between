## 素材原像素按背景与地图的比例换算为地图单位。
##
## 独立运行：godot --headless --path <项目> --script res://tests/test_map_asset_scale.gd
##
## 只在唯一的 user:// 临时目录生成 PNG；不导入、不写正式地图或素材。
extends SceneTree

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	var directory := "user://test_map_asset_scale_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	h.check("比例测试临时目录创建成功", error, OK)
	if error != OK:
		return
	var images := {"background.png": Vector2i(1200, 800),
		"other_background.png": Vector2i(600, 400), "prop.png": Vector2i(120, 80),
		"small_prop.png": Vector2i(19, 13), "fallback_prop.png": Vector2i(2, 2)}
	var ready := true
	for filename: String in images:
		var size: Vector2i = images[filename]
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2, 0.5, 0.8, 1.0))
		var saved := image.save_png(directory.path_join(filename))
		h.check("比例测试 PNG 可保存 %s" % filename, saved, OK)
		ready = ready and saved == OK
	if ready:
		test_scale(h, directory)
		test_assignment(h, directory)
		test_fractional_placement(h, directory)
		test_display_independence(h, directory)
		test_fallback(h, directory)
	var temporary := DirAccess.open(directory)
	if temporary != null:
		for filename: String in temporary.get_files():
			h.check("清理比例测试文件 %s" % filename,
				DirAccess.remove_absolute(directory.path_join(filename)), OK)
	h.check("清理比例测试目录", DirAccess.remove_absolute(directory), OK)


static func fixture(directory: String) -> Dictionary:
	return {"id": "asset_scale", "size": [300, 200], "walls": [], "actors": [],
		"background": directory.path_join("background.png")}


static func test_scale(h: TestHarness, directory: String) -> void:
	var model = Model.new()
	model.data = fixture(directory)
	h.check("素材像素按背景四分之一比例换算", model.world_size_for_image(Vector2(120, 80)),
		Vector2(30, 20))
	h.check("换算保留不足一个地图单位的细节", model.world_size_for_image(Vector2(19, 13)),
		Vector2(4.75, 3.25))
	model.data["size"] = [300, 100]
	h.check("X/Y 分别使用背景到地图的比例", model.world_size_for_image(Vector2(120, 80)),
		Vector2(30, 10))
	model.data["size"] = [1200, 800]
	h.check("背景与地图同尺寸时保持原像素尺寸", model.world_size_for_image(Vector2(120, 80)),
		Vector2(120, 80))
	model.data["size"] = [300, 200]
	model.data["background"] = directory.path_join("other_background.png")
	h.check("切换背景立即采用新背景的实际像素", model.world_size_for_image(Vector2(120, 80)),
		Vector2(60, 40))
	h.check("零尺寸预览不产生物件尺寸", model.world_size_for_image(Vector2.ZERO), Vector2.ZERO)
	h.check("负尺寸预览不产生物件尺寸", model.world_size_for_image(Vector2(-1, 20)), Vector2.ZERO)


static func test_assignment(h: TestHarness, directory: String) -> void:
	var model = Model.new()
	model.data = fixture(directory)
	var source := directory.path_join("prop.png")
	var added: int = model.add_actor_with_sprite(source, true)
	h.check("拖入物件采用背景对应尺寸", model.rect_of(Model.Kind.ACTOR, added).size, Vector2(30, 20))
	h.check("拖入物件按换算后的尺寸居中", model.rect_of(Model.Kind.ACTOR, added).position,
		Vector2(135, 90))
	h.check("拖入物件保留遮挡选项", model.actor_field(added, "cover"), true)
	model.set_rect(Model.Kind.ACTOR, added, Rect2(10, 20, 99, 75))
	var another: int = model.add_actor_with_sprite(source)
	h.check("同图再次拖入不复用已缩放实例尺寸", model.rect_of(Model.Kind.ACTOR, another).size,
		Vector2(30, 20))
	var existing: int = model.add_actor()
	var actor: Dictionary = model.actor_dict(existing)
	actor["rect"] = [18.25, 26.5, 99, 75]
	actor["collision"] = [[1.25, 2.5, 30, 14]]
	actor["reach_local"] = [-4.5, 12.25, 45, 20]
	actor["reach"] = [5.25, 6.5, 40.75, 22.25]
	actor["sort_collider"] = 0
	actor["sort_offset"] = -3.5
	actor["cover_y"] = 64.5
	actor["event"] = "preserve_story"
	var properties: Dictionary = actor.duplicate(true)
	properties.erase("rect")
	h.check("已有物件可更换贴图", model.assign_actor_sprite(existing, source), true)
	h.check("赋贴图保留小数位置并按背景换算尺寸", model.rect_of(Model.Kind.ACTOR, existing),
		Rect2(18.25, 26.5, 30, 20))
	var after: Dictionary = model.actor_dict(existing).duplicate(true)
	after.erase("rect")
	after.erase("sprite")
	h.check("赋贴图保留碰撞交互排序和剧情属性", after, properties)
	model.set_rect(Model.Kind.ACTOR, existing, Rect2(18.25, 26.5, 90, 70))
	h.check("恢复原图尺寸入口成功", model.restore_original_size(existing), true)
	h.check("恢复尺寸仍保留小数位置", model.rect_of(Model.Kind.ACTOR, existing),
		Rect2(18.25, 26.5, 30, 20))
	var before_failure: Dictionary = model.data.duplicate(true)
	model.dirty = false
	h.check("无效贴图赋值失败", model.assign_actor_sprite(existing, directory.path_join("missing.png")), false)
	h.check("无效贴图不修改任何物件数据", model.data, before_failure)
	h.check("无效贴图不产生脏标记", model.dirty, false)
	h.check("无效物件不能恢复尺寸", model.restore_original_size(-1), false)


static func test_fractional_placement(h: TestHarness, directory: String) -> void:
	var model = Model.new()
	model.data = fixture(directory)
	var index: int = model.add_actor_with_sprite(directory.path_join("small_prop.png"))
	h.check("拖入不把小数尺寸取整", model.rect_of(Model.Kind.ACTOR, index).size, Vector2(4.75, 3.25))
	h.check("小数尺寸物件仍准确居中", model.rect_of(Model.Kind.ACTOR, index).position,
		Vector2(147.625, 98.375))
	model.set_rect(Model.Kind.ACTOR, index, Rect2(35.5, 42.25, 4.75, 3.25))
	h.check("画布落点写回不破坏预览尺寸", model.rect_of(Model.Kind.ACTOR, index),
		Rect2(35.5, 42.25, 4.75, 3.25))
	model.set_rect(Model.Kind.ACTOR, index, Rect2(35.5, 42.25, 80, 60))
	h.check("小数尺寸素材可恢复", model.restore_original_size(index), true)
	h.check("恢复小数尺寸保留落点", model.rect_of(Model.Kind.ACTOR, index),
		Rect2(35.5, 42.25, 4.75, 3.25))
	var saved: Dictionary = JSON.parse_string(Model.stringify(model.data))
	h.check("序列化保留背景像素对应的小数尺寸", saved["actors"][index]["rect"],
		[35.5, 42.25, 4.75, 3.25])
	var other: int = model.add_actor_with_sprite(directory.path_join("small_prop.png"))
	model.set_rect(Model.Kind.ACTOR, other, Rect2(100, 80, 4.75, 3.25))
	var selected: Array[int] = [index, other]
	h.check("小数物件可执行对齐", model.align_actors(selected, Model.ActorAlignment.CENTER_X), true)
	h.check("对齐不改变第一个物件的精确尺寸", model.rect_of(Model.Kind.ACTOR, index).size,
		Vector2(4.75, 3.25))
	h.check("对齐不改变第二个物件的精确尺寸", model.rect_of(Model.Kind.ACTOR, other).size,
		Vector2(4.75, 3.25))
	h.check("小数物件对齐中心一致", model.rect_of(Model.Kind.ACTOR, index).get_center().x,
		model.rect_of(Model.Kind.ACTOR, other).get_center().x)
	model.copy_actors(selected)
	var pasted: Array[int] = model.paste_actors()
	h.check("小数物件可复制粘贴", pasted.size(), 2)
	for copied: int in pasted:
		h.check("复制平移不改变精确尺寸 %d" % copied, model.rect_of(Model.Kind.ACTOR, copied).size,
			Vector2(4.75, 3.25))
	var wall: int = model.add_rect(Model.Kind.WALL, Rect2(1.2, 2.3, 4.75, 3.25))
	h.check("墙仍保持原有整数坐标语义", model.rect_of(Model.Kind.WALL, wall), Rect2(1, 2, 5, 3))
	var portal: int = model.add_rect(Model.Kind.PORTAL, Rect2(1.2, 2.3, 4.75, 3.25))
	h.check("传送区仍保持原有整数坐标语义", model.rect_of(Model.Kind.PORTAL, portal), Rect2(1, 2, 5, 3))


static func test_display_independence(h: TestHarness, directory: String) -> void:
	var model = Model.new()
	model.data = fixture(directory)
	var window := h.root as Window
	if window == null:
		h.check("比例测试拥有窗口根节点", false, true)
		return
	var original_size := window.size
	var original_content := window.content_scale_size
	window.size = Vector2i(640, 480)
	window.content_scale_size = Vector2i(320, 180)
	h.check("小窗口不改变素材地图尺寸", model.world_size_for_image(Vector2(120, 80)), Vector2(30, 20))
	window.size = Vector2i(1920, 1080)
	window.content_scale_size = Vector2i(640, 360)
	h.check("窗口及内容缩放变化不改变地图尺寸", model.world_size_for_image(Vector2(120, 80)),
		Vector2(30, 20))
	window.size = original_size
	window.content_scale_size = original_content


static func test_fallback(h: TestHarness, directory: String) -> void:
	var model = Model.new()
	model.data = fixture(directory)
	model.data.erase("background")
	h.check("缺背景时拒绝无法换算的物件尺寸", model.world_size_for_image(Vector2(120, 80)), Vector2.ZERO)
	h.check("无背景时小素材也拒绝无法换算尺寸", model.world_size_for_image(Vector2(2, 2)), Vector2.ZERO)
	model.data["background"] = directory.path_join("missing.png")
	h.check("背景丢失时拒绝无法换算的物件尺寸", model.world_size_for_image(Vector2(120, 80)), Vector2.ZERO)
	var corrupt := directory.path_join("corrupt.png")
	var file := FileAccess.open(corrupt, FileAccess.WRITE)
	h.check("可创建坏背景样例", file != null, true)
	if file != null:
		file.store_string("invalid PNG")
		file.close()
		model.data["background"] = corrupt
		var print_errors := Engine.print_error_messages
		Engine.print_error_messages = false
		var rejected_size: Vector2 = model.world_size_for_image(Vector2(120, 80))
		Engine.print_error_messages = print_errors
		h.check("背景解码失败时拒绝无法换算的物件尺寸", rejected_size, Vector2.ZERO)
	model.data["background"] = directory.path_join("background.png")
	model.data["size"] = [0, 200]
	h.check("无效地图尺寸拒绝生成物件尺寸", model.world_size_for_image(Vector2(120, 80)), Vector2.ZERO)
	model.data["size"] = [300, 200]
	var index: int = model.add_actor_with_sprite(directory.path_join("prop.png"))
	h.check("有效背景下实际添加采用像素换算尺寸",
		model.rect_of(Model.Kind.ACTOR, index).size, Vector2(30, 20))
	var tiny: int = model.add_actor_with_sprite(directory.path_join("fallback_prop.png"))
	h.check("小素材同样按背景比例换算",
		model.rect_of(Model.Kind.ACTOR, tiny).size, Vector2(0.5, 0.5))
	var actor_count := model.count(Model.Kind.ACTOR)
	model.data["background"] = ""
	h.check("无背景时实际添加入口拒绝素材",
		model.add_actor_with_sprite(directory.path_join("prop.png")), -1)
	h.check("拒绝添加不会留下半成品物件", model.count(Model.Kind.ACTOR), actor_count)
	var existing: int = model.add_actor()
	var before: Dictionary = model.data.duplicate(true)
	h.check("无背景时给已有物件换贴图失败",
		model.assign_actor_sprite(existing, directory.path_join("prop.png")), false)
	h.check("换贴图失败不修改已有物件", model.data, before)
