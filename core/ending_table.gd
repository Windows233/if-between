## 结局表：整个游戏有哪些结局，以及玩家的达成进度。
##
## 达成进度存在 `WorldState` 里，键是 `ending/<id>`，值为 true。
## 存进世界状态而不是另起一份记录，是为了让存档只需要存一样东西 ——
## 将来存档就存 `flags` 加当前场景，不需要额外打包结局列表。
class_name EndingTable
extends RefCounted

## 结局进度的键前缀。带斜杠是为了跟普通剧情变量区分开，
## 免得哪个剧情变量正好也叫 `ending`。
const FLAG_PREFIX := "ending/"

var endings: Array[EndingDef] = []


static func from_array(raw: Variant) -> EndingTable:
	var table := EndingTable.new()
	if not (raw is Array):
		return table
	for item: Variant in raw:
		table.endings.append(EndingDef.from_dictionary(item))
	return table


func get_ending(id: StringName) -> EndingDef:
	for ending: EndingDef in endings:
		if ending.id == id:
			return ending
	return null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for ending: EndingDef in endings:
		out.append(ending.id)
	return out


func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen: Array[StringName] = []
	for ending: EndingDef in endings:
		problems.append_array(ending.validate())
		if ending.id == &"":
			continue
		if seen.has(ending.id):
			problems.append("结局 id 重复：%s" % ending.id)
		seen.append(ending.id)
	return problems


# ---------------------------------------------------------------- 达成进度

## 某个结局在世界状态里的键名。
static func flag_key(id: StringName) -> StringName:
	return StringName(FLAG_PREFIX + str(id))


## 标记一个结局达成。重复达成是空操作（值没变，不记变更）。
static func unlock(p_flags: WorldState, id: StringName) -> void:
	if p_flags == null or id == &"":
		return
	p_flags.set_value(flag_key(id), true)


static func is_unlocked(p_flags: WorldState, id: StringName) -> bool:
	if p_flags == null:
		return false
	return p_flags.get_value(flag_key(id), false) == true


## 已达成的所有结局，按表里的顺序返回 —— 顺序稳定，做结局列表时不会乱跳。
func unlocked_in(p_flags: WorldState) -> Array[EndingDef]:
	var out: Array[EndingDef] = []
	for ending: EndingDef in endings:
		if EndingTable.is_unlocked(p_flags, ending.id):
			out.append(ending)
	return out


func count_unlocked(p_flags: WorldState) -> int:
	return unlocked_in(p_flags).size()
