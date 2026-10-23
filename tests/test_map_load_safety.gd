## 地图载入与外部 PNG 导入的失败回归。
## 失败不能改变正在编辑的地图，也不能把坏图片留在资源目录。
## 夹具只写入独立 user:// 临时目录，不改正式地图或素材。
extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


static func run(h: TestHarness) -> void:
	var folder := "user://__editor_load_safety_%d" % Time.get_ticks_usec()
	var drafts := folder.path_join("drafts")
	var props := folder.path_join("props")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(drafts))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(props))
	_test_failed_load_keeps_current_map(h, drafts)
	_test_import_requires_valid_png(h, folder, props)
	_remove_flat_dir(drafts)
	_remove_flat_dir(props)
	_remove_flat_dir(folder)


static func _test_failed_load_keeps_current_map(h: TestHarness, drafts: String) -> void:
	var model := Model.new()
	model.draft_dir = drafts
	h.check("安全载入夹具地图", model.load_map("gatehouse", false), true)
	model.add_rect(Model.Kind.WALL, Rect2(1, 2, 3, 4))
	model.record_history()
	model.stash_draft()
	h.check("正常草稿仍优先载入", model.load_map("gatehouse"), true)
	h.check("载入草稿标记保留", model.from_draft, true)
	model.add_rect(Model.Kind.WALL, Rect2(5, 6, 7, 8))
	model.record_history()
	var snapshot := _model_state(model)
	h.check("不存在的地图载入失败", model.load_map("__editor_load_safety_missing", false), false)
	h.check("载入失败完整保留当前数据、保存基准与撤销历史", _model_state(model), snapshot)
	h.check("载入失败后仍可撤销", model.undo(), true)
	h.check("载入失败后仍可重做", model.redo(), true)
	h.check("重做后回到失败前状态", _model_state(model), snapshot)
	_write(drafts.path_join("__editor_invalid_draft.json"), "[]".to_utf8_buffer())
	h.check("无有效正式地图的坏草稿载入失败", model.load_map("__editor_invalid_draft"), false)
	h.check("坏草稿同样不替换当前地图身份", _model_state(model), snapshot)
	_write(drafts.path_join("gatehouse.json"), "[]".to_utf8_buffer())
	h.check("坏草稿可回退到正式地图", model.load_map("gatehouse"), true)
	h.check("回退正式地图后没有草稿标记", model.from_draft, false)
	h.check("回退正式地图后没有未保存改动", model.dirty, false)


static func _model_state(model) -> Dictionary:
	return {"map_id": model.map_id, "path": model.path, "data": model.data.duplicate(true),
		"dirty": model.dirty, "from_draft": model.from_draft,
		"saved_text": model._saved_text, "history": model._history.duplicate(true),
		"history_index": model._history_index}


static func _test_import_requires_valid_png(h: TestHarness, folder: String, props: String) -> void:
	var model := Model.new()
	var invalid := folder.path_join("renamed_text.png")
	_write(invalid, "this is not an image".to_utf8_buffer())
	h.check("改成 PNG 后缀的文本不能导入", model.import_image(invalid, props), "")
	h.check("拒绝伪 PNG 后目标目录不留残片", DirAccess.get_files_at(props).is_empty(), true)
	var truncated := folder.path_join("truncated.png")
	_write(truncated, PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]))
	# 解码器会为刻意损坏的 PNG 打引擎错误；断言检查返回值和落盘结果。
	var print_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	var truncated_result: String = model.import_image(truncated, props)
	Engine.print_error_messages = print_errors
	h.check("PNG 文件头正确但数据损坏也不能导入", truncated_result, "")
	h.check("损坏 PNG 不会落入目标目录", DirAccess.get_files_at(props).is_empty(), true)
	var source := folder.path_join("valid.png")
	var image := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.6, 0.5))
	h.check("创建有效 PNG 夹具", image.save_png(source), OK)
	var imported: String = model.import_image(source, props)
	h.check("有效 PNG 正常导入", imported, props.path_join("valid.png"))
	h.check("导入保留 PNG 原始字节", FileAccess.get_file_as_bytes(imported), FileAccess.get_file_as_bytes(source))
	var duplicate: String = model.import_image(source, props)
	h.check("有效 PNG 重名仍不覆盖", duplicate, props.path_join("valid_2.png"))
	h.check("原始导入图仍保持完整", FileAccess.get_file_as_bytes(imported), FileAccess.get_file_as_bytes(source))


static func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


static func _remove_flat_dir(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
