## 存档的「组装与反馈」：把当前局面拼成 SaveData 交给 SaveStore，
## 读档时反过来把状态灌回 WorldState，并且每次都给玩家一句提示。
##
## 跟 `SaveStore` 的分工：
##   - `SaveStore` 只管文件（路径、读写、删、列出），不认识游戏里任何东西
##   - 这里认识 `WorldState` 和 `Toast`，但不自己开文件
##
## 从 `main.gd` 拆出来的理由：存档是「有事就做、做完就忘」的一块，
## 跟场景、相机、剧情都没有往来，摆在入口里只会让入口变长。
class_name SaveManager
extends RefCounted

var flags: WorldState = null
var toast: Toast = null
## 结局表。用来把结局 id 翻成标题，写进存档摘要里。
var table: EndingTable = null
## 当前槽位。多槽的切换界面属于表现层，没做之前固定用 0。
var slot := 0


func setup(p_flags: WorldState, p_toast: Toast, p_table: EndingTable = null) -> void:
	flags = p_flags
	toast = p_toast
	table = p_table


## 存一局。槽位不传就用当前槽位。
##
## `snapshot` 由外面收集：场景、出生点、坐标、朝向、剧情进度。
## 这里不认识 MapDef 和 Player，所以让外面把「当前局面」递进来。
func save(snapshot: SaveData, slot_override: int = -1) -> bool:
	var target := slot if slot_override < 0 else slot_override

	snapshot.slot = target
	# **本地时间，不是 UTC** —— 这串将来要在存档列表上给玩家看。
	snapshot.saved_at = Time.get_datetime_string_from_system(false).replace("T", " ")

	# 键转成 String：StringName 做 JSON 的键不好控制，读回来一律是字符串
	var raw := flags.snapshot()
	var plain: Dictionary = {}
	for key: Variant in raw:
		plain[str(key)] = raw[key]
	snapshot.flags = plain
	# 结局列表从 flags 倒出来，跟 flags 一起写，读的时候两边互证
	snapshot.endings = snapshot.ending_ids()

	if not SaveStore.write(target, snapshot):
		_say("保存失败，看日志")
		return false

	_say("已保存到槽位 %d · %s" % [target + 1, snapshot.summary(table)])
	return true


## 读一局。**只负责把状态灌回来**，场景切换是外面的事 ——
## 这里不认识 MapDef，也不该认识。
##
## 返回 null 表示没读成（槽位是空的，或者存档坏了），原因已经打进日志。
func load_state(slot_override: int = -1) -> SaveData:
	var target := slot if slot_override < 0 else slot_override
	var data := SaveStore.read(target)
	if data == null:
		_say("槽位 %d 还是空的" % [target + 1])
		return null

	for problem: String in data.validate():
		push_error("[存档] " + problem)

	# 先清空再灌：load_values 是合并，直接合并的话
	# 存档里没有的变量会残留着读档之前的值。
	flags.clear()
	flags.load_values(data.flags)

	# 存档记的结局和 flags 里的结局进度对一遍，缺哪边补哪边。
	# 两边是同一件事的两面，对不上就说明有一边坏了。
	var restored := data.reconcile_endings(flags)
	if not restored.is_empty():
		push_warning("[存档] 结局进度在 flags 里缺失，已从存档补回 %d 个" % restored.size())

	_say("已读取槽位 %d · %s" % [target + 1, data.summary(table)])
	return data


## 某个槽位上达成了哪些结局。给将来的结局图鉴用 ——
## 「这个存档走到了哪个结局」是要能分开看的。
func endings_in(slot_override: int = -1) -> Array[EndingDef]:
	var target := slot if slot_override < 0 else slot_override
	var data := SaveStore.read(target)
	if data == null:
		return []
	var out: Array[EndingDef] = []
	if table == null:
		return out
	for id: StringName in data.ending_ids():
		var def := table.get_ending(id)
		if def != null:
			out.append(def)
	return out


## 删掉一个槽位。
func delete(slot_override: int = -1) -> bool:
	var target := slot if slot_override < 0 else slot_override
	if not SaveStore.delete(target):
		_say("槽位 %d 本来就是空的" % [target + 1])
		return false
	_say("已删除槽位 %d" % [target + 1])
	return true


func _say(text: String) -> void:
	if toast != null:
		toast.show_text(text)
