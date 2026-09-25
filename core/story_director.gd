## 剧情导演：把推进器算出来的东西演出来，再把玩家的选择送回推进器。
##
## 从 `main.gd` 拆出来的理由：那两件事（推进 / 演出）互相咬得很紧，
## 但跟场景、相机、角色、存档一点关系都没有。混在入口里，
## 光是「对话播完该问谁」这种事就要在 500 行里翻。
##
## **不认识结局表和存档** —— 走到结局时只报 id，演出归 main。
## 认识 DialogueBox、ChoiceMenu 与 Cutscene，但不认识 MapView、Player、Camera。
##
## 一个节点按 `stage → talk → choices` 的顺序走。演出那一层要等画面，
## 所以这里是**协程**：`_run()` 一路 await 下去，中途靠 `_running` 挡住
## 外面的回调 —— 演出自己在播台词时，`dialogue.finished` 不能又被当成
## 「玩家推完了这一句」处理，否则一个节点会被走两遍。
class_name StoryDirector
extends RefCounted

## 一段剧情走完。`ending_id` 非空表示这次走到了结局。
## 外面据此重画场景、演结局演出。
signal ended(ending_id: StringName)

var flags: WorldState = null
var runtime := StoryRuntime.new()
var dialogue: DialogueBox = null
var menu: ChoiceMenu = null
var cutscene: Cutscene = null
var active := false
## 正在演的事件 id。存档要记它，读档才能接着演。
var event_id: StringName = &""
## 演出脚本正在跑（await 中）。这期间外面的回调一律不认。
var _running := false


## 接上界面。重复调用安全。
func setup(p_dialogue: DialogueBox, p_menu: ChoiceMenu, p_cutscene: Cutscene = null) -> void:
	dialogue = p_dialogue
	menu = p_menu
	cutscene = p_cutscene


func is_active() -> bool:
	return active


## 演出脚本正在跑吗。外面据此决定「这一下点击算不算数」。
func is_running() -> bool:
	return _running


## 当前演到哪个节点。给测试和调试用。
func current_node_id() -> StringName:
	return runtime.current_node_id()


## 当前节点演到第几步、这段台词播过没有。存档写的是这两个数。
##
## 见 `StoryRuntime.stage_step` / `spoke`。
func stage_step() -> int:
	return runtime.current_stage_step()


func spoke() -> bool:
	return runtime.has_spoken()


## 开始一段剧情。事件为 null 时什么都不做（外面已经打过日志了）。
##
## `resume_node_id` 非空则从那个节点接着演（读档用），见 `StoryRuntime.start()`。
## 后两个参数是**节点内**的进度，理由同上。
func start(event: StoryEvent, p_flags: WorldState, resume_node_id: StringName = &"",
		resume_step: int = 0, resume_spoke: bool = false) -> void:
	if event == null:
		return
	flags = p_flags
	event_id = event.id
	runtime.start(event, p_flags, resume_node_id, resume_step, resume_spoke)
	if runtime.is_finished():
		return
	active = true
	_run()


## 切场景时收尾。把状态清干净，别带进下一个场景。
##
## 正常玩法里剧情进行中角色动不了、也就切不了场景，
## 但测试会走到这条路，将来「剧情中途换场景」也会。
func cancel() -> void:
	active = false
	_running = false
	event_id = &""
	if cutscene != null:
		cutscene.cancel()
	if dialogue != null:
		dialogue.release_hold()
		dialogue.close()
	if menu != null:
		menu.close()


# ---------------------------------------------------------------- 回调

## 对话框播完了一句（或整段被跳过）。
## 只在这次真的有剧情在跑、而且演出没在自己播台词时才该被调用。
func on_dialogue_finished() -> void:
	if not active or _running:
		return

	# **这一段台词播完了，记一笔。** 读档靠它判断「别再念一遍」。
	#
	# 必须赶在 `runtime.on_dialogue_finished()` 前面：那一步多半会把
	# 节点换成下一个，而换节点会把节点内的进度归零。
	_note_spoken()

	if runtime.on_dialogue_finished():
		_open_choices()
		return

	if runtime.is_finished():
		_end()
		return

	_run()


## 选项菜单选了一项。返回 true 表示这次选择是剧情的 IF 选项，
## 外面就不用再当角色动作处理了。
func choose(id: StringName) -> bool:
	if not active or _running:
		return false
	# 选项不在列表里、或者条件不满足时，推进器会拒绝。
	# 外面应当当作没发生，别往下走 —— 悄悄跳到别的分支是最难查的一类 bug。
	if not runtime.choose(id):
		return true

	if dialogue != null:
		# 内嵌选项那一次面板是留着的，这里把它收掉。
		# release_hold 不发 finished，免得又绕回来推进一遍。
		dialogue.release_hold()
	if menu != null:
		menu.close()

	if runtime.is_finished():
		_end()
	else:
		_run()
	return true


## 直接跳到某个节点。**演出指令自己决定下一步时用**（目前只有 IF 框）。
##
## 转发给 `runtime.jump_to()` —— 外面不该自己去摸 `runtime`。
##
## **跳完这里不调 `_run()`。** 调用方是演出里的协程（`cutscene._if_panel`），
## 它那条 `await` 还没返回；等它返回，`_run()` 的循环会把当前节点重新取一次，
## 自然就走到新的那个上了。在这儿再 `_run()` 一次会把同一段演两遍。
func jump_to(node_id: StringName) -> bool:
	return runtime.jump_to(node_id)


# ---------------------------------------------------------------- 内部

## 把当前节点走完：先演 stage，再播 talk，没有说话就自己往下走。
##
## 写成循环而不是递归：连着好几个「纯演出节点」时，
## 递归会一层层压栈，而且中途出错很难看出走到第几个了。
func _run() -> void:
	while true:
		if not active:
			return
		var node := runtime.current_node()
		if node == null:
			return

		if not node.stage.is_empty():
			if cutscene == null:
				push_warning("[剧情] 节点 %s 有演出指令，但没有接上演出的执行器" % node.id)
			else:
				_running = true
				# **从哪儿接着演。** 正常是从头；读档回来时 `runtime.stage_step`
				# 记着上次演到第几条，补演前面的画面、从那条往下继续 ——
				# 从头演一遍就是「重放」（用户报的）。
				await cutscene.run(node.stage, runtime.stage_step, _on_stage_step)
				_running = false
			if not active:
				return
			node = runtime.current_node()
			if node == null:
				return

		if not node.is_silent():
			if runtime.spoke:
				# **读档回来，这段台词玩家已经看过了。**
				# 摆成「播完」的样子就行：立绘就位、有选项就停在等选择上。
				# 再念一遍就是「回到对话开头重新放」。
				dialogue.restore_played(node.dialogue, node.has_choices())
			else:
				# 有选项的节点，最后一句播完**不收起面板** ——
				# 选项就摆在对话框中间，两边立绘留着。
				dialogue.play(node.dialogue, node.has_choices())
				if cutscene != null and cutscene.instant:
					# 即时模式（无头测试）：不等玩家点，把这一段记完直接往下走。
					# 这段期间 `_running` 是 false，所以这条 finished 会绕回这里，
					# 由本函数重入一次把流程推到底 —— 每次只深一层，不会堆爆。
					dialogue.skip()
			return

		# 没有说话：这个节点自己走完，接着看下一个
		if runtime.on_dialogue_finished():
			_open_choices()
			return
		if runtime.is_finished():
			_end()
			return


## 舞台演完了一条，把进度推到「已经演完几条」。存档读的就是这个数。
func _on_stage_step(done: int) -> void:
	runtime.stage_step = done


## 当前节点的台词播完了，记一笔。
##
## `is_silent()` 的节点（没有 `talk`）没什么可记的 —— 给它标上反而
## 会让读档时以为「这段话说过」，把该演的跳过。
func _note_spoken() -> void:
	var node := runtime.current_node()
	if node != null and not node.is_silent():
		runtime.spoke = true


func _open_choices() -> void:
	var options: Array[ChoiceOption] = []
	for choice: StoryChoice in runtime.current_choices():
		# 条件不满足的**不列出来**，不是灰掉。
		# 灰着摆在那儿等于提前告诉玩家「这里本来有条路」——
		# 第一章的「观察」要回溯之后才出现，提前露脸就把转折漏了。
		if not choice.is_available(runtime.flags):
			continue
		options.append(ChoiceOption.make(choice.id, choice.label))

	if options.is_empty():
		# 全被条件挡住了。没有可选的还把玩家留在菜单里，就是死在那儿。
		push_warning("[剧情] 节点 %s 的选项一条都不可选，直接收尾" % runtime.current_node_id())
		if dialogue != null:
			dialogue.release_hold()
		_end()
		return

	if dialogue != null and dialogue.is_holding():
		# 对话框留着（两个人站在框里），选项框浮在它上方 —— 稿子③。
		menu.open_above(options, dialogue.hold_top())
		return
	menu.open("", options)


func _end() -> void:
	active = false
	_running = false
	# 取走结局 id 再发信号：结局只该被演出一次
	var ending_id := runtime.take_ending()
	# 剧情演完了，读档不该再回到这段里
	event_id = &""
	ended.emit(ending_id)
