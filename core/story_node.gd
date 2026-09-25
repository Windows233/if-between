## 剧情里的一个节点：一段演出（可选）+ 一段对话（可选）+ 一组选项（可选）。
##
## 走法有两种：
##   - 没有选项：对话播完，顺着 `next_id` 去下一个节点
##   - 有选项：对话播完弹出选项，玩家选哪个就走哪条
##
## **三者按顺序发生**：`stage` 先演（黑屏、章标题、等人点击、谁走到哪、
## 换场景这些都写在这儿），演完才播 `talk`，`talk` 播完才轮到 `choices`。
## 只写 `stage`、不写 `talk` 的节点是「纯演出节点」，推进器会自动往下走。
##
## 为什么把演出写进节点、而不是另起一套「过场脚本」：过场和台词本来就是
## 交替的（说两句、黑屏、再说两句）。拆成两个文件，改一句台词要翻两处。
class_name StoryNode
extends RefCounted

var id: StringName = &""
## 先演的东西。空数组表示这个节点没有演出，直接进对话。
var stage: Array[StageStep] = []
var dialogue: Dialogue = Dialogue.new()
var choices: Array[StoryChoice] = []
## 没有选项时，对话播完去哪个节点。空表示这段剧情到此结束。
var next_id: StringName = &""
## 走到这里算达成哪个结局。填结局 id，对应 `data/endings.json` 里的一项。
##
## **写了这个字段，节点就是终点** —— 对话播完标记结局并结束，不再看 `next`。
## 结局本来就该是终点；留着 next 反而会出现「演完结局又接了一段」的怪事。
var ending: StringName = &""
## 进这个节点时写什么状态。格式同选项的 `set`。
##
## 给它的理由是「有的事不需要玩家选」：捡到东西、某人退场、天黑了。
## 这些是剧情自己在推进，硬把它们塞进一次假选项里会很别扭。
## 写法一致（键是变量名，值是要设成什么），所以条件那套照旧能用。
var effects: Dictionary = {}


static func from_dictionary(raw: Variant) -> StoryNode:
	var node := StoryNode.new()
	if not (raw is Dictionary):
		return node

	var data := raw as Dictionary
	node.id = StringName(str(data.get("id", "")))
	node.next_id = StringName(str(data.get("next", "")))
	node.ending = StringName(str(data.get("ending", "")))
	node.dialogue = Dialogue.from_array(data.get("talk"))

	var raw_stage: Variant = data.get("stage", [])
	if raw_stage is Array:
		for item: Variant in raw_stage:
			node.stage.append(StageStep.from_dictionary(item))

	var raw_set: Variant = data.get("set", {})
	if raw_set is Dictionary:
		for key: Variant in raw_set:
			node.effects[StringName(str(key))] = raw_set[key]

	var raw_choices: Variant = data.get("choices", [])
	if raw_choices is Array:
		for item: Variant in raw_choices:
			node.choices.append(StoryChoice.from_dictionary(item))

	return node


func has_choices() -> bool:
	return not choices.is_empty()


## 这个节点只演过场、没有说话吗。推进器靠它决定「演完直接往下走」。
func is_silent() -> bool:
	return dialogue.is_empty()


## 这是个结局节点吗。
func is_ending() -> bool:
	return ending != &""
