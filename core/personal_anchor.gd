class_name PersonalAnchor
extends RefCounted

var _captured := false
var _map_id: StringName = &""
var _spawn: StringName = &"default"
var _player_position := Vector2.ZERO
var _facing := Vector2.DOWN
var _inventory: Dictionary = {}
var _personal_flags: Dictionary = {}

const PERSONAL_FLAG_PREFIX := "ch2/personal/"


func is_captured() -> bool:
	return _captured


func capture_once(save_data: SaveData, flags: WorldState) -> bool:
	if _captured or save_data == null or flags == null:
		return false

	_map_id = save_data.map_id
	_spawn = save_data.spawn
	_player_position = save_data.player_position
	_facing = save_data.facing

	_inventory.clear()
	_personal_flags.clear()
	for key: StringName in flags.keys():
		if ItemTable.is_item_flag(key):
			var item_id := ItemTable.id_from_flag(key)
			_inventory[item_id] = ItemTable.count_of(flags, item_id)
		elif str(key).begins_with(PERSONAL_FLAG_PREFIX):
			_personal_flags[key] = flags.get_value(key)

	_captured = true
	return true


func restore(save_data: SaveData, flags: WorldState) -> bool:
	if not _captured or save_data == null or flags == null:
		return false

	save_data.map_id = _map_id
	save_data.spawn = _spawn
	save_data.player_position = _player_position
	save_data.facing = _facing

	for key: StringName in flags.keys():
		if ItemTable.is_item_flag(key) and not _inventory.has(ItemTable.id_from_flag(key)):
			flags.unset_value(key)

	for item_id: Variant in _inventory:
		flags.set_value(ItemTable.flag_key(StringName(item_id)), _inventory[item_id])

	for key: StringName in flags.keys():
		if str(key).begins_with(PERSONAL_FLAG_PREFIX) and not _personal_flags.has(key):
			flags.unset_value(key)
	for key: Variant in _personal_flags:
		flags.set_value(StringName(key), _personal_flags[key])

	return true


func to_dictionary() -> Dictionary:
	var inventory: Dictionary = {}
	for item_id: Variant in _inventory:
		inventory[str(item_id)] = int(_inventory[item_id])
	var personal_flags: Dictionary = {}
	for key: Variant in _personal_flags:
		personal_flags[str(key)] = _personal_flags[key]
	return {
		"captured": _captured,
		"map_id": str(_map_id),
		"spawn": str(_spawn),
		"player_position": [_player_position.x, _player_position.y],
		"facing": [_facing.x, _facing.y],
		"inventory": inventory,
		"personal_flags": personal_flags,
	}


func load_dictionary(raw: Variant) -> bool:
	if not (raw is Dictionary):
		return false
	var data := raw as Dictionary
	if data.get("captured", false) != true:
		return false
	_map_id = StringName(str(data.get("map_id", "")))
	_spawn = StringName(str(data.get("spawn", "default")))
	_player_position = _read_vector(data.get("player_position"), Vector2.ZERO)
	_facing = _read_vector(data.get("facing"), Vector2.DOWN)
	_inventory.clear()
	var raw_inventory: Variant = data.get("inventory", {})
	if raw_inventory is Dictionary:
		for key: Variant in raw_inventory:
			_inventory[StringName(str(key))] = int(raw_inventory[key])
	_personal_flags.clear()
	var raw_personal_flags: Variant = data.get("personal_flags", {})
	if raw_personal_flags is Dictionary:
		for key: Variant in raw_personal_flags:
			_personal_flags[StringName(str(key))] = raw_personal_flags[key]
	_captured = true
	return true


func _read_vector(raw: Variant, fallback: Vector2) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	if raw is Vector2:
		return raw
	return fallback
