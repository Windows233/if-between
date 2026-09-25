## 世界状态：一组 `变量 -> 值` 的映射，附带变更记录。
##
## 变量名用带点的字符串表达层级，例如 `girl.mood`、`door.locked`、`weather`。
## 这是规则引擎唯一的持久状态载体，不依赖任何场景、节点或 UI，
## 因此可以在无头模式下单独测试。
##
## 状态不设固定 schema：关卡里出现什么变量，状态里就有什么变量。
## 未设置的变量视为不存在（`null`），条件求值时按「不存在」处理。
class_name WorldState
extends RefCounted

## 变量名 -> 当前值
var _values: Dictionary = {}
## 变量名 -> 初始值，用于 reset
var _initial: Dictionary = {}
## 自上次 clear_changes 以来的变更列表，元素形如
## `{"key": StringName, "from": Variant, "to": Variant, "existed": bool}`
var _changes: Array[Dictionary] = []


## 写入一个变量。值没有实际变化时不记入变更。
func set_value(key: StringName, value: Variant) -> void:
	var existed: bool = _values.has(key)
	var old: Variant = _values.get(key)
	if existed and old == value:
		return
	_values[key] = value
	_changes.append({"key": key, "from": old, "to": value, "existed": existed})


## 读取一个变量。不存在时返回 default_value。
func get_value(key: StringName, default_value: Variant = null) -> Variant:
	return _values.get(key, default_value)


func has_value(key: StringName) -> bool:
	return _values.has(key)


## 删除一个变量。删不存在的变量是空操作。
func unset_value(key: StringName) -> void:
	if not _values.has(key):
		return
	var old: Variant = _values[key]
	_values.erase(key)
	_changes.append({"key": key, "from": old, "to": null, "existed": true})


## 当前所有变量的浅拷贝。
func snapshot() -> Dictionary:
	return _values.duplicate()


## 派生一份独立的状态副本。
## 规则引擎每轮求值都基于一份快照，所有动作都从同一份快照读值，
## 这样同一轮内规则之间不会互相影响，结果只取决于优先级。
func fork() -> WorldState:
	var copy := WorldState.new()
	copy._values = _values.duplicate()
	copy._initial = _initial.duplicate()
	return copy


## 自上次 clear_changes 以来的变更。
func changes() -> Array[Dictionary]:
	return _changes


func clear_changes() -> void:
	_changes.clear()


## 把当前状态登记为「初始状态」。关卡加载完成后调用一次。
func mark_initial() -> void:
	_initial = _values.duplicate()
	_changes.clear()


## 回到 mark_initial 时的状态。
func reset() -> void:
	_values = _initial.duplicate()
	_changes.clear()


## 清空所有变量。读档时用 —— `load_values()` 是**合并**，
## 直接合并的话，存档里没有的变量会残留着读档之前的值，
## 表现就是「读了档，但某个标记还是旧的样子」。
func clear() -> void:
	_values.clear()
	_changes.clear()


## 一次性批量写入，用于关卡初始化。
func load_values(values: Dictionary) -> void:
	for key: Variant in values:
		_values[StringName(key)] = values[key]
	_changes.clear()


## 列出所有变量名，按字典序排序，保证输出确定。
func keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _values:
		out.append(StringName(key))
	out.sort()
	return out


## 供测试与调试使用的人类可读快照。
func to_text() -> String:
	var lines: Array[String] = []
	for key: StringName in keys():
		lines.append("%s = %s" % [key, _values[key]])
	return "\n".join(lines)
