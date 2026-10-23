## 地图触发运行器：记录进入边缘与本次切图尚未执行的触发。
## 调用方提供世界状态、事件查询和剧情入口，忙碌或暂停时不消耗状态。
## once 存入 WorldState，切图仅清本地边缘，新游戏随世界状态清空。
extends RefCounted

const Trigger := preload("res://core/map_trigger.gd")

var _map_id: StringName = &""
var _triggers: Array = []
var _state: WorldState
var _event_exists: Callable
var _start_event: Callable
var _inside: Dictionary = {}
var _pending_enter: Dictionary = {}
var _pending_map: Dictionary = {}
var _dispatching := false


func reset() -> void:
	_map_id = &""
	_triggers = []
	_state = null
	_inside = {}
	_pending_enter = {}
	_pending_map = {}
	_event_exists = Callable()
	_start_event = Callable()


func configure(map_id: StringName, triggers: Array, state: WorldState,
		event_exists: Callable, start_event: Callable) -> void:
	reset()
	_map_id = map_id
	_state = state
	_event_exists = event_exists
	_start_event = start_event
	var counts: Dictionary = {}
	var parsed: Array = []
	for raw: Variant in triggers:
		var trigger = Trigger.from_dictionary(raw) if raw is Dictionary else raw
		if not trigger is Trigger or not trigger.validate().is_empty():
			continue
		parsed.append(trigger)
		counts[trigger.id] = counts.get(trigger.id, 0) + 1
	for trigger in parsed:
		if counts[trigger.id] != 1:
			continue
		_triggers.append(trigger)
		if trigger.mode == &"enter_map":
			_pending_map[trigger.id] = true


static func once_key(map_id: StringName, trigger_id: StringName) -> StringName:
	return StringName("map_trigger/once/" + JSON.stringify([str(map_id), str(trigger_id)]))


func update(position: Vector2, busy: bool = false, paused: bool = false) -> bool:
	if _blocked(busy, paused):
		return false
	for trigger in _triggers:
		if trigger.mode != &"enter":
			continue
		var inside: bool = trigger.rect.has_point(position)
		if inside and not _inside.get(trigger.id, false):
			_pending_enter[trigger.id] = true
		if not inside:
			_pending_enter.erase(trigger.id)
		_inside[trigger.id] = inside
	for trigger in _triggers:
		if (_pending_map.has(trigger.id) or _pending_enter.has(trigger.id)) and _fire(trigger):
			return true
	return false


func interact(position: Vector2, busy: bool = false, paused: bool = false) -> bool:
	return _at(&"interact", position, busy, paused)


func click(position: Vector2, busy: bool = false, paused: bool = false) -> bool:
	return _at(&"click", position, busy, paused)


func _blocked(busy: bool, paused: bool) -> bool:
	return busy or paused or _dispatching or _state == null \
		or not _event_exists.is_valid() or not _start_event.is_valid()


func _at(mode: StringName, position: Vector2, busy: bool, paused: bool) -> bool:
	if _blocked(busy, paused):
		return false
	for trigger in _triggers:
		if trigger.mode == mode and trigger.rect.has_point(position) and _fire(trigger):
			return true
	return false


func _fire(trigger) -> bool:
	var state := _state
	var key := once_key(_map_id, trigger.id)
	if not trigger.is_active(state) or (trigger.once and state.get_value(key, false) == true):
		return false
	if not _event_exists.call(trigger.event):
		return false
	var pending_map := _pending_map
	var pending_enter := _pending_enter
	_dispatching = true
	var had_flag := state.has_value(key)
	var old_flag: Variant = state.get_value(key)
	if trigger.once:
		state.set_value(key, true)
	var accepted: bool = _start_event.call(trigger.event) == true
	_dispatching = false
	if not accepted:
		if trigger.once:
			if had_flag:
				state.set_value(key, old_flag)
			else:
				state.unset_value(key)
		return false
	pending_map.erase(trigger.id)
	pending_enter.erase(trigger.id)
	return true
