## 剧情节点上的一个选项。
##
## 跟 UI 层的 `ChoiceOption` 分开：那个只管「显示成什么样、能不能点」，
## 这个还带着「选完往哪走、写什么状态」。混成一个的话，
## UI 层就得知道剧情的事，改个界面还要懂剧本结构。
class_name StoryChoice
extends RefCounted

var id: StringName = &""
var label: String = ""
## 满足这个条件才让选。为 null 表示无条件。
var condition: Condition = null
## 选中后写进世界状态的变量，`变量名 -> 值`。
## 这一条就是策划说的「玩家的选择被记录下来」。
var effects: Dictionary = {}
## 选中后跳到哪个节点。空表示这段剧情到此为止。
var next_id: StringName = &""


static func from_dictionary(raw: Variant) -> StoryChoice:
	var choice := StoryChoice.new()
	if not (raw is Dictionary):
		return choice

	var data := raw as Dictionary
	choice.id = StringName(str(data.get("id", "")))
	choice.label = str(data.get("label", choice.id))
	choice.condition = Condition.from_dictionary(data.get("if"))
	choice.next_id = StringName(str(data.get("next", "")))

	var raw_set: Variant = data.get("set", {})
	if raw_set is Dictionary:
		for key: Variant in raw_set:
			choice.effects[StringName(str(key))] = raw_set[key]

	return choice


## 这个选项现在能不能选。没有条件就一直能选。
func is_available(state: WorldState) -> bool:
	if condition == null:
		return true
	return condition.eval(state)
