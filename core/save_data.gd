## 一份存档的内容：玩家在哪、站在哪个坐标、剧情走到哪、世界状态是什么。
##
## **按 RPG 的惯例存「当前全部状态」**，读档要回到玩家离开时的那一步，
## 而不是把他丢回场景开头 —— 那样等于丢进度。具体包括：
##
##   - 场景 + 出生点（出生点作兜底：坐标缺失时才用）
##   - **角色坐标与朝向**：走了一半的路不该白走
##   - **剧情进度**：正在演的事件与节点，读档从那个节点接着演
##   - 世界状态 `flags`：玩家的选择、已触发的事件、结局进度
##   - 已达成结局的 id 列表（跟 flags 互相印证，见 `reconcile_endings()`）
##
## 纯数据，不碰文件系统。读写是 `scenes/save_store.gd` 的事。
class_name SaveData
extends RefCounted

## 存档格式版本。将来字段变了靠它判断还能不能读。
##
## v1：只有场景 + 出生点 + flags。v2 起多了坐标、朝向、剧情进度、结局列表。
## v3 起剧情进度细到**节点内**（`story_step` / `story_spoke`）。
## 老存档仍可读，缺的字段走默认值（步数 0 等于「从头演」，正是加它之前的行为）。
const VERSION := 3
## 还能读的最低版本。比这更老的存档不认识。
const MIN_READABLE := 1

var version := VERSION
## 槽位号。存进文件里是为了让读出来的存档自己知道来自哪，
## 列出存档列表时不用另外维护一份映射。
var slot := 0
## 存档时间，人类可读字符串。由外面填 —— core 层不碰 Time 单例。
var saved_at := ""

var map_id: StringName = &""
## 出生点名字。只在坐标缺失时兜底用。
var spawn: StringName = &"default"
## 角色当时站在哪。零向量表示「没记」，读档会退回出生点。
var player_position := Vector2.ZERO
## 角色当时朝哪。没有朝向系统的版本里只作记录，不参与逻辑。
var facing := Vector2.DOWN

## 正在演的剧情事件与节点。都空表示当时不在剧情里。
##
## 只到**节点**这一层不够：在「等选择」那一步存档时，节点刚刚开了个头，
## 读档照节点重演会把整段台词再放一遍。所以还要记节点内的进度。
var story_event: StringName = &""
var story_node: StringName = &""
## 节点内的进度：舞台演完了几条。
## 在「等选择」那一步它正好等于这个节点的 `stage` 长度。
var story_step := 0
## 节点内那句对话（`talk`）玩家看过没有。理由同上，是同一件事的后半段。
var story_spoke := false

## 世界状态快照。玩家的选择、已触发的事件、结局进度全在这里。
var flags: Dictionary = {}
## 已达成结局的 id。跟 flags 里的 `ending/<id>` 是同一件事的两份记录，
## 存两份是为了**互相印证**：一边丢了能用另一边补回来。
var endings: Array[StringName] = []

## 场上站着的**临时角色**（演出放出来、演完留在场上的那些人）。
##
## 为什么得存：他们不是地图数据的一部分，是演出现造的（`Cutscene`）。
## 不存的话读档回来人就不见了 —— 剧情正停在「跟神秘人说话」上，
## 而神秘人不在了（2026-09-24 策划报的）。每条是
## `{id, sprite, at, height, z, pose, flip, talk}`。
var actors: Array = []


func to_dictionary() -> Dictionary:
	return {
		"version": version,
		"slot": slot,
		"saved_at": saved_at,
		"map": str(map_id),
		"spawn": str(spawn),
		"player_position": [player_position.x, player_position.y],
		"facing": [facing.x, facing.y],
		"story_event": str(story_event),
		"story_node": str(story_node),
		"story_step": story_step,
		"story_spoke": story_spoke,
		"flags": flags,
		"endings": _strings(endings),
		"actors": actors,
	}


static func from_dictionary(raw: Variant) -> SaveData:
	var data := SaveData.new()
	if not (raw is Dictionary):
		return data

	var dict := raw as Dictionary
	data.version = int(dict.get("version", VERSION))
	data.slot = int(dict.get("slot", 0))
	data.saved_at = str(dict.get("saved_at", ""))
	data.map_id = StringName(str(dict.get("map", "")))
	data.spawn = StringName(str(dict.get("spawn", "default")))
	data.player_position = _to_vector2(dict.get("player_position"))
	data.facing = _to_vector2(dict.get("facing"), Vector2.DOWN)
	data.story_event = StringName(str(dict.get("story_event", "")))
	data.story_node = StringName(str(dict.get("story_node", "")))
	# 老存档没这两个字段 → 0 / false，等于「从头演」。
	# 那正是加它们之前的行为，不会比原来更差。
	data.story_step = int(dict.get("story_step", 0))
	data.story_spoke = bool(dict.get("story_spoke", false))

	var raw_flags: Variant = dict.get("flags", {})
	data.flags = raw_flags.duplicate(true) if raw_flags is Dictionary else {}

	var raw_actors: Variant = dict.get("actors", [])
	data.actors = raw_actors.duplicate(true) if raw_actors is Array else []

	var raw_endings: Variant = dict.get("endings", [])
	if raw_endings is Array:
		for item: Variant in raw_endings:
			data.endings.append(StringName(str(item)))
	# 老存档没有 endings 字段，从 flags 里倒出来
	if data.endings.is_empty():
		data.endings = data.ending_ids()

	return data


## 校验。返回问题列表，空数组表示没问题。
## 版本不认识是 `SaveStore` 该管的事，这里只管「这份数据本身完不完整」。
func validate() -> Array[String]:
	var problems: Array[String] = []
	if map_id == &"":
		problems.append("存档没写场景")
	if spawn == &"":
		problems.append("存档没写出生点")
	return problems


## 记了坐标吗。为零说明没记（老存档），读档时要退回出生点。
func has_position() -> bool:
	return player_position != Vector2.ZERO


## 正在剧情里吗。
func in_story() -> bool:
	return story_event != &"" and story_node != &""


# ---------------------------------------------------------------- 结局

## 从 flags 里倒出已达成的结局 id。
func ending_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in flags:
		var name := str(key)
		if not name.begins_with(EndingTable.FLAG_PREFIX):
			continue
		if flags[key] != true:
			continue
		out.append(StringName(name.substr(EndingTable.FLAG_PREFIX.length())))
	out.sort()
	return out


## 把「flags 里的结局进度」和「存档记的结局列表」对成一份。
##
## 两边互相补：文件里记了但 flags 丢了 → 补回 flags；
## flags 里有但文件没记 → 补进列表。返回补回了哪些。
##
## 存档和结局进度是同一件事的两面，对不上就说明有一边坏了 ——
## 静默按一边算，玩家会莫名少一个结局。
func reconcile_endings(p_flags: WorldState) -> Array[StringName]:
	var from_flags := ending_ids()
	var restored: Array[StringName] = []

	for id: StringName in endings:
		if not from_flags.has(id):
			EndingTable.unlock(p_flags, id)
			restored.append(id)
	for id: StringName in from_flags:
		if not endings.has(id):
			endings.append(id)

	endings.sort()
	return restored


## 存档列表上的一行摘要。`table` 用来把结局 id 翻成标题，不传就只写数量。
func summary(table: EndingTable = null) -> String:
	var where := str(map_id)
	var ids := ending_ids()
	if ids.is_empty():
		return where

	if table == null:
		return "%s · 结局 %d" % [where, ids.size()]

	var titles: Array[String] = []
	for id: StringName in ids:
		var def := table.get_ending(id)
		titles.append(def.display_title() if def != null else str(id))
	return "%s · %s" % [where, " / ".join(titles)]


static func _strings(values: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for value: StringName in values:
		out.append(str(value))
	return out


static func _to_vector2(raw: Variant, fallback := Vector2.ZERO) -> Vector2:
	if raw is Array and (raw as Array).size() == 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	if raw is Vector2:
		return raw
	return fallback
