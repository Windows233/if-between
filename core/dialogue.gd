## 一段对话：若干行，每行是一个 `DialogueLine`。
##
## 纯数据，不碰界面。`DialogueBox` 负责把它演出来。
##
## 单独抽出来是因为剧情事件系统（M2）也要产出这个结构，
## 而那时候不一定有界面 —— 校验、测试、将来的剧本预览都要用。
##
## 一次交互对应一段对话，所以「自动放下一句」和「跳过这一段」
## 才有操作对象。只有一行的话，那两个功能没有意义。
class_name Dialogue
extends RefCounted

var lines: Array[DialogueLine] = []


## 从 JSON 数组构造：
## `[{"speaker": "邻居", "text": "今天天气不错。"}, {"text": "（她指了指门外。）"}]`
static func from_array(raw: Variant) -> Dialogue:
	var dialogue := Dialogue.new()
	if not (raw is Array):
		return dialogue
	for item: Variant in raw:
		dialogue.lines.append(DialogueLine.from_dictionary(item))
	return dialogue


## 只有一行的对话。数据里写简写时用。
static func single(speaker: String, text: String) -> Dialogue:
	var dialogue := Dialogue.new()
	var line := DialogueLine.new()
	line.speaker = speaker
	line.text = text
	dialogue.lines.append(line)
	return dialogue


func is_empty() -> bool:
	return lines.is_empty()


func size() -> int:
	return lines.size()


## 拼成纯文本，供对话记录与调试日志使用。
func to_text() -> String:
	var parts: Array[String] = []
	for line: DialogueLine in lines:
		if line.speaker == "":
			parts.append(line.text)
		else:
			parts.append("%s：%s" % [line.speaker, line.text])
	return "\n".join(parts)
