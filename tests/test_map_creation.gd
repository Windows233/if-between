## 新地图创建的独立回归：真实 PNG、像素 1:1、唯一性、失败回滚与对话框。
##
## 全部文件限于本次 user:// 临时目录；不写正式地图，不修改全量测试入口。
##
## 可直接 --headless --script 运行，也可由调用者通过 static run(h) 执行。
extends SceneTree

const Creation := preload("res://addons/if_map_editor/map_creation.gd")
const Dialog := preload("res://addons/if_map_editor/map_creation_dialog.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	run(harness)
	await _test_popup_layout(harness)
	quit(0 if harness.report() else 1)


func _test_popup_layout(h: TestHarness) -> void:
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.gui_embed_subwindows = true
	root.size = Vector2i(1024, 768)
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.open_creation("user://creation_layout_maps", "user://creation_layout_art")
	for frame: int in 6:
		await process_frame
	h.check("768窗口首次弹出为600×580", dialog.size, Vector2i(600, 580))
	h.check("首次弹出内容不溢出", dialog._content.get_combined_minimum_size().y <= 500.0, true)
	dialog._source_label.text = "很长的场景图目录/".repeat(30) + "场景.png"
	for frame: int in 6:
		await process_frame
	h.check("长路径不让窗口无限增长", dialog.size, Vector2i(600, 580))
	h.check("长路径有行数上限", dialog._source_label.get_combined_minimum_size().y <= 64.0, true)
	dialog.hide()
	dialog.open_creation("user://creation_layout_maps", "user://creation_layout_art")
	for frame: int in 6:
		await process_frame
	h.check("重复打开尺寸不累积", dialog.size, Vector2i(600, 580))
	if DisplayServer.get_name() != "headless":
		await process_frame
		h.check("保存对话框布局截图", root.get_texture().get_image().save_png(
			"res://.godot/map_creation_dialog_preview.png"), OK)
	root.size = Vector2i(480, 768)
	dialog.hide()
	dialog.open_creation("user://creation_layout_maps", "user://creation_layout_art")
	for frame: int in 6:
		await process_frame
	h.check("窄窗口按可用宽度缩小", dialog.size, Vector2i(448, 580))
	h.check("窄窗口内容仍能放入", dialog._content.get_combined_minimum_size().y <= 500.0, true)
	dialog.canceled.emit()
	await process_frame
	h.check("取消连接queue_free后释放窗口", is_instance_valid(dialog), false)


## 所有断言与清理均使用独立测试目录；h 为现有 TestHarness。
static func run(h: TestHarness) -> void:
	var directory := "user://test_map_creation_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	h.check("创建测试目录", DirAccess.make_dir_recursive_absolute(directory), OK)
	var source := directory.path_join("scene.PNG")
	var image := Image.create(120, 84, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.6, 1.0))
	h.check("生成真实 PNG", image.save_png(source), OK)
	_test_creation(h, directory, source)
	_test_rejections(h, directory, source)
	_test_assets(h, directory, source)
	_test_rollback(h, directory, source)
	_test_dialog(h, directory, source)
	_remove_tree(directory)
	h.check("测试清理完整", DirAccess.dir_exists_absolute(directory), false)


static func _test_creation(h: TestHarness, directory: String, source: String) -> void:
	var maps := directory.path_join("maps")
	var art := directory.path_join("art")
	var original := FileAccess.get_file_as_bytes(source)
	var result := Creation.create("test_01", "  旧图书馆  ", source, maps, art)
	h.check("新建成功", result["ok"], true)
	h.check("成功无错误", result["error"], "")
	if not result["ok"]:
		return
	h.check("地图路径", result["path"], maps.path_join("test_01.json"))
	h.check("背景路径", result["background"], art.path_join("test_01.png"))
	var data: Dictionary = result["data"]
	h.check("尺寸直接取原图，绝不除以 12", data["size"], [120, 84])
	h.check("显示名写入 MapDef.name", MapDef.from_dictionary(data).name, "旧图书馆")
	h.check("默认出生点名为 start", data["spawns"].keys(), ["start"])
	h.check("默认出生点在中心", data["spawns"]["start"], [60.0, 42.0])
	h.check("MapDef 能按 start 取得出生点", MapDef.from_dictionary(data).spawn_point(&"start"), Vector2(60, 42))
	for key: String in ["actors", "walls", "portals"]:
		h.check("新地图空布局 " + key, data[key], [])
	h.check("新地图通过全部 MapDef 校验", MapDef.from_dictionary(data).validate(), [])
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result["path"]))
	h.check("落盘 JSON 通过 MapDef 校验", MapDef.from_dictionary(saved).validate(), [])
	h.check("落盘 JSON 的标识、名称和背景", [saved["id"], saved["name"], saved["background"]],
		[data["id"], data["name"], data["background"]])
	h.check("落盘 JSON 的原像素尺寸", MapDef.from_dictionary(saved).size, Vector2i(120, 84))
	h.check("JSON 使用两空格缩进", FileAccess.get_file_as_string(result["path"]), JSON.stringify(data, "  ") + "\n")
	h.check("背景原样复制", FileAccess.get_file_as_bytes(result["background"]), original)
	h.check("不改源图", FileAccess.get_file_as_bytes(source), original)
	var old_map := FileAccess.get_file_as_bytes(result["path"])
	var before := _inventory(directory)
	_check_failure(h, "重复 ID", Creation.create("test_01", "重复", source, maps, art))
	h.check("重复创建无额外文件", _inventory(directory), before)
	h.check("旧图数据逐字节保留", FileAccess.get_file_as_bytes(result["path"]), old_map)
	var tiny_source := directory.path_join("tiny.png")
	var tiny := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	h.check("最小正尺寸 PNG", tiny.save_png(tiny_source), OK)
	var small := Creation.create("tiny", "小图", tiny_source, maps, art)
	h.check("尺寸限制沿用 MapDef", small["ok"], true)
	if small["ok"]:
		h.check("小图出生点不越界", MapDef.from_dictionary(small["data"]).validate(), [])


static func _test_rejections(h: TestHarness, directory: String, source: String) -> void:
	var maps := directory.path_join("maps")
	var art := directory.path_join("art")
	var before := _inventory(directory)
	for map_id: String in ["", "Upper", "a-b", "a/b", "../bad", "a\\b", "has space", "中文", "é", "a\n", "a "]:
		_check_failure(h, "非法 ID " + var_to_str(map_id), Creation.create(map_id, "名称", source, maps, art))
	for label: String in ["", "   ", "第一行\n第二行", "名称\t"]:
		_check_failure(h, "非法名称 " + var_to_str(label), Creation.create("invalid_name", label, source, maps, art))
	_check_failure(h, "源图不存在", Creation.create("missing", "名称", directory.path_join("missing.png"), maps, art))
	h.check("校验失败无落盘", _inventory(directory), before)
	var fake := directory.path_join("fake.png")
	_write_bytes(fake, "not a PNG".to_utf8_buffer())
	_check_failure(h, "伪装 PNG", Creation.create("fake", "名称", fake, maps, art))
	_write_bytes(fake, PackedByteArray(Creation.PNG_SIGNATURE) + PackedByteArray([0, 0, 0, 0]))
	var previous_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	var truncated := Creation.create("truncated", "名称", fake, maps, art)
	Engine.print_error_messages = previous_errors
	_check_failure(h, "签名正确但不能解码", truncated)
	var renamed := directory.path_join("renamed.jpg")
	_write_bytes(renamed, FileAccess.get_file_as_bytes(source))
	_check_failure(h, "扩展名也必须是 PNG", Creation.create("renamed", "名称", renamed, maps, art))
	_write_bytes(maps.path_join("other_filename.json"), '{"id":"claimed"}'.to_utf8_buffer())
	_check_failure(h, "不同文件名中的重复 ID", Creation.create("claimed", "名称", source, maps, art))
	var occupied := maps.path_join("occupied.json")
	DirAccess.make_dir_absolute(occupied)
	_check_failure(h, "目录占用地图路径", Creation.create("occupied", "名称", source, maps, art))
	_check_failure(h, "输出目录是已有文件", Creation.create("blocked", "名称", source, fake, art))
	_check_failure(h, "素材目录是已有文件", Creation.create("blocked", "名称", source, maps, fake))
	_check_failure(h, "拒绝相对输出目录", Creation.create("relative", "名称", source, "data/maps", art))


static func _test_assets(h: TestHarness, directory: String, source: String) -> void:
	var maps := directory.path_join("maps")
	var art := directory.path_join("art")
	var sentinel := "旧素材，不可覆盖".to_utf8_buffer()
	_write_bytes(art.path_join("collision.png"), sentinel)
	DirAccess.make_dir_absolute(art.path_join("collision_2.png"))
	_write_bytes(art.path_join("collision_3.png.import"), sentinel)
	var result := Creation.create("collision", "素材重名", source, maps, art)
	h.check("素材重名仍可新建", result["ok"], true)
	h.check("文件、目录与导入旁车都避让", result["background"], art.path_join("collision_4.png"))
	h.check("已有素材不变", FileAccess.get_file_as_bytes(art.path_join("collision.png")), sentinel)
	h.check("已有导入旁车不变", FileAccess.get_file_as_bytes(art.path_join("collision_3.png.import")), sentinel)
	var inside := art.path_join("same_source.png")
	_write_bytes(inside, FileAccess.get_file_as_bytes(source))
	var same := Creation.create("same_source", "原图就在素材目录", inside, maps, art)
	h.check("源图等于默认背景路径时避让", same["background"], art.path_join("same_source_2.png"))
	h.check("源图内容保留", FileAccess.get_file_as_bytes(inside), FileAccess.get_file_as_bytes(source))


static func _test_rollback(h: TestHarness, directory: String, source: String) -> void:
	var blocked_map := directory.path_join("old_map.json")
	DirAccess.make_dir_absolute(blocked_map)
	var sentinel := "不能删除旧文件".to_utf8_buffer()
	var marker := blocked_map.path_join("keep.txt")
	_write_bytes(marker, sentinel)
	var before := _inventory(directory)
	var background := directory.path_join("rollback/nested/new.png")
	var result := Creation._persist(blocked_map, background, {"id": "rollback"}, FileAccess.get_file_as_bytes(source))
	_check_failure(h, "背景已写入后地图写入失败", result)
	h.check("部分失败清理本次文件与目录", _inventory(directory), before)
	h.check("旧目录内文件不动", FileAccess.get_file_as_bytes(marker), sentinel)
	var blocked_folder := directory.path_join("blocked_folder")
	_write_bytes(blocked_folder, sentinel)
	before = _inventory(directory)
	result = Creation.create("directory_failure", "目录失败", source,
		directory.path_join("new_map_folders/maps"), blocked_folder.path_join("art"))
	_check_failure(h, "公开接口创建素材目录失败", result)
	h.check("目录创建失败清理本次空目录", _inventory(directory), before)
	h.check("挡住目录的旧文件不动", FileAccess.get_file_as_bytes(blocked_folder), sentinel)
	var old_background := directory.path_join("old.png")
	_write_bytes(old_background, sentinel)
	before = _inventory(directory)
	result = Creation._persist(directory.path_join("new_maps/new.json"), old_background,
		{"id": "rollback"}, FileAccess.get_file_as_bytes(source))
	_check_failure(h, "写入前发现素材被占用", result)
	h.check("素材冲突回滚本次空目录", _inventory(directory), before)
	h.check("已存在素材逐字节保留", FileAccess.get_file_as_bytes(old_background), sentinel)


static func _test_dialog(h: TestHarness, directory: String, source: String) -> void:
	var maps := directory.path_join("dialog_maps")
	var art := directory.path_join("dialog_art")
	var dialog := Dialog.new()
	dialog.configure(maps, art)
	var received: Array[Dictionary] = []
	dialog.map_created.connect(func(result: Dictionary) -> void: received.append(result))
	h.check("对话框是 ConfirmationDialog", dialog is ConfirmationDialog, true)
	h.check("文件选择器只选文件", dialog._file_dialog.file_mode, FileDialog.FILE_MODE_OPEN_FILE)
	h.check("可选择外部 PNG", dialog._file_dialog.access, FileDialog.ACCESS_FILESYSTEM)
	h.check("未选图不能确认", dialog.get_ok_button().disabled, true)
	h.check("未选图先禁用配置", dialog._id_edit.editable or dialog._name_edit.editable, false)
	dialog._prepare_popup_layout(Vector2i(600, 580))
	h.check("首次弹出前为内容设置最小宽度", dialog._content.custom_minimum_size.x, 568.0)
	h.check("首次弹出前为换行文本分配宽度", dialog._status.size.x, 568.0)
	h.check("首次弹出内容高度不撑破窗口", dialog._content.get_combined_minimum_size().y <= 500.0, true)
	dialog._select_source(source)
	h.check("有效图开放配置", dialog._id_edit.editable and dialog._name_edit.editable, true)
	h.check("原图缩略预览", dialog._preview.texture.get_size(), Vector2(120, 84))
	h.check("尺寸说明为 1:1", dialog._dimensions.text.contains("120 × 84（像素 1:1）"), true)
	dialog._id_edit.text = "dialog_map"
	dialog._name_edit.text = "新场景"
	dialog._refresh_validation()
	h.check("合法信息允许确认", dialog.get_ok_button().disabled, false)
	h.check("配置不创建文件", DirAccess.dir_exists_absolute(maps), false)
	dialog.canceled.emit()
	h.check("取消无文件", DirAccess.dir_exists_absolute(art), false)
	dialog._id_edit.text = "Bad"
	dialog._refresh_validation()
	h.check("无效 ID 禁止确认", dialog.get_ok_button().disabled, true)
	dialog._id_edit.text = "dialog_map"
	dialog._refresh_validation()
	dialog._confirm_creation()
	h.check("成功只发一次信号", received.size(), 1)
	if received.size() == 1:
		h.check("信号包含创建后的路径", FileAccess.file_exists(received[0]["path"]), true)
		h.check("信号数据满足 MapDef", MapDef.from_dictionary(received[0]["data"]).validate(), [])
	dialog._confirm_creation()
	h.check("重复确认不发成功信号", received.size(), 1)
	var changing := directory.path_join("changing.png")
	_write_bytes(changing, FileAccess.get_file_as_bytes(source))
	dialog._select_source(changing)
	dialog._id_edit.text = "changed_source"
	dialog._refresh_validation()
	_write_bytes(changing, "replaced".to_utf8_buffer())
	dialog._confirm_creation()
	h.check("确认重新检查原图", received.size(), 1)
	h.check("源图变坏没有地图残留", FileAccess.file_exists(maps.path_join("changed_source.json")), false)
	dialog._select_source(changing)
	h.check("坏图清空旧预览", dialog._preview.texture, null)
	h.check("坏图禁用确认与配置", dialog.get_ok_button().disabled and not dialog._id_edit.editable, true)
	dialog.free()


static func _check_failure(h: TestHarness, label: String, result: Dictionary) -> void:
	h.check(label + "：失败", result["ok"], false)
	h.check(label + "：说明原因", not str(result["error"]).is_empty(), true)
	h.check(label + "：没有成功路径或数据", [result["path"], result["background"], result["data"]], ["", "", {}])


static func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


static func _inventory(path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	for filename: String in directory.get_files():
		result.append(path.path_join(filename))
	for folder: String in directory.get_directories():
		var child := path.path_join(folder)
		result.append(child + "/")
		result.append_array(_inventory(child))
	result.sort()
	return result


static func _remove_tree(path: String) -> void:
	if not path.begins_with("user://test_map_creation_"):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for folder: String in directory.get_directories():
		_remove_tree(path.path_join(folder))
	DirAccess.remove_absolute(path)
