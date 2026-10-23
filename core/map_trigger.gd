## 地图触发定义：解析矩形、事件绑定、触发方式与条件。
## 纯数据层，不读取文件，不启动剧情，不持有场景节点。
## 校验失败的定义保留错误，由地图校验与运行器共同拒绝执行。
class_name MapTrigger
extends RefCounted

const MODES := [&"enter_map", &"enter", &"interact", &"click"]
const OPERATORS := ["==", "=", "eq", "!=", "<>", "ne", ">", "gt", ">=", "ge", "<", "lt", "<=", "le"]

var id: StringName = &""
var rect := Rect2()
var event: StringName = &""
var mode: StringName = &"enter"
var enabled := true
var once := false
var condition: Condition = null
var _errors: Array[String] = []


static func from_dictionary(raw: Variant) -> MapTrigger:
	var trigger := MapTrigger.new()
	if not raw is Dictionary:
		trigger._errors.append("触发区域必须是字典")
		return trigger
	for field: String in ["id", "event", "mode"]:
		var value: Variant = raw.get(field, "enter" if field == "mode" else "")
		if value is String or value is StringName:
			trigger.set(field, StringName(value))
		else:
			trigger._errors.append("%s 必须是字符串" % field)
	for field: String in ["enabled", "once"]:
		var value: Variant = raw.get(field, field == "enabled")
		if value is bool:
			trigger.set(field, value)
		else:
			trigger._errors.append("%s 必须是布尔值" % field)
	var bounds: Variant = raw.get("rect")
	if _valid_rect(bounds):
		trigger.rect = Rect2(bounds[0], bounds[1], bounds[2], bounds[3])
	else:
		trigger._errors.append("rect 必须是四个有限数值且宽高大于零")
	if raw.has("condition"):
		if valid_condition(raw.condition):
			trigger.condition = Condition.from_dictionary(raw.condition)
		else:
			trigger._errors.append("condition 不是有效的条件字典")
	return trigger


func validate() -> Array[String]:
	var errors: Array[String] = _errors.duplicate()
	if str(id).strip_edges().is_empty():
		errors.append("触发区域缺少 id")
	if str(event).strip_edges().is_empty():
		errors.append("触发区域缺少 event")
	if not mode in MODES:
		errors.append("触发区域 mode 无效：%s" % mode)
	if not rect.position.is_finite() or not rect.size.is_finite() \
			or rect.size.x <= 0 or rect.size.y <= 0:
		errors.append("触发区域矩形必须有有限坐标和正宽高")
	return errors


func is_active(state: WorldState) -> bool:
	return enabled and validate().is_empty() and state != null \
		and (condition == null or condition.eval(state))


static func _valid_rect(raw: Variant) -> bool:
	if not raw is Array or raw.size() != 4:
		return false
	for value: Variant in raw:
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
	return raw[2] > 0 and raw[3] > 0


static func valid_condition(raw: Variant, depth: int = 0) -> bool:
	if not raw is Dictionary or depth > 32:
		return false
	var branches := 0
	for field: String in ["all", "any", "not", "exists", "var"]:
		if raw.has(field):
			branches += 1
	if branches != 1:
		return false
	for field: String in ["all", "any"]:
		if raw.has(field):
			if not raw[field] is Array:
				return false
			for child: Variant in raw[field]:
				if not valid_condition(child, depth + 1):
					return false
			return true
	if raw.has("not"):
		return valid_condition(raw["not"], depth + 1)
	var key: Variant = raw.get("exists", raw.get("var"))
	if not (key is String or key is StringName) or str(key).strip_edges().is_empty():
		return false
	return raw.has("exists") or (raw.has("value") and raw.get("op", "==") in OPERATORS)
