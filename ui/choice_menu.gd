## 选项菜单：一列可选的条目，键盘上下选、回车确认，鼠标也能点。
##
## 两个地方都要用它，所以它**不认识剧情也不认识 NPC**，只认一组带 id 的条目，
## 选完发一个信号，由调用方自己解释 id 的含义：
##
##   1. 靠近可互动物件时的动作菜单（交谈 / 查看委托 / 离开）
##   2. 剧情节点的 IF 选项（接受 / 不接受）
##
## 灰掉的条目（`enabled = false`）会显示出来但选不中，
## 剧情里「条件不满足所以这个选项现在不给选」要用到。
##
## 两种摆法，同一套选择和命中逻辑：
##   - `open()` —— 右上角独立的一块面板。角色的动作菜单用它。
##   - `open_above()` —— **浮在对话框上方**、水平居中。剧情的 IF 选项用它
##     （稿子③：「选项框直接出现在对话框上方一点」）。
##
## 「摆进对话框里面」那一版（`open_inside`）2026-09-23 删掉了：面板改成只占
## 屏幕下三分之一之后，里面还站着两个立绘，中间那一列放不下两行选项。
class_name ChoiceMenu
extends CanvasLayer

## 选中一项时发出
signal chosen(id: StringName)
## 按 ESC 取消时发出
signal cancelled

const PANEL_WIDTH := 116.0
const PANEL_MARGIN := 8.0
const PANEL_GAP_TOP := 24.0
const HEADER_HEIGHT := 16.0
const ROW_HEIGHT := 14.0
## 浮在对话框上方时，底边离面板上沿留多少空（稿子③的「一点」）。
const ABOVE_GAP := 5.0

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.94)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const HEADER_COLOR := Color("#e8c07a")
const ROW_COLOR := Color("#d8d8d8")
const ROW_DISABLED_COLOR := Color("#6a6f74")
const HIGHLIGHT_COLOR := Color(0.22, 0.30, 0.26, 1.0)

var _root: Control
var _edge: ColorRect
var _panel: ColorRect
var _highlight: ColorRect
var _header: Label
var _row_labels: Array[Label] = []
var _options: Array[ChoiceOption] = []
var _cursor := 0
var _open := false
## 浮在对话框上方。`_above_bottom` 是对话框面板的上沿。
var _above := false
var _above_bottom := 0.0
## 这一份能不能按 ESC 取消。
##
## 剧情的 IF 选项**不能** —— 那一步必须选一个，关掉它只会留下一个空对话框，
## 选项没了、剧情还卡在原地，玩家除了读档没别的出路（2026-09-23 踩过）。
## 角色的动作菜单（交谈 / 查看 / 离开）能取消，那是「我不想做这件事」。
var _cancellable := true


func _ready() -> void:
	setup()


## 抽成显式方法，理由同 DialogueBox.setup()。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	# 13：在对话框（10）**之上**、暂停菜单（14）**之下**。
	#
	# 「之下」是要紧的：剧情正等着玩家选的时候按 ESC 会开暂停菜单，
	# 两个同时在场上。选项框原来取的 15，画在暂停菜单上面 ——
	# 结果就是「按 ESC 菜单出来了，但被选项框盖住」，看着像没反应。
	layer = 13

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	_edge = _make_rect("Edge", EDGE_COLOR)
	_panel = _make_rect("Panel", BG_COLOR)
	_highlight = _make_rect("Highlight", HIGHLIGHT_COLOR)

	_header = Label.new()
	_header.name = "Header"
	_header.add_theme_font_size_override("font_size", 8)
	_header.add_theme_color_override("font_color", HEADER_COLOR)
	_root.add_child(_header)

	_root.visible = false


func _make_rect(node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


## 打开菜单，**浮在对话框上方**。
##
## `box_top` 由 `DialogueBox.hold_top()` 给。稿子③：「选项框直接出现在
## 对话框上方一点」。整块水平居中、底边贴住面板上沿，自己带面板和外框。
func open_above(options: Array[ChoiceOption], box_top: float, cancellable: bool = false) -> void:
	_above = true
	_above_bottom = box_top
	_cancellable = cancellable
	_open_menu("", options)


## 打开菜单。`prompt` 留空则不显示标题行。屏幕右上角独立的一块面板。
func open(prompt: String, options: Array[ChoiceOption]) -> void:
	_above = false
	_cancellable = true
	_open_menu(prompt, options)


func _open_menu(prompt: String, options: Array[ChoiceOption]) -> void:
	setup()
	if options.is_empty():
		return

	_options = options
	_cursor = _first_selectable()
	_open = true
	_root.visible = true

	_header.text = prompt
	_header.visible = prompt != ""
	_rebuild_rows()
	_layout()
	_update_highlight()


func close() -> void:
	_root.visible = false
	_open = false
	_above = false


func is_open() -> bool:
	return _open


func option_count() -> int:
	return _options.size()


func cursor() -> int:
	return _cursor


## 当前光标所在的选项 id。测试和调试用。
func current_id() -> StringName:
	if _cursor < 0 or _cursor >= _options.size():
		return &""
	return _options[_cursor].id


## 键盘操作。上下移动、回车确认、ESC 取消。
## 返回 true 表示这次按键被菜单吃掉了，外面不用再处理。
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
		KEY_ESCAPE:
			if not _cancellable:
				# **不认这个键**，返回 false 让外面接手（开暂停菜单）。
				# 这里要是把菜单关掉，场上就剩一个空对话框：选项没了、
				# 剧情还停在这一步、点哪儿都没反应 —— 玩家只能读档。
				return false
			_open = false
			_root.visible = false
			cancelled.emit()
			return true
	return false


## 直接选中某一项（鼠标点击与测试都用它）。
func select_index(index: int) -> void:
	if index < 0 or index >= _options.size():
		return
	if not _options[index].enabled:
		return
	_cursor = index
	_update_highlight()


## 按 id 选中某一项。找不到、或者那一项灰着，返回 false。
## 给测试和「记住上次选的哪一项」这类用法。
func select_id(id: StringName) -> bool:
	for index: int in _options.size():
		if _options[index].id == id and _options[index].enabled:
			select_index(index)
			return true
	return false


func confirm() -> void:
	_confirm()


func _confirm() -> void:
	if not _open:
		return
	if _cursor < 0 or _cursor >= _options.size():
		return
	var option := _options[_cursor]
	if not option.enabled:
		return
	_open = false
	_root.visible = false
	chosen.emit(option.id)


## 从当前位置往一个方向找下一个可选项，找不到就不动。
## 全是灰的时候返回 0，让光标停在原地而不是跑飞。
func _move(step: int) -> void:
	if _options.is_empty():
		return
	var count := _options.size()
	var index := _cursor
	for _i: int in count:
		index = (index + step + count) % count
		if _options[index].enabled:
			_cursor = index
			_update_highlight()
			return


func _first_selectable() -> int:
	for i: int in _options.size():
		if _options[i].enabled:
			return i
	return 0


func _rebuild_rows() -> void:
	for label: Label in _row_labels:
		label.queue_free()
	_row_labels.clear()

	for option: ChoiceOption in _options:
		var label := Label.new()
		label.text = option.label
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_color_override(
			"font_color", ROW_COLOR if option.enabled else ROW_DISABLED_COLOR
		)
		_root.add_child(label)
		_row_labels.append(label)


func _view_size() -> Vector2:
	# 不查 viewport，理由同 DialogueBox：`--script` 模式下取不准
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)


func _layout() -> void:
	var view := _view_size()
	_root.position = Vector2.ZERO
	_root.size = view

	var box := panel_rect()
	_edge.position = box.position
	_edge.size = box.size
	_panel.position = box.position + Vector2(1.0, 1.0)
	_panel.size = box.size - Vector2(2.0, 2.0)

	if _header.visible:
		_header.position = Vector2(box.position.x + 6.0, box.position.y + 4.0)
		_header.size = Vector2(PANEL_WIDTH - 12.0, HEADER_HEIGHT)

	var header := HEADER_HEIGHT if _header.visible else 0.0
	var row_top := box.position.y + header + 4.0
	for i: int in _row_labels.size():
		var label := _row_labels[i]
		label.position = Vector2(box.position.x + 8.0, row_top + float(i) * ROW_HEIGHT)
		label.size = Vector2(PANEL_WIDTH - 14.0, ROW_HEIGHT)


func _row_rect(index: int) -> Rect2:
	var box := panel_rect()
	var header := HEADER_HEIGHT if _header.visible else 0.0
	var row_top := box.position.y + header + 4.0
	return Rect2(box.position.x + 2.0, row_top + float(index) * ROW_HEIGHT,
		PANEL_WIDTH - 4.0, ROW_HEIGHT)


## 独立面板占的那块地方。两种摆法：
##
## - **浮在对话框上方**（`_above`，剧情里的 IF 选项走这条）：底边贴着
##   面板上沿往上留一点空，**靠右摆**。
## - 其余（打开菜单、截图工具）贴在屏幕右上角。
##
## 为什么靠右而不是水平居中：对话框上方那块地方正是两个人物站着的位置
## （镜头照着他们），居中的话选项框会把人整个盖住 —— 截图里试过，
## 老人被盖得只剩头顶。靠右摆就都看得见。
func panel_rect() -> Rect2:
	var view := _view_size()
	var header := HEADER_HEIGHT if _header.visible else 0.0
	var height := header + float(_options.size()) * ROW_HEIGHT + 8.0
	var left := view.x - PANEL_MARGIN - PANEL_WIDTH
	if _above:
		return Rect2(left, _above_bottom - ABOVE_GAP - height, PANEL_WIDTH, height)
	return Rect2(left, PANEL_GAP_TOP, PANEL_WIDTH, height)


func _update_highlight() -> void:
	if _cursor < 0 or _cursor >= _options.size():
		_highlight.visible = false
		return
	var rect := _row_rect(_cursor)
	_highlight.position = rect.position
	_highlight.size = rect.size
	_highlight.visible = true
	# 高亮块要压在文字下面
	_root.move_child(_highlight, _panel.get_index() + 1)


func _on_gui_input(event: InputEvent) -> void:
	if not _open:
		return

	# 悬停即移光标（高亮跟着来）。选项框本来就是「点一下就走」，
	# 这里补的是悬停那一下 —— 以前鼠标划过没有任何反应，
	# 看着像这一块根本不接鼠标。
	if event is InputEventMouseMotion:
		var hover := _row_at((event as InputEventMouseMotion).position)
		if hover >= 0 and _options[hover].enabled:
			select_index(hover)
		return

	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return

	var index := _row_at(click.position)
	if index >= 0 and _options[index].enabled:
		_cursor = index
		_update_highlight()
		_confirm()


## 鼠标落在第几行。没落上返回 -1。
func _row_at(point: Vector2) -> int:
	for i: int in _options.size():
		if _row_rect(i).has_point(point):
			return i
	return -1
