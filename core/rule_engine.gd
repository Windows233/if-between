## 规则引擎：把一堆规则在世界状态上反复求值，直到世界稳定下来。
##
## 求值语义（这几条决定了整个游戏的手感，改动前先想清楚）：
##
## 1. **每轮基于同一份快照**。一轮里所有规则都从同一份状态副本读值，
##    动作也不直接落地，而是先攒成「提案」。所以同一轮内规则之间不互相影响，
##    结果与规则的处理顺序无关，只由优先级决定。
## 2. **优先级决定胜负**。多条规则在同一轮改同一个变量时，优先级最高的生效；
##    同优先级且值不同，记为冲突（留给悖论机制去做文章）；同优先级且值相同，
##    按规则 id 字典序取一条，保证结果可复现。
## 3. **反复迭代到不动点**。一轮结束后若状态还有变化，就再跑一轮。
##    这是「连锁反应」的来源，也是死循环的来源。
## 4. **不收敛就是悖论**。跑到迭代上限仍在变化，判定为死循环。
##
## 引擎不认识场景、节点、UI。所有要展示的东西都通过 RuleRunResult 返回。
class_name RuleEngine
extends RefCounted

## 单次运行的最大迭代轮数。正常关卡 1~3 轮就该收敛。
const DEFAULT_MAX_ITERATIONS := 64
## 逐轮记录最多保留几轮，避免大关卡把内存吃光
const TRACE_LIMIT := 8


## 在 state 上运行 rules。**会直接修改 state**（关卡数据本身不动）。
## options:
##   `max_iterations: int` 迭代上限
##   `scopes: Array`       只启用这些作用域的规则；留空表示全部启用
static func run(state: WorldState, rules: Array[Rule], options: Dictionary = {}) -> RuleRunResult:
	var result := RuleRunResult.new()
	var max_iterations: int = int(options.get("max_iterations", DEFAULT_MAX_ITERATIONS))
	var scopes: Array = options.get("scopes", [])

	var active: Array[Rule] = _active_rules(rules, scopes)

	# 自引用在跑之前就能静态查出来。注意它只是**提示**：
	# `IF x=0 THEN x=1` 也读了自己写的变量，但一轮就收敛，没有任何问题。
	# 真正的硬悖论要看运行结果（不收敛）。
	result.warnings.append_array(_detect_self_reference(active))

	for iteration: int in range(1, max_iterations + 1):
		result.iterations = iteration

		# 1. 快照 + 收集提案
		var snapshot := state.fork()
		var proposals := _collect_proposals(active, snapshot)

		# 2. 裁决冲突（同一个冲突在多轮里会反复出现，只记第一次）
		var round_conflicts := _resolve_conflicts(proposals)
		for conflict: Dictionary in round_conflicts:
			conflict["first_iteration"] = iteration
			if not _conflict_recorded(result.conflicts, conflict):
				result.conflicts.append(conflict)

		# 3. 落地
		var applied := _apply(state, proposals, result, iteration)

		if iteration <= TRACE_LIMIT:
			result.rounds.append({
				"iteration": iteration,
				"fired": _fired_rule_ids(proposals),
				"applied": applied,
			})

		if applied.is_empty():
			result.converged = true
			result.final_state = state.snapshot()
			return result

	# 跑满上限还在变 = 死循环
	result.converged = false
	result.paradoxes.append({
		"type": "divergence",
		"detail": "跑到 %d 轮上限状态仍在变化，判定为死循环" % max_iterations,
	})
	result.final_state = state.snapshot()
	return result


## 过滤出参与求值的规则，并给出一个确定的处理顺序。
## 顺序不影响结果（同一轮用快照），只影响日志与同优先级裁决的可复现性。
static func _active_rules(rules: Array[Rule], scopes: Array) -> Array[Rule]:
	var out: Array[Rule] = []
	for rule: Rule in rules:
		if not rule.enabled:
			continue
		if not scopes.is_empty() and not scopes.has(rule.scope):
			continue
		out.append(rule)
	out.sort_custom(func(a: Rule, b: Rule) -> bool: return str(a.id) < str(b.id))
	return out


## 让每条规则对着快照求值，产出「目标变量 -> 提案列表」。
static func _collect_proposals(rules: Array[Rule], snapshot: WorldState) -> Dictionary:
	var proposals: Dictionary = {}
	for rule: Rule in rules:
		var branch_index: int = rule.evaluate_branch_index(snapshot)
		if branch_index < 0:
			continue
		var branch: Rule.Branch = rule.branches[branch_index]
		for action: Action in branch.actions:
			var proposal: Dictionary = action.propose(snapshot)
			var target: StringName = proposal.get("target", &"")
			if target == &"":
				continue
			if not proposals.has(target):
				proposals[target] = []
			proposals[target].append({
				"target": target,
				"value": proposal.get("value"),
				"unset": action.kind == Action.Kind.UNSET,
				"rule_id": rule.id,
				"priority": rule.priority,
				"action": action,
				"branch_index": branch_index,
			})
	return proposals


## 找出同轮里对同一变量提出不同值的规则。
##
## 分两种：
##   `ambiguous = false` —— 优先级不同，高优先级依法胜出。属于正常裁决。
##   `ambiguous = true`  —— 最高优先级层里就有两个不同的值，引擎没法裁决。
##                          这是真正的冲突，也是悖论机制的素材。
## 两种情况都记下来，交给 UI 提示玩家「你写的规则打架了」。
static func _resolve_conflicts(proposals: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for target: Variant in proposals:
		var entries: Array = proposals[target]
		if entries.size() < 2:
			continue
		var values: Array = _unique_values(entries)
		if values.size() < 2:
			continue
		var top: Array = _top_priority_entries(entries)
		var top_values: Array = _unique_values(top)
		out.append({
			"target": StringName(target),
			"values": values,
			"rules": _rule_ids(entries),
			"ambiguous": top_values.size() > 1,
		})
	return out


## 把裁决结果写进 state，返回真正发生变化的变量。
static func _apply(
	state: WorldState,
	proposals: Dictionary,
	result: RuleRunResult,
	iteration: int
) -> Dictionary:
	var applied: Dictionary = {}
	for target_variant: Variant in proposals:
		var target := StringName(target_variant)
		var top: Array = _top_priority_entries(proposals[target_variant])
		top.sort_custom(_by_rule_id)
		var winner: Dictionary = top[0]

		var changed := false
		if winner["unset"]:
			changed = state.has_value(target)
			if changed:
				state.unset_value(target)
		else:
			var desired: Variant = winner["value"]
			changed = (not state.has_value(target)) or state.get_value(target) != desired
			if changed:
				state.set_value(target, desired)

		if not changed:
			continue

		applied[target] = null if winner["unset"] else winner["value"]

		if winner["action"].personal:
			result.debt_delta += 1
		if winner["action"].kind == Action.Kind.SAY:
			result.events.append({
				"type": "say",
				"speaker": winner["action"].payload.get("speaker", &""),
				"line": winner["action"].payload.get("line", &""),
				"iteration": iteration,
			})
	return applied


## 取优先级最高的那批提案。
static func _top_priority_entries(entries: Array) -> Array:
	var max_priority: int = -2147483648
	for entry: Dictionary in entries:
		max_priority = maxi(max_priority, int(entry["priority"]))
	var out: Array = []
	for entry: Dictionary in entries:
		if int(entry["priority"]) == max_priority:
			out.append(entry)
	return out


static func _unique_values(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		var value: Variant = entry["value"]
		if not out.has(value):
			out.append(value)
	return out


## 同一个变量上的冲突在多轮里会反复出现，只保留第一次的记录。
static func _conflict_recorded(existing: Array[Dictionary], candidate: Dictionary) -> bool:
	for item: Dictionary in existing:
		if item["target"] == candidate["target"] and item["ambiguous"] == candidate["ambiguous"]:
			return true
	return false


static func _rule_ids(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		if not out.has(entry["rule_id"]):
			out.append(entry["rule_id"])
	return out


static func _fired_rule_ids(proposals: Dictionary) -> Array:
	var out: Array = []
	for target: Variant in proposals:
		for entry: Dictionary in proposals[target]:
			if not out.has(entry["rule_id"]):
				out.append(entry["rule_id"])
	return out


## 同优先级的兜底排序：按规则 id 字典序，保证多次运行结果一致。
static func _by_rule_id(a: Dictionary, b: Dictionary) -> bool:
	return str(a["rule_id"]) < str(b["rule_id"])


## 静态自指检测：规则读的变量里，有它自己写的。
## 也就是策划案里那句「如果本规则为真，则删除本规则」的最小形态。
static func _detect_self_reference(rules: Array[Rule]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rule: Rule in rules:
		var reads: Array[StringName] = rule.read_variables()
		if reads.is_empty():
			continue
		var writes: Array[StringName] = rule.written_variables()
		var overlap: Array[StringName] = []
		for name: StringName in reads:
			if writes.has(name):
				overlap.append(name)
		if not overlap.is_empty():
			out.append({
				"type": "self_reference",
				"rule": rule.id,
				"variables": overlap,
				"detail": "规则 %s 读的变量 %s 正是它自己写的" % [rule.id, ", ".join(overlap)],
			})
	return out
