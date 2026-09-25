## 结局图鉴的**全局记录**：跨存档、只增不减的那一份。
##
## 为什么跟存档分开：存档存的是「这一条路线走到了哪」，删掉槽位就没了。
## 图鉴要回答的是另一件事 —— 「你一共见过几个结局」。
## 玩家在三条路线上各拿到一个结局，图鉴该显示 3，而不是「当前这条路线有 1 个」。
##
## 所以这份记录：
##   - 放在 `user://endings.json`，**不在 `saves/` 目录下**，删档扫不到它
##   - **只增不减**：达成时追加，从不因为读旧档或删档而减少
##   - 不认识 `EndingTable`，只记 id 和首次达成时间；表里没有的 id 由界面自己忽略
##
## 跟 `SaveStore` 一样放 `scenes/`：它要碰文件系统，而 core 层不许。
class_name EndingGallery
extends RefCounted

## 记录文件的路径。**刻意不在 `saves/` 里** —— 那里是存档的地盘，
## 玩家删档是删整个目录，图鉴记录不能被连带删掉。
const PATH := "user://endings.json"
## 记录格式版本。将来字段变了靠它判断还能不能读。
const VERSION := 1

## 结局 id（StringName）→ 首次达成时间（人类可读字符串）。
## 只增不减：`unlock()` 对已经记过的 id 不动时间。
var records: Dictionary = {}


## 读记录。文件不存在或坏了就是空记录 —— 图鉴记录丢了最多是图鉴空着，
## 不该让游戏起不来。原因已经打进日志。
func load_records() -> void:
	records = {}

	if not FileAccess.file_exists(PATH):
		return

	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("[图鉴] 读不了记录文件：%s" % PATH)
		return
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("[图鉴] 记录文件不是合法的 JSON 对象：%s" % PATH)
		return

	var data := parsed as Dictionary
	var raw: Variant = data.get("entries", {})
	if not (raw is Dictionary):
		return
	for key: Variant in raw:
		records[StringName(str(key))] = str((raw as Dictionary)[key])


## 写记录。失败返回 false，原因打进日志。
func save_records() -> bool:
	var plain: Dictionary = {}
	for key: Variant in records:
		plain[str(key)] = records[key]

	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("[图鉴] 写不了记录文件：%s" % PATH)
		return false
	file.store_string(JSON.stringify({
		"version": VERSION,
		"entries": plain,
	}, "\t"))
	file.close()
	return true


## 记下一个结局。返回**是不是这次新达成的** —— 重复走到同一个结局不该再提示一次。
func unlock(id: StringName) -> bool:
	if id == &"" or records.has(id):
		return false
	# **本地时间，不是 UTC** —— 这串是要给玩家看的（图鉴详情里的「首次达成」）。
	records[id] = _now_text()
	return save_records()


## 现在几点，给人看的格式：`2026-09-21 21:28`。
## 默认的 ISO 串中间是 `T` 还带 UTC 偏移，摆进界面里像报错。
static func _now_text() -> String:
	return Time.get_datetime_string_from_system(false).replace("T", " ").substr(0, 16)


func has(id: StringName) -> bool:
	return records.has(id)


## 第一次走到这个结局的时间。没记过返回空串。
func first_at(id: StringName) -> String:
	return str(records.get(id, ""))


## 已记录的结局 id，按字典序。**顺序稳定**，界面上的列表才不会乱跳。
func ids() -> Array[StringName]:
	# 先按 String 排。`Array[StringName].sort()` 比的是内部句柄，不是字面，
	# 排出来的顺序会莫名变动。
	var raw: Array[String] = []
	for key: Variant in records:
		raw.append(str(key))
	raw.sort()

	var out: Array[StringName] = []
	for text: String in raw:
		out.append(StringName(text))
	return out


func count() -> int:
	return records.size()


## 清空。**只有测试该调它** —— 正式玩法里图鉴是只增不减的，
## 给玩家一个「清图鉴」的口子等于让他自己删成就。
func clear() -> void:
	records = {}
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.file_exists(PATH):
		dir.remove(PATH)
