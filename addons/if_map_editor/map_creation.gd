## 独立的新地图文件服务：解码 PNG，再按原图像素尺寸生成 MapDef 数据。
##
## 不依赖 dock、模型或编辑器导入缓存；res:// 与 user:// 都可作为输出目录。
##
## 只创建新文件，失败回滚本次文件与空目录；不迁移旧图，也不建立剧情入口。
@tool
extends RefCounted

const PNG_SIGNATURE := [137, 80, 78, 71, 13, 10, 26, 10]


## 返回 {ok, error, path, background, data}；失败时后三项为空。
## map_id 仅接受 ASCII [a-z0-9_]；label 写入 MapDef 的 name 字段。
static func create(map_id: String, label: String, source_path: String,
		map_dir := "res://data/maps", art_dir := "res://art/map") -> Dictionary:
	var source := inspect_png(source_path)
	if not source["ok"]:
		return _failure(source["error"])
	var identity_error := validate_identity(map_id, label, map_dir)
	if not identity_error.is_empty():
		return _failure(identity_error)
	var art_error := _directory_error(art_dir)
	if not art_error.is_empty():
		return _failure(art_error)
	var map_path := map_dir.path_join(map_id + ".json")
	var background := art_dir.path_join(map_id + ".png")
	var suffix := 2
	while _occupied(background) or _occupied(background + ".import"):
		background = art_dir.path_join("%s_%d.png" % [map_id, suffix])
		suffix += 1
	var size: Vector2i = source["size"]
	var data := {"id": map_id, "name": label.strip_edges(), "kind": "room",
		"size": [size.x, size.y], "background": background,
		"spawns": {"start": [size.x * 0.5, size.y * 0.5]},
		"actors": [], "walls": [], "portals": []}
	var problems := MapDef.from_dictionary(data).validate()
	if not problems.is_empty():
		return _failure("地图校验失败：" + "；".join(problems))
	return _persist(map_path, background, data, source["bytes"])


## 直接读取原文件，验证扩展名、PNG 签名与真实解码。
## 返回 {ok, error, size, image, bytes}；失败时只保证 ok 和 error。
static func inspect_png(source_path: String) -> Dictionary:
	if source_path.get_extension().to_lower() != "png":
		return {"ok": false, "error": "请先选择 PNG 格式的场景大图。"}
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "无法读取场景图：" + source_path}
	var bytes := file.get_buffer(file.get_length())
	var read_error := file.get_error()
	file.close()
	if read_error != OK or bytes.size() < PNG_SIGNATURE.size():
		return {"ok": false, "error": "PNG 文件为空、损坏或读取不完整。"}
	for index: int in PNG_SIGNATURE.size():
		if bytes[index] != PNG_SIGNATURE[index]:
			return {"ok": false, "error": "文件内容不是 PNG 图像。"}
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.is_empty():
		return {"ok": false, "error": "PNG 无法解码，请重新选择完整的场景大图。"}
	var size := image.get_size()
	if size.x <= 0 or size.y <= 0:
		return {"ok": false, "error": "场景图宽高必须大于零。"}
	return {"ok": true, "error": "", "size": size, "image": image, "bytes": bytes}


## 对话框实时校验名称、ASCII ID 和目录内唯一性；不写文件，空字符串表示通过。
static func validate_identity(map_id: String, label: String,
		map_dir := "res://data/maps") -> String:
	if map_id.is_empty():
		return "请输入唯一 map_id（小写英文字母、数字、下划线）。"
	for index: int in map_id.length():
		var code := map_id.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return "map_id 只能包含 ASCII 小写英文字母、数字和下划线。"
	if label.strip_edges().is_empty():
		return "请输入地图显示名。"
	for index: int in label.length():
		if label.unicode_at(index) < 32 or label.unicode_at(index) == 127:
			return "地图显示名不能包含换行或控制字符。"
	var directory_error := _directory_error(map_dir)
	if not directory_error.is_empty():
		return directory_error
	if _occupied(map_dir.path_join(map_id + ".json")):
		return "地图已存在：%s；请使用其他 map_id。" % map_id
	var directory := DirAccess.open(map_dir)
	if directory != null:
		for filename: String in directory.get_files():
			if filename.get_extension().to_lower() != "json":
				continue
			var file := FileAccess.open(map_dir.path_join(filename), FileAccess.READ)
			if file == null:
				return "无法核对已有地图的 ID：" + filename
			var json := JSON.new()
			var parse_error := json.parse(file.get_as_text())
			file.close()
			if parse_error == OK and json.data is Dictionary and json.data.get("id") == map_id:
				return "已有地图使用此 map_id：" + filename
	return ""


static func _directory_error(path: String) -> String:
	if not (path.begins_with("res://") or path.begins_with("user://")):
		return "输出目录必须使用 res:// 或 user:// 路径。"
	if FileAccess.file_exists(path):
		return "输出目录被已有文件占用：" + path
	return ""


static func _occupied(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


static func _ensure_directory(path: String, created: Array[String]) -> String:
	if DirAccess.dir_exists_absolute(path):
		return ""
	if FileAccess.file_exists(path):
		return "目录被已有文件占用：" + path
	var parent := path.get_base_dir()
	if parent == path or parent.is_empty():
		return "无法创建目录：" + path
	var parent_error := _ensure_directory(parent, created)
	if not parent_error.is_empty():
		return parent_error
	var make_error := DirAccess.make_dir_absolute(path)
	if make_error != OK:
		return "无法创建目录：%s（%s）" % [path, error_string(make_error)]
	created.append(path)
	return ""


static func _write_new(path: String, bytes: PackedByteArray, created: Array[String]) -> String:
	if _occupied(path):
		return "拒绝覆盖已有文件或目录：" + path
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "无法新建文件：%s（%s）" % [path, error_string(FileAccess.get_open_error())]
	created.append(path)
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "文件写入失败：%s（%s）" % [path, error_string(write_error)]
	return ""


static func _persist(map_path: String, background: String, data: Dictionary,
		bytes: PackedByteArray) -> Dictionary:
	var directories: Array[String] = []
	var files: Array[String] = []
	var failure := _ensure_directory(map_path.get_base_dir(), directories)
	if failure.is_empty():
		failure = _ensure_directory(background.get_base_dir(), directories)
	if failure.is_empty():
		failure = _write_new(background, bytes, files)
	if failure.is_empty():
		failure = _write_new(map_path, (JSON.stringify(data, "  ") + "\n").to_utf8_buffer(), files)
	if not failure.is_empty():
		files.reverse()
		directories.reverse()
		for path: String in files + directories:
			var remove_error := DirAccess.remove_absolute(path)
			if remove_error != OK:
				failure += "；回滚失败：%s（%s）" % [path, error_string(remove_error)]
		return _failure(failure)
	return {"ok": true, "error": "", "path": map_path, "background": background, "data": data}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "path": "", "background": "", "data": {}}
