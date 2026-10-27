## 一段剧情：若干节点组成的小图。从 `entry` 进，顺着 next / choices 往下走。
##
## 之所以做成「图」而不是「一串」，是因为概念图里的剧情有合流：
## 分支①和分支②走到后面会汇到同一段。用数组表达不了，用 id 引用才自然。
##
## 纯数据。推进逻辑在 `StoryRuntime`，演在 `DialogueBox` / `ChoiceMenu`。
class_name StoryEvent
extends RefCounted

var id: StringName = &""
## 从哪个节点开始。留空就用第一个。
var entry: StringName = &""
var nodes: Array[StoryNode] = []


static func from_dictionary(raw: Variant) -> StoryEvent:
	var event := StoryEvent.new()
	if not (raw is Dictionary):
		return event

	var data := raw as Dictionary
	event.id = StringName(str(data.get("id", "")))
	event.entry = StringName(str(data.get("entry", "")))

	var raw_nodes: Variant = data.get("nodes", [])
	if raw_nodes is Array:
		for item: Variant in raw_nodes:
			event.nodes.append(StoryNode.from_dictionary(item))

	return event


## 按 id 找节点。找不到返回 null。
func node(node_id: StringName) -> StoryNode:
	for node: StoryNode in nodes:
		if node.id == node_id:
			return node
	return null


## 入口节点。`entry` 没写就取第一个。
func entry_node() -> StoryNode:
	if entry != &"":
		return node(entry)
	if nodes.is_empty():
		return null
	return nodes[0]


## 校验。返回问题列表，空数组表示没问题。
##
## 在剧情加载时调用一次。跳转到不存在的节点是最容易犯的错，
## 而且不校验的话要玩到那一步才会发现 —— 那时已经是一段黑屏了。
##
## `known_endings` 传结局表里已有的 id，用来查结局节点有没有写错名字。
## 不传就不查 —— core 层不读文件，结局表由外面加载好传进来。
func validate(known_endings: Array[StringName] = []) -> Array[String]:
	var problems: Array[String] = []

	if nodes.is_empty():
		problems.append("事件 %s 没有任何节点" % id)
		return problems

	if entry_node() == null:
		problems.append("事件 %s 的 entry「%s」指向不存在的节点" % [id, entry])

	# 临时角色是**跨节点**活的：这个节点把老人放出来，下一个节点让他走。
	# 所以「先放出来再使唤」这条要沿着整段剧情的顺序累计着查。
	var spawned: Array[String] = []

	var seen: Array[StringName] = []
	for node: StoryNode in nodes:
		if node.id == &"":
			problems.append("事件 %s 里有节点没写 id" % id)
			continue
		if seen.has(node.id):
			problems.append("事件 %s 里节点 id 重复：%s" % [id, node.id])
		seen.append(node.id)

	for node: StoryNode in nodes:
		if node.next_id != &"" and self.node(node.next_id) == null:
			problems.append("节点 %s 的 next 指向不存在的节点：%s" % [node.id, node.next_id])

		if node.is_ending():
			# 结局节点写了 next 是白写，多半是写着写着忘了删
			if node.next_id != &"":
				problems.append("节点 %s 是结局节点，它的 next 会被忽略" % node.id)
			if not known_endings.is_empty() and not known_endings.has(node.ending):
				problems.append("节点 %s 的结局「%s」不在结局表里" % [node.id, node.ending])

		for choice: StoryChoice in node.choices:
			if choice.id == &"":
				problems.append("节点 %s 里有选项没写 id" % node.id)
			if choice.next_id != &"" and self.node(choice.next_id) == null:
				problems.append("节点 %s 的选项 %s 指向不存在的节点：%s"
					% [node.id, choice.id, choice.next_id])

		problems.append_array(_validate_stage(node, spawned))
		if node.id == &"first_item_select":
			var has_inventory_selection := false
			for step: StageStep in node.stage:
				if step.kind == &"inventory_select" \
						and step.text("result") == "ch2/library/first_cat_medium":
					has_inventory_selection = true
			if not has_inventory_selection:
				problems.append("节点 %s 缺少动态背包道具选择" % node.id)

	return problems


## 查一个节点的演出指令。
##
## 除了「指令本身写没写全」，还查**先放出来、再动它**这个顺序：
## 让一个还没出场的临时角色走过去，是剧本里很容易犯的错，
## 演到那一步只会静静地什么都不发生。
##
## `spawned` 是**已经放出来过**的临时角色，逐个节点累积着传下去。
static func _validate_stage(node: StoryNode, spawned: Array[String]) -> Array[String]:
	var problems: Array[String] = []

	for index: int in node.stage.size():
		var step := node.stage[index]
		for problem: String in step.validate():
			problems.append("节点 %s 第 %d 条演出指令：%s" % [node.id, index + 1, problem])

		match step.kind:
			&"npc":
				spawned.append(step.text("id"))
			&"npc_move", &"npc_remove":
				var who := step.text("id")
				if who != "" and not spawned.has(who):
					problems.append("节点 %s 第 %d 条演出指令：临时角色「%s」还没放出来就被使唤了"
						% [node.id, index + 1, who])

	return problems
