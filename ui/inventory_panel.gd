## 背包：身上有什么、各有几件。
##
## 跟 `EndingGalleryPanel` 一样是「给玩家看的表」——**东西存在世界状态里**
## （`item/<id>` 键），这里只负责摆出来。所以打开时要外面把
## `ItemTable` 和 `WorldState` 递进来，它自己不去读存档。
##
## 两个入口：按 B 键，或者点右下角那个背包图标。
## 图标是**常驻**的：玩家得先看见有这么个东西，才会想到去按 B。
class_name InventoryPanel
extends CanvasLayer

## 点了右下角那个图标。外面接上「打开背包」——
## 面板不认识游戏状态，不知道该拿哪份物品表。
signal open_requested

const PAD := 10.0
const HEADER_HEIGHT := 18.0
const FOOTER_HEIGHT := 12.0
## 每格多大，以及图标在格子里占多大
const CELL_WIDTH := 44.0
const CELL_HEIGHT := 46.0
const ICON_SIZE := 32.0
## 至少摆两行，只有一件东西的时候面板也别缩成一条
const MIN_ROWS := 2
const COLUMNS := 4

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.96)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const HEADER_COLOR := Color("#e8c07a")
const NAME_COLOR := Color("#d8dce2")
const COUNT_COLOR := Color("#9fb0a4")
const EMPTY_COLOR := Color("#7f858c")
const HINT_COLOR := Color("#7f858c")
## 缺图标时那块占位方块的底色
const SLOT_COLOR := Color(0.14, 0.17, 0.21, 1.0)
const SLOT_EDGE := Color(0.28, 0.34, 0.30, 1.0)

## 右下角那个图标的底
const BUTTON_BG := Color(0.07, 0.10, 0.09, 0.82)
const BUTTON_EDGE := Color(0.40, 0.54, 0.44, 1.0)
const BUTTON_TEXT := Color("#dfe6da")

var _root: Control
var _edge: ColorRect
var _panel: ColorRect
var _header: Label
var _footer: Label
var _empty: Label
var _button: Control
var _button_edge: ColorRect
var _button_bg: ColorRect
var _button_label: Label

## 每一格的图标。重建时整批换掉。
var _slots: Array[Control] = []
var _entries: Array[Dictionary] = []
var _open := false


func _ready() -> void:
	setup()


## 建界面。抽成显式方法，理由同 main.gd 的 boot()：
## `--script` 模式下 add_child 不会触发 `_ready`。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	layer = 19
	_build_panel()
	_build_button()
	_root.visible = false
	# **建完就摆一次。** 以前只在 `_layout()` 里摆，而 `_layout()` 要到
	# 第一次打开才跑 —— 于是那个图标一直待在左上角，直到玩家开过一次背包。
	_layout_button(_view_size())


func _build_panel() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_edge = _rect(_root, "Edge", EDGE_COLOR)
	_panel = _rect(_root, "Panel", BG_COLOR)

	_header = _label(_root, "Header", 9, HEADER_COLOR)
	_footer = _label(_root, "Footer", 7, HINT_COLOR)
	_empty = _label(_root, "Empty", 8, EMPTY_COLOR)


## 右下角那个常驻的背包图标。
##
## 单独挂在**面板之外**（同一个 CanvasLayer，但不是 `_root` 的子节点）：
## 它要在面板关着的时候也看得见，而 `_root` 一关就整块藏了。
func _build_button() -> void:
	_button = Control.new()
	_button.name = "BagButton"
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.gui_input.connect(_on_button_input)
	add_child(_button)

	_button_edge = _rect(_button, "Edge", BUTTON_EDGE)
	_button_bg = _rect(_button, "Panel", BUTTON_BG)
	_button_label = _label(_button, "Icon", 8, BUTTON_TEXT)
	_button_label.text = "背包"


func _rect(parent: Control, node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _label(parent: Control, node_name: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


# ---------------------------------------------------------------- 开合

## 打开背包。`items` 给名字、`flags` 给数量，两个都由外面递进来。
func open(items: ItemTable, flags: WorldState) -> void:
	setup()
	_entries = collect(items, flags)
	_open = true
	_root.visible = true
	_button.visible = false
	_rebuild()
	_layout()


func close() -> void:
	setup()
	_root.visible = false
	_open = false
	_button.visible = true


func is_open() -> bool:
	return _open


## 右下角那个图标现在看得见吗。
func is_button_visible() -> bool:
	return _button != null and _button.visible


## 让图标显隐。过场、菜单开着的时候收起来 ——
## 那时候画面上的东西都该由演出说了算。
func set_button_visible(on: bool) -> void:
	setup()
	_button.visible = on and not _open


func button_rect() -> Rect2:
	setup()
	return Rect2(_button.position, _button.size)


## 点了那个图标。测试与调试用；鼠标走 `_on_button_input`。
func press_button() -> void:
	if not is_button_visible():
		return
	open_requested.emit()


## 键盘操作。返回 true 表示这次按键被吃掉了。
func handle_key(keycode: int) -> bool:
	if not _open:
		return false
	match keycode:
		KEY_B, KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			close()
			return true
	return false


# ---------------------------------------------------------------- 内容

## 身上都有什么。
##
## 只列**有数量的**东西：用掉的（归零）不显示，不然背包里会堆着一串 0。
## 顺序按 id 排，稳定 —— 不然每次打开位置都在跳。
static func collect(items: ItemTable, flags: WorldState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if flags == null:
		return out

	var ids: Array[String] = []
	for key: StringName in flags.keys():
		if ItemTable.is_item_flag(key):
			ids.append(str(ItemTable.id_from_flag(key)))
	# **必须先转 String 再排**：`Array[StringName].sort()` 比的是内部句柄，
	# 不是字面，排出来的顺序跟看见的没关系。图鉴那边踩过同一个坑。
	ids.sort()

	for text: String in ids:
		var id := StringName(text)
		var count := ItemTable.count_of(flags, id)
		if count <= 0:
			continue
		out.append({
			"id": id,
			"name": items.name_of(id) if items != null else text,
			"count": count,
			"icon": icon_path(id),
		})
	return out


## 物品图标。没有就返回空字符串，格子会画成占位方块。
static func icon_path(id: StringName) -> String:
	var path := "res://art/item/%s.png" % id
	return path if ResourceLoader.exists(path) else ""


## 现在列出来的条目。测试与调试用。
func entries() -> Array[Dictionary]:
	return _entries


func entry_count() -> int:
	return _entries.size()


# ---------------------------------------------------------------- 布局

func _rebuild() -> void:
	for slot: Control in _slots:
		slot.queue_free()
	_slots.clear()

	if _entries.is_empty():
		_empty.text = "还没有东西。"
		_empty.visible = true
		return
	_empty.visible = false

	for entry: Dictionary in _entries:
		_slots.append(_make_slot(entry))


func _make_slot(entry: Dictionary) -> Control:
	var cell := Control.new()
	cell.name = "Slot_%s" % entry["id"]
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 裁到格子里。Label 的**最小高度是字体行高**，字号写 7 它也要二十来个像素，
	# 名字那一行会探到下一行的格子上；裁掉就不会串行。
	cell.clip_contents = true
	_root.add_child(cell)

	var path: String = entry["icon"]
	if path != "":
		var icon := TextureRect.new()
		icon.texture = load(path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
	else:
		# 缺图不空着：一块底 + 名字首字，至少看得出「这里有一件东西」
		var plate := _rect(cell, "Plate", SLOT_COLOR)
		plate.name = "Plate"
		var initial := _label(cell, "Initial", 9, SLOT_EDGE)
		initial.name = "Initial"
		initial.text = str(entry["name"]).substr(0, 1)

	var name_label := _label(cell, "Name", 7, NAME_COLOR)
	name_label.name = "Name"
	name_label.text = str(entry["name"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var count_label := _label(cell, "Count", 7, COUNT_COLOR)
	count_label.name = "Count"
	count_label.text = "x%d" % int(entry["count"])
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	return cell


func _rows() -> int:
	return maxi(MIN_ROWS, int(ceil(float(maxi(1, _entries.size())) / float(COLUMNS))))


func _panel_rect() -> Rect2:
	var view := _view_size()
	var width := float(COLUMNS) * CELL_WIDTH + PAD * 2.0
	var height := HEADER_HEIGHT + float(_rows()) * CELL_HEIGHT + FOOTER_HEIGHT + PAD
	return Rect2((view.x - width) * 0.5, (view.y - height) * 0.5, width, height)


func _layout() -> void:
	var view := _view_size()
	_root.position = Vector2.ZERO
	_root.size = view

	var box := _panel_rect()
	_edge.position = box.position
	_edge.size = box.size
	_panel.position = box.position + Vector2.ONE
	_panel.size = box.size - Vector2(2.0, 2.0)

	_header.text = "背包"
	_header.position = box.position + Vector2(PAD, 3.0)
	_header.size = Vector2(box.size.x - PAD * 2.0, HEADER_HEIGHT)

	_footer.text = "B / ESC 关上"
	_footer.position = box.position + Vector2(PAD, box.size.y - FOOTER_HEIGHT - 2.0)
	_footer.size = Vector2(box.size.x - PAD * 2.0, FOOTER_HEIGHT)

	if _empty.visible:
		_empty.position = box.position + Vector2(PAD, HEADER_HEIGHT + CELL_HEIGHT * 0.5)
		_empty.size = Vector2(box.size.x - PAD * 2.0, CELL_HEIGHT)

	# 每格：图标在上、名字在下
	for index: int in _slots.size():
		var cell := _slots[index]
		var column := index % COLUMNS
		var row := index / COLUMNS
		cell.position = box.position + Vector2(
			PAD + float(column) * CELL_WIDTH,
			HEADER_HEIGHT + float(row) * CELL_HEIGHT
		)
		cell.size = Vector2(CELL_WIDTH, CELL_HEIGHT)

		var icon_top := (CELL_HEIGHT - ICON_SIZE - 10.0) * 0.5
		for child: Node in cell.get_children():
			if child is TextureRect:
				(child as TextureRect).position = Vector2((CELL_WIDTH - ICON_SIZE) * 0.5, icon_top)
				(child as TextureRect).size = Vector2(ICON_SIZE, ICON_SIZE)
			elif child is ColorRect:
				(child as ColorRect).position = Vector2((CELL_WIDTH - ICON_SIZE) * 0.5, icon_top)
				(child as ColorRect).size = Vector2(ICON_SIZE, ICON_SIZE)
			elif child is Label:
				var label := child as Label
				if label.name == "Initial":
					label.position = Vector2((CELL_WIDTH - ICON_SIZE) * 0.5, icon_top)
					label.size = Vector2(ICON_SIZE, ICON_SIZE)
					label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				elif label.name == "Name":
					label.position = Vector2(1.0, icon_top + ICON_SIZE + 1.0)
					label.size = Vector2(CELL_WIDTH - 2.0, 9.0)
				elif label.name == "Count":
					label.position = Vector2(1.0, icon_top + ICON_SIZE - 9.0)
					label.size = Vector2(CELL_WIDTH - 4.0, 9.0)

	_layout_button(view)


func _layout_button(view: Vector2) -> void:
	var size := Vector2(30.0, 18.0)
	_button.position = Vector2(view.x - size.x - 6.0, view.y - size.y - 6.0)
	_button.size = size
	_button_edge.position = Vector2.ZERO
	_button_edge.size = size
	_button_bg.position = Vector2.ONE
	_button_bg.size = size - Vector2(2.0, 2.0)
	_button_label.position = Vector2.ZERO
	_button_label.size = size
	_button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _on_button_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		press_button()


func _view_size() -> Vector2:
	# 尺寸取自项目设置的固定分辨率，**不去查 viewport**
	# —— viewport 尺寸在 `--script` 模式下取不准（节点刚进树时是 0）。
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
