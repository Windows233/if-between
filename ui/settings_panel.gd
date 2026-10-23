## 设置面板：显示模式、窗口尺寸、文字速度。
##
## 从标题界面进。**它自己就改设置并存盘**，改完发一个信号让外面同步
## —— 面板不该认识对话框，认识的是「设置里有个值变了」。
##
## 左右改当前这一行，上下换行。挂 CanvasLayer，不受相机影响。
class_name SettingsPanel
extends CanvasLayer

## 某一项变了。外面据此把新值喂给需要它的地方。
signal changed

const PANEL_WIDTH := 190.0
const HEADER_HEIGHT := 16.0
const ROW_HEIGHT := 16.0
const FOOTER_HEIGHT := 12.0
## 面板上下留白
const PAD_TOP := 4.0
const PAD_BOTTOM := 6.0

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.96)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const HEADER_COLOR := Color("#e8c07a")
const ROW_COLOR := Color("#c8ccd2")
## 光标停的那一行
const ROW_ACTIVE_COLOR := Color("#ffffff")
const VALUE_COLOR := Color("#e8c07a")
const HINT_COLOR := Color("#7f858c")

const TITLE := "设置"
const HINT := "↑↓ 选择　←→ 修改"

## 底部那个「返回」按钮。**鼠标用得着** ——
## 键盘有 ESC，鼠标原先只能在面板里点行、想出去得去够键盘。
##
## 它占的是底部提示行**右边**那一块，不另开一行：面板高度是排好的，
## 多加一行要牵动 `_panel_height()` 和一堆偏移。所以 HINT 里那句
## 「ESC 返回」也去掉了，位置让给按钮本身。
const BACK_TEXT := "← 返回"
const BACK_WIDTH := 44.0

## 面板里都有哪几行，顺序就是显示顺序
const ROWS: Array[StringName] = [&"display", &"size", &"speed", &"music", &"sfx", &"developer"]
const ROW_LABELS: Array[String] = [
	"显示模式", "分辨率", "文字速度", "音乐音量", "音效音量", "开发者选项",
]

## 带**滑条**的那两行。其余几行是按左右换一档的枚举，值是「〈 全屏 〉」那样。
##
## 音量做成滑条而不是文字枚举：它是个连续量，五档文字跳来跳去看不出「现在多大」。
const SLIDER_ROWS: Array[StringName] = [&"music", &"sfx"]
## 滑条槽的宽高，以及槽底 / 已填充两段的颜色
const TRACK_WIDTH := 58.0
const TRACK_HEIGHT := 5.0
const TRACK_BG_COLOR := Color(1, 1, 1, 0.16)
const TRACK_FILL_COLOR := Color("#e8c07a")

var _root: Control
var _edge: ColorRect
var _panel: ColorRect
var _header: Label
var _footer: Label
## 右下角那个「返回」。可点，用来回上一层（主菜单或暂停菜单）。
var _back: Label
var _rows: Array[Label] = []
var _values: Array[Label] = []
## 滑条的两截：键是行名（`&"music"` / `&"sfx"`）。
## 槽底下垫一层，填充盖在它上面，宽度按当前值算。
var _tracks: Dictionary = {}
var _fills: Dictionary = {}
var _settings: GameSettings = null
var _cursor := 0
## 正在被鼠标拖着的那一行。只有音量那两根滑条会用到，-1 表示没在拖。
var _dragging := -1
var _open := false


func _ready() -> void:
	setup()


## 抽成显式方法，理由同 DialogueBox.setup()。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	# 22：**比标题（21）高。**
	#
	# 从标题的「设置」进来时，标题**自己不收**（见 `TitleScreen.STAY_OPEN`），
	# 所以这一层得画在它上面，否则开出来看不见 —— 而键已经在设置手里了。
	# 这是 2026-09-24 那次「主菜单点设置、按 ESC 黑屏」的另一半原因：
	# 当时靠标题收起来腾位置，结果关掉设置就没人把标题开回去了。
	layer = 22

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	_edge = _make_rect("Edge", EDGE_COLOR)
	_panel = _make_rect("Panel", BG_COLOR)
	_header = _make_label("Header", 9, HEADER_COLOR)
	_footer = _make_label("Footer", 7, HINT_COLOR)
	_back = _make_label("Back", 7, ROW_ACTIVE_COLOR)
	_back.text = BACK_TEXT
	_back.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	for index: int in ROWS.size():
		_rows.append(_make_label("Row%d" % index, 8, ROW_COLOR))
		_values.append(_make_label("Value%d" % index, 8, VALUE_COLOR))

	# 滑条的两截。**建在标签之后** —— 同层按加入顺序画，填充得压在槽底上。
	for row: StringName in SLIDER_ROWS:
		_tracks[row] = _make_rect("Track_%s" % row, TRACK_BG_COLOR)
		_fills[row] = _make_rect("Fill_%s" % row, TRACK_FILL_COLOR)

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

func open(p_settings: GameSettings) -> void:
	setup()
	if p_settings == null:
		return
	_settings = p_settings
	_cursor = 0
	_open = true
	_root.visible = true
	_layout()


func close() -> void:
	if _root != null:
		_root.visible = false
	_open = false


func is_open() -> bool:
	return _open


# ---------------------------------------------------------------- 查询

## 光标停在哪一行（给测试和外面看）
func cursor() -> int:
	return _cursor


## 当前行的值文本，形如「〈 全屏 〉」
func value_text() -> String:
	if _cursor < 0 or _cursor >= _values.size():
		return ""
	return _values[_cursor].text


## 某一行的值文本，不含箭头
func row_value(index: int) -> String:
	if index < 0 or index >= _values.size():
		return ""
	return _values[index].text.replace("〈 ", "").replace(" 〉", "")


# ---------------------------------------------------------------- 操作

## 键盘操作。返回 true 表示这次按键被面板吃掉了。
func handle_key(keycode: int) -> bool:
	if not _open:
		return false

	match keycode:
		KEY_UP:
			_cursor = posmod(_cursor - 1, ROWS.size())
			_layout()
			return true
		KEY_DOWN:
			_cursor = posmod(_cursor + 1, ROWS.size())
			_layout()
			return true
		KEY_LEFT:
			_cycle_current(-1)
			return true
		KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_cycle_current(1)
			return true
		KEY_ESCAPE:
			close()
			return true
	return false


## 改当前这一行的值。
##
## `direction` 只对音量那两根滑条有意义（往左调小、往右调大）；
## 枚举那几行是「一档一档绕着转」，左右都一样。
func _cycle_current(direction: int = 1) -> void:
	if _settings == null:
		return
	match ROWS[_cursor]:
		&"display":
			var mode := _settings.cycle_display()
			WindowMode.apply(mode, _settings.window_size)
		&"size":
			# 全屏下调尺寸没意义 —— 先把人切回窗口，再改。意图很明白。
			if _settings.display == "fullscreen":
				_settings.display = "window"
				_settings.save_settings()
			var size := _settings.cycle_window_size()
			WindowMode.apply(_settings.display, size)
		&"speed":
			_settings.cycle_speed()
		&"music":
			_settings.adjust_music(direction)
		&"sfx":
			_settings.adjust_sfx(direction)
		&"developer":
			_settings.toggle_developer_options()
	_layout()
	changed.emit()


# ---------------------------------------------------------------- 布局

func _panel_height() -> float:
	return HEADER_HEIGHT + ROW_HEIGHT * float(ROWS.size()) + FOOTER_HEIGHT \
		+ PAD_TOP + PAD_BOTTOM


func _panel_rect() -> Rect2:
	var view := _view_size()
	var height := _panel_height()
	return Rect2((view.x - PANEL_WIDTH) * 0.5, (view.y - height) * 0.5,
		PANEL_WIDTH, height)


## 第 `index` 行的**整行**可点区域。
##
## 横向铺满面板，不只是文字那一段 —— 鼠标点这一行哪儿都算，不用去瞄那行字。
## `_layout()` 也用它摆标签，省得两处各算一遍位置（算两遍迟早会走样）。
func _row_rect(index: int) -> Rect2:
	var box := _panel_rect()
	return Rect2(box.position.x + 8.0,
		box.position.y + HEADER_HEIGHT + PAD_TOP + float(index) * ROW_HEIGHT,
		PANEL_WIDTH - 16.0, ROW_HEIGHT)


## 「返回」按钮的可点区域。贴着面板右下角，和底部那行提示同一行。
func _back_rect() -> Rect2:
	var box := _panel_rect()
	return Rect2(box.end.x - BACK_WIDTH - 8.0, box.end.y - FOOTER_HEIGHT - 3.0,
		BACK_WIDTH, FOOTER_HEIGHT)


## 鼠标落在第几行。没落上返回 -1。
func _row_at(point: Vector2) -> int:
	for i: int in ROWS.size():
		if _row_rect(i).has_point(point):
			return i
	return -1


## 鼠标：划过就移光标（悬停有高亮），点一下就有反应，**滑条还能拖**。
##
## 这个面板以前**根本不接鼠标**（`_root` 设了 STOP，但没有 `_on_gui_input`），
## 设置只能用键盘改 —— 整个游戏里鼠标最该有手感的地方，鼠标是死的。
func _on_gui_input(event: InputEvent) -> void:
	if not _open:
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging >= 0:
			_drag_to(_dragging, motion.position.x)
			return
		var hover := _row_at(motion.position)
		if hover >= 0 and hover != _cursor:
			_cursor = hover
			_layout()
		return

	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if click.button_index != MOUSE_BUTTON_LEFT:
		return

	# 松手：拖拽结束，这时候才把值落盘（拖的过程中每帧只改内存）
	if not click.pressed:
		if _dragging >= 0:
			_dragging = -1
			if _settings != null:
				_settings.save_settings()
		return

	# 返回按钮先判。它和那几行不重叠，但先看更清楚，也免得将来
	# 面板长高了、按钮挪到行区里去的时候判反。
	if _back_rect().has_point(click.position):
		close()
		return

	var index := _row_at(click.position)
	if index < 0:
		return
	_cursor = index
	_layout()

	var row := ROWS[index]
	if row in SLIDER_ROWS:
		# 滑条：按下去就开始拖，顺手把值设到鼠标那儿
		_dragging = index
		_drag_to(index, click.position.x)
		return

	# 枚举行：点在左半往左、右半往右。
	# 这样「点一下」永远有反应，而不是点了没动。
	var rect := _row_rect(index)
	_cycle_current(-1 if click.position.x < rect.get_center().x else 1)


## 把某一行的滑条拖到鼠标所在的横坐标。
##
## 槽的起点和宽度跟 `_layout_slider()` 用的是同一套数（`TRACK_WIDTH` 和
## `box.position.x + PANEL_WIDTH - 96`）—— 两边各算一遍的话，改布局就会错位。
func _drag_to(index: int, x: float) -> void:
	if _settings == null:
		return
	var box := _panel_rect()
	var track_x := box.position.x + PANEL_WIDTH - 96.0
	var t := clampf((x - track_x) / TRACK_WIDTH, 0.0, 1.0)
	match ROWS[index]:
		&"music":
			_settings.set_music_volume(t, false)
		&"sfx":
			_settings.set_sfx_volume(t, false)
		_:
			return
	_layout()
	changed.emit()


func _layout() -> void:
	var view := _view_size()
	_root.position = Vector2.ZERO
	_root.size = view

	var box := _panel_rect()
	_edge.position = box.position
	_edge.size = box.size
	_panel.position = box.position + Vector2.ONE
	_panel.size = box.size - Vector2(2.0, 2.0)

	_header.text = TITLE
	_header.position = box.position + Vector2(8.0, 3.0)
	_header.size = Vector2(PANEL_WIDTH - 16.0, HEADER_HEIGHT)

	for index: int in ROWS.size():
		var row := ROWS[index]
		var active := index == _cursor
		var row_rect := _row_rect(index)
		var label := _rows[index]
		# 光标那一行前面挂个 ▸，看得出在选哪个
		label.text = ("▸ %s" % ROW_LABELS[index]) if active else ("　%s" % ROW_LABELS[index])
		label.add_theme_color_override("font_color",
			ROW_ACTIVE_COLOR if active else ROW_COLOR)
		label.position = row_rect.position
		label.size = Vector2(90.0, ROW_HEIGHT)

		var value := _values[index]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.position.y = row_rect.position.y
		value.size.y = ROW_HEIGHT

		if row in SLIDER_ROWS:
			_layout_slider(row, box, value)
		else:
			value.text = "〈 %s 〉" % _value_of(row)
			value.position.x = box.position.x + PANEL_WIDTH - 96.0
			value.size.x = 88.0

	_footer.text = HINT
	_footer.position = box.position + Vector2(8.0, box.size.y - FOOTER_HEIGHT - 3.0)
	# 宽度收到按钮左边为止，免得长提示压到按钮上
	_footer.size = Vector2(PANEL_WIDTH - 16.0 - BACK_WIDTH - 4.0, FOOTER_HEIGHT)

	# 返回按钮：贴着右下角，和提示同一行
	_back.position = _back_rect().position
	_back.size = _back_rect().size


## 摆一行滑条：槽、填充、右边那个百分比。
##
## 值那一格本来是 88 宽的文字，这里换成一整根条 —— 所以行内三段的宽度
## 是量着分的：**槽 58 + 间隔 6 + 百分比 24 = 88**，正好占满原来那格。
func _layout_slider(row: StringName, box: Rect2, value: Label) -> void:
	var track_x := box.position.x + PANEL_WIDTH - 96.0
	var track_y := value.position.y + (ROW_HEIGHT - TRACK_HEIGHT) * 0.5

	var track: ColorRect = _tracks[row]
	var fill: ColorRect = _fills[row]
	track.position = Vector2(track_x, track_y)
	track.size = Vector2(TRACK_WIDTH, TRACK_HEIGHT)
	track.visible = true
	# 填充从槽的左边长出来，长度按当前值算
	fill.position = track.position
	fill.size = Vector2(TRACK_WIDTH * _slider_of(row), TRACK_HEIGHT)
	fill.visible = true

	value.text = _value_of(row)
	value.position.x = track_x + TRACK_WIDTH + 6.0
	value.size.x = box.position.x + PANEL_WIDTH - 8.0 - value.position.x


## 某一行滑条现在的值（0..1）。
func _slider_of(row: StringName) -> float:
	if _settings == null:
		return 0.0
	return _settings.music_volume if row == &"music" else _settings.sfx_volume


## 某一行的值显示成什么。
func _value_of(row: StringName) -> String:
	if _settings == null:
		return ""
	match row:
		&"display":
			return _settings.display_label()
		&"size":
			# 全屏下窗口尺寸不起作用，标出来别让人白改
			if _settings.display == "fullscreen":
				return "全屏时无效"
			return _settings.window_size_label()
		&"speed":
			return _settings.speed_label()
		&"music":
			return _settings.music_label()
		&"sfx":
			return _settings.sfx_label()
		&"developer":
			return "开启" if _settings.developer_options_enabled else "关闭"
	return ""


func _view_size() -> Vector2:
	# 不查 viewport，理由同 DialogueBox：`--script` 模式下取不准
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
