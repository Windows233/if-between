## 规则引擎：IF / THEN / ELSE IF、优先级、冲突、悖论、连锁反应。
## 对应 M1，是整套条件判定的地基。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
class_name TestRules
extends RefCounted


static func run(h: TestHarness) -> void:
	test_basic_if_then(h)
	test_else_branch(h)
	test_else_if_chain(h)
	test_logic_operators(h)
	test_cascade_chain_reaction(h)
	test_same_round_isolation(h)
	test_priority_decides(h)
	test_same_priority_is_ambiguous(h)
	test_divergence_detected(h)
	test_self_reference_is_warning(h)
	test_add_converges_with_guard(h)
	test_unguarded_add_diverges(h)
	test_unset(h)
	test_causal_debt(h)
	test_scope_filter(h)


static func test_basic_if_then(h: TestHarness) -> void:
	var state := WorldState.new()
	state.load_values({"player.has_key": true, "door.locked": true})

	var rule := Rule.new()
	rule.id = &"door_key"
	rule.add_branch(
		Condition.equals(&"player.has_key", true),
		[Action.set_value(&"door.locked", false)]
	)
	var rules: Array[Rule] = [rule]

	var result := RuleEngine.run(state, rules)
	h.check("有钥匙则门开", state.get_value(&"door.locked"), false)
	h.check("已收敛", result.converged, true)
	h.check("第 2 轮确认无变化后收敛", result.iterations, 2)
	h.check("无悖论", result.has_paradox(), false)


static func test_else_branch(h: TestHarness) -> void:
	var state := WorldState.new()
	state.load_values({"player.has_key": false, "door.locked": false})

	var rule := Rule.new()
	rule.id = &"door"
	rule.add_branch(
		Condition.equals(&"player.has_key", true),
		[Action.set_value(&"door.locked", false)]
	)
	rule.add_else([Action.set_value(&"door.locked", true)])
	var rules: Array[Rule] = [rule]

	RuleEngine.run(state, rules)
	h.check("没钥匙则门锁上", state.get_value(&"door.locked"), true)


static func test_else_if_chain(h: TestHarness) -> void:
	var rules: Array[Rule] = [_girl_rule()]

	var rain := WorldState.new()
	rain.load_values({"weather": "rain"})
	RuleEngine.run(rain, rules)
	h.check("雨天带伞出门", rain.get_value(&"girl.action"), "take_umbrella")

	var sunny := WorldState.new()
	sunny.load_values({"weather": "sunny"})
	RuleEngine.run(sunny, rules)
	h.check("晴天去公园", sunny.get_value(&"girl.action"), "go_park")

	var snow := WorldState.new()
	snow.load_values({"weather": "snow"})
	RuleEngine.run(snow, rules)
	h.check("其它天气待在家", snow.get_value(&"girl.action"), "stay_home")


static func test_logic_operators(h: TestHarness) -> void:
	var state := WorldState.new()
	state.load_values({"a": true, "b": false, "c": true, "n": 7})

	h.check("AND 全真为真", Condition.all_of([
		Condition.equals(&"a", true),
		Condition.equals(&"c", true),
	]).eval(state), true)

	h.check("AND 有假为假", Condition.all_of([
		Condition.equals(&"a", true),
		Condition.equals(&"b", true),
	]).eval(state), false)

	h.check("OR 有真为真", Condition.any_of([
		Condition.equals(&"b", true),
		Condition.equals(&"c", true),
	]).eval(state), true)

	h.check("OR 全假为假", Condition.any_of([
		Condition.equals(&"b", true),
		Condition.equals(&"n", 99),
	]).eval(state), false)

	h.check("NOT 取反", Condition.negate(Condition.equals(&"b", true)).eval(state), true)
	h.check("不存在的变量按 null 比较，等于判断为假",
		Condition.equals(&"zzz", true).eval(state), false)
	h.check("EXISTS 对未定义变量为假", Condition.exists(&"zzz").eval(state), false)
	h.check("EXISTS 对已定义变量为真", Condition.exists(&"a").eval(state), true)

	h.check("数值比较 >", Condition.compare(&"n", Condition.Op.GT, 5).eval(state), true)
	h.check("数值比较 <= 假", Condition.compare(&"n", Condition.Op.LE, 5).eval(state), false)
	h.check("文本与数字不做大小比较",
		Condition.compare(&"a", Condition.Op.GT, 0).eval(state), false)


static func test_cascade_chain_reaction(h: TestHarness) -> void:
	# 教学关：浇花 -> 花盆里出现钥匙 -> 开门。三件事必须分轮发生。
	var state := WorldState.new()
	state.load_values({
		"pot.watered": true,
		"player.has_key": false,
		"door.locked": true,
	})

	var r_pot := Rule.new()
	r_pot.id = &"pot_gives_key"
	r_pot.add_branch(
		Condition.equals(&"pot.watered", true),
		[Action.set_value(&"player.has_key", true)]
	)

	var r_door := Rule.new()
	r_door.id = &"key_opens_door"
	r_door.add_branch(
		Condition.equals(&"player.has_key", true),
		[Action.set_value(&"door.locked", false)]
	)

	var rules: Array[Rule] = [r_pot, r_door]
	var result := RuleEngine.run(state, rules)

	h.check("钥匙出现", state.get_value(&"player.has_key"), true)
	h.check("门被打开", state.get_value(&"door.locked"), false)
	h.check("级联花了 3 轮", result.iterations, 3)
	h.check("每轮都有记录", result.rounds.size() >= 2, true)


static func test_same_round_isolation(h: TestHarness) -> void:
	# 同轮内后面的规则不该看到前面规则刚写的值，否则结果就依赖处理顺序。
	# b 只有在下一轮才能看到 a 写下的 x=1。
	var state := WorldState.new()
	state.load_values({"trigger": true, "x": 0})

	var r_a := Rule.new()
	r_a.id = &"a_sets_x"
	r_a.add_branch(Condition.equals(&"trigger", true), [Action.set_value(&"x", 1)])

	var r_b := Rule.new()
	r_b.id = &"b_reads_x"
	r_b.add_branch(Condition.equals(&"x", 1), [Action.set_value(&"y", 99)])

	var rules: Array[Rule] = [r_a, r_b]
	var result := RuleEngine.run(state, rules)

	h.check("轮 1 里 b 未命中", result.rounds[0]["fired"].has(&"b_reads_x"), false)
	h.check("轮 2 里 b 命中了", result.rounds[1]["fired"].has(&"b_reads_x"), true)
	h.check("最终 y = 99", state.get_value(&"y"), 99)
	h.check("总共 3 轮", result.iterations, 3)


static func test_priority_decides(h: TestHarness) -> void:
	var state := WorldState.new()
	state.load_values({"flag": true, "x": 0})

	var high := Rule.new()
	high.id = &"high"
	high.priority = 10
	high.add_branch(Condition.equals(&"flag", true), [Action.set_value(&"x", 1)])

	var low := Rule.new()
	low.id = &"low"
	low.priority = 5
	low.add_branch(Condition.equals(&"flag", true), [Action.set_value(&"x", 2)])

	var rules: Array[Rule] = [low, high]
	var result := RuleEngine.run(state, rules)

	h.check("高优先级胜出", state.get_value(&"x"), 1)
	h.check("记下了这次竞争", result.conflicts.size(), 1)
	h.check("但不算无法裁决", result.conflicts[0]["ambiguous"], false)
	h.check("规则数组顺序不影响结果", result.conflicts[0]["target"], &"x")


static func test_same_priority_is_ambiguous(h: TestHarness) -> void:
	var state := WorldState.new()
	state.load_values({"flag": true, "x": 0})

	var one := Rule.new()
	one.id = &"one"
	one.priority = 5
	one.add_branch(Condition.equals(&"flag", true), [Action.set_value(&"x", 1)])

	var two := Rule.new()
	two.id = &"two"
	two.priority = 5
	two.add_branch(Condition.equals(&"flag", true), [Action.set_value(&"x", 2)])

	var rules: Array[Rule] = [one, two]
	var result := RuleEngine.run(state, rules)

	h.check("识别为无法裁决", result.conflicts.size() >= 1, true)
	h.check("冲突标记正确", result.conflicts[0]["ambiguous"], true)
	# 同优先级时按 id 字典序取一条，保证可复现
	h.check("按 id 序取到 one", state.get_value(&"x"), 1)


static func test_divergence_detected(h: TestHarness) -> void:
	# 两条规则来回踢，世界永远停不下来。
	var state := WorldState.new()
	state.load_values({"x": 0})

	var to_one := Rule.new()
	to_one.id = &"to_one"
	to_one.add_branch(Condition.equals(&"x", 0), [Action.set_value(&"x", 1)])

	var to_zero := Rule.new()
	to_zero.id = &"to_zero"
	to_zero.add_branch(Condition.equals(&"x", 1), [Action.set_value(&"x", 0)])

	var rules: Array[Rule] = [to_one, to_zero]
	var result := RuleEngine.run(state, rules, {"max_iterations": 20})

	h.check("判定为不收敛", result.converged, false)
	h.check("有悖论", result.has_paradox(), true)
	h.check("悖论类型是 divergence", result.paradoxes[0]["type"], "divergence")
	h.check("跑满 20 轮", result.iterations, 20)


static func test_self_reference_is_warning(h: TestHarness) -> void:
	# 读自己写的变量属于提示，不是悖论：这条规则一轮就收敛了。
	var state := WorldState.new()
	state.load_values({"x": 0})

	var rule := Rule.new()
	rule.id = &"self_touch"
	rule.add_branch(Condition.equals(&"x", 0), [Action.set_value(&"x", 1)])
	var rules: Array[Rule] = [rule]

	var result := RuleEngine.run(state, rules)
	h.check("给出提示", result.has_warning(), true)
	h.check("提示类型是 self_reference", result.warnings[0]["type"], "self_reference")
	h.check("不受影响地收敛了", result.converged, true)
	h.check("不算悖论", result.has_paradox(), false)


static func test_add_converges_with_guard(h: TestHarness) -> void:
	# ADD 是**非幂等**的：同一轮条件成立就加一次，下一轮如果条件还成立就再加。
	# 所以 `IF flag THEN x += 1` 永远不会收敛，会一路跑到迭代上限。
	# 想让加法收敛，条件里必须带上界，写成「加到满足某条件为止」。
	var state := WorldState.new()
	state.load_values({"count": 0, "flag": true})

	var rule := Rule.new()
	rule.id = &"count_up"
	rule.add_branch(
		Condition.all_of([
			Condition.equals(&"flag", true),
			Condition.compare(&"count", Condition.Op.LT, 3),
		]),
		[Action.add_value(&"count", 1)]
	)
	var rules: Array[Rule] = [rule]

	var result := RuleEngine.run(state, rules)
	h.check("带上界后累加到 3", state.get_value(&"count"), 3)
	h.check("收敛了", result.converged, true)


static func test_unguarded_add_diverges(h: TestHarness) -> void:
	# 反面教材：没有上界的加法。这是玩家最可能踩的坑，
	# 结果会以 divergence 悖论的形式呈现，正好接上策划案里的「调试」环节。
	var state := WorldState.new()
	state.load_values({"flag": true, "count": 0})

	var rule := Rule.new()
	rule.id = &"runaway_add"
	rule.add_branch(Condition.equals(&"flag", true), [Action.add_value(&"count", 1)])
	var rules: Array[Rule] = [rule]

	var result := RuleEngine.run(state, rules, {"max_iterations": 16})
	h.check("无上界的加法不收敛", result.converged, false)
	h.check("报为 divergence", result.paradoxes[0]["type"], "divergence")
	h.check("累加到了迭代上限", state.get_value(&"count"), 16)


static func test_unset(h: TestHarness) -> void:
	var state := WorldState.new()
	state.load_values({"temp": "here", "flag": true})

	var rule := Rule.new()
	rule.id = &"clear_temp"
	rule.add_branch(Condition.equals(&"flag", true), [Action.unset_value(&"temp")])
	var rules: Array[Rule] = [rule]

	RuleEngine.run(state, rules)
	h.check("变量被删除", state.has_value(&"temp"), false)
	h.check("删除后再取为 null", state.get_value(&"temp"), null)


static func test_causal_debt(h: TestHarness) -> void:
	var state := WorldState.new()
	state.load_values({"weather": "rain", "girl.action": "stay_home"})

	var rule := Rule.new()
	rule.id = &"rewrite_girl"
	rule.add_branch(
		Condition.equals(&"weather", "rain"),
		[Action.set_value(&"girl.action", "take_umbrella", true)]  # personal = true
	)
	var rules: Array[Rule] = [rule]

	var result := RuleEngine.run(state, rules)
	h.check("因果债 +1", result.debt_delta, 1)
	h.check("女孩的结局被改写", state.get_value(&"girl.action"), "take_umbrella")


static func test_scope_filter(h: TestHarness) -> void:
	var state := WorldState.new()
	state.load_values({"flag": true})

	var global_rule := Rule.new()
	global_rule.id = &"global_rule"
	global_rule.scope = &"global"
	global_rule.add_branch(Condition.equals(&"flag", true), [Action.set_value(&"g", 1)])

	var local_rule := Rule.new()
	local_rule.id = &"local_rule"
	local_rule.scope = &"rain_city"
	local_rule.add_branch(Condition.equals(&"flag", true), [Action.set_value(&"l", 1)])

	var rules: Array[Rule] = [global_rule, local_rule]

	RuleEngine.run(state, rules, {"scopes": [&"global"]})
	h.check("作用域内的规则生效", state.get_value(&"g"), 1)
	h.check("作用域外的规则被跳过", state.has_value(&"l"), false)


## 「女孩出门」这条规则，好几个用例拿它当夹具。
static func _girl_rule() -> Rule:
	var rule := Rule.new()
	rule.id = &"girl"
	rule.add_branch(
		Condition.equals(&"weather", "rain"),
		[Action.set_value(&"girl.action", "take_umbrella")]
	)
	rule.add_branch(
		Condition.equals(&"weather", "sunny"),
		[Action.set_value(&"girl.action", "go_park")]
	)
	rule.add_else([Action.set_value(&"girl.action", "stay_home")])
	return rule
