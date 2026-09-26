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

enum Kind { WALL, PORTAL, ACTOR, SPAWN }

var map_id: String = ""
var path: String = ""
var data: Dictionary = {}
var dirty: bool = false


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


func load_map(id: String) -> bool:
	map_id = id
	path = "%s/%s.json" % [MAP_DIR, id]
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	data = parsed
	dirty = false
	return true


func map_size() -> Vector2:
	var raw: Variant = data.get("size", [0, 0])
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO


func background_path() -> String:
	return str(data.get("background", ""))


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


func count(kind: int) -> int:
	match kind:
		Kind.WALL:
			return walls().size()
		Kind.PORTAL:
			return portals().size()
		Kind.ACTOR:
			return actors().size()
		_:
			return spawns().size()


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
	var list: Array = portals() if kind == Kind.PORTAL else actors()
	if index < 0 or index >= list.size():
		return Rect2()
	var item: Variant = list[index]
	if item is Dictionary:
		return _to_rect((item as Dictionary).get("rect"))
	return Rect2()


func set_rect(kind: int, index: int, rect: Rect2) -> void:
	if kind == Kind.SPAWN:
		set_spawn_point(index, rect.position + rect.size * 0.5)
		return
	var box := _rect_to_array(rect)
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
			(item as Dictionary)["rect"] = box
	dirty = true


## 新画一个矩形。墙和传送区都往对应列表末尾追加，返回下标。
##
## 传送区会带一个占位的 label —— `check_data` 不查它，但界面里空着不好认。
func add_rect(kind: int, rect: Rect2) -> int:
	var box := _rect_to_array(rect)
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
		list.remove_at(index)
		if kind == Kind.PORTAL:
			data["portals"] = list
		else:
			data["actors"] = list
	dirty = true


## 把布局（`walls` / `portals` / `actors`）**覆盖**到另一份地图数据上。
##
## 用在「白天版 / 夜间版」这种同布置、不同配色的图上：摆一遍，复制过去。
## **尺寸、背景、前景层、音乐、脚步都不动** —— 那些是每张图自己的。
## `with_spawns` 为真才连出生点一起复制（默认不动：出生点是按入口给的）。
##
## 拷的是**深拷贝**：之后改源不会连带改目标。
static func copy_layout(source: Dictionary, target: Dictionary, with_spawns := false) -> void:
	for key in ["walls", "portals", "actors"]:
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
		return "写 %s 失败，错误码 %d" % [target_id, err]
	return ""


func label_of(kind: int, index: int) -> String:
	if kind == Kind.WALL:
		return "墙"
	if kind == Kind.SPAWN:
		var names := spawn_names()
		return names[index] if index >= 0 and index < names.size() else ""
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
	var rect := rect_of(Kind.ACTOR, index)
	var list := actors()
	if index >= 0 and index < list.size():
		var item: Variant = list[index]
		if item is Dictionary and (item as Dictionary).has("cover_y"):
			return float((item as Dictionary)["cover_y"])
	return rect.position.y + rect.size.y


func has_cover_override(index: int) -> bool:
	var list := actors()
	if index < 0 or index >= list.size():
		return false
	var item: Variant = list[index]
	return item is Dictionary and (item as Dictionary).has("cover_y")


func set_actor_cover_y(index: int, y: float) -> void:
	var list := actors()
	if index < 0 or index >= list.size():
		return
	var item: Variant = list[index]
	if item is Dictionary:
		(item as Dictionary)["cover_y"] = int(round(y))
		dirty = true


func clear_actor_cover_y(index: int) -> void:
	var list := actors()
	if index < 0 or index >= list.size():
		return
	var item: Variant = list[index]
	if item is Dictionary and (item as Dictionary).has("cover_y"):
		(item as Dictionary).erase("cover_y")
		dirty = true


# ---------------------------------------------------------------- 保存

## 写回磁盘。`to_path` 留空就写回原来那份。
##
## **不做备份** —— 项目有 git，改坏了 `git checkout -- <文件>` 就回来了。
func save_to(to_path: String = "") -> Error:
	var target := to_path if to_path != "" else path
	if target == "":
		return ERR_UNCONFIGURED
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(stringify(data))
	f.close()
	if target == path:
		dirty = false
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
