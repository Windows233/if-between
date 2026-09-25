## 物品表：游戏里有哪些东西，以及名字叫什么。
##
## 跟 `EndingTable` 一个路子：**内容在表里，进度在 `WorldState` 里**。
## 手里有几件东西记在 `WorldState` 的 `item/<id>` 键上，值就是数量。
## 这么放的理由跟结局一样 —— 存档只需要存世界状态，不用再打包一份背包。
##
## 表只管「名字对不对得上 id」和「怎么读写数量」，
## 「什么时候给、什么时候要用」是剧情数据和门禁条件的事。
class_name ItemTable
extends RefCounted

## 物品数量的键前缀。带斜杠是为了跟普通剧情变量区分开。
const FLAG_PREFIX := "item/"

## 物品 id -> 显示名。
var names: Dictionary = {}


static func from_dictionary(raw: Variant) -> ItemTable:
	var table := ItemTable.new()
	if not (raw is Dictionary):
		return table
	for key: Variant in raw:
		table.names[StringName(str(key))] = str(raw[key])
	return table


## 读不出名字就退回 id 本身 —— 缺一行数据是内容不全，不该显示成空白。
func name_of(id: StringName) -> String:
	if names.has(id):
		return str(names[id])
	return str(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in names:
		out.append(StringName(str(key)))
	return out


func validate() -> Array[String]:
	var problems: Array[String] = []
	for key: Variant in names:
		if str(key) == "":
			problems.append("物品 id 不能为空")
		elif str(names[key]) == "":
			problems.append("物品 %s 没有写名字" % str(key))
	return problems


# ---------------------------------------------------------------- 数量读写

## 某个物品在世界状态里的键名。
static func flag_key(id: StringName) -> StringName:
	return StringName(FLAG_PREFIX + str(id))


## 这个键是物品吗。主循环靠它从「这次变了什么」里挑出物品来提示。
static func is_item_flag(key: StringName) -> bool:
	return str(key).begins_with(FLAG_PREFIX)


## 从键名反推物品 id。
static func id_from_flag(key: StringName) -> StringName:
	return StringName(str(key).substr(FLAG_PREFIX.length()))


## 手里有几件。没有就是 0。
static func count_of(flags: WorldState, id: StringName) -> int:
	if flags == null:
		return 0
	var value: Variant = flags.get_value(flag_key(id), 0)
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	return 0


## 有这么多件吗。
static func has(flags: WorldState, id: StringName, count: int = 1) -> bool:
	return count_of(flags, id) >= count


## 加进去，返回加完之后有几件。
static func add(flags: WorldState, id: StringName, count: int = 1) -> int:
	if flags == null:
		return 0
	flags.set_value(flag_key(id), count_of(flags, id) + count)
	return count_of(flags, id)


## 拿走。不够就不动，返回 false —— 静默失败比扣成负数好。
static func remove(flags: WorldState, id: StringName, count: int = 1) -> bool:
	if flags == null or not has(flags, id, count):
		return false
	flags.set_value(flag_key(id), count_of(flags, id) - count)
	return true
