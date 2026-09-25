## 存档的读写。放 `scenes/` 而不是 `core/`，是因为它要碰文件系统
## （`user://` + `FileAccess`），而 core 层不许依赖这些 —— 否则存档逻辑
## 就没法脱离引擎单独测了。它自己不是节点，只是跟 main.gd 同层的应用服务。
##
## 一个槽位一个 JSON 文件。用 JSON 而不是 Godot 的 `ResourceSaver`，
## 是为了让存档**人能打开看**：出问题的时候可以直接用记事本查。
class_name SaveStore
extends RefCounted

## 槽位数量。UI 与校验都按这个数走。
const SLOT_COUNT := 3
const SAVE_DIR := "user://saves/"
const FILE_NAME := "save_%d.json"


## 某个槽位的存档文件路径。
static func path_for(slot: int) -> String:
	return SAVE_DIR + (FILE_NAME % slot)


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path_for(slot))


## 写一份存档。文件夹不存在就建。
## 返回是否成功；失败的原因已经打到日志里了。
static func write(slot: int, data: SaveData) -> bool:
	if data == null:
		return false

	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("[存档] 打不开 user:// ：%s" % error_string(DirAccess.get_open_error()))
		return false
	if not dir.dir_exists(SAVE_DIR):
		var err := dir.make_dir_recursive(SAVE_DIR)
		if err != OK and err != ERR_ALREADY_EXISTS:
			push_error("[存档] 建目录失败：%s（错误码 %d）" % [SAVE_DIR, err])
			return false

	var path := path_for(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[存档] 写不了文件：%s" % path)
		return false

	data.slot = slot
	file.store_string(JSON.stringify(data.to_dictionary(), "\t"))
	file.close()
	return true


## 读一份存档。没有、坏了、或者版本不认识都返回 null，
## 并且把原因打到日志 —— 读档失败时玩家得知道是「没有存档」还是「存档坏了」。
static func read(slot: int) -> SaveData:
	var path := path_for(slot)
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[存档] 读不了文件：%s" % path)
		return null
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("[存档] 不是合法的 JSON 对象：%s" % path)
		return null

	var data := SaveData.from_dictionary(parsed)
	# 比当前版本新 → 不敢读；比能读的最低版本老 → 字段对不上，也不读。
	# 中间版本照读，缺的字段走默认值（`SaveData` 里都写了兜底）。
	if data.version > SaveData.VERSION or data.version < SaveData.MIN_READABLE:
		push_error("[存档] 版本不认识：%s（文件是 v%d，能读的范围是 v%d–v%d）"
			% [path, data.version, SaveData.MIN_READABLE, SaveData.VERSION])
		return null

	for problem: String in data.validate():
		push_error("[存档] " + problem)
	return data


static func delete(slot: int) -> bool:
	var path := path_for(slot)
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	return dir.remove(path) == OK


## 列出所有槽位上有内容的存档，按槽位号排序。
static func list_all() -> Array[SaveData]:
	var out: Array[SaveData] = []
	for slot: int in SLOT_COUNT:
		var data := read(slot)
		if data != null:
			out.append(data)
	return out
