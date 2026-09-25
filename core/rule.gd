## 规则：一条完整的 `IF ... THEN ... ELSE IF ... THEN ... ELSE ...` 语句。
##
## 一条规则由若干**分支**组成，按顺序取第一个条件成立的分支执行；
## 条件为 null 的分支是兜底 ELSE，永远成立，只能放在最后。
## 这样 `ELSE IF` 不需要拆成多条规则，也就不会出现「第二条规则的条件里
## 忘记否定第一条」这类错误。
##
## 规则本身不碰状态，`evaluate()` 只回答「该执行哪些动作」。
class_name Rule
extends RefCounted

## 一个分支：条件 + 命中后要执行的动作。condition 为 null 表示兜底 ELSE。
class Branch:
	extends RefCounted

	var condition: Condition = null
	var actions: Array[Action] = []


var id: StringName = &""
## 桌面上的可读名字，UI 与日志用
var label: String = ""
## 数值越大越优先。同一轮里多条规则改同一个变量时，优先级高的胜出。
var priority: int = 0
## 作用域。目前是自由标签（`global` / 区域 id / 角色 id），
## 由引擎决定哪些规则参与当前场景的求值。
var scope: StringName = &"global"
## 分支列表，顺序即判定顺序
var branches: Array[Branch] = []
## 关掉的规则不参与求值，但保留在关卡数据里（供 UI 显示与恢复）
var enabled: bool = true
## 这条规则从哪来：`level` 关卡预置、`player` 玩家编写
var origin: StringName = &"level"


## 追加一个分支。actions 传空数组也可以，表示「命中但什么都不做」。
func add_branch(p_condition: Condition, p_actions: Array[Action]) -> Rule:
	var branch := Branch.new()
	branch.condition = p_condition
	branch.actions = p_actions
	branches.append(branch)
	return self


## 追加兜底 ELSE 分支。必须是最后一个。
func add_else(p_actions: Array[Action]) -> Rule:
	return add_branch(null, p_actions)


## 求值：返回第一个命中分支的动作列表。没有分支命中时返回空数组。
func evaluate(state: WorldState) -> Array[Action]:
	for branch: Branch in branches:
		if branch.condition == null or branch.condition.eval(state):
			return branch.actions
	return []


## 命中分支的序号，-1 表示没有分支命中。UI 用它高亮当前走的是哪条。
func evaluate_branch_index(state: WorldState) -> int:
	for i: int in branches.size():
		var branch: Branch = branches[i]
		if branch.condition == null or branch.condition.eval(state):
			return i
	return -1


## 静态分析：这条规则可能写入哪些变量。冲突预检与自指检测用。
func written_variables() -> Array[StringName]:
	var out: Array[StringName] = []
	for branch: Branch in branches:
		for action: Action in branch.actions:
			if not out.has(action.target):
				out.append(action.target)
	return out


## 静态分析：这条规则读了哪些变量。
func read_variables() -> Array[StringName]:
	var out: Array[StringName] = []
	for branch: Branch in branches:
		# 兜底分支没有条件，不算读
		if branch.condition == null:
			continue
		for name: StringName in branch.condition.referenced_variables():
			if not out.has(name):
				out.append(name)
	return out


## 渲染成可读的规则文本。
func to_text() -> String:
	var lines: Array[String] = []
	for i: int in branches.size():
		var branch: Branch = branches[i]
		var head: String
		if branch.condition == null:
			head = "ELSE"
		elif i == 0:
			head = "IF %s" % branch.condition.to_text()
		else:
			head = "ELSE IF %s" % branch.condition.to_text()
		var actions: Array[String] = []
		for action: Action in branch.actions:
			actions.append(action.to_text())
		lines.append("%s THEN %s" % [head, ", ".join(actions)])
	return "\n".join(lines)
