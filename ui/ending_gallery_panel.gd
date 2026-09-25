## 结局图鉴：整个游戏有哪些结局、你见过哪几个、各自讲了什么。
##
## 数据来自两个地方，**两件事不要混**：
##   - `EndingTable` —— 这个游戏一共有哪些结局（`data/endings.json`）
##   - `EndingGallery` —— 你一共见过哪几个（跨存档的全局记录）
##
## 所以列表按结局表走，**没见过的也要占一行**（显示「？？？」）。
## 只列见过的话，玩家不知道自己还差几个，也就没有去凑的动力。
##
## 挂 CanvasLayer，不受相机影响。布局用绝对坐标，分辨率固定 320x180。
## 认识 `EndingTable` 和 `EndingGallery`，不认识存档、剧情、地图。
class_name EndingGalleryPanel
extends CanvasLayer

## 一屏最多显示几行。超了跟着光标滚。
const MAX_ROWS := 7
const ROW_HEIGHT := 12.0
const HEADER_HEIGHT := 15.0
const FOOTER_HEIGHT := 12.0

## 底部那个「返回」。**鼠标用得着**：键盘有 ESC，鼠标原先只能选行。
## 位置占提示行右边那一块，不另开一行（面板高度是排好的）。
const BACK_TEXT := "← 返回"
const BACK_WIDTH := 44.0

const PANEL_WIDTH := 220.0
const PANEL_HEIGHT := 128.0
const LIST_WIDTH := 100.0
const DETAIL_WIDTH := 102.0

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.96)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const HEADER_COLOR := Color("#e8c07a")
const ROW_COLOR := Color("#d8d8d8")
const ROW_LOCKED_COLOR := Color("#6a6f74")
const HIGHLIGHT_COLOR := Color(0.22, 0.30, 0.26, 1.0)
const TITLE_COLOR := Color("#e8c07a")
const SUMMARY_COLOR := Color("#c8c8c8")
const HINT_COLOR := Color("#7f858c")

## 没见过的结局在列表上显示成什么
const LOCKED_LABEL := "？？？"
## 没见过的结局在详情里显示什么
const LOCKED_DETAIL := "还没走到这个结局。"

var _root: Control
var _edge: ColorRect
var _panel: ColorRect
var _highlight: ColorRect
var _header: Label
var _footer: Label
## 右下角那个「返回」。可点，用来回主菜单。
var _back: Label
var _detail_title: Label
var _detail_body: Label
var _row_labels: Array[Label] = []

## 当前显示的结局，按表里的顺序
var _ids: Array[StringName] = []
var _table: EndingTable = null
var _gallery: EndingGallery = null
var _cursor := 0
## 列表窗口的第一行。条目多于一屏时跟着光标滚。
var _scroll := 0
var _open := false


func _ready() -> void:
	setup()


## 抽成显式方法，理由同 DialogueBox.setup()：
## `--script` 模式下 add_child 不会触发 `_ready`。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	# 24：最上面。它从标题开（标题 21），而标题自己不收。
	# 理由同 `settings_panel.gd` 里那段。
	layer = 24

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	_edge = _make_rect("Edge", EDGE_COLOR)
	_panel = _make_rect("Panel", BG_COLOR)
	_highlight = _make_rect("Highlight", HIGHLIGHT_COLOR)

	_header = _make_label("Header", 9, HEADER_COLOR)
	_footer = _make_label("Footer", 7, HINT_COLOR)
	_back = _make_label("Back", 7, HINT_COLOR)
	_back.text = BACK_TEXT
	_back.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_detail_title = _make_label("DetailTitle", 9, TITLE_COLOR)
	_detail_body = _make_label("DetailBody", 8, SUMMARY_COLOR)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_root.visible = false


func _make_rect(node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


func _make_label(node_name: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label


# ---------------------------------------------------------------- 开合

func open(table: EndingTable, gallery: EndingGallery) -> void:
	setup()
	_table = table
	_gallery = gallery
	_ids = table.ids() if table != null else []
	_cursor = 0
	_scroll = 0
	_open = true
	_root.visible = true
	_rebuild_rows()
	_layout()
	_update_highlight()
	_update_detail()


func close() -> void:
	if _root != null:
		_root.visible = false
	_open = false


func is_open() -> bool:
	return _open


# ---------------------------------------------------------------- 查询

## 列表上共有几项（包括没见过的）。
func row_count() -> int:
	return _ids.size()


func cursor() -> int:
	return _cursor


## 光标所在的结局 id。测试和调试用。
func current_id() -> StringName:
	if _cursor < 0 or _cursor >= _ids.size():
		return &""
	return _ids[_cursor]


## 光标那一项是不是已经见过。
func current_unlocked() -> bool:
	return _gallery != null and _gallery.has(current_id())


## 某一行在列表上显示的文字。测试用。
func row_text(index: int) -> String:
	if index < 0 or index >= _row_labels.size():
		return ""
	return _row_labels[index].text


## 详情区当前显示的正文。测试用。
func detail_text() -> String:
	return _detail_body.text if _detail_body != null else ""


# ---------------------------------------------------------------- 操作

## 键盘操作。上下移动、ESC 关闭。返回 true 表示这次按键被面板吃掉了。
func handle_key(keycode: int) -> bool:
	if not _open:
		return false

	match keycode:
		KEY_UP, KEY_W:
			_move(-1)
			return true
		KEY_DOWN, KEY_S:
			_move(1)
			return true
		KEY_ESCAPE, KEY_F4:
			close()
			return true
	return false


func select_index(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	_cursor = index
	_scroll = _scroll_for(_cursor)
	_update_highlight()
	_update_detail()


func _move(step: int) -> void:
	if _ids.is_empty():
		return
	var count := _ids.size()
	_cursor = (_cursor + step + count) % count
	_scroll = _scroll_for(_cursor)
	_update_highlight()
	_update_detail()


## 让光标始终落在窗口里。滚的是窗口，不是光标。
func _scroll_for(index: int) -> int:
	if index < _scroll:
		return index
	if index >= _scroll + MAX_ROWS:
		return index - MAX_ROWS + 1
	return _scroll


func _on_gui_input(event: InputEvent) -> void:
	if not _open:
		return

	# 悬停即移光标。**图鉴是浏览**：点一下只是选中、把详情显示出来，
	# 不像按钮那样「点了就执行」，所以这里没有 `_confirm()`。
	if event is InputEventMouseMotion:
		var hover := _row_at((event as InputEventMouseMotion).position)
		if hover >= 0:
			select_index(hover)
		return

	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return

	# 返回按钮先判（和那几行不重叠，先看更清楚）
	if _back_rect().has_point(click.position):
		close()
		return

	var index := _row_at(click.position)
	if index >= 0:
		select_index(index)


## 「返回」按钮的可点区域。贴着面板右下角，和底部那行提示同一行。
func _back_rect() -> Rect2:
	var box := _panel_rect()
	return Rect2(box.end.x - BACK_WIDTH - 8.0, box.end.y - FOOTER_HEIGHT - 2.0,
		BACK_WIDTH, FOOTER_HEIGHT)


## 鼠标落在第几行。**返回的是实际行号**（带上滚动偏移），没落上返回 -1。
func _row_at(point: Vector2) -> int:
	for i: int in _visible_rows():
		if _row_rect(i).has_point(point):
			return _scroll + i
	return -1


# ---------------------------------------------------------------- 内部

func _rebuild_rows() -> void:
	for label: Label in _row_labels:
		label.queue_free()
	_row_labels.clear()

	for id: StringName in _ids:
		var label := _make_label("Row", 8, ROW_COLOR)
		if _gallery != null and _gallery.has(id):
			var def := _table.get_ending(id) if _table != null else null
			label.text = def.display_title() if def != null else str(id)
			label.add_theme_color_override("font_color", ROW_COLOR)
		else:
			label.text = LOCKED_LABEL
			label.add_theme_color_override("font_color", ROW_LOCKED_COLOR)
		_row_labels.append(label)


func _update_detail() -> void:
	var id := current_id()
	if id == &"":
		_detail_title.text = ""
		_detail_body.text = ""
		return

	if _gallery == null or not _gallery.has(id):
		_detail_title.text = LOCKED_LABEL
		_detail_body.text = LOCKED_DETAIL
		return

	var def := _table.get_ending(id) if _table != null else null
	var title := def.display_title() if def != null else str(id)
	var body := def.summary if def != null and def.summary != "" else "（这个结局还没有写简介。）"
	var at := _gallery.first_at(id)
	if at != "":
		body += "\n首次达成 %s" % at

	_detail_title.text = title
	_detail_body.text = body


func _visible_rows() -> int:
	return mini(MAX_ROWS, _row_labels.size() - _scroll)


func _row_rect(slot: int) -> Rect2:
	var origin := _panel_rect().position
	return Rect2(
		origin.x + 8.0,
		origin.y + HEADER_HEIGHT + float(slot) * ROW_HEIGHT,
		LIST_WIDTH,
		ROW_HEIGHT
	)


func _panel_rect() -> Rect2:
	var view := _view_size()
	return Rect2(
		(view.x - PANEL_WIDTH) * 0.5,
		(view.y - PANEL_HEIGHT) * 0.5,
		PANEL_WIDTH,
		PANEL_HEIGHT
	)


func _update_highlight() -> void:
	var slot := _cursor - _scroll
	if slot < 0 or slot >= MAX_ROWS:
		_highlight.visible = false
		return
	var rect := _row_rect(slot)
	_highlight.position = rect.position
	_highlight.size = rect.size
	_highlight.visible = true
	_root.move_child(_highlight, _panel.get_index() + 1)


func _layout() -> void:
	var view := _view_size()
	_root.position = Vector2.ZERO
	_root.size = view

	var box := _panel_rect()
	_edge.position = box.position
	_edge.size = box.size
	_panel.position = box.position + Vector2.ONE
	_panel.size = box.size - Vector2(2.0, 2.0)

	var seen := 0
	for id: StringName in _ids:
		if _gallery != null and _gallery.has(id):
			seen += 1
	_header.text = "结局图鉴 · %d / %d" % [seen, _ids.size()]
	_header.position = box.position + Vector2(8.0, 3.0)
	_header.size = Vector2(PANEL_WIDTH - 16.0, HEADER_HEIGHT)

	_footer.text = "↑↓ 选择"
	_footer.position = box.position + Vector2(8.0, PANEL_HEIGHT - FOOTER_HEIGHT - 2.0)
	_footer.size = Vector2(PANEL_WIDTH - 16.0 - BACK_WIDTH - 4.0, FOOTER_HEIGHT)

	# 返回按钮：贴着右下角，和提示同一行
	_back.position = _back_rect().position
	_back.size = _back_rect().size

	for i: int in _row_labels.size():
		var label := _row_labels[i]
		var slot := i - _scroll
		label.visible = slot >= 0 and slot < MAX_ROWS
		if not label.visible:
			continue
		var rect := _row_rect(slot)
		label.position = rect.position + Vector2(4.0, 0.0)
		label.size = Vector2(LIST_WIDTH - 8.0, ROW_HEIGHT)

	var detail_left := box.position.x + 8.0 + LIST_WIDTH + 6.0
	var detail_top := box.position.y + HEADER_HEIGHT
	_detail_title.position = Vector2(detail_left, detail_top)
	_detail_title.size = Vector2(DETAIL_WIDTH, ROW_HEIGHT)

	_detail_body.position = Vector2(detail_left, detail_top + ROW_HEIGHT + 2.0)
	_detail_body.size = Vector2(DETAIL_WIDTH, PANEL_HEIGHT - HEADER_HEIGHT - ROW_HEIGHT - FOOTER_HEIGHT - 8.0)


func _view_size() -> Vector2:
	# 不查 viewport，理由同 DialogueBox：`--script` 模式下取不准
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
