## 鼠标悬停时弹的小提示框：地点名 + 详细介绍。
##
## 大地图上地点挨得近，详情常驻会把地图糊住，所以做成悬停才出。
##
## 位置跟着鼠标走，但会**避开屏幕边缘** —— 贴边弹出去一半看不见，比不弹还糟。
##
## 挂 CanvasLayer，不受相机影响。
class_name MapTooltip
extends CanvasLayer

const WIDTH := 150.0
const PAD := 5.0
const TITLE_HEIGHT := 12.0
const BODY_LINE_HEIGHT := 10.0

## 底图：素材包里的「悬浮框_透明度55」。README 说 35% 时白字压在亮画面上
## 读起来吃力，55% 稳一些。
const PANEL_TEXTURE := "res://art/ui/info_panel.png"
## 九宫格的角（源图像素）：外留白 44 + 切角 52 = 96。**四条边只有 6。**
##
## 别把四个方向都写成 96 —— 上下边各 96、加起来 192 远超过面板高度，
## 边框会整个塌成一堆菱形（在 `map_view` 那边就是这么错的）。
const PANEL_CORNER := 96.0
const PANEL_SIDE := 6.0
## 成图比面板本身大一圈（1048x568 对 960x480），四边各留 44。
## 画的时候要往外扩这么多，不然贴图的留白会把内容挤进来。
const PANEL_BLEED := 44.0
## 估算每行能放几个字，用来算框高。中文按字号宽度估就够了，不必精确排版。
const CHARS_PER_LINE := 15.0
## 离鼠标多远弹出来
const CURSOR_OFFSET := Vector2(9.0, 12.0)

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.96)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const TITLE_COLOR := Color("#e8c07a")
const BODY_COLOR := Color("#c8cdd2")

var _root: Control
## 底是素材包里的「悬浮框」。**九宫格拉伸** —— 这个框显示得够大
## （一百多个游戏单位），缩得少，切角和四角菱形都保得住。
var _panel: NinePatchRect
var _title: Label
var _body: Label
var _open := false


func _ready() -> void:
	setup()


## 抽成显式方法，理由同 DialogueBox.setup()。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	layer = 12

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = NinePatchRect.new()
	_panel.name = "Panel"
	if ResourceLoader.exists(PANEL_TEXTURE):
		_panel.texture = load(PANEL_TEXTURE)
		# 边距是**源图像素**：四角 96（= 外留白 44 + 切角 52），四条边 6。
		# 这两个数是素材包 README 给的，别自己猜。
		_panel.patch_margin_left = int(PANEL_CORNER)
		_panel.patch_margin_right = int(PANEL_CORNER)
		_panel.patch_margin_top = int(PANEL_SIDE)
		_panel.patch_margin_bottom = int(PANEL_SIDE)
		_panel.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		_panel.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	_root.add_child(_panel)

	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_size_override("font_size", 9)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_root.add_child(_title)

	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 8)
	_body.add_theme_color_override("font_color", BODY_COLOR)
	_root.add_child(_body)

	_root.visible = false


func _make_rect(node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


## 弹出提示。文字都为空时自动收起。
##
## `anchor` 是弹出的参考点（一般是鼠标所在的世界坐标）。留空则去问真实鼠标位置，
## 但那条路在 `--script` 模式下取不准，所以调用方最好直接传进来。
func show_text(title: String, detail: String, anchor: Variant = null) -> void:
	setup()
	if title == "" and detail == "":
		hide_tip()
		return

	_title.text = title
	_title.visible = title != ""
	_body.text = detail
	_body.visible = detail != ""

	var body_lines := 0
	if detail != "":
		body_lines = maxi(1, ceili(float(detail.length()) / CHARS_PER_LINE))
	var body_height := float(body_lines) * BODY_LINE_HEIGHT
	var height := PAD * 2.0 + (TITLE_HEIGHT if title != "" else 0.0) + body_height

	_place(height, body_height, anchor)
	_root.visible = true
	_open = true


func hide_tip() -> void:
	if _root != null:
		_root.visible = false
	_open = false


func is_open() -> bool:
	return _open


## 给测试看的：当前显示的文字。
func current_title() -> String:
	return _title.text if _title != null else ""


func current_detail() -> String:
	return _body.text if _body != null else ""


func _view_size() -> Vector2:
	# 不查 viewport，理由同 DialogueBox：`--script` 模式下取不准
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)


func _place(height: float, body_height: float, anchor: Variant) -> void:
	var view := _view_size()

	var point: Vector2
	if anchor == null:
		var vp := get_viewport()
		point = vp.get_mouse_position() if vp != null else view * 0.5
	else:
		point = anchor

	var max_left := maxf(2.0, view.x - WIDTH - 2.0)
	var max_top := maxf(2.0, view.y - height - 2.0)
	var left := clampf(point.x + CURSOR_OFFSET.x, 2.0, max_left)
	var top := clampf(point.y + CURSOR_OFFSET.y, 2.0, max_top)

	_root.position = Vector2.ZERO
	_root.size = view

	# 底图那圈的留白要往外扩，内容才和原来的位置对得上。
	# 留白是**按面板宽度等比缩**的：素材 960 宽配 44 的留白，
	# 这里面板只有 WIDTH 宽，留白跟着缩。
	var bleed := PANEL_BLEED * WIDTH / 960.0
	_panel.position = Vector2(left - bleed, top - bleed)
	_panel.size = Vector2(WIDTH + bleed * 2.0, height + bleed * 2.0)

	var text_left := left + PAD
	var text_width := WIDTH - PAD * 2.0
	var cursor_y := top + PAD

	if _title.visible:
		_title.position = Vector2(text_left, cursor_y)
		_title.size = Vector2(text_width, TITLE_HEIGHT)
		cursor_y += TITLE_HEIGHT
	if _body.visible:
		_body.position = Vector2(text_left, cursor_y)
		_body.size = Vector2(text_width, body_height)
