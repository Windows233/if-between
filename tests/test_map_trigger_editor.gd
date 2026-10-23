## 地图触发编辑 UI 定向回归：控件、内存数据往返与统一撤销历史。
## 只绑定已有事件；不保存正式地图、不写剧情数据。
## 可独立运行，也可由插件测试入口 await run(harness)。
extends SceneTree

const Editor := preload("res://addons/if_map_editor/map_trigger_editor.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


func _initialize() -> void:
	call_deferred("_standalone")


func _standalone() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	await run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("地图触发编辑面板与事件选择")
	var model := Model.new()
	model.data = {"id": "trigger_fixture", "size": [100, 100], "actors": [
		{"id": "actor", "rect": [0, 0, 1, 1], "event": ""}], "opaque": {"preserve": true}}
	model.reset_history()
	var original := model.data.duplicate(true)
	var panel := Editor.new()
	h.root.add_child(panel)
	panel.configure(model)
	var signals := {"selected": -1, "edits": 0, "bounds": -1}
	panel.selection_changed.connect(func(index: int) -> void: signals.selected = index)
	panel.edited.connect(func() -> void: signals.edits += 1)
	panel.bounds_requested.connect(func(index: int) -> void: signals.bounds = index)
	var events := Editor.existing_events()
	h.check("事件选择来自现有目录", events.has("ch2_library_locked"), true)
	panel.find_child("AddTrigger", true, false).pressed.emit()
	h.check("添加按钮新建区域", model.data.triggers.size(), 1)
	h.check("添加发出画布选择信号", signals.selected, 0)
	panel.find_child("UseSelectionBounds", true, false).pressed.emit()
	h.check("取选区矩形发送当前区域索引", signals.bounds, 0)
	h.check("添加进入统一脏标记", model.dirty, true)
	h.check("点区域默认 1x1", model.data.triggers[0].rect, [0, 0, 1, 1])
	h.check("默认绑定现有事件", events.has(model.data.triggers[0].event), true)
	var id := panel.find_child("TriggerId", true, false) as LineEdit
	id.text = "entrance"
	id.text_submitted.emit(id.text)
	h.check("id 编辑写入数据", model.data.triggers[0].id, "entrance")
	var picker := panel.find_child("TriggerEvent", true, false) as OptionButton
	var event_index := _event_index(picker, "ch2_library_locked")
	picker.select(event_index)
	picker.item_selected.emit(event_index)
	h.check("选择现有事件绑定", model.data.triggers[0].event, "ch2_library_locked")
	h.check("任意不存在的事件不能绑定", panel.set_trigger_field(0, "event", "missing_event"), false)
	var mode := panel.find_child("TriggerMode", true, false) as OptionButton
	mode.select(0)
	mode.item_selected.emit(0)
	h.check("模式控件写 enter_map", model.data.triggers[0].mode, "enter_map")
	var width := panel.find_child("TriggerWidth", true, false) as SpinBox
	width.value = 32
	h.check("尺寸控件写回矩形", model.data.triggers[0].rect, [0, 0, 32, 1])
	h.check("画布矩形接口更新", panel.set_trigger_rect(0, Rect2(8, 9, 30, 40)), true)
	h.check("矩形数据读回画布", panel.trigger_rect(0), Rect2(8, 9, 30, 40))
	h.check("负宽拒绝", panel.set_trigger_rect(0, Rect2(0, 0, -1, 1)), false)
	var once := panel.find_child("TriggerOnce", true, false) as CheckBox
	once.button_pressed = true
	h.check("一次标记控件写入", model.data.triggers[0].once, true)
	var enabled := panel.find_child("TriggerEnabled", true, false) as CheckBox
	enabled.button_pressed = false
	h.check("启用开关控件写入", model.data.triggers[0].enabled, false)
	var condition := panel.find_child("TriggerCondition", true, false) as TextEdit
	condition.text = '{"all":[{"var":"gate.open","value":true},{"not":{"exists":"locked"}}]}'
	panel.find_child("ApplyCondition", true, false).pressed.emit()
	h.check("条件参数 UI 写入完整树", model.data.triggers[0].condition,
		{"all": [{"var": "gate.open", "value": true}, {"not": {"exists": "locked"}}]})
	var before_bad := model.data.duplicate(true)
	condition.text = '{"all":[{}]}'
	panel.find_child("ApplyCondition", true, false).pressed.emit()
	h.check("错误条件 UI 不改数据", model.data, before_bad)
	condition.text = ""
	panel.find_child("ApplyCondition", true, false).pressed.emit()
	h.check("空条件删除字段", model.data.triggers[0].has("condition"), false)
	var snapshot := model.data.duplicate(true)
	var second := panel.add_trigger(Rect2(1, 2, 1, 1))
	h.check("第二条 id 不重复", model.data.triggers[0].id != model.data.triggers[1].id, true)
	h.check("重复 id 被拒绝", panel.set_trigger_field(second, "id", "entrance"), false)
	panel.find_child("DeleteTrigger", true, false).pressed.emit()
	h.check("删除 UI 恢复前一条数据", model.data, snapshot)
	h.check("删除可撤销", model.undo(), true)
	panel.refresh()
	h.check("撤销删除恢复列表", (panel.find_child("TriggerList", true, false) as ItemList).item_count, 2)
	h.check("删除可重做", model.redo(), true)
	panel.refresh()
	h.check("重做删除保留前一条", model.data, snapshot)
	var serialized := Model.stringify(model.data)
	var recovered: Dictionary = JSON.parse_string(serialized)
	h.check("触发 JSON 完整往返", Model.stringify(recovered), serialized)
	h.check("未知字段保留", recovered.opaque, original.opaque)
	h.check("触发编辑发送刷新通知", signals.edits > 8, true)
	_test_actor_binding(h, model, signals)
	while model.undo():
		pass
	h.check("统一撤销最终回到原地图", model.data, original)
	h.check("撤销到原始数据清脏", model.dirty, false)
	panel.refresh()
	h.check("无触发时清理选择", panel.selected_index, -1)
	panel.queue_free()
	await h.root.get_tree().process_frame


static func _test_actor_binding(h: TestHarness, model, signals: Dictionary) -> void:
	var picker := Editor.create_actor_event_selector(model, 0,
		func() -> void: signals.edits += 1)
	var index := _event_index(picker, "ch2_library_locked")
	picker.select(index)
	picker.item_selected.emit(index)
	h.check("Actor 绑定只写 event 字段", model.data.actors[0].event, "ch2_library_locked")
	h.check("Actor 绑定进入同份历史", model.undo(), true)
	h.check("Actor 撤销恢复空绑定", model.data.actors[0].event, "")
	h.check("Actor 绑定可重做", model.redo(), true)
	h.check("Actor 重做恢复绑定", model.data.actors[0].event, "ch2_library_locked")
	picker.select(0)
	picker.item_selected.emit(0)
	h.check("取消事件绑定删除event键而非空值遮住对白", model.data.actors[0].has("event"), false)
	model.set_actor_field(0, "decor", true)
	model.record_history()
	picker.free()
	picker = Editor.create_actor_event_selector(model, 0)
	index = _event_index(picker, "ch2_library_locked")
	picker.select(index)
	picker.item_selected.emit(index)
	h.check("装饰物件绑定事件后恢复可交互", model.data.actors[0].decor, false)
	h.check("事件与可交互状态可整步撤销", model.undo(), true)
	h.check("撤销绑定恢复装饰和无事件", [model.data.actors[0].decor, model.data.actors[0].has("event")], [true, false])
	picker.free()
	model.data.actors[0]["actions"] = [{"id": "look", "label": "观察", "event": "ch2_library_locked"}]
	var menu := Editor.create_actor_event_selector(model, 0)
	h.check("多动作物件不提供会被菜单遮住的顶层绑定", menu.disabled, true)
	menu.free()


static func _event_index(picker: OptionButton, event_id: String) -> int:
	for index: int in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == event_id:
			return index
	return -1
