## 剧情推进器：拿着一段剧情和一份世界状态，回答「现在该显示什么」。
##
## 纯逻辑，**不碰界面**。外面只做三件事：
##   1. 把 `current_dialogue()` 交给 DialogueBox 演
##   2. 把 `current_choices()` 交给 ChoiceMenu 显示
##   3. 在对话播完时回调 `on_dialogue_finished()`，在玩家选择时回调 `choose()`
##
## 这样整套剧情逻辑可以脱离界面跑测试，改界面也不会碰坏剧本。
class_name StoryRuntime
extends RefCounted

## 这段剧情走完了
signal finished

## 玩家做过的选择都存在这里。剧情里的条件判定也读它。
var flags: WorldState = null
var event: StoryEvent = null
var node: StoryNode = null
## 本次运行达成的结局。用 `take_ending()` 取走并清空。
var reached_ending: StringName = &""

## 当前节点已经演完了几条舞台指令。
##
## 存档要它。在「等选择」那一步存的档，它正好等于 `stage.size()`；
## 读档回来舞台**从这一条接着演**，而不是从头 ——
## 不然玩家得把整段台词再听一遍（用户报的）。
var stage_step := 0

## 当前节点的对话（`talk`）玩家看过没有。
##
## 和 `stage_step` 分开记：一个节点里这是先后两件事（先演舞台、再念对话），
## 存档可能停在中间任何一处。`elder_commission` 那类「只有 talk」的节点
## 没有舞台，全靠这一位。
var spoke := false

var _done := true


## 开始一段剧情。`p_flags` 跨事件复用，玩家的选择会一直累积。
##
## `resume_node_id` 非空时从**那个节点**接着演，而不是从入口开始。
## 读档用：玩家存档时正演到一半，读回来不该从头再听一遍。
## 节点不存在就退回入口 —— 剧本改过、节点被删了也不该让读档崩掉。
##
## `resume_step` / `resume_spoke` 是**节点内**的进度（见上面两个变量）。
## 只在真的定位到存档记的那个节点时才认：退回了入口，那位进度就是
## 别的节点的，套上去会错位，不如从 0 开始。
func start(p_event: StoryEvent, p_flags: WorldState, resume_node_id: StringName = &"",
		resume_step: int = 0, resume_spoke: bool = false) -> void:
	event = p_event
	flags = p_flags
	_done = false
	node = null
	reached_ending = &""

	if event != null:
		node = event.entry_node()
		var resumed := false
		if resume_node_id != &"":
			var target := event.node(resume_node_id)
			if target != null:
				node = target
				resumed = true
		_enter_node()
		if resumed:
			stage_step = maxi(resume_step, 0)
			spoke = resume_spoke

	if node == null:
		_finish()


func is_finished() -> bool:
	return _done


## 当前节点演到第几步、对话播过没有。存档写的是这两个数。
func current_stage_step() -> int:
	return stage_step


func has_spoken() -> bool:
	return spoke


func current_node_id() -> StringName:
	return node.id if node != null else &""


## 当前节点本身。导演要读它的演出指令，所以得能拿到。
## 拿到的可能是 null（还没开始、或者已经走完）。
func current_node() -> StoryNode:
	return node


func current_dialogue() -> Dialogue:
	return node.dialogue if node != null else Dialogue.new()


## 当前节点上的全部选项。能不能选要另外用 `StoryChoice.is_available(flags)` 判断，
## 灰着显示比直接消失好 —— 玩家能看出「这里本来有条路，只是我现在走不了」。
func current_choices() -> Array[StoryChoice]:
	return node.choices if node != null else []


## 对话播完了。
##
## 返回 true 表示「现在该弹选项了」；返回 false 表示已经自己往下走了一步，
## 外面应当去看 `current_dialogue()` 有没有新内容。
func on_dialogue_finished() -> bool:
	if node == null:
		return false

	# 结局节点是终点：标记结局并收尾，不看 next
	if node.is_ending():
		_mark_ending(node.ending)
		return false

	if node.has_choices():
		return true
	# **走 `resolved_next` 而不是直接 `next_id`** —— 节点可以用 `next_when`
	# 按状态挑两个下游（见 `StoryNode.next_when`）。
	_goto(node.resolved_next(flags))
	return false


## 玩家选了某一项。
##
## 返回 false 表示这次选择没被接受（id 不存在，或者条件不满足），
## 外面应当当作没发生，别往下推进。
func choose(choice_id: StringName) -> bool:
	if node == null:
		return false

	for choice: StoryChoice in node.choices:
		if choice.id != choice_id:
			continue
		if not choice.is_available(flags):
			return false
		_apply(choice)
		_goto(choice.next_id)
		return true

	return false


## 直接跳到某个节点，**跳过 `next` / 选项那条正常的路**。
##
## 给「演出指令自己决定下一步」用 —— 目前只有 IF 框：玩家在里面摆出来的结果
## 决定往哪走（摆对了继续、没改就再转一圈，见 `cutscene.gd` 的 `_if_panel`）。
##
## 普通的推进**不要**用它：该走 `on_dialogue_finished()` / `choose()`，
## 那是剧本数据说了算的。返回 false 表示节点不存在、没跳成。
func jump_to(node_id: StringName) -> bool:
	if node_id == &"" or event == null:
		return false
	if event.node(node_id) == null:
		push_error("[剧情] 跳转到不存在的节点：%s" % node_id)
		return false
	_goto(node_id)
	return true


## 取走本次达成的结局并清空。外面靠它决定「要不要演结局演出」。
func take_ending() -> StringName:
	var id := reached_ending
	reached_ending = &""
	return id


func _apply(choice: StoryChoice) -> void:
	if flags == null:
		return
	for key: Variant in choice.effects:
		flags.set_value(StringName(str(key)), choice.effects[key])


func _goto(node_id: StringName) -> void:
	if node_id == &"" or event == null:
		_finish()
		return

	var next := event.node(node_id)
	if next == null:
		push_error("[剧情] 跳转到不存在的节点：%s" % node_id)
		_finish()
		return

	node = next
	_enter_node()


## 进一个节点时先把它自己带的状态写了。
##
## 放在「进入」而不是「播完」：条件判定发生在**演到这一步**的时候，
## 晚一步写就会让同一段剧情里的后续分支读到旧值。
##
## 顺带把节点内的进度归零 —— 换了节点，上一节点的第几步、说过话没有
## 都跟这个节点没关系。
func _enter_node() -> void:
	stage_step = 0
	spoke = false
	if node == null or flags == null:
		return
	for key: Variant in node.effects:
		flags.set_value(StringName(str(key)), node.effects[key])


## 标记结局达成，然后收尾。
##
## 记在**对话播完之后**而不是进入节点那一刻 —— 台词还没看到就发「达成结局」，
## 玩家会觉得莫名其妙。跳过整段对话也算，那时候 `finished` 照样会发出来。
func _mark_ending(id: StringName) -> void:
	EndingTable.unlock(flags, id)
	reached_ending = id
	_finish()


func _finish() -> void:
	node = null
	_done = true
	finished.emit()
