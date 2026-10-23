## 地图触发定向回归：解析、进入边缘、持久 once 与主场景剧情入口。
## 仅使用内存地图和已有事件，不写正式地图、剧情或玩家存档。
## 可独立运行，也可由游戏测试入口调用 run(harness)。
extends SceneTree

const Trigger := preload("res://core/map_trigger.gd")
const Runner := preload("res://scenes/map_trigger_runner.gd")


class EventSink extends RefCounted:
	var events: Array[StringName] = []
	var accept := true
	var available := true

	func exists(_event_id: StringName) -> bool:
		return available

	func start(event_id: StringName) -> bool:
		if not accept:
			return false
		events.append(event_id)
		return true


func _initialize() -> void:
	call_deferred("_standalone")


func _standalone() -> void:
	var harness := TestHarness.new()
	harness.setup(root)
	await run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("地图触发区域与事件绑定")
	_test_definition(h)
	_test_entry_edges(h)
	_test_busy_and_conditions(h)
	_test_once_and_restore(h)
	_test_explicit_modes(h)
	_test_invalid_bindings(h)
	await _test_main_story_entry(h)


static func _definition(mode: String = "enter", once: bool = false) -> Dictionary:
	return {"id": "region", "rect": [10, 20, 30, 40], "event": "ch2_library_locked",
		"mode": mode, "enabled": true, "once": once}


static func _runner(sink: EventSink, state: WorldState, definitions: Array,
		map_id: StringName = &"fixture"):
	var runner := Runner.new()
	runner.configure(map_id, definitions, state, sink.exists, sink.start)
	return runner


static func _test_definition(h: TestHarness) -> void:
	var trigger := Trigger.from_dictionary(_definition())
	h.check("触发定义有效", trigger.validate(), [])
	h.check("矩形解析", trigger.rect, Rect2(10, 20, 30, 40))
	h.check("默认启用", Trigger.from_dictionary({"id": "x", "rect": [0, 0, 1, 1],
		"event": "event"}).enabled, true)
	for changes: Dictionary in [{"id": ""}, {"event": ""}, {"mode": "unknown"},
		{"rect": [1, 2, 0, 4]}, {"rect": [1, "2", 3, 4]}, {"enabled": "false"},
		{"once": 1}, {"condition": {}}, {"condition": {"all": [false]}},
		{"condition": {"not": {"var": "flag", "op": "oops", "value": true}}}]:
		var invalid := _definition()
		invalid.merge(changes, true)
		h.check("拒绝畸形字段 %s" % changes, Trigger.from_dictionary(invalid).validate().is_empty(), false)
	h.check("非字典拒绝", Trigger.from_dictionary(null).validate().is_empty(), false)
	var map := MapDef.from_dictionary({"id": "fixture", "size": [100, 100],
		"triggers": [_definition()]})
	h.check("MapDef 解析触发数组", map.triggers.size(), 1)
	h.check("MapDef 保留事件绑定", map.triggers[0].event, &"ch2_library_locked")
	var duplicated := _definition()
	map = MapDef.from_dictionary({"id": "fixture", "size": [100, 100],
		"triggers": [duplicated, duplicated]})
	h.check("MapDef 拒绝重复触发 id", map.validate().is_empty(), false)


static func _test_entry_edges(h: TestHarness) -> void:
	var state := WorldState.new()
	var sink := EventSink.new()
	var runner = _runner(sink, state, [_definition()])
	h.check("区域外不触发", runner.update(Vector2.ZERO), false)
	h.check("首次进入触发", runner.update(Vector2(11, 21)), true)
	h.check("留在区域内不重复", runner.update(Vector2(12, 22)), false)
	runner.update(Vector2.ZERO)
	h.check("离开后再进入触发", runner.update(Vector2(11, 21)), true)
	h.check("进入次数", sink.events.size(), 2)
	var entrance := _definition("enter_map")
	runner.configure(&"fixture", [entrance], state, sink.exists, sink.start)
	h.check("进入地图不要求站在矩形内", runner.update(Vector2.ZERO), true)
	h.check("同次切图只进入一次", runner.update(Vector2.ZERO), false)
	runner.configure(&"fixture", [entrance], state, sink.exists, sink.start)
	h.check("重进地图重新触发非 once", runner.update(Vector2.ZERO), true)
	var overlap := _definition()
	overlap.id = "second"
	runner.configure(&"fixture", [_definition(), overlap], state, sink.exists, sink.start)
	h.check("重叠区域首个触发", runner.update(Vector2(11, 21)), true)
	h.check("首个剧情后保留另一区域边缘", runner.update(Vector2(11, 21)), true)
	h.check("两处完成后不重触发", runner.update(Vector2(11, 21)), false)


static func _test_busy_and_conditions(h: TestHarness) -> void:
	var state := WorldState.new()
	var sink := EventSink.new()
	var raw := _definition("enter_map", true)
	raw.condition = {"all": [{"var": "key", "value": true}, {"not": {"exists": "locked"}}]}
	var runner = _runner(sink, state, [raw])
	h.check("条件不满足不触发", runner.update(Vector2.ZERO), false)
	state.set_value(&"key", true)
	h.check("忙碌时不触发", runner.update(Vector2.ZERO, true), false)
	h.check("暂停时不触发", runner.update(Vector2.ZERO, false, true), false)
	h.check("忙碌与暂停不写 once", state.has_value(Runner.once_key(&"fixture", &"region")), false)
	h.check("条件满足且解除忙碌后执行待触发", runner.update(Vector2.ZERO), true)
	runner = _runner(sink, WorldState.new(), [_definition()])
	h.check("进入边缘在忙碌时保留", runner.update(Vector2(11, 21), true), false)
	h.check("进入边缘在暂停时保留", runner.update(Vector2(11, 21), false, true), false)
	h.check("解除暂停后真实进入触发", runner.update(Vector2(11, 21)), true)
	sink.accept = false
	runner = _runner(sink, state, [_definition("enter", true)], &"rejected")
	h.check("剧情入口拒绝不视为触发", runner.update(Vector2(11, 21)), false)
	h.check("拒绝不消耗持久 once", state.has_value(Runner.once_key(&"rejected", &"region")), false)
	sink.accept = true
	h.check("入口恢复后不丢边缘", runner.update(Vector2(11, 21)), true)


static func _test_once_and_restore(h: TestHarness) -> void:
	var state := WorldState.new()
	var sink := EventSink.new()
	var raw := _definition("enter_map", true)
	var runner = _runner(sink, state, [raw])
	h.check("once 第一次执行", runner.update(Vector2.ZERO), true)
	h.check("持久 once 写入世界状态", state.get_value(Runner.once_key(&"fixture", &"region")), true)
	runner.configure(&"fixture", [raw], state, sink.exists, sink.start)
	h.check("切回地图 once 保留", runner.update(Vector2.ZERO), false)
	var save := SaveData.new()
	save.flags = state.snapshot()
	var restored := SaveData.from_dictionary(JSON.parse_string(JSON.stringify(save.to_dictionary())))
	var loaded := WorldState.new()
	loaded.load_values(restored.flags)
	runner.configure(&"fixture", [raw], loaded, sink.exists, sink.start)
	h.check("保存 flags 往返恢复 once", runner.update(Vector2.ZERO), false)
	runner.configure(&"another", [raw], loaded, sink.exists, sink.start)
	h.check("地图命名空间隔离", runner.update(Vector2.ZERO), true)
	h.check("带斜杠 id 不撞命名空间", Runner.once_key(&"a/b", &"c") == Runner.once_key(&"a", &"b/c"), false)
	loaded.clear()
	runner.reset()
	runner.configure(&"fixture", [raw], loaded, sink.exists, sink.start)
	h.check("新游戏清 flags 后可再触发", runner.update(Vector2.ZERO), true)


static func _test_explicit_modes(h: TestHarness) -> void:
	var sink := EventSink.new()
	var raw := _definition("interact")
	var runner = _runner(sink, WorldState.new(), [raw])
	h.check("交互模式不自动触发", runner.update(Vector2(11, 21)), false)
	h.check("点击不替代按键模式", runner.click(Vector2(11, 21)), false)
	h.check("交互区外不触发", runner.interact(Vector2.ZERO), false)
	h.check("交互键触发", runner.interact(Vector2(11, 21)), true)
	h.check("忙碌交互被挡", runner.interact(Vector2(11, 21), true), false)
	raw = _definition("click", true)
	raw.rect = [10, 20, 1, 1]
	runner = _runner(sink, WorldState.new(), [raw])
	h.check("点击模式不自动触发", runner.update(Vector2(10, 20)), false)
	h.check("点模式半开边界", runner.click(Vector2(11, 20)), false)
	h.check("暂停点击不消耗", runner.click(Vector2(10, 20), false, true), false)
	h.check("点模式支持 1x1", runner.click(Vector2(10, 20)), true)
	h.check("点击 once 不重复", runner.click(Vector2(10, 20)), false)


static func _test_invalid_bindings(h: TestHarness) -> void:
	var sink := EventSink.new()
	sink.available = false
	var state := WorldState.new()
	var raw := _definition("enter_map", true)
	var runner = _runner(sink, state, [raw])
	h.check("不存在事件不触发", runner.update(Vector2.ZERO), false)
	h.check("不存在事件不消耗 once", state.keys().is_empty(), true)
	sink.available = true
	h.check("事件恢复后仍可触发", runner.update(Vector2.ZERO), true)
	raw.enabled = false
	runner = _runner(sink, WorldState.new(), [raw])
	h.check("禁用区域不触发", runner.update(Vector2.ZERO), false)
	raw.enabled = true
	runner = _runner(sink, WorldState.new(), [raw, raw])
	h.check("重复 id 不执行", runner.update(Vector2.ZERO), false)
	raw.condition = {"all": [true]}
	runner = _runner(sink, WorldState.new(), [raw, null, 3])
	h.check("畸形触发与条件不执行", runner.update(Vector2.ZERO), false)


static func _test_main_story_entry(h: TestHarness) -> void:
	var main = h.new_main()
	main.start_at_title = false
	main.skip_opening = true
	main.set_process(false)
	await h.root.get_tree().process_frame
	main.title_screen.close()
	main.new_game()
	var raw := _definition("enter_map", true)
	main.current_map.triggers = [Trigger.from_dictionary(raw)]
	main.map_triggers.configure(main.current_map.id, main.current_map.triggers, main.flags,
		main._map_trigger_event_exists, main._start_map_trigger)
	h.check("不存在的主线事件被查询拒绝", main._map_trigger_event_exists(&"missing_trigger_event"), false)
	h.check("路径逃逸事件被查询拒绝", main._map_trigger_event_exists(&"../ch2_library_locked"), false)
	main.open_pause_menu()
	main._update_map_triggers()
	h.check("主入口暂停菜单不启动剧情", main.story.is_active(), false)
	main.pause_menu.close()
	h.check("关闭暂停菜单后触发入口空闲", main._map_trigger_busy(), false)
	main._update_map_triggers()
	h.check("主入口启动已绑定真实剧情", main.story.event_id, &"ch2_library_locked")
	h.check("触发进入现有剧情导演", main.story.is_active(), true)
	h.check("主入口记下 seen flag", main.has_seen(&"ch2_library_locked"), true)
	h.check("触发后角色控制关闭", main.player.is_physics_processing(), false)
	var flag := Runner.once_key(main.current_map.id, &"region")
	h.check("主入口写 once", main.flags.get_value(flag), true)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_SPACE
	main._unhandled_input(key)
	h.check("剧情输入不重启触发事件", main.flags.get_value(flag), true)
	var save_slot := 8901
	while SaveStore.exists(save_slot):
		save_slot += 1
	h.check("真实存档写入触发 once", main.save_game(save_slot), true)
	main.story.cancel()
	main.flags.clear()
	h.check("真实读档成功", main.load_game(save_slot), true)
	h.check("真实读档恢复持久 once", main.flags.get_value(flag), true)
	main.story.cancel()
	main.map_triggers.configure(main.current_map.id, [Trigger.from_dictionary(raw)], main.flags,
		main._map_trigger_event_exists, main._start_map_trigger)
	h.check("恢复的 once 阻止再次启动同事件", main.map_triggers.update(main.player.global_position), false)
	h.check("存档测试清理自建槽位", SaveStore.delete(save_slot), true)
	main.new_game()
	h.check("新游戏清理旧触发标记", main.flags.has_value(flag), false)
	main._update_map_triggers()
	h.check("切图清理临时触发定义", main.flags.has_value(flag), false)
	main.queue_free()
