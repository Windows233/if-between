## 条件：`IF` 后面的那一半。
##
## 是一棵小树（AST），叶子是变量比较或存在性判断，内部节点是 AND / OR / NOT。
## 之所以做成树而不是字符串，是因为：
##   1. 玩家拖拽的是"块"，天然就是树形结构；
##   2. 求值不需要解析，也不会因为输入格式出错；
##   3. 可以静态分析它读了哪些变量（自指悖论检测要用）。
##
## 变量不存在时的语义：取其值为 `null`，然后按 GDScript 的 `==` / `<` 等原生比较。
## 也就是说 `IF 女孩=在家` 在 `女孩` 未定义时为假，会走 ELSE 分支。
## 要显式判断"有没有这个变量"，用 `Condition.exists()`。
class_name Condition
extends RefCounted

enum Kind {
	COMPARE,  ## left op right
	EXISTS,   ## 变量存在且不为 null
	ALL,      ## 全部子条件为真
	ANY,      ## 任一子条件为真
	NOT,      ## 子条件取反
}

enum Op {
	EQ,
	NE,
	GT,
	GE,
	LT,
	LE,
}

var kind: Kind = Kind.COMPARE
## COMPARE / EXISTS 使用的变量名
var variable: StringName = &""
var op: Op = Op.EQ
## COMPARE 使用的右值（字面量）
var value: Variant = null
## ALL / ANY / NOT 的子条件
var children: Array[Condition] = []


## 构造一个比较条件：`变量 op 值`。
static func compare(p_variable: StringName, p_op: Op, p_value: Variant) -> Condition:
	var c := Condition.new()
	c.kind = Kind.COMPARE
	c.variable = p_variable
	c.op = p_op
	c.value = p_value
	return c


## 语法糖：相等比较，`IF 天气=雨`。
static func equals(p_variable: StringName, p_value: Variant) -> Condition:
	return compare(p_variable, Op.EQ, p_value)


## 语法糖：不等比较。
static func not_equals(p_variable: StringName, p_value: Variant) -> Condition:
	return compare(p_variable, Op.NE, p_value)


## `变量` 存在且不为 null。
static func exists(p_variable: StringName) -> Condition:
	var c := Condition.new()
	c.kind = Kind.EXISTS
	c.variable = p_variable
	return c


## 全部为真（AND）。参数收未类型化的 Array，方便直接传数组字面量。
static func all_of(p_children: Array) -> Condition:
	var c := Condition.new()
	c.kind = Kind.ALL
	for child: Condition in p_children:
		c.children.append(child)
	return c


## 任一为真（OR）。
static func any_of(p_children: Array) -> Condition:
	var c := Condition.new()
	c.kind = Kind.ANY
	for child: Condition in p_children:
		c.children.append(child)
	return c


## 取反（NOT）。
static func negate(p_child: Condition) -> Condition:
	var c := Condition.new()
	c.kind = Kind.NOT
	c.children = [p_child]
	return c


## 从字典构造，用于剧情数据里写条件。
##
## 支持这几种写法：
##   `{ "var": "saw_cat", "op": "==", "value": true }`
##   `{ "exists": "saw_cat" }`
##   `{ "all": [ ...条件... ] }`
##   `{ "any": [ ...条件... ] }`
##   `{ "not": { ...条件... } }`
##
## 认不出来的返回 null。调用方拿到 null 应当当成「无条件」，
## 而不是当成「条件为假」—— 写错一处条件不该让整段剧情消失。
static func from_dictionary(raw: Variant) -> Condition:
	if not (raw is Dictionary):
		return null
	var data := raw as Dictionary

	if data.has("all"):
		return all_of(_list_from(data["all"]))
	if data.has("any"):
		return any_of(_list_from(data["any"]))
	if data.has("not"):
		return negate(from_dictionary(data["not"]))
	if data.has("exists"):
		return exists(StringName(str(data["exists"])))
	if data.has("var"):
		return compare(
			StringName(str(data["var"])),
			op_from_text(str(data.get("op", "=="))),
			data.get("value")
		)
	return null


## 把 `"=="` / `"!="` 这类写法转成枚举。认不出来的按相等处理。
static func op_from_text(text: String) -> Op:
	match text.strip_edges():
		"==", "=", "eq":
			return Op.EQ
		"!=", "<>", "ne":
			return Op.NE
		">", "gt":
			return Op.GT
		">=", "ge":
			return Op.GE
		"<", "lt":
			return Op.LT
		"<=", "le":
			return Op.LE
	return Op.EQ


static func _list_from(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for item: Variant in raw:
			var condition := from_dictionary(item)
			if condition != null:
				out.append(condition)
	return out


## 求值。返回值是确定的，不修改状态。
func eval(state: WorldState) -> bool:
	match kind:
		Kind.COMPARE:
			var lhs: Variant = state.get_value(variable)
			return _compare(lhs, op, value)
		Kind.EXISTS:
			return state.has_value(variable) and state.get_value(variable) != null
		Kind.ALL:
			for child: Condition in children:
				if not child.eval(state):
					return false
			return true
		Kind.ANY:
			for child: Condition in children:
				if child.eval(state):
					return true
			return false
		Kind.NOT:
			if children.is_empty():
				return false
			return not children[0].eval(state)
	return false


## 静态分析：这棵树读了哪些变量。自指检测与 UI 高亮都会用。
func referenced_variables() -> Array[StringName]:
	var out: Array[StringName] = []
	_collect_variables(out)
	return out


func _collect_variables(out: Array[StringName]) -> void:
	if kind == Kind.COMPARE or kind == Kind.EXISTS:
		if not out.has(variable):
			out.append(variable)
		return
	for child: Condition in children:
		child._collect_variables(out)


## 渲染成可读的规则文本，用于 UI 与日志。
func to_text() -> String:
	match kind:
		Kind.COMPARE:
			return "%s %s %s" % [variable, _op_text(op), _value_text(value)]
		Kind.EXISTS:
			return "%s 存在" % variable
		Kind.ALL:
			return "(" + " AND ".join(_children_text()) + ")"
		Kind.ANY:
			return "(" + " OR ".join(_children_text()) + ")"
		Kind.NOT:
			return "NOT " + _children_text()[0]
	return "?"


func _children_text() -> Array[String]:
	var out: Array[String] = []
	for child: Condition in children:
		out.append(child.to_text())
	if out.is_empty():
		out.append("?")
	return out


static func _op_text(p_op: Op) -> String:
	match p_op:
		Op.EQ: return "="
		Op.NE: return "!="
		Op.GT: return ">"
		Op.GE: return ">="
		Op.LT: return "<"
		Op.LE: return "<="
	return "?"


static func _value_text(p_value: Variant) -> String:
	if p_value is String or p_value is StringName:
		return str(p_value)
	return var_to_str(p_value)


static func _compare(lhs: Variant, p_op: Op, rhs: Variant) -> bool:
	match p_op:
		Op.EQ: return lhs == rhs
		Op.NE: return lhs != rhs
		Op.GT: return _ordered(lhs, rhs, 1)
		Op.GE: return _ordered(lhs, rhs, 1) or lhs == rhs
		Op.LT: return _ordered(lhs, rhs, -1)
		Op.LE: return _ordered(lhs, rhs, -1) or lhs == rhs
	return false


## 只有两边都是数字时才做大小比较，避免字符串与数字比较时得到无意义结果。
static func _ordered(lhs: Variant, rhs: Variant, want_sign: int) -> bool:
	if not (lhs is float or lhs is int) or not (rhs is float or rhs is int):
		return false
	var diff: float = float(lhs) - float(rhs)
	if diff == 0.0:
		return false
	return signf(diff) == float(want_sign)
