## 读数据文件：地图、剧情事件、结局表、物品表。
##
## **全项目的 I/O 只在这里。** 理由：
##   - core 层不许碰文件系统，所以读文件的活必须留在外面
##   - 但也不该散在入口里 —— 入口该管「拿数据做什么」，不是「文件怎么读」
##
## 全是静态方法：读文件没有状态可存，做成静态反而更难用错。
class_name DataLoader
extends RefCounted

const MAP_DIR := "res://data/maps/"
const EVENT_DIR := "res://data/events/"
const ENDINGS_PATH := "res://data/endings.json"
const ITEMS_PATH := "res://data/items.json"


## 读地图。找不到、不是合法 JSON 都返回 null，原因已经打进日志。
static func load_map(map_id: StringName) -> MapDef:
	var data: Variant = _read_json_object("%s%s.json" % [MAP_DIR, map_id], "地图")
	if data == null:
		return null
	return MapDef.from_dictionary(data)


## 读一个剧情事件并校验。
##
## `known_endings` 是结局表里已有的 id，用来查结局节点有没有写错名字。
## 写错的话玩家走到那一步才会发现，那时已经是一段没有标题的结局了。
static func load_event(event_id: StringName, known_endings: Array[StringName] = []) -> StoryEvent:
	var data: Variant = _read_json_object("%s%s.json" % [EVENT_DIR, event_id], "剧情")
	if data == null:
		return null

	var event := StoryEvent.from_dictionary(data)
	for problem: String in event.validate(known_endings):
		push_error("[剧情] " + problem)
	return event


## 读结局表。读不到就当没有结局，不拦着游戏跑 ——
## 结局是内容，缺了内容是空，缺了框架才是崩。
static func load_endings() -> EndingTable:
	if not FileAccess.file_exists(ENDINGS_PATH):
		push_warning("[结局] 找不到文件：%s" % ENDINGS_PATH)
		return EndingTable.new()

	var text := FileAccess.get_file_as_string(ENDINGS_PATH)
	var data: Variant = JSON.parse_string(text)
	if not (data is Array):
		push_error("[结局] 不是合法的 JSON 数组：%s" % ENDINGS_PATH)
		return EndingTable.new()

	var table := EndingTable.from_array(data)
	for problem: String in table.validate():
		push_error("[结局] " + problem)
	return table


## 读物品表。读不到就当一件物品都没有 ——
## 缺表格的结果是「名字显示不出来」，不该让游戏起不来。
static func load_items() -> ItemTable:
	if not FileAccess.file_exists(ITEMS_PATH):
		push_warning("[物品] 找不到文件：%s" % ITEMS_PATH)
		return ItemTable.new()

	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_PATH))
	if not (data is Dictionary):
		push_error("[物品] 不是合法的 JSON 对象：%s" % ITEMS_PATH)
		return ItemTable.new()

	var table := ItemTable.from_dictionary(data)
	for problem: String in table.validate():
		push_error("[物品] " + problem)
	return table


## 读一个 JSON 文件并要求它是对象。失败统一在这里打日志并返回 null，
## 免得三处读文件写三遍同样的检查。
static func _read_json_object(path: String, tag: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("[%s] 找不到文件：%s" % [tag, path])
		return null

	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		push_error("[%s] 不是合法的 JSON 对象：%s" % [tag, path])
		return null
	return data
