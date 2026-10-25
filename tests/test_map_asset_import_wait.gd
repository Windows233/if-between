## PNG 扫描结束后仍未导入的回归：目标纹理真正可载入后才能落地。
## 用内存地图、user:// 图片和可控导入延迟，不扫描或重导正式项目资源。
## 可独立 --script 运行，也可由插件测试入口 await run(harness)。
extends SceneTree

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")


class MemoryImportModel extends Model:
	var copied_path := ""

	func import_image(_source_path: String, _target_dir := "res://art/props",
			_preferred_name := "") -> String:
		return copied_path


class ImportDock extends Dock:
	var ready_paths: Dictionary = {}
	var scan_requests := 0
	var retry_requests := 0
	var complete_retry := true
	var ready_texture: Texture2D
	var wait_budget := 300
	var ready_delay_msec := 0

	func _ready() -> void:
		model = MemoryImportModel.new()
		_status = Label.new()
		add_child(_status)
		canvas = Canvas.new()
		canvas.model = model
		add_child(canvas)
		ready_texture = ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGBA8))

	func _load_imported_asset(path: String) -> Texture2D:
		return ready_texture if ready_paths.has(path) else null

	func _asset_import_timeout_msec() -> int:
		return wait_budget

	func _refresh_assets_after_scan() -> void:
		scan_requests += 1
		await get_tree().process_frame

	func _retry_asset_import(path: String, _deadline: int) -> void:
		retry_requests += 1
		if complete_retry:
			_finish_import_later(path)

	func _finish_import_later(path: String) -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		if ready_delay_msec > 0:
			await get_tree().create_timer(float(ready_delay_msec) / 1000.0).timeout
		ready_paths[path] = true

	func _allow_selection_edit() -> bool:
		return true

	func _on_edited() -> void:
		model.record_history()

	func _refresh_selection() -> void:
		pass

	func _on_tool(which: int) -> void:
		canvas.tool = which


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	await run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("导入等待目标纹理就绪")
	var folder := "user://test_map_import_wait_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var created := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	h.check("导入等待临时目录可创建", created, OK)
	if created != OK:
		return
	var source := folder.path_join("source.png")
	var copied := folder.path_join("copied.png")
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.6, 0.8))
	var source_saved := image.save_png(source)
	var copy_saved := image.save_png(copied)
	h.check("导入等待源图可保存", source_saved, OK)
	h.check("导入等待目标图可保存", copy_saved, OK)
	if source_saved == OK and copy_saved == OK:
		_test_incomplete_remap(h, copied)
		var dock := ImportDock.new()
		h.root.add_child(dock)
		_reset(dock, source, copied)
		await _test_waiting(h, dock, copied)
		await _test_import_actions(h, dock, source, copied)
		await _test_failed_import(h, dock, source, copied)
		await _test_stale_requests(h, dock, source, copied)
		dock.queue_free()
		await h.root.get_tree().process_frame
	var directory := DirAccess.open(folder)
	if directory != null:
		for filename: String in directory.get_files():
			h.check("清理导入等待文件 " + filename,
				DirAccess.remove_absolute(folder.path_join(filename)), OK)
	h.check("清理导入等待目录", DirAccess.remove_absolute(folder), OK)


static func _test_incomplete_remap(h: TestHarness, path: String) -> void:
	var dock := Dock.new()
	h.check("只有源 PNG 不会提前载入资源", dock._load_imported_asset(path), null)
	var config := ConfigFile.new()
	config.set_value("remap", "path", path + ".missing.ctex")
	h.check("缺失缓存夹具可保存", config.save(path + ".import"), OK)
	h.check("import 记录已写但纹理缓存缺失仍等待", dock._load_imported_asset(path), null)
	config.set_value("remap", "valid", false)
	config.set_value("remap", "path", path.get_base_dir().path_join("source.png"))
	h.check("无效 import 夹具可保存", config.save(path + ".import"), OK)
	h.check("标记导入失败的资源不会尝试载入", dock._load_imported_asset(path), null)
	h.check("清理模拟导入记录", DirAccess.remove_absolute(path + ".import"), OK)
	dock.free()


static func _reset(dock, source: String, copied: String) -> void:
	dock.model.data = {"id": "import_wait", "size": [640, 480], "walls": [],
		"background": source, "actors": [
			{"id": "desk", "rect": [20, 30, 100, 80], "sprite": source},
			{"id": "peer", "rect": [200, 30, 100, 80], "sprite": source}]}
	dock.model.map_id = "import_wait"
	dock.model.copied_path = copied
	dock.model.reset_history()
	dock.canvas.map_size = dock.model.map_size()
	var selected: Array[int] = [0]
	dock.canvas.select_actors(selected)
	dock._panel_index = 0
	dock.ready_paths.clear()
	dock.ready_paths[source] = true
	dock.scan_requests = 0
	dock.retry_requests = 0
	dock.complete_retry = true
	dock.ready_delay_msec = 0
	dock.wait_budget = 300


static func _test_waiting(h: TestHarness, dock, path: String) -> void:
	dock.ready_paths[path] = true
	var texture: Texture2D = await dock._wait_for_imported_asset(path)
	h.check("扫描后已就绪纹理可直接使用", texture != null, true)
	h.check("已经导入的目标无需重复导入", dock.retry_requests, 0)
	dock.ready_paths.erase(path)
	texture = await dock._wait_for_imported_asset(path)
	h.check("扫描先完成而目标延迟时仍能等待成功", texture != null, true)
	h.check("目标尚未就绪时明确重试导入一次", dock.retry_requests, 1)
	dock.ready_paths.erase(path)
	dock.complete_retry = false
	var start := Time.get_ticks_msec()
	texture = await dock._wait_for_imported_asset(path)
	h.check("真正导入失败返回空纹理", texture, null)
	h.check("真正导入失败按等待预算结束", Time.get_ticks_msec() - start < 1500, true)
	h.check("失败时也只重试一次", dock.retry_requests, 2)
	dock.complete_retry = true
	dock.wait_budget = 10000
	dock.ready_delay_msec = 4000
	start = Time.get_ticks_msec()
	texture = await dock._wait_for_imported_asset(path)
	h.check("扫描结束四秒后纹理就绪仍能成功", texture != null, true)
	h.check("等待的是目标纹理而非扫描完成标记", Time.get_ticks_msec() - start >= 4000, true)


static func _test_import_actions(h: TestHarness, dock, source: String, copied: String) -> void:
	_reset(dock, source, copied)
	await dock._import_and_create(source)
	h.check("新物件等待延迟导入后才创建", dock.model.count(Model.Kind.ACTOR), 3)
	h.check("新物件写入真正就绪的贴图", dock.model.actor_field(2, "sprite", ""), copied)
	h.check("新物件导入完成进入选择工具", dock.canvas.tool, Canvas.Tool.SELECT)
	_reset(dock, source, copied)
	await dock._import_overlay(source)
	h.check("前景层同样等待目标纹理后应用", dock.model.data.get("overlay", ""), copied)
	_reset(dock, source, copied)
	var rect: Rect2 = dock.model.rect_of(Model.Kind.ACTOR, 0)
	await dock._import_actor_texture(source, dock.model, dock.model.map_id, 0, "desk")
	h.check("已有物件换图等待导入后才应用", dock.model.actor_field(0, "sprite", ""), copied)
	h.check("已有物件换图等待期间保留尺寸", dock.model.rect_of(Model.Kind.ACTOR, 0), rect)
	_reset(dock, source, copied)
	await dock._set_actor_texture_after_scan(0, copied, dock.model, dock.model.map_id, "desk")
	h.check("手填贴图路径也共用目标等待", dock.model.actor_field(0, "sprite", ""), copied)


static func _test_failed_import(h: TestHarness, dock, source: String, copied: String) -> void:
	_reset(dock, source, copied)
	dock.complete_retry = false
	var before: Dictionary = dock.model.data.duplicate(true)
	await dock._import_and_create(source)
	h.check("真正导入失败不会创建半成品物件", dock.model.data, before)
	h.check("失败信息说明图片已复制", dock._status.text.contains("PNG 已复制到"), true)
	h.check("失败信息说明未创建物件", dock._status.text.contains("尚未创建物件"), true)
	h.check("超时状态不误判成图片导入永久失败", dock._status.text.contains("可能仍在导入"), true)
	h.check("超时提示使用已复制文件避免反复复制", dock._status.text.contains("使用已有文件"), true)
	h.check("导入失败保留复制的 PNG 以便重试", FileAccess.file_exists(copied), true)


static func _test_stale_requests(h: TestHarness, dock, source: String, copied: String) -> void:
	_reset(dock, source, copied)
	var before: Dictionary = dock.model.data.duplicate(true)
	dock._import_and_create(source)
	dock.model.map_id = "another_map"
	await _finish_frames(dock)
	h.check("等待导入时切换地图不会写入旧物件", dock.model.data, before)
	_reset(dock, source, copied)
	before = dock.model.data.duplicate(true)
	dock._import_actor_texture(source, dock.model, dock.model.map_id, 0, "desk")
	var selected: Array[int] = [1]
	dock.canvas.select_actors(selected)
	dock._panel_index = 1
	await _finish_frames(dock)
	h.check("等待导入时切换选区不会误改物件", dock.model.data, before)
	_reset(dock, source, copied)
	dock._import_actor_texture(source, dock.model, dock.model.map_id, 0, "desk")
	h.check("等待导入时新贴图请求可立即应用", dock._set_actor_texture(0, source), true)
	before = dock.model.data.duplicate(true)
	await _finish_frames(dock)
	h.check("较旧导入请求不能覆盖更新的贴图请求", dock.model.data, before)


static func _finish_frames(node: Node) -> void:
	for index: int in 6:
		await node.get_tree().process_frame
