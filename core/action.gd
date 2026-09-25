## 动作：`THEN` / `ELSE` 后面的那一半。
##
## 关键设计：动作**不直接修改世界状态**，只产出一个「提案」
## （目标变量 + 期望值）。真正落地由 RuleEngine 在所有规则求值完毕后统一裁决。
##
## 这条约束是整套机制的地基：
##   - 同一轮里多条规则改同一个变量，才能被识别成**冲突**而不是「谁跑得快谁说了算」；
##   - 求值顺序才不会影响结果，规则的效果只由优先级决定；
##   - 悖论（同轮互相矛盾、跨轮来回振荡）才有统一的检测点。
##
## 一旦让动作直接写状态，上面三件事就全做不到了。
class_name Action
extends RefCounted

enum Kind {
	SET,    ## 变量 = 值
	ADD,    ## 变量 += 增量（数字）
	UNSET,  ## 删除变量
	SAY,    ## 触发一段对话：写 `dialogue` 变量，同时给表现层发事件
}

var kind: Kind = Kind.SET
## 目标变量名
var target: StringName = &""
var value: Variant = null
## 是否属于「改写他人命运」。为真的动作会累积因果债。
var personal: bool = false
## 表现层用的附加信息（比如对话 id），不参与规则求值。
var payload: Dictionary = {}


static func set_value(p_target: StringName, p_value: Variant, p_personal: bool = false) -> Action:
	var a := Action.new()
	a.kind = Kind.SET
	a.target = p_target
	a.value = p_value
	a.personal = p_personal
	return a


## 累加。
##
## **注意这是非幂等操作。** 条件是「电平触发」的：只要成立，每一轮都会再加一次。
## 所以 `IF flag THEN x += 1` 永远不会收敛，会一路跑到迭代上限，
## 最终被报成 divergence 悖论。
## 要让加法停下来，条件里必须带上界，例如 `IF flag AND x < 10 THEN x += 1`。
##
## 对玩家来说这是最常踩的坑，UI 上应当把「没有上界的加法」标出来提醒。
static func add_value(p_target: StringName, p_delta: Variant) -> Action:
	var a := Action.new()
	a.kind = Kind.ADD
	a.target = p_target
	a.value = p_delta
	return a


static func unset_value(p_target: StringName) -> Action:
	var a := Action.new()
	a.kind = Kind.UNSET
	a.target = p_target
	return a


## 让某个角色说话。同时会写一个 `dialogue.<角色>` 变量，
## 表现层据此播放对话；规则之间也能读这个变量继续联动。
static func say(p_speaker: StringName, p_line_id: StringName) -> Action:
	var a := Action.new()
	a.kind = Kind.SAY
	a.target = StringName("dialogue.%s" % p_speaker)
	a.value = p_line_id
	a.payload = {"speaker": p_speaker, "line": p_line_id}
	return a


## 产出提案。ADD / SET 需要读当前状态才能算出目标值，所以传入 state。
## 返回 `{"target": StringName, "value": Variant}`；UNSET 的 value 为 null。
func propose(state: WorldState) -> Dictionary:
	match kind:
		Kind.ADD:
			var current: Variant = state.get_value(target)
			if not (current is float or current is int):
				# 对非数字做加法无意义，按 0 起算，避免静默出错
				current = 0
			return {"target": target, "value": current + value}
		Kind.UNSET:
			return {"target": target, "value": null}
		_:
			return {"target": target, "value": value}


func to_text() -> String:
	match kind:
		Kind.SET:
			return "%s = %s" % [target, var_to_str(value)]
		Kind.ADD:
			return "%s += %s" % [target, var_to_str(value)]
		Kind.UNSET:
			return "删除 %s" % target
		Kind.SAY:
			return "%s 说 %s" % [payload.get("speaker", "?"), payload.get("line", "?")]
	return "?"
