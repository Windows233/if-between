## 开新游戏时给主角起昵称的面板。
##
## 标题选「新游戏」后弹出；确认后才真正开局，取消回到标题。
## 名字规则（中文或英文字母、长度上限）只在 `PlayerName` 一处定义，这里只负责显示和输入。
##
## 输入框用 `LineEdit`：它直接接 Godot 的文字输入事件，中文输入法（IME）也走这一条，
## 所以打字不经过 `UiHost.handle_key`。回车/ESC 在输入框上就地处理，
## `handle_key` 只兜底输入框没拿到焦点的情况。
##
## 挂 CanvasLayer，不受相机影响。布局用绝对坐标，视口 320x180。
class_name NameEntryPanel
extends CanvasLayer

## 玩家确认了一个合法昵称（已规整）。
signal confirmed(player_name: String)
## 玩家取消，外面应回到标题。
signal cancelled

const PANEL_SIZE := Vector2(200.0, 96.0)
const INPUT_HEIGHT := 20.0
const BG_COLOR := Color(0.05, 0.06, 0.09, 0.97)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const HEADER_COLOR := Color("#e8c07a")
const HINT_COLOR := Color("#7f858c")
const ERROR_COLOR := Color("#e07a6a")
const BUTTON_COLOR := Color("#ffffff")
const BUTTON_FILL := Color(0.22, 0.30, 0.26, 1.0)
const SHADE_COLOR := Color(0.0, 0.0, 0.0, 0.55)

const TITLE := "为主角起个昵称"
const HINT := "中文或英文，最多 %d 个字" % PlayerName.MAX_LENGTH
const CONFIRM_TEXT := "确定"
const CANCEL_TEXT := "返回"
const BUTTON_SIZE := Vector2(46.0, 14.0)

var _root: Control
var _shade: ColorRect
var _edge: ColorRect
var _panel: ColorRect
var _header: Label
var _input: LineEdit
var _message: Label
var _confirm_fill: ColorRect
var _confirm: Label
var _cancel_fill: ColorRect
var _cancel: Label
var _open := false


func _ready() -> void:
	setup()


## 抽成显式方法，理由同 DialogueBox.setup()。重复调用安全。
func setup() -> void:
	if _root != null:
		return
	# 25：比标题（21）及其子面板（设置 22、存档 23、图鉴 24）都高。
	layer = 25

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	_shade = _make_rect("Shade", SHADE_COLOR)
	_edge = _make_rect("Edge", EDGE_COLOR)
	_panel = _make_rect("Panel", BG_COLOR)
	_header = _make_label("Header", 9, HEADER_COLOR)
	_header.text = TITLE
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_input = LineEdit.new()
	_input.name = "Input"
	_input.max_length = PlayerName.MAX_LENGTH
	_input.placeholder_text = "输入昵称"
	_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input.context_menu_enabled = false
	_input.add_theme_font_size_override("font_size", 9)
	_input.text_submitted.connect(func(_text: String) -> void: submit())
	_input.text_changed.connect(func(_text: String) -> void: _show_hint())
	_input.gui_input.connect(_on_input_gui_input)
	_root.add_child(_input)

	_message = _make_label("Message", 7, HINT_COLOR)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_confirm_fill = _make_rect("ConfirmFill", BUTTON_FILL)
	_confirm = _make_label("Confirm", 8, BUTTON_COLOR)
	_confirm.text = CONFIRM_TEXT
	_confirm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cancel_fill = _make_rect("CancelFill", BUTTON_FILL.darkened(0.35))
	_cancel = _make_label("Cancel", 8, BUTTON_COLOR)
	_cancel.text = CANCEL_TEXT
	_cancel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cancel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_layout()
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

func open(initial: String = "") -> void:
	setup()
	_input.text = initial
	_input.caret_column = initial.length()
	_open = true
	_root.visible = true
	_show_hint()
	if _input.is_inside_tree():
		_input.grab_focus()


func close() -> void:
	_open = false
	if _root != null:
		_root.visible = false
	if _input != null and _input.has_focus():
		_input.release_focus()


func is_open() -> bool:
	return _open


# ---------------------------------------------------------------- 查询（测试用）

func text() -> String:
	return _input.text if _input != null else ""


func set_text(value: String) -> void:
	setup()
	_input.text = value
	_show_hint()


func message() -> String:
	return _message.text if _message != null else ""


func confirm_rect() -> Rect2:
	return Rect2(_confirm_fill.position, _confirm_fill.size)


func cancel_rect() -> Rect2:
	return Rect2(_cancel_fill.position, _cancel_fill.size)


# ---------------------------------------------------------------- 操作

## 试着确认当前输入。不合法时留在面板上并显示原因。
func submit() -> bool:
	if not _open:
		return false
	var problem := PlayerName.problem(_input.text)
	if problem != "":
		_show_error(problem)
		return false
	var clean := PlayerName.normalize(_input.text)
	close()
	confirmed.emit(clean)
	return true


func cancel() -> void:
	if not _open:
		return
	close()
	cancelled.emit()


## 输入框没拿到焦点时的兜底键盘处理。返回 true 表示吃掉了这次按键。
func handle_key(keycode: int) -> bool:
	if not _open:
		return false
	match keycode:
		KEY_ENTER, KEY_KP_ENTER:
			submit()
			return true
		KEY_ESCAPE:
			cancel()
			return true
	if _input != null and _input.is_inside_tree() and not _input.has_focus():
		_input.grab_focus()
	return true


func _on_input_gui_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if InputUtil.keycode_of(key) == KEY_ESCAPE:
		cancel()
		_input.accept_event()


func _on_gui_input(event: InputEvent) -> void:
	if not _open or not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if confirm_rect().has_point(click.position):
		submit()
	elif cancel_rect().has_point(click.position):
		cancel()
	elif _input != null:
		_input.grab_focus()


# ---------------------------------------------------------------- 内部

func _show_hint() -> void:
	if _message == null:
		return
	_message.text = HINT
	_message.add_theme_color_override("font_color", HINT_COLOR)


func _show_error(text_value: String) -> void:
	_message.text = text_value
	_message.add_theme_color_override("font_color", ERROR_COLOR)


func _layout() -> void:
	var view := _view_size()
	_root.position = Vector2.ZERO
	_root.size = view
	_shade.position = Vector2.ZERO
	_shade.size = view

	var origin := ((view - PANEL_SIZE) * 0.5).floor()
	_edge.position = origin - Vector2.ONE
	_edge.size = PANEL_SIZE + Vector2(2.0, 2.0)
	_panel.position = origin
	_panel.size = PANEL_SIZE

	_header.position = origin + Vector2(0.0, 6.0)
	_header.size = Vector2(PANEL_SIZE.x, 12.0)

	# 输入框高度按它自己的最小尺寸来（字号 + 主题边距），免得字顶出框或压到下面的提示。
	var input_height := maxf(INPUT_HEIGHT, _input.get_combined_minimum_size().y)
	_input.position = origin + Vector2(30.0, 22.0)
	_input.size = Vector2(PANEL_SIZE.x - 60.0, input_height)

	_message.position = origin + Vector2(0.0, 22.0 + input_height + 4.0)
	_message.size = Vector2(PANEL_SIZE.x, 10.0)

	var button_y := origin.y + PANEL_SIZE.y - BUTTON_SIZE.y - 8.0
	var center := origin.x + PANEL_SIZE.x * 0.5
	_confirm_fill.position = Vector2(center - BUTTON_SIZE.x - 6.0, button_y)
	_confirm_fill.size = BUTTON_SIZE
	_confirm.position = _confirm_fill.position
	_confirm.size = BUTTON_SIZE
	_cancel_fill.position = Vector2(center + 6.0, button_y)
	_cancel_fill.size = BUTTON_SIZE
	_cancel.position = _cancel_fill.position
	_cancel.size = BUTTON_SIZE


func _view_size() -> Vector2:
	# 不查 viewport，理由同 DialogueBox：`--script` 模式下取不准
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
