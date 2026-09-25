## 一个结局：id、标题、简介、类型。
##
## 单独一份表，而不把标题写进剧情节点，是因为**同一个结局可能从多条路走到**
## （概念图里分支后面会合流）。标题写死在节点上，改一次要改好几个地方。
##
## 纯数据，不碰文件系统。读 JSON 是 main.gd 的事。
class_name EndingDef
extends RefCounted

## 结局类型。只用于展示排序与配色，不参与逻辑判定。
enum Kind {
	NORMAL,  ## 普通结局
	GOOD,    ## 好结局
	BAD,     ## 坏结局
	TRUE,    ## 真结局
}

var id: StringName = &""
var title: String = ""
## 达成时显示的一两句说明
var summary: String = ""
var kind := Kind.NORMAL


static func from_dictionary(raw: Variant) -> EndingDef:
	var ending := EndingDef.new()
	if not (raw is Dictionary):
		return ending

	var data := raw as Dictionary
	ending.id = StringName(str(data.get("id", "")))
	ending.title = str(data.get("title", ""))
	ending.summary = str(data.get("summary", ""))
	ending.kind = _to_kind(data.get("kind"))
	return ending


## 标题没写就退回 id，界面上至少不至于显示空白。
func display_title() -> String:
	return title if title != "" else str(id)


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("结局表里有一项没写 id")
	return problems


static func _to_kind(raw: Variant) -> Kind:
	match str(raw).to_lower():
		"good", "he":
			return Kind.GOOD
		"bad", "be":
			return Kind.BAD
		"true", "te":
			return Kind.TRUE
		_:
			return Kind.NORMAL
