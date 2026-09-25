## 存读档菜单：三个槽位摆出来，玩家自己挑一个存、读、或者删。
##
## 之前只有 F5 / F9 固定打在槽位 0 上 —— 存档系统做完了，
## 但玩家看不见有几个槽、不能选、不能删，等于做了用不上。
##
## **它不认识 SaveStore 也不认识 SaveData**：条目由外面组装好递进来，
## 这里只负责摆出来和收下玩家的选择。理由同 `ChoiceMenu` ——
## 认识的东西越少，越不会在某处被当成别的东西用。
##
## 挂 CanvasLayer，不受相机影响。布局用绝对坐标，分辨率固定 320x180。
class_name SaveMenu
extends CanvasLayer

## 打开菜单是为了存还是为了读。存的时候才给删。
enum Mode { SAVE, LOAD }

## 菜单上的一行。
##
## 做成嵌套类而不是顶层类，是因为它**只在存读档菜单里有意义**，
## 但按第七节的教训，两层引用（`SaveMenu.Entry`）是能解析的，三层才不行。
class Entry:
	extends RefCounted

	var slot := 0
	## 空槽显示「（空）」，有内容显示摘要
	var summary := ""
	## 存档时间。空槽为空串。
	var saved_at := ""
	## 这个槽位是不是空的。空的槽位读不出来。
	var empty := true

	static func make(p_slot: int, p_summary: String, p_saved_at: String, p_empty: bool) -> Entry:
		var entry := Entry.new()
		entry.slot = p_slot
		entry.summary = p_summary
		entry.saved_at = p_saved_at
		entry.empty = p_empty
		return entry

	## 列表上显示的文字。空槽也要占一行，并明确说它是空的 ——
	## 不然玩家不知道这个槽能用。
	func line() -> String:
		if empty:
			return "槽位 %d　（空）" % [slot + 1]
		return "槽位 %d　%s" % [slot + 1, summary]


## 选了某个槽位。`mode` 告诉外面这次是存还是读，
## 外面自己决定调 `save_game()` 还是 `load_game()`。
signal chosen(slot: int, mode: int)
## 要删某个槽位。删之前菜单自己已经确认过一次。
signal deleted(slot: int)
signal cancelled

const PANEL_WIDTH := 208.0
const PANEL_HEIGHT := 118.0
const HEADER_HEIGHT := 16.0
const ROW_HEIGHT := 14.0
const DETAIL_HEIGHT := 30.0
const FOOTER_HEIGHT := 12.0

## 底部那个「返回」。**鼠标用得着** —— 键盘有 ESC，鼠标原先只能选行，
## 想出去得去够键盘。位置占提示行右边那一块，不另开一行（面板高度是排好的）。
## 所以下面 HINT 里那句「ESC 取消」也去掉了，位置让给按钮。
const BACK_TEXT := "← 返回"
const BACK_WIDTH := 44.0

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.96)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const HEADER_COLOR := Color("#e8c07a")
const ROW_COLOR := Color("#d8d8d8")
const ROW_EMPTY_COLOR := Color("#6a6f74")
const HIGHLIGHT_COLOR := Color(0.22, 0.30, 0.26, 1.0)
const WARN_COLOR := Color("#d98b7a")
const DETAIL_COLOR := Color("#c8c8c8")
const HINT_COLOR := Color("#7f858c")

## 按了一次删除之后，这一行显示成什么 —— 再按一次才真删。
const CONFIRM_TEXT := "再按一次 X 删除"

var _root: Control
var _edge: ColorRect
var _panel: ColorRect
var _highlight: ColorRect
var _header: Label
var _detail: Label
var _footer: Label
## 右下角那个「返回」。可点，用来回上一层（主菜单或暂停菜单）。
var _back: Label
var _row_labels: Array[Label] = []
var _entries: Array[Entry] = []
var _mode := Mode.SAVE
var _cursor := 0
## 已经按过一次删除、等着再按一次的槽位。-1 表示没在等。
var _pending_delete := -1
var _open := false


func _ready() -> void:
	setup()


## 抽成显式方法，理由同 DialogueBox.setup()：
## `--script` 模式下 add_child 不会触发 `_ready`。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	# 23：比标题（21）和设置（22）高。它既从标题开、也从暂停菜单开，
	# 两种场合都得画在调用者上面。理由同 `settings_panel.gd` 里那段。
	layer = 23

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	_edge = _make_rect("Edge", EDGE_COLOR)
	_panel = _make_rect("Panel", BG_COLOR)
	_highlight = _make_rect("Highlight", HIGHLIGHT_COLOR)

	_header = _make_label("Header", 9, HEADER_COLOR)
	_detail = _make_label("Detail", 8, DETAIL_COLOR)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer = _make_label("Footer", 7, HINT_COLOR)
	_back = _make_label("Back", 7, ROW_COLOR)
	_back.text = BACK_TEXT
	_back.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

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

func open(entries: Array[Entry], mode: int = Mode.SAVE) -> void:
	setup()
	if entries.is_empty():
		return

	_entries = entries
	_mode = mode as Mode
	_cursor = 0
	_pending_delete = -1
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
	_pending_delete = -1


func is_open() -> bool:
	return _open


func mode() -> int:
	return _mode


# ---------------------------------------------------------------- 查询

func entry_count() -> int:
	return _entries.size()


func cursor() -> int:
	return _cursor


## 光标所在那一行的文字。测试用。
func row_text(index: int) -> String:
	if index < 0 or index >= _row_labels.size():
		return ""
	return _row_labels[index].text


func detail_text() -> String:
	return _detail.text if _detail != null else ""


## 是不是在等「再按一次删除」。
func is_confirming_delete() -> bool:
	return _pending_delete >= 0


# ---------------------------------------------------------------- 操作

## 键盘操作。上下移动、回车确认、X 删除、ESC 取消。
## 返回 true 表示这次按键被菜单吃掉了。
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
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm()
			return true
		KEY_X:
			# 删档要按两次。误删一个存档的代价太大，一次确认挡不住手滑。
			if _mode == Mode.SAVE:
				_try_delete()
			return true
		KEY_ESCAPE:
			_close_and_cancel()
			return true
	return false


func select_index(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	_cursor = index
	# 换了行就等于放弃了刚才那次删除确认
	_pending_delete = -1
	_update_highlight()
	_update_detail()


func _move(step: int) -> void:
	if _entries.is_empty():
		return
	var count := _entries.size()
	_cursor = (_cursor + step + count) % count
	_pending_delete = -1
	_update_highlight()
	_update_detail()


func _confirm() -> void:
	if not _open:
		return
	if _cursor < 0 or _cursor >= _entries.size():
		return
	var entry := _entries[_cursor]
	# 空槽不能读 —— 读了也是一句「槽位还是空的」，不如直接不给选
	if _mode == Mode.LOAD and entry.empty:
		return
	_open = false
	_root.visible = false
	chosen.emit(entry.slot, _mode)


func _try_delete() -> void:
	if _cursor < 0 or _cursor >= _entries.size():
		return
	var entry := _entries[_cursor]
	if entry.empty:
		return
	if _pending_delete != entry.slot:
		_pending_delete = entry.slot
		_update_detail()
		return

	var slot := entry.slot
	_pending_delete = -1
	deleted.emit(slot)


func _close_and_cancel() -> void:
	_open = false
	if _root != null:
		_root.visible = false
	cancelled.emit()


func _on_gui_input(event: InputEvent) -> void:
	if not _open:
		return

	# 悬停即移光标（高亮跟着来），点一下就生效。
	# 理由和另外几个列表面板一样，见 `pause_menu.gd` 里那段注释。
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
	if index < 0:
		return
	select_index(index)
	_confirm()


## 「返回」按钮的可点区域。贴着面板右下角，和底部那行提示同一行。
func _back_rect() -> Rect2:
	var box := _panel_rect()
	return Rect2(box.end.x - BACK_WIDTH - 8.0, box.end.y - FOOTER_HEIGHT - 3.0,
		BACK_WIDTH, FOOTER_HEIGHT)


## 鼠标落在第几行。没落上返回 -1。
func _row_at(point: Vector2) -> int:
	for i: int in _entries.size():
		if _row_rect(i).has_point(point):
			return i
	return -1


# ---------------------------------------------------------------- 内部

func _rebuild_rows() -> void:
	for label: Label in _row_labels:
		label.queue_free()
	_row_labels.clear()

	for entry: Entry in _entries:
		var label := _make_label("Row", 8, ROW_COLOR)
		label.text = entry.line()
		label.add_theme_color_override(
			"font_color", ROW_EMPTY_COLOR if entry.empty else ROW_COLOR
		)
		_row_labels.append(label)


func _update_detail() -> void:
	if _cursor < 0 or _cursor >= _entries.size():
		_detail.text = ""
		return

	var entry := _entries[_cursor]
	if _pending_delete == entry.slot:
		_detail.text = CONFIRM_TEXT
		_detail.add_theme_color_override("font_color", WARN_COLOR)
		return

	_detail.add_theme_color_override("font_color", DETAIL_COLOR)
	if entry.empty:
		_detail.text = "这个槽位还是空的。"
		return
	# 显示到分钟就好，秒数是给排查用的，界面上是噪音
	_detail.text = entry.saved_at.substr(0, 16)


func _row_rect(index: int) -> Rect2:
	var origin := _panel_rect().position
	return Rect2(
		origin.x + 8.0,
		origin.y + HEADER_HEIGHT + float(index) * ROW_HEIGHT,
		PANEL_WIDTH - 16.0,
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
	if _cursor < 0 or _cursor >= _entries.size():
		_highlight.visible = false
		return
	var rect := _row_rect(_cursor)
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

	_header.text = "保存到槽位" if _mode == Mode.SAVE else "读取自槽位"
	_header.position = box.position + Vector2(8.0, 3.0)
	_header.size = Vector2(PANEL_WIDTH - 16.0, HEADER_HEIGHT)

	var rows_bottom := HEADER_HEIGHT + float(_entries.size()) * ROW_HEIGHT
	for i: int in _row_labels.size():
		var rect := _row_rect(i)
		var label := _row_labels[i]
		label.position = rect.position + Vector2(4.0, 0.0)
		label.size = Vector2(rect.size.x - 8.0, ROW_HEIGHT)

	_detail.position = box.position + Vector2(8.0, rows_bottom + 4.0)
	_detail.size = Vector2(PANEL_WIDTH - 16.0, DETAIL_HEIGHT)

	_footer.text = "↑↓ 选择　ENTER 确认　X 删除" if _mode == Mode.SAVE \
		else "↑↓ 选择　ENTER 读取"
	_footer.position = box.position + Vector2(8.0, PANEL_HEIGHT - FOOTER_HEIGHT - 3.0)
	# 宽度收到按钮左边为止，免得长提示压到按钮上
	_footer.size = Vector2(PANEL_WIDTH - 16.0 - BACK_WIDTH - 4.0, FOOTER_HEIGHT)

	# 返回按钮：贴着右下角，和提示同一行
	_back.position = _back_rect().position
	_back.size = _back_rect().size


func _view_size() -> Vector2:
	# 不查 viewport，理由同 DialogueBox：`--script` 模式下取不准
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
