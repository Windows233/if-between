## 选项菜单里的一项。
##
## 单独一个顶层类，理由同 `DialogueLine`：GDScript 对三层嵌套引用支持不好。
class_name ChoiceOption
extends RefCounted

## 选中后回传给调用方的标识。谁用这个菜单，谁自己解释它的含义。
var id: StringName = &""
## 显示文字
var label: String = ""
## 灰掉的选项会显示但选不中。剧情里常用「条件不满足」的选项。
var enabled: bool = true


static func make(p_id: StringName, p_label: String, p_enabled: bool = true) -> ChoiceOption:
	var option := ChoiceOption.new()
	option.id = p_id
	option.label = p_label
	option.enabled = p_enabled
	return option


## 从 `{"id": "talk", "label": "交谈"}` 这种字典构造。
static func from_dictionary(raw: Variant) -> ChoiceOption:
	var option := ChoiceOption.new()
	if raw is Dictionary:
		option.id = StringName(str(raw.get("id", "")))
		option.label = str(raw.get("label", ""))
		option.enabled = bool(raw.get("enabled", true))
	return option


## 从数组构造一批。
static func list_from_array(raw: Variant) -> Array[ChoiceOption]:
	var out: Array[ChoiceOption] = []
	if raw is Array:
		for item: Variant in raw:
			out.append(from_dictionary(item))
	return out
