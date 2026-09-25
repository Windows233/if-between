## 一次「运行」的结果。
##
## 规则引擎不做任何表现，所有该展示的东西都塞在这里返回：
## 收敛情况、冲突、悖论、逐轮记录、因果债增量、表现层事件。
## 这样引擎可以完全脱离场景在无头模式下跑测试。
class_name RuleRunResult
extends RefCounted

## 是否收敛到不动点。false 表示跑到迭代上限时状态还在变，也就是死循环。
var converged: bool = true
## 实际迭代轮数。收敛的正常关卡通常 1~3 轮。
var iterations: int = 0
## 同轮冲突：多条规则在同一轮里把同一个变量设成了不同的值。
## 元素形如 `{"target", "values": Array, "rules": Array[StringName]}`
var conflicts: Array[Dictionary] = []
## 提示级问题：不一定是错，但值得让玩家看到。
## 目前只有 `self_reference`（规则读了自己写的变量）。
## `IF x=0 THEN x=1` 属于这一类，它完全正常；真正可疑的是那种
## 「写完会让自己条件再变真」的写法，那要靠运行结果（不收敛）来判定。
## 所以这里**不**触发悖论怪物，UI 上标黄提示即可。
var warnings: Array[Dictionary] = []
## 悖论。元素形如 `{"type": "divergence", "detail": ...}`
## 目前只有 `divergence`（跑到迭代上限还没收敛）。
## 规则级自指（「如果本规则为真，则删除本规则」）是终章机制，尚未实现，
## 那类悖论将来会以新的 type 出现在这里。
var paradoxes: Array[Dictionary] = []
## 逐轮求值记录，供 UI 回放「世界是怎么一步步演算的」。
## 元素形如 `{"iteration": int, "fired": Array[StringName], "applied": Dictionary}`
var rounds: Array[Dictionary] = []
## 本次运行累积的因果债增量
var debt_delta: int = 0
## 结束时的状态快照
var final_state: Dictionary = {}
## 表现层事件（对话等），按发生顺序。
## 元素形如 `{"type": "say", "speaker": StringName, "line": StringName, "iteration": int}`
var events: Array[Dictionary] = []


func has_paradox() -> bool:
	return not paradoxes.is_empty()


func has_warning() -> bool:
	return not warnings.is_empty()


func has_conflict() -> bool:
	return not conflicts.is_empty()


func paradox_types() -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in paradoxes:
		var t: String = str(p.get("type", "?"))
		if not out.has(t):
			out.append(t)
	return out


func summary() -> String:
	var parts: Array[String] = []
	parts.append("迭代 %d 轮" % iterations)
	parts.append("已收敛" if converged else "未收敛")
	if not conflicts.is_empty():
		parts.append("冲突 %d 处" % conflicts.size())
	if not warnings.is_empty():
		parts.append("提示 %d 条" % warnings.size())
	if not paradoxes.is_empty():
		parts.append("悖论 %s" % ", ".join(paradox_types()))
	if debt_delta != 0:
		parts.append("因果债 +%d" % debt_delta)
	return "，".join(parts)
