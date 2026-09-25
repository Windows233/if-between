## 屏幕一角的一行提示：存档、读档、拿到东西时说一句话，三秒后自己消失。
##
## 单独做出来是因为「按了 F5 之后什么都没发生」最让人心里没底 ——
## 存档这件事在画面上是看不出变化的，必须有反馈。
##
## 「三秒」和「右上角」是稿子②定的：「提示出现在画面右上角，在3秒后渐渐消失」。
##
## 挂 CanvasLayer，不受相机影响。同一时刻只显示一条，
## 后一条直接顶掉前一条（连按两次 F5 不该叠成两行）。
class_name Toast
extends CanvasLayer

## 提示出现在哪儿。
##
## - `CORNER`：右上角。稿子②给所有提示定的位置。
## - `CENTER`：画面中线上方。稿子单独给「此处建议存档」指了这儿。
##
## 为什么要有第二档而不是全挪到右上角：那条提示是要玩家**当下**做决定的
## （该存档了吗），摆在眼前比缩在角落里有效。
enum Place { CORNER, CENTER }

## 显示多久
const LIFE := 3.0
## 淡出用了最后这么久
const FADE := 0.4
## 离屏幕上边和右边的留白
const MARGIN_TOP := 8.0
const MARGIN_X := 6.0
const HEIGHT := 18.0
const PAD_X := 10.0
## `CENTER` 档：条子上边落在「画面中线往上这么多」的位置。
##
## 44 这个数是量出来的 —— 选项框底边贴着对话框上沿（y=107 上下）、
## 上沿在 71 左右，提示摆在 46..64 正好在它上面、也整个落在中线（90）之上。
const CENTER_LIFT := 44.0

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.88)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const TEXT_COLOR := Color("#eaeaea")

var _root: Control
var _edge: ColorRect
var _panel: ColorRect
var _label: Label
var _timer := 0.0
var _open := false
var _place: Place = Place.CORNER


func _ready() -> void:
	setup()


## 建界面。抽成显式方法，理由同 main.gd 的 boot()：
## `--script` 模式下 add_child 不会触发 `_ready`。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	layer = 20

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.visible = false

	_edge = _rect("Edge", EDGE_COLOR)
	_panel = _rect("Panel", BG_COLOR)

	_label = Label.new()
	_label.name = "Text"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# **不开 autowrap。** 它开着的时候 `get_minimum_size()` 会失灵，
	# 宽度算出来太小，文字挤成几行溢出面板。提示条就该是一行。
	_label.add_theme_font_size_override("font_size", 9)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_label)


func _rect(node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


## 显示一条提示。文字为空就当收起。
func show_text(text: String, place: Place = Place.CORNER) -> void:
	setup()
	if text == "":
		hide_now()
		return

	_place = place
	_label.text = text
	_label.modulate = Color.WHITE
	_timer = LIFE
	_open = true
	_root.visible = true
	_layout()


func hide_now() -> void:
	if _root != null:
		_root.visible = false
	_open = false
	_timer = 0.0


func is_open() -> bool:
	return _open


func current_text() -> String:
	return _label.text if _label != null else ""


## 当前那条提示摆在哪儿。测试和调试用。
func place() -> Place:
	return _place


func _process(delta: float) -> void:
	if not _open:
		return
	_timer -= delta
	if _timer <= 0.0:
		hide_now()
		return
	# 最后一段淡出，别到点硬消失
	if _timer < FADE:
		_label.modulate = Color(1, 1, 1, _timer / FADE)


func _layout() -> void:
	var view := _view_size()
	# 宽度按字符数估：中文字宽约等于字号。估宽比量尺寸稳，
	# 字体没加载完的时候 get_minimum_size() 会返回 0。
	var text_width := _label.text.length() * 9.0 + PAD_X * 2.0
	var width := minf(view.x - 40.0, maxf(96.0, text_width))

	var left := view.x - MARGIN_X - width
	var top := MARGIN_TOP
	if _place == Place.CENTER:
		left = (view.x - width) * 0.5
		top = view.y * 0.5 - CENTER_LIFT

	_edge.position = Vector2(left, top)
	_edge.size = Vector2(width, HEIGHT)
	_panel.position = Vector2(left + 1.0, top + 1.0)
	_panel.size = Vector2(width - 2.0, HEIGHT - 2.0)
	_label.position = Vector2(left, top)
	_label.size = Vector2(width, HEIGHT)


func _view_size() -> Vector2:
	# 尺寸取自项目设置的固定分辨率，**不去查 viewport**
	# —— viewport 尺寸在 `--script` 模式下取不准（节点刚进树时是 0）。
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
