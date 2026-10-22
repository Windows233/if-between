## IF 地图编辑器的数据层：读写 `data/maps/*.json`。
##
## **纯逻辑**：不碰编辑器 API、不碰渲染、不引用任何场景 ——
## 所以它能被无头测试直接跑（见 `tests/test_map_editor.gd`）。
## 界面层（`map_edit_canvas.gd` / `map_edit_dock.gd`）只调这里。
##
## 两条规矩：
## 1. **写回要保持能对 diff。** JSON 里 96 不能变成 96.0 ——
##    多人协作下那会让每次保存都变成整片改动。见 `_normalize()`。
## 2. **键序不动。** Godot 的 Dictionary 保插入顺序，解析进来什么样就什么样，
##    只有被动过的条目才换值，别重建整个字典。
extends RefCounted

const MAP_DIR := "res://data/maps"
const BackupStore := preload("res://addons/if_map_editor/map_backup_store.gd")

enum Kind { WALL, PORTAL, ACTOR, SPAWN, OVERLAY }
enum ActorAlignment { LEFT, CENTER_X, RIGHT, TOP, CENTER_Y, BOTTOM }
enum DistributionAxis { HORIZONTAL, VERTICAL }

var map_id: String = ""
var path: String = ""
var data: Dictionary = {}
var dirty: bool = false
var _history: Array[Dictionary] = []
var _history_index := -1
var _saved_text := ""
var _clipboard: Array[Dictionary] = []
var _clipboard_groups: Array[Dictionary] = []
var _paste_serial := 0
var backup_store = BackupStore.new()
var last_backup_name := ""
var last_backup_failed := false
var _background_pixel_path := ""
var _background_pixel_modified := -1
var _background_pixel_size := Vector2.ZERO

## 草稿目录。**切地图时没保存的改动会写到这儿**（`user://`，在仓库外面）——
## 这样「改到一半去看另一张图」不会白干。
##
## 放 `user://` 而不是仓库里：草稿不该跟着 git 走，也不该被 `check_data` 看见。
## 测试可以把它指到别处，免得污染真正的草稿。
var draft_dir := "user://map_editor_drafts"

## 现在这份数据是不是从草稿来的（界面上要提示「这是没保存的草稿」）。
var from_draft := false


static func list_maps() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(MAP_DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".json"):
			out.append(name.trim_suffix(".json"))
	out.sort()
	return out


## 载入一张图。`prefer_draft` 为真（默认）时**优先吃草稿** ——
## 上次改到一半切走了，回来接着改，而不是把改动丢了。
func load_map(id: String, prefer_draft := true) -> bool:
	map_id = id
	path = "%s/%s.json" % [MAP_DIR, id]
	from_draft = false
	if prefer_draft and draft_exists(id):
		var draft_text := FileAccess.get_file_as_string(_draft_path(id))
		var draft_data: Variant = JSON.parse_string(draft_text)
		if draft_data is Dictionary:
			data = draft_data
			dirty = true
			from_draft = true
			reset_history()
			return true
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	data = parsed
	dirty = false
	reset_history()
	return true


func reset_history() -> void:
	_history = [data.duplicate(true)]
	_history_index = 0
	_saved_text = stringify(data)
	if from_draft and FileAccess.file_exists(path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if saved is Dictionary:
			_saved_text = stringify(saved)


func record_history() -> void:
	if _history_index < 0:
		reset_history()
		return
	if stringify(_history[_history_index]) == stringify(data):
		dirty = stringify(data) != _saved_text
		return
	_history.resize(_history_index + 1)
	_history.append(data.duplicate(true))
	if _history.size() > 80:
		_history.pop_front()
	_history_index = _history.size() - 1
	dirty = stringify(data) != _saved_text


func undo() -> bool:
	return _restore_history(_history_index - 1)


func redo() -> bool:
	return _restore_history(_history_index + 1)


func _restore_history(index: int) -> bool:
	if index < 0 or index >= _history.size():
		return false
	_history_index = index
	data = _history[index].duplicate(true)
	dirty = stringify(data) != _saved_text
	return true


func copy_actors(indices: Array[int]) -> void:
	_clipboard.clear()
	_clipboard_groups.clear()
	_paste_serial = 0
	var selected := expand_group_selection(indices)
	var clipboard_offsets: Dictionary = {}
	for index: int in selected:
		var item := actor_dict(index)
		if item.is_empty():
			continue
		clipboard_offsets[str(item.get("id", ""))] = _clipboard.size()
		_clipboard.append(item.duplicate(true))
	for group: Variant in editor_groups():
		if not group is Dictionary:
			continue
		var offsets: Array[int] = []
		var complete := true
		for member: Variant in (group as Dictionary).get("members", []):
			var member_id := str(member)
			if not clipboard_offsets.has(member_id):
				complete = false
				break
			offsets.append(int(clipboard_offsets[member_id]))
		if complete and offsets.size() >= 2:
			_clipboard_groups.append({"name": str(group.get("name", "组")), "offsets": offsets})


func paste_actors() -> Array[int]:
	_paste_serial += 1
	var pasted := insert_actors(_clipboard, Vector2.ONE * 12.0 * _paste_serial)
	for group: Dictionary in _clipboard_groups:
		var members: Array[int] = []
		for offset: int in group.get("offsets", []):
			if offset >= 0 and offset < pasted.size():
				members.append(pasted[offset])
		if members.size() >= 2:
			var copied_name := str(group.get("name", "组")) + " 副本"
			if _paste_serial > 1:
				copied_name += " %d" % _paste_serial
			group_actors(members, copied_name)
	return pasted


func insert_actors(items: Array[Dictionary], offset: Vector2) -> Array[int]:
	var result: Array[int] = []
	var list := actors()
	for source: Dictionary in items:
		var item := source.duplicate(true)
		var stem := str(item.get("id", "object"))
		if stem.is_empty():
			stem = "object"
		var candidate := stem
		var suffix := 2
		while _actor_id_exists(candidate, list):
			candidate = "%s_%d" % [stem, suffix]
			suffix += 1
		item["id"] = candidate
		_shift_actor(item, offset)
		list.append(item)
		result.append(list.size() - 1)
	data["actors"] = list
	if not result.is_empty():
		dirty = true
	return result


func _actor_id_exists(candidate: String, list: Array) -> bool:
	for item: Variant in list:
		if item is Dictionary and str(item.get("id", "")) == candidate:
			return true
	return false


func _shift_actor(item: Dictionary, offset: Vector2) -> void:
	var rect := _to_rect(item.get("rect"))
	var position := rect.position + offset
	item["rect"] = _normalize([position.x, position.y, rect.size.x, rect.size.y])
	if item.has("reach"):
		var reach := _to_rect(item["reach"])
		item["reach"] = _rect_to_array(Rect2(reach.position + offset, reach.size))
	if item.has("cover_y"):
		item["cover_y"] = float(item["cover_y"]) + offset.y


# ---------------------------------------------------------------- 草稿

func _draft_path(id: String) -> String:
	return "%s/%s.json" % [draft_dir, id]


func draft_exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(_draft_path(id))


## 现在这份改动存成草稿（切地图之前叫它）。没改动就什么都不做。
func stash_draft() -> void:
	if not dirty or map_id == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(draft_dir))
	var f := FileAccess.open(_draft_path(map_id), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(stringify(data))
	f.close()


## 草稿的写盘时间（`2026-09-27 12:30:05`），给界面提示用。没有就返回空串。
func draft_time(id: String) -> String:
	if not draft_exists(id):
		return ""
	var stamp := FileAccess.get_modified_time(_draft_path(id))
	return Time.get_datetime_string_from_unix_time(stamp, true)


func draft_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(draft_dir)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".json"):
			out.append(name.trim_suffix(".json"))
	out.sort()
	return out


## 把草稿扔掉（**没保存的改动就此消失**，界面要问一句再叫这个）。
func drop_draft(id := "") -> void:
	var target := id if id != "" else map_id
	if target == "":
		return
	if draft_exists(target):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_draft_path(target)))
	if target == map_id:
		from_draft = false


func map_size() -> Vector2:
	var raw: Variant = data.get("size", [0, 0])
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO


func background_path() -> String:
	return str(data.get("background", ""))


func world_size_for_image(image_size: Vector2) -> Vector2:
	if not is_finite(image_size.x) or not is_finite(image_size.y) \
			or image_size.x <= 0.0 or image_size.y <= 0.0:
		return Vector2.ZERO
	var world_size := map_size()
	if not is_finite(world_size.x) or not is_finite(world_size.y) \
			or world_size.x <= 0.0 or world_size.y <= 0.0:
		return image_size
	var pixels := _background_pixels()
	if pixels.x <= 0.0 or pixels.y <= 0.0:
		return image_size
	return image_size * world_size / pixels


func _background_pixels() -> Vector2:
	var source := background_path()
	if source == "" or not FileAccess.file_exists(source):
		return Vector2.ZERO
	var modified := FileAccess.get_modified_time(source)
	if source == _background_pixel_path and modified == _background_pixel_modified:
		return _background_pixel_size
	var image := Image.load_from_file(source)
	_background_pixel_path = source
	_background_pixel_modified = modified
	_background_pixel_size = Vector2.ZERO
	if image != null and not image.is_empty():
		_background_pixel_size = Vector2(image.get_size())
	return _background_pixel_size


func overlay_path() -> String:
	return str(data.get("overlay", ""))


func spawns() -> Dictionary:
	var raw: Variant = data.get("spawns", {})
	return raw if raw is Dictionary else {}


# ---------------------------------------------------------------- 三个列表

func walls() -> Array:
	var raw: Variant = data.get("walls", [])
	return raw if raw is Array else []


func portals() -> Array:
	var raw: Variant = data.get("portals", [])
	return raw if raw is Array else []


func actors() -> Array:
	var raw: Variant = data.get("actors", [])
	return raw if raw is Array else []


func editor_groups() -> Array:
	var raw: Variant = data.get("editor_groups", [])
	return raw if raw is Array else []


func group_name_for_actor(index: int) -> String:
	var actor_id := str(actor_field(index, "id", ""))
	if actor_id.is_empty():
		return ""
	for group: Variant in editor_groups():
		if group is Dictionary and (group as Dictionary).get("members", []).has(actor_id):
			return str((group as Dictionary).get("name", "组"))
	return ""


func group_members_for_actor(index: int) -> Array[int]:
	var actor_id := str(actor_field(index, "id", ""))
	var result: Array[int] = []
	if actor_id.is_empty():
		return result
	for group: Variant in editor_groups():
		if not group is Dictionary or not (group as Dictionary).get("members", []).has(actor_id):
			continue
		var member_ids: Array = (group as Dictionary).get("members", [])
		for candidate: int in actors().size():
			if member_ids.has(str(actor_field(candidate, "id", ""))):
				result.append(candidate)
		break
	return result


func expand_group_selection(indices: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for index: int in indices:
		if index >= 0 and index < actors().size() and not result.has(index):
			result.append(index)
	var changed := true
	while changed:
		changed = false
		var selected_ids: Dictionary = {}
		for index: int in result:
			var actor_id := str(actor_field(index, "id", ""))
			if not actor_id.is_empty():
				selected_ids[actor_id] = true
		for group: Variant in editor_groups():
			if not group is Dictionary:
				continue
			var members: Array = (group as Dictionary).get("members", [])
			var intersects := false
			for member: Variant in members:
				if selected_ids.has(str(member)):
					intersects = true
					break
			if not intersects:
				continue
			for index: int in actors().size():
				if members.has(str(actor_field(index, "id", ""))) and not result.has(index):
					result.append(index)
					changed = true
	return result


func group_actors(indices: Array[int], requested_name := "") -> String:
	var selected := expand_group_selection(indices)
	if selected.size() < 2:
		return ""
	var member_ids: Array[String] = []
	for index: int in selected:
		var actor_id := str(actor_field(index, "id", ""))
		if actor_id.is_empty() or member_ids.has(actor_id):
			return ""
		var matches := 0
		for candidate: Variant in actors():
			if candidate is Dictionary and str((candidate as Dictionary).get("id", "")) == actor_id:
				matches += 1
		if matches != 1:
			return ""
		member_ids.append(actor_id)
	var groups: Array = []
	for group: Variant in editor_groups():
		if not group is Dictionary:
			continue
		var intersects := false
		for member: Variant in (group as Dictionary).get("members", []):
			if member_ids.has(str(member)):
				intersects = true
				break
		if not intersects:
			groups.append((group as Dictionary).duplicate(true))
	var name := requested_name.strip_edges()
	if name.is_empty():
		name = "组 %d" % (_next_group_number(groups))
	var base_name := name
	var suffix := 2
	while _group_name_exists(groups, name):
		name = "%s %d" % [base_name, suffix]
		suffix += 1
	groups.append({"id": _next_group_id(groups), "name": name, "members": member_ids})
	data["editor_groups"] = groups
	dirty = true
	return name


func rename_group(group_id: String, requested_name: String) -> bool:
	var name := requested_name.strip_edges()
	if group_id.is_empty() or name.is_empty():
		return false
	var groups := editor_groups()
	var target: Dictionary = {}
	var matches := 0
	for group: Variant in groups:
		if group is Dictionary and str((group as Dictionary).get("id", "")) == group_id:
			target = group
			matches += 1
	if matches != 1:
		return false
	if str(target.get("name", "")) == name:
		return true
	if _group_name_exists(groups, name):
		return false
	target["name"] = name
	data["editor_groups"] = groups
	dirty = true
	return true


func ungroup_actors(indices: Array[int]) -> int:
	var selected_ids: Dictionary = {}
	for index: int in indices:
		var actor_id := str(actor_field(index, "id", ""))
		if not actor_id.is_empty():
			selected_ids[actor_id] = true
	var groups: Array = []
	var removed := 0
	for group: Variant in editor_groups():
		if not group is Dictionary:
			continue
		var intersects := false
		for member: Variant in (group as Dictionary).get("members", []):
			if selected_ids.has(str(member)):
				intersects = true
				break
		if intersects:
			removed += 1
		else:
			groups.append((group as Dictionary).duplicate(true))
	if removed > 0:
		if groups.is_empty():
			data.erase("editor_groups")
		else:
			data["editor_groups"] = groups
		dirty = true
	return removed


func _next_group_id(groups: Array) -> String:
	var number := 1
	while true:
		var candidate := "group_%d" % number
		var used := false
		for group: Variant in groups:
			if group is Dictionary and str((group as Dictionary).get("id", "")) == candidate:
				used = true
				break
		if not used:
			return candidate
		number += 1
	return "group"


func _next_group_number(groups: Array) -> int:
	var number := 1
	while _group_name_exists(groups, "组 %d" % number):
		number += 1
	return number


func _group_name_exists(groups: Array, candidate: String) -> bool:
	for group: Variant in groups:
		if group is Dictionary and str((group as Dictionary).get("name", "")) == candidate:
			return true
	return false


func _remove_actor_from_groups(actor_id: String) -> void:
	if actor_id.is_empty():
		return
	var groups: Array = []
	for group: Variant in editor_groups():
		if not group is Dictionary:
			continue
		var updated: Dictionary = (group as Dictionary).duplicate(true)
		var members: Array = updated.get("members", []).duplicate()
		members.erase(actor_id)
		if members.size() >= 2:
			updated["members"] = members
			groups.append(updated)
	if groups.is_empty():
		data.erase("editor_groups")
	else:
		data["editor_groups"] = groups


func count(kind: int) -> int:
	match kind:
		Kind.WALL:
			return walls().size()
		Kind.PORTAL:
			return portals().size()
		Kind.ACTOR:
			return actors().size()
		Kind.SPAWN:
			return spawns().size()
		_:
			return 1 if overlay_path() != "" else 0


# ---------------------------------------------------------------- 出生点
#
# 出生点不是矩形，是一个点（`"start": [x, y]`）。为了复用画布那套
# 「选中 / 拖动」的机制，这里把它**包装成一个 6×6 的小矩形**：
# 读出来是「以点为中心」的小方块，写回去取方块的中心。
# 位置语义始终是那个点，别被这 6 像素迷惑。

const SPAWN_HIT_SIZE := 6.0


func spawn_names() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in spawns():
		out.append(str(key))
	return out


func spawn_point(index: int) -> Vector2:
	var names := spawn_names()
	if index < 0 or index >= names.size():
		return Vector2.ZERO
	var raw: Variant = spawns()[names[index]]
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO


func set_spawn_point(index: int, point: Vector2) -> void:
	var names := spawn_names()
	if index < 0 or index >= names.size():
		return
	spawns()[names[index]] = [int(round(point.x)), int(round(point.y))]
	dirty = true


## 加一个出生点。名字重了就不加（返回 -1）—— 出生点是按名字取的，
## 重名会让传送点指向哪个变得说不清。
func add_spawn(name: String) -> int:
	if name.strip_edges() == "":
		return -1
	var box := spawns()
	if box.has(name):
		return -1
	var center := map_size() * 0.5
	box[name] = [int(round(center.x)), int(round(center.y))]
	data["spawns"] = box
	dirty = true
	return spawn_names().size() - 1


func _remove_spawn(index: int) -> void:
	var names := spawn_names()
	if index < 0 or index >= names.size():
		return
	spawns().erase(names[index])
	dirty = true


## 取第 i 项的矩形。墙是数组 `[x,y,w,h]`，传送区和物件是 `{"rect":[...]}`，
## 出生点是**以点为中心的 6×6 小方块**（见上面的说明）。
func rect_of(kind: int, index: int) -> Rect2:
	if kind == Kind.WALL:
		var list := walls()
		if index < 0 or index >= list.size():
			return Rect2()
		return _to_rect(list[index])
	if kind == Kind.SPAWN:
		var p := spawn_point(index)
		return Rect2(p - Vector2.ONE * (SPAWN_HIT_SIZE * 0.5), Vector2.ONE * SPAWN_HIT_SIZE)
	if kind == Kind.OVERLAY:
		# 前景层是**一整张拉伸到地图大小**的图，数据里只有路径、没有位置。
		# 画布那边会拿它真正有像素的范围来画选框（见 `_overlay_game_rect`），
		# 这里给个整图矩形兜底。
		return Rect2(Vector2.ZERO, map_size())
	var list: Array = portals() if kind == Kind.PORTAL else actors()
	if index < 0 or index >= list.size():
		return Rect2()
	var item: Variant = list[index]
	if item is Dictionary:
		return _to_rect((item as Dictionary).get("rect"))
	return Rect2()


func set_rect(kind: int, index: int, rect: Rect2) -> void:
	if kind == Kind.OVERLAY:
		return          # 前景层没有位置数据（整张拉伸），拖它不改变什么
	if kind == Kind.SPAWN:
		set_spawn_point(index, rect.position + rect.size * 0.5)
		return
	var box := _rect_to_array(rect)
	if kind == Kind.ACTOR:
		box = _normalize([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	if kind == Kind.WALL:
		var list := walls()
		if index < 0 or index >= list.size():
			return
		list[index] = box
	else:
		var list: Array = portals() if kind == Kind.PORTAL else actors()
		if index < 0 or index >= list.size():
			return
		var item: Variant = list[index]
		if item is Dictionary:
			if kind == Kind.ACTOR:
				var old_rect := _to_rect(item.get("rect"))
				_shift_actor(item, rect.position - old_rect.position)
			(item as Dictionary)["rect"] = box
	dirty = true


func align_actors(indices: Array[int], alignment: int) -> bool:
	if alignment < ActorAlignment.LEFT or alignment > ActorAlignment.BOTTOM:
		return false
	var selected := _unique_actor_indices(indices)
	if selected.size() < 2:
		return false
	var bounds := rect_of(Kind.ACTOR, selected[0])
	for index: int in selected.slice(1):
		bounds = bounds.merge(rect_of(Kind.ACTOR, index))
	var targets: Array[Rect2] = []
	for index: int in selected:
		var rect := rect_of(Kind.ACTOR, index)
		var position := rect.position
		match alignment:
			ActorAlignment.LEFT:
				position.x = bounds.position.x
			ActorAlignment.CENTER_X:
				position.x = bounds.get_center().x - rect.size.x * 0.5
			ActorAlignment.RIGHT:
				position.x = bounds.end.x - rect.size.x
			ActorAlignment.TOP:
				position.y = bounds.position.y
			ActorAlignment.CENTER_Y:
				position.y = bounds.get_center().y - rect.size.y * 0.5
			ActorAlignment.BOTTOM:
				position.y = bounds.end.y - rect.size.y
		targets.append(Rect2(position, rect.size))
	return _apply_actor_rects(selected, targets)


func distribute_actors(indices: Array[int], axis: int) -> bool:
	if axis != DistributionAxis.HORIZONTAL and axis != DistributionAxis.VERTICAL:
		return false
	var ordered := _unique_actor_indices(indices)
	if ordered.size() < 3:
		return false
	var horizontal := axis == DistributionAxis.HORIZONTAL
	ordered.sort_custom(func(left: int, right: int) -> bool:
		var left_rect := rect_of(Kind.ACTOR, left)
		var right_rect := rect_of(Kind.ACTOR, right)
		var left_start := left_rect.position.x if horizontal else left_rect.position.y
		var right_start := right_rect.position.x if horizontal else right_rect.position.y
		return left < right if is_equal_approx(left_start, right_start) else left_start < right_start)
	var first := rect_of(Kind.ACTOR, ordered[0])
	var last := rect_of(Kind.ACTOR, ordered[-1])
	var start := first.position.x if horizontal else first.position.y
	var finish := last.end.x if horizontal else last.end.y
	var occupied := 0.0
	for index: int in ordered:
		var rect := rect_of(Kind.ACTOR, index)
		occupied += rect.size.x if horizontal else rect.size.y
	var gap := (finish - start - occupied) / float(ordered.size() - 1)
	var cursor := start
	var targets: Array[Rect2] = []
	for item_index: int in ordered.size():
		var rect := rect_of(Kind.ACTOR, ordered[item_index])
		var dimension := rect.size.x if horizontal else rect.size.y
		var position := rect.position
		if item_index == ordered.size() - 1:
			if horizontal:
				position.x = finish - dimension
			else:
				position.y = finish - dimension
		elif item_index > 0:
			if horizontal:
				position.x = cursor
			else:
				position.y = cursor
		targets.append(Rect2(position, rect.size))
		cursor = (position.x if horizontal else position.y) + dimension + gap
	return _apply_actor_rects(ordered, targets)


func _unique_actor_indices(indices: Array[int]) -> Array[int]:
	var unique: Array[int] = []
	var seen := {}
	for index: int in indices:
		if index < 0 or index >= count(Kind.ACTOR) or seen.has(index):
			continue
		seen[index] = true
		unique.append(index)
	return unique


func _apply_actor_rects(indices: Array[int], targets: Array[Rect2]) -> bool:
	var changed := false
	for item_index: int in indices.size():
		var target := targets[item_index]
		target.position = Vector2(roundi(target.position.x), roundi(target.position.y))
		if target.position != rect_of(Kind.ACTOR, indices[item_index]).position:
			changed = true
	if not changed:
		return false
	for item_index: int in indices.size():
		set_rect(Kind.ACTOR, indices[item_index], targets[item_index])
	return true


## 新画一个矩形。墙和传送区都往对应列表末尾追加，返回下标。
##
## 传送区会带一个占位的 label —— `check_data` 不查它，但界面里空着不好认。
func add_rect(kind: int, rect: Rect2) -> int:
	var box := _rect_to_array(rect)
	if kind == Kind.ACTOR:
		box = _normalize([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	if kind == Kind.WALL:
		var list := walls()
		list.append(box)
		data["walls"] = list
		dirty = true
		return list.size() - 1
	var list: Array = portals() if kind == Kind.PORTAL else actors()
	var item := {"rect": box}
	if kind == Kind.PORTAL:
		item["label"] = "新传送区"
		item["locked"] = true
		item["blocked_text"] = "（还没有连接）"
	list.append(item)
	if kind == Kind.PORTAL:
		data["portals"] = list
	else:
		data["actors"] = list
	dirty = true
	return list.size() - 1


func remove_at(kind: int, index: int) -> void:
	if kind == Kind.OVERLAY:
		clear_overlay()
		return
	if kind == Kind.SPAWN:
		_remove_spawn(index)
		return
	if kind == Kind.WALL:
		var list := walls()
		if index < 0 or index >= list.size():
			return
		list.remove_at(index)
		data["walls"] = list
	else:
		var list: Array = portals() if kind == Kind.PORTAL else actors()
		if index < 0 or index >= list.size():
			return
		var removed_actor_id := ""
		if kind == Kind.ACTOR and list[index] is Dictionary:
			removed_actor_id = str((list[index] as Dictionary).get("id", ""))
		list.remove_at(index)
		if kind == Kind.PORTAL:
			data["portals"] = list
		else:
			data["actors"] = list
			_remove_actor_from_groups(removed_actor_id)
	dirty = true


## 把布局（`walls` / `portals` / `actors`）**覆盖**到另一份地图数据上。
##
## 用在「白天版 / 夜间版」这种同布置、不同配色的图上：摆一遍，复制过去。
## **尺寸、背景、前景层、音乐、脚步都不动** —— 那些是每张图自己的。
## `with_spawns` 为真才连出生点一起复制（默认不动：出生点是按入口给的）。
##
## 拷的是**深拷贝**：之后改源不会连带改目标。
static func copy_layout(source: Dictionary, target: Dictionary, with_spawns := false) -> void:
	for key in ["walls", "portals", "actors", "editor_groups"]:
		if source.has(key):
			target[key] = _normalize(source[key])
		else:
			target.erase(key)
	if with_spawns and source.has("spawns"):
		target["spawns"] = _normalize(source["spawns"])


## 把当前这份布局写到 `target_id` 那张图上（读进来、覆盖、存回去）。
##
## 返回空串表示成功，否则是要显示给人看的一句话。
func copy_layout_to(target_id: String, with_spawns := false) -> String:
	if target_id == "" or target_id == map_id:
		return "目标地图没选对"
	var other = (get_script() as GDScript).new()
	if not other.load_map(target_id):
		return "找不到目标地图 %s" % target_id
	copy_layout(data, other.data, with_spawns)
	other.dirty = true
	var err: Error = other.save_to()
	if err != OK:
		if other.last_backup_failed:
			return "复制已取消：无法为 %s 创建自动备份，目标地图未覆盖" % target_id
		return "写 %s 失败，错误码 %d" % [target_id, err]
	return ""


# ---------------------------------------------------------------- 物件字段
#
# **就地改字段，不重建字典。** 这一条是硬的：对话行支持
# `speaker / text / side / portrait / size_delta / shake` 六个键，
# 编辑器认得的就编，认不得的（以后新加的、或者别人手写的）必须原样留着 ——
# 重建字典会把它们静默抹掉。

func actor_dict(index: int) -> Dictionary:
	var list := actors()
	if index < 0 or index >= list.size():
		return {}
	var item: Variant = list[index]
	return item if item is Dictionary else {}


func actor_field(index: int, key: String, fallback: Variant = "") -> Variant:
	return actor_dict(index).get(key, fallback)


func set_actor_field(index: int, key: String, value: Variant) -> void:
	var d := actor_dict(index)
	if d.is_empty():
		return
	d[key] = value
	dirty = true


func erase_actor_field(index: int, key: String) -> void:
	var d := actor_dict(index)
	if d.is_empty() or not d.has(key):
		return
	d.erase(key)
	dirty = true


## 这件物件的互动用的是哪种写法。**四种互斥**（见 `MapDef._actor_from`）：
## `actions`（多动作菜单）/ `event`（挂一段剧情）/ `talk`（多句对话）/
## `line`（一句旁白）/ `decor`（纯装饰，不交互）。
func actor_form(index: int) -> String:
	var d := actor_dict(index)
	if d.has("actions"):
		return "actions"
	if d.has("event"):
		return "event"
	if d.has("talk"):
		return "talk"
	if d.has("line"):
		return "line"
	if bool(d.get("decor", false)):
		return "decor"
	return "none"


## 这件物件的对话行数组（**是数据里那一份本身**，改它就是改地图数据；
## 改完记得叫 `mark_dirty()`）。不是多句对话就返回空数组。
func actor_talk(index: int) -> Array:
	var raw: Variant = actor_field(index, "talk", [])
	return raw if raw is Array else []


## 新建一件物件，落在**地图正中**、40×40，id 自动避开重名。
## 之后由编辑器把它拖到位置上、再填名字与互动。
func add_actor() -> int:
	var list := actors()
	var used := {}
	for item: Variant in list:
		if item is Dictionary:
			used[str((item as Dictionary).get("id", ""))] = true
	var id := "new_actor"
	var n := 2
	while used.has(id):
		id = "new_actor_%d" % n
		n += 1
	var center := map_size() * 0.5
	list.append({
		"id": id,
		"label": "新物件",
		"rect": [int(round(center.x)) - 20, int(round(center.y)) - 20, 40, 40],
	})
	data["actors"] = list
	dirty = true
	return list.size() - 1


## 把「改过东西」标上（界面上直接改字典时用）。
func mark_dirty() -> void:
	dirty = true


## `art/props/` 下的图，给「贴图」下拉用。返回 res:// 路径。
func prop_files() -> Array[String]:
	return _scan_pngs("res://art/props")


## `art/portrait/` 下的立绘（含子目录，如 `protagonist/reading`）。
## 返回值是**立绘名**（不带 res:// 前缀、不带 .png），和 `portrait` 字段一致。
func portrait_names() -> Array[String]:
	var out: Array[String] = []
	_walk_portraits("res://art/portrait", out)
	out.sort()
	return out


func _walk_portraits(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		if name.ends_with(".png"):
			out.append(dir_path.trim_prefix("res://art/portrait/") + "/" + name.trim_suffix(".png"))
	for sub in dir.get_directories():
		_walk_portraits(dir_path + "/" + sub, out)


func _scan_pngs(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".png"):
			out.append(dir_path + "/" + name)
	out.sort()
	return out


## 剧情文件 id 列表，给「挂事件」下拉用。
func event_ids() -> Array[String]:
	return _scan_ids("res://data/events")


func _scan_ids(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".json"):
			out.append(name.trim_suffix(".json"))
	out.sort()
	return out


## 传送点挂了什么别处的东西 —— 删它之前提醒用（删掉就断了那条路）。
func portal_references(index: int) -> Array[String]:
	var out: Array[String] = []
	var list := portals()
	if index < 0 or index >= list.size():
		return out
	var item: Variant = list[index]
	if not (item is Dictionary):
		return out
	var d := item as Dictionary
	if d.has("to"):
		out.append("它连着地图「%s」（从它走能过去）" % str(d["to"]))
	if d.has("event"):
		out.append("挂着剧情事件「%s」（走上去会演那段）" % str(d["event"]))
	if d.has("action"):
		out.append("动作是「%s」" % str(d["action"]))
	if bool(d.get("locked", false)):
		out.append("它现在是锁着的（摆着但还不通往任何地方）")
	return out


## 这件物件挂了什么「别处的东西」——删它、或者勾「只装饰」之前提醒用。
##
## 查的是**跨文件/跨系统的关联**，不是它自己的字段：
## 挂的剧情事件、动作菜单里挂的事件、出现的条件、演完写什么状态、是不是一次性。
## 返回人话，直接显示给操作的人看。
func actor_references(index: int) -> Array[String]:
	var out: Array[String] = []
	var d := actor_dict(index)
	if d.is_empty():
		return out
	if d.has("event"):
		out.append("挂着剧情事件「%s」（正文在 data/events/%s.json）" % [str(d["event"]), str(d["event"])])
	var actions: Variant = d.get("actions", [])
	if actions is Array:
		for item: Variant in actions:
			if not (item is Dictionary):
				continue
			var act := item as Dictionary
			var label := str(act.get("label", act.get("id", "?")))
			var only_once := bool(act.get("once", false))
			if act.has("event"):
				out.append("动作「%s」挂着剧情事件「%s」%s" % [
					label, str(act["event"]), "（只演一次）" if only_once else ""])
			elif only_once:
				out.append("动作「%s」是只演一次的" % label)
	if d.has("if"):
		out.append("有出现条件（if）—— 条件不满足时玩家根本看不到它")
	var effects: Variant = d.get("set", {})
	if effects is Dictionary and not (effects as Dictionary).is_empty():
		out.append("演完会写状态：%s" % ", ".join((effects as Dictionary).keys()))
	return out


## 这件物件身上有没有「剧情」类的东西（挂事件，或动作菜单里挂事件）。
## 给「勾只装饰」「删物件」这类会切断入口的操作做前置判断。
func actor_has_story(index: int) -> bool:
	var d := actor_dict(index)
	if d.has("event"):
		return true
	var actions: Variant = d.get("actions", [])
	if actions is Array:
		for item: Variant in actions:
			if item is Dictionary and (item as Dictionary).has("event"):
				return true
	return false


## 新建一件物件并指定贴图。`cover` 为真就是「会挡人的遮挡片」——
## 导入一张图做遮罩时走这条：位置和基线之后在画布上调。
func add_actor_with_sprite(sprite_path: String, cover := false) -> int:
	var index := add_actor()
	assign_actor_sprite(index, sprite_path)
	var rect := rect_of(Kind.ACTOR, index)
	rect.position = (map_size() - rect.size) * 0.5
	set_rect(Kind.ACTOR, index, rect)
	if cover:
		set_actor_field(index, "cover", true)
	return index


func assign_actor_sprite(index: int, sprite_path: String) -> bool:
	if index < 0 or index >= count(Kind.ACTOR):
		return false
	if sprite_path == "":
		set_actor_field(index, "sprite", "")
		return true
	if not FileAccess.file_exists(sprite_path):
		return false
	var image := Image.load_from_file(sprite_path)
	if image == null or image.is_empty():
		return false
	var rect := rect_of(Kind.ACTOR, index)
	rect.size = world_size_for_image(Vector2(image.get_size()))
	var actor := actor_dict(index)
	actor["sprite"] = sprite_path
	actor["rect"] = _normalize([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	dirty = true
	return true


func restore_original_size(index: int) -> bool:
	var sprite_path := str(actor_field(index, "sprite", ""))
	return sprite_path != "" and assign_actor_sprite(index, sprite_path)


## 设/清前景层（`overlay`）。**一张图拉伸到整张地图**，所以不用管图的尺寸。
## 习惯命名：`art/map/<地图名>_wall.png`。
func set_overlay_path(path: String) -> void:
	data["overlay"] = path
	dirty = true


func clear_overlay() -> void:
	if data.has("overlay"):
		data.erase("overlay")
		dirty = true


## 把一张外部图片拷进项目的目录，返回它落地的 res:// 路径（失败给空串）。
##
## 名字会被收拾成项目习惯的样子：小写、空格换下划线、去掉路径里那些碍事的符号。
## 重名就往后加 _2、_3，不覆盖别人已经切好的图。
## `target_dir` 可以在测试里指到别处，免得往仓库里写东西；
## `preferred_name`（不含扩展名）用来按项目习惯命名，比如前景层要叫 `<地图名>_wall`。
func import_image(source_path: String, target_dir := "res://art/props",
		preferred_name := "") -> String:
	if not FileAccess.file_exists(source_path):
		return ""
	if not source_path.to_lower().ends_with(".png"):
		return ""
	var base := preferred_name if preferred_name != "" else source_path.get_file().get_basename()
	base = _clean_asset_name(base)
	if base == "":
		return ""
	var dir := DirAccess.open(target_dir)
	if dir == null:
		return ""
	var name := base + ".png"
	var n := 2
	while FileAccess.file_exists(target_dir + "/" + name):
		name = "%s_%d.png" % [base, n]
		n += 1
	var bytes := FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty():
		return ""
	var out := FileAccess.open(target_dir + "/" + name, FileAccess.WRITE)
	if out == null:
		return ""
	out.store_buffer(bytes)
	out.close()
	return target_dir + "/" + name


## 图片名收拾：小写、碍事的符号换成下划线、去掉重复与首尾的下划线，
## 只留字母数字下划线和汉字。`__Editor Odd-Name!.png` → `editor_odd_name.png`。
static func _clean_asset_name(raw: String) -> String:
	var out := ""
	for ch in raw.to_lower():
		var code := ch.unicode_at(0)
		var is_word := (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
		var is_cjk := code >= 0x4E00 and code <= 0x9FFF
		if is_word or is_cjk:
			out += ch
		else:
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")


func label_of(kind: int, index: int) -> String:
	if kind == Kind.WALL:
		return "墙"
	if kind == Kind.SPAWN:
		var names := spawn_names()
		return names[index] if index >= 0 and index < names.size() else ""
	if kind == Kind.OVERLAY:
		return "前景层"
	var list: Array = portals() if kind == Kind.PORTAL else actors()
	if index < 0 or index >= list.size():
		return ""
	var item: Variant = list[index]
	if not (item is Dictionary):
		return ""
	var d := item as Dictionary
	var text := str(d.get("label", ""))
	if text == "":
		text = str(d.get("id", ""))
	return text


# ---------------------------------------------------------------- 遮挡基线

func is_cover_actor(index: int) -> bool:
	var list := actors()
	if index < 0 or index >= list.size():
		return false
	var item: Variant = list[index]
	return item is Dictionary and bool((item as Dictionary).get("cover", false))


## 这件遮挡物的基线。**没写 `cover_y` 就是贴图框的下边界**（自动），
## 写了就用写的那个（手动覆盖）。和 `map_view` 里那条判据保持一致。
func actor_cover_y(index: int) -> float:
	return MapDef._actor_from(actor_dict(index)).effective_cover_y()


func has_cover_override(index: int) -> bool:
	var list := actors()
	if index < 0 or index >= list.size():
		return false
	var item: Variant = list[index]
	return item is Dictionary and (item.has("cover_y") or float(item.get("sort_offset", 0)) != 0.0)


func set_actor_cover_y(index: int, y: float) -> void:
	var list := actors()
	if index < 0 or index >= list.size():
		return
	var item: Variant = list[index]
	if item is Dictionary:
		if item.has("collision"):
			var actor := MapDef._actor_from(item)
			item.erase("cover_y")
			item["sort_offset"] = roundf(y - actor.auto_cover_y())
		else:
			item["cover_y"] = int(round(y))
		dirty = true


func clear_actor_cover_y(index: int) -> void:
	var list := actors()
	if index < 0 or index >= list.size():
		return
	var item: Variant = list[index]
	if item is Dictionary:
		item.erase("cover_y")
		item.erase("sort_offset")
		dirty = true


func use_local_geometry(index: int) -> void:
	var item := actor_dict(index)
	if item.is_empty() or item.has("collision"):
		return
	var actor := MapDef._actor_from(item)
	var shapes: Array = []
	if actor.solid or actor.person:
		for shape: Rect2 in actor.collision_rects():
			shapes.append(_rect_to_array(Rect2(shape.position - actor.rect.position, shape.size)))
	else:
		shapes.append([0, roundf(actor.rect.size.y * 0.65), actor.rect.size.x,
			maxf(1, roundf(actor.rect.size.y * 0.35))])
	item["collision"] = shapes
	item["reach_local"] = _rect_to_array(Rect2(actor.reach.position - actor.rect.position, actor.reach.size))
	item.erase("reach")
	item["sort_collider"] = 0
	item["cover"] = true
	item.erase("over")
	dirty = true


func validation_errors() -> Array[String]:
	var result := MapDef.from_dictionary(data).validate()
	var seen: Dictionary = {}
	for item: Variant in actors():
		var actor_id := str(item.get("id", ""))
		if seen.has(actor_id):
			result.append("物件 id 重复：%s" % actor_id)
		seen[actor_id] = true
	return result


func add_collision_rect(index: int, world_rect: Rect2) -> void:
	var item := actor_dict(index)
	if item.is_empty():
		return
	var actor := MapDef._actor_from(item)
	var shapes: Array = item.get("collision", []).duplicate(true)
	shapes.append(_rect_to_array(Rect2(world_rect.position - actor.rect.position, world_rect.size)))
	item["collision"] = shapes
	if not item.has("reach_local"):
		item["reach_local"] = _rect_to_array(Rect2(actor.reach.position - actor.rect.position, actor.reach.size))
		item.erase("reach")
	item["cover"] = true
	item["sort_collider"] = int(item.get("sort_collider", 0))
	dirty = true


# ---------------------------------------------------------------- 保存

## 写回磁盘。`to_path` 留空就写回原来那份。
func save_to(to_path: String = "") -> Error:
	var target := to_path if to_path != "" else path
	if target == "":
		return ERR_UNCONFIGURED
	last_backup_name = ""
	last_backup_failed = false
	if FileAccess.file_exists(target):
		var target_map_id := target.get_file().get_basename()
		last_backup_name = backup_store.create_snapshot(target_map_id, target)
		if last_backup_name == "":
			last_backup_failed = true
			return ERR_CANT_CREATE
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var serialized := stringify(data)
	f.store_string(serialized)
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		return write_error
	if target == path:
		_saved_text = serialized
		dirty = false
		from_draft = false
		drop_draft(map_id)   # 已经写进仓库了，草稿留着只会下次吃回旧的
	return OK


func restore_backup(name: String) -> Error:
	if map_id == "":
		return ERR_UNCONFIGURED
	var restored := backup_store.read_snapshot(map_id, name)
	if restored.is_empty():
		return ERR_FILE_CORRUPT
	var current_data := data
	data = restored
	var problems := validation_errors()
	data = current_data
	if not problems.is_empty():
		return ERR_INVALID_DATA
	record_history()
	data = restored
	record_history()
	from_draft = false
	return OK


## JSON 文本。**整数写成整数**（96 不是 96.0），两空格缩进 ——
## 和项目里既有文件的格式一致，diff 才干净。
static func stringify(payload: Variant) -> String:
	return JSON.stringify(_normalize(payload), "  ")


## 递归把「整数值的浮点」压成 int。JSON 解析出来全是 float，
## 直接 stringify 会满篇 `96.0`。
static func _normalize(v: Variant) -> Variant:
	if v is float:
		var f := v as float
		if is_finite(f) and absf(f - round(f)) < 0.0000001:
			return int(round(f))
		return f
	if v is Array:
		var out: Array = []
		for item: Variant in v:
			out.append(_normalize(item))
		return out
	if v is Dictionary:
		var out := {}
		for key: Variant in v:
			out[key] = _normalize(v[key])
		return out
	return v


# ---------------------------------------------------------------- 小工具

func _to_rect(raw: Variant) -> Rect2:
	if raw is Array and (raw as Array).size() >= 4:
		return Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	return Rect2()


func _rect_to_array(rect: Rect2) -> Array:
	return [
		int(round(rect.position.x)),
		int(round(rect.position.y)),
		int(round(rect.size.x)),
		int(round(rect.size.y)),
	]
