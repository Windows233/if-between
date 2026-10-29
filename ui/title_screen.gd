## 标题界面：游戏跑起来第一眼看到的东西。
##
## 做它的直接理由是**没人知道快捷键** —— F4 图鉴、F5 存档、F9 读档
## 只写在开发文档里，玩家一个都看不见。底部那行按键说明就是为这个。
##
## 另一条：它是「这个东西能给人玩」的第一步。之前一启动就直接落进房间，
## 既没有「新游戏」，也没有「继续」，连存档在哪都看不出来。
##
## **它不认识存档也不认识图鉴**：选了什么只发一个 id 出去，
## 由外面决定读哪个槽、开哪个面板。理由同 ChoiceMenu。
##
## 挂 CanvasLayer，不受相机影响。布局用绝对坐标，分辨率固定 320x180。
class_name TitleScreen
extends CanvasLayer

## 选了某一项。id 是 `new` / `continue` / `gallery`，由外面解释。
signal chosen(id: StringName)

## 菜单项的 id。外面靠它分辨选了什么，别写成散在的字符串。
const ID_NEW: StringName = &"new"
const ID_CHAPTER_TWO: StringName = &"chapter_two"
const ID_CONTINUE: StringName = &"continue"
const ID_GALLERY: StringName = &"gallery"
const ID_SETTINGS: StringName = &"settings"
const ID_QUIT: StringName = &"quit"

## 行的顺序。写死在这里，跟 `PauseMenu.ORDER` 一个道理。
##
## 「退出游戏」排在**最后**：它不可逆，误选就没了。
## 放在最下面离光标默认位置（第一行）最远，也跟绝大多数游戏一致。
const ORDER: Array[StringName] = [
	ID_NEW, ID_CONTINUE, ID_GALLERY, ID_SETTINGS, ID_QUIT,
]

## 选完**自己不收**的几项。
##
## 它们开出来的是画在标题上面的子面板（设置 22、存档/加载 23、图鉴 24，
## 都比标题的 21 高），关掉子面板之后玩家还在标题这一层。
## 其余几项是「离开这一层」（开新游戏 / 退出），选完就该把标题收掉。
##
## **「继续」也算在里面** —— 它开的是加载界面，不是直接读档
## （见 `MenuFlow.on_title_chosen`）。以前它自动读最近那个档、读完就进游戏，
## 所以那时候不收是对的；现在改了语义，这里也得跟着收进来，
## 否则标题一收、加载界面关掉之后就没人把标题开回来了。
##
## **不收是必须的。** 收掉之后没人再把它开回来：子面板一关，屏幕上一片黑
## （2026-09-24 报的，主菜单点设置、按 ESC 就黑屏）。理由同 `PauseMenu.STAY_OPEN`。
##
## 「新游戏」「进入第二章」也不收：它们先弹起名面板（25 层），确认后由
## `MenuFlow.on_name_confirmed` 收掉标题再开局，取消就留在标题（2026-10-29）。
const STAY_OPEN: Array[StringName] = [ID_NEW, ID_CHAPTER_TWO, ID_CONTINUE, ID_GALLERY, ID_SETTINGS]

## 纵向排布（视口 320x180）。
##
## 这几个数是**一行一行量着排下来的**：五行菜单 + 两行按键说明要全塞进 180。
## 加行的话（比如又来一个菜单项）得回来重算，不然底下那两行会被挤出画面。
const TITLE_Y := 34.0
const SUBTITLE_Y := 58.0
const MENU_TOP := 74.0
const ROW_HEIGHT := 15.0
const ROWS_WIDTH := 140.0
const CHAPTER_BUTTON_WIDTH := 78.0
const CHAPTER_BUTTON_RIGHT := 8.0
## 底部按键说明分两行。原来是一行，加了「游戏内 ESC 菜单」之后
## 整行宽度超过了视口 320，居中的标签就把右半边顶到画面外面去了
## （Label 的框不够宽时，居中的字是往右溢出的）。
const HINT_Y := 152.0
const HINT_LINE_HEIGHT := 12.0

const BG_COLOR := Color(0.03, 0.04, 0.07, 0.98)

## 主界面背景图。**加载不出来就退回 `BG_COLOR` 那块纯色。**
##
## 背景是好看用的，不是必须的 —— 素材缺了不该连标题都开不起来。
const BG_PATH := "res://art/ui/title_bg.png"
const TITLE_COLOR := Color("#f0e2c0")
const SUBTITLE_COLOR := Color("#8a8f96")
const ROW_COLOR := Color("#d8d8d8")
const ROW_DISABLED_COLOR := Color("#5c6166")
const HIGHLIGHT_COLOR := Color(0.22, 0.30, 0.26, 1.0)
const HINT_COLOR := Color("#6a7078")
const CHAPTER_EDGE_COLOR := Color("#83744f")
const CHAPTER_EDGE_ACTIVE_COLOR := Color("#e8c07a")
const CHAPTER_FILL_COLOR := Color("#111817")
const CHAPTER_FILL_ACTIVE_COLOR := Color("#354839")

var _root: Control
var _bg: ColorRect
## 背景图。素材不在时是 null，由 `_bg` 那块纯色顶着。
var _bg_picture: TextureRect
var _highlight: ColorRect
var _chapter_button_edge: ColorRect
var _chapter_button_fill: ColorRect
var _title: Label
var _subtitle: Label
var _hint: Label
var _hint_play: Label
var _row_labels: Array[Label] = []
var _ids: Array[StringName] = []
var _enabled: Array[bool] = []
var _cursor := 0
var _open := false
var _can_continue := false
var _chapter_two_enabled := false


func _ready() -> void:
	setup()


## 抽成显式方法，理由同 DialogueBox.setup()。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	# 21：盖得住图鉴（18）和 toast（20）。
	# 标题开着的时候画面上不该有别的，包括刚弹出来的存档提示。
	layer = 21

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	_bg = _make_rect("Bg", BG_COLOR)
	_bg_picture = _make_picture("BgPicture", BG_PATH)
	_highlight = _make_rect("Highlight", HIGHLIGHT_COLOR)
	_chapter_button_edge = _make_rect("ChapterTwoEdge", CHAPTER_EDGE_COLOR)
	_chapter_button_fill = _make_rect("ChapterTwoFill", CHAPTER_FILL_COLOR)
	_chapter_button_edge.visible = false
	_chapter_button_fill.visible = false

	_title = _make_label("Title", 16, TITLE_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_subtitle = _make_label("Subtitle", 8, SUBTITLE_COLOR)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_hint = _make_label("Hint", 7, HINT_COLOR)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_hint_play = _make_label("HintPlay", 7, HINT_COLOR)
	_hint_play.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_root.visible = false


## 铺满屏幕的一张图。素材不在、或者不是图，就返回 null —— 底下的纯色顶着。
##
## `EXPAND_IGNORE_SIZE` + `COVERED`：铺满且不变形（素材是 16:9，和视口一致）。
## 和 `ScreenShatter` 那边用的是同一套。
func _make_picture(node_name: String, path: String) -> TextureRect:
	if not ResourceLoader.exists(path):
		return null
	var texture: Resource = load(path)
	if not (texture is Texture2D):
		return null
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


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

## `can_continue` 为 false 时「继续」那一项灰掉 —— 一个存档都没有，
## 点下去只会得到一句「槽位还是空的」。
func open(can_continue: bool, allow_chapter_two: bool = false) -> void:
	setup()
	_can_continue = can_continue
	_chapter_two_enabled = allow_chapter_two
	_refresh_rows(ID_NEW)
	_open = true
	_root.visible = true
	_layout()
	_update_highlight()


func close() -> void:
	if _root != null:
		_root.visible = false
	_open = false


func is_open() -> bool:
	return _open


func set_chapter_two_enabled(enabled: bool) -> void:
	if _chapter_two_enabled == enabled:
		return
	var selected_id := current_id()
	_chapter_two_enabled = enabled
	if not _open:
		return
	_refresh_rows(selected_id)
	_layout()
	_update_highlight()


# ---------------------------------------------------------------- 查询

func item_count() -> int:
	return _ids.size()


func cursor() -> int:
	return _cursor


func current_id() -> StringName:
	if _cursor < 0 or _cursor >= _ids.size():
		return &""
	return _ids[_cursor]


func row_text(index: int) -> String:
	if index < 0 or index >= _row_labels.size():
		return ""
	return _row_labels[index].text


## 某一项能不能选。「继续」在没有存档时会是 false。
func is_enabled(index: int) -> bool:
	if index < 0 or index >= _enabled.size():
		return false
	return _enabled[index]


# ---------------------------------------------------------------- 操作

## 键盘操作。上下移动、回车确认。返回 true 表示这次按键被界面吃掉了。
##
## **ESC 在这里什么也不做** —— 虽然菜单里现在有「退出游戏」，
## 但那是**不可逆**的（没存档的进度就没了），不该挂在 ESC 这种顺手键上。
## 想退就得移光标移过去、按回车，两步。
## 另外这一层也没有「上一层」可退，ESC 在这儿没有别的语义。
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
		KEY_LEFT:
			return _move_to_chapter_button(false)
		KEY_RIGHT:
			return _move_to_chapter_button(true)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm()
			return true
	return false


func select_index(index: int) -> void:
	if index < 0 or index >= _ids.size() or not _enabled[index]:
		return
	_cursor = index
	_update_highlight()


func _move(step: int) -> void:
	if _ids.is_empty():
		return
	var count := _ids.size()
	var index := _cursor
	var current_y := _row_rect(_cursor).position.y
	# 跳过不能选的那一项，跟 ChoiceMenu 一个道理
	for _i: int in count:
		index = (index + step + count) % count
		if _enabled[index] and not is_equal_approx(_row_rect(index).position.y, current_y):
			_cursor = index
			_update_highlight()
			return


func _move_to_chapter_button(to_chapter_two: bool) -> bool:
	if not _chapter_two_enabled:
		return false
	var target_id: StringName = ID_CHAPTER_TWO if to_chapter_two else ID_NEW
	if to_chapter_two and current_id() != ID_NEW:
		return false
	if not to_chapter_two and current_id() != ID_CHAPTER_TWO:
		return false
	select_index(_ids.find(target_id))
	return true


func _confirm() -> void:
	if not _open:
		return
	if not is_enabled(_cursor):
		return
	var id := current_id()
	# 开子面板的那几项**自己不收** —— 收了就再也回不来（见 `STAY_OPEN`）。
	if not STAY_OPEN.has(id):
		_open = false
		_root.visible = false
	chosen.emit(id)


func _on_gui_input(event: InputEvent) -> void:
	if not _open:
		return

	# 鼠标划过哪一行，光标就跟到哪一行 —— **悬停因此有高亮**。
	# 借的是光标那一行自己的绘制，不另做一套 hover 样式。
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

	# **点一下就生效**，不用先点一次选中再点一次确认。
	var index := _row_at(click.position)
	if index < 0:
		return
	select_index(index)
	_confirm()


## 鼠标落在第几行。没落上返回 -1。
func _row_at(point: Vector2) -> int:
	for i: int in _ids.size():
		if _row_rect(i).has_point(point):
			return i
	return -1


# ---------------------------------------------------------------- 内部

func _rebuild_rows() -> void:
	for label: Label in _row_labels:
		label.queue_free()
	_row_labels.clear()

	for i: int in _ids.size():
		var label := _make_label("Row", 10, ROW_COLOR)
		label.text = _label_for(_ids[i])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override(
			"font_color", ROW_COLOR if _enabled[i] else ROW_DISABLED_COLOR
		)
		_row_labels.append(label)


func _refresh_rows(selected_id: StringName) -> void:
	_ids = ORDER.duplicate()
	if _chapter_two_enabled:
		_ids.insert(1, ID_CHAPTER_TWO)
	_enabled.clear()
	for id: StringName in _ids:
		_enabled.append(id != ID_CONTINUE or _can_continue)
	_rebuild_rows()
	_cursor = _ids.find(selected_id)
	if _cursor < 0 or not _enabled[_cursor]:
		_cursor = 0


func _label_for(id: StringName) -> String:
	match id:
		ID_NEW:
			return "新游戏"
		ID_CHAPTER_TWO:
			return "进入第二章"
		ID_CONTINUE:
			return "继续"
		ID_GALLERY:
			return "结局图鉴"
		ID_SETTINGS:
			return "设置"
		ID_QUIT:
			return "退出游戏"
	return str(id)


func _row_rect(index: int) -> Rect2:
	var view := _view_size()
	if _ids[index] == ID_CHAPTER_TWO:
		return Rect2(view.x - CHAPTER_BUTTON_RIGHT - CHAPTER_BUTTON_WIDTH,
			MENU_TOP, CHAPTER_BUTTON_WIDTH, ROW_HEIGHT)
	var left := (view.x - ROWS_WIDTH) * 0.5
	var row_index := index - 1 if _chapter_two_enabled and index > 0 else index
	return Rect2(left, MENU_TOP + float(row_index) * ROW_HEIGHT, ROWS_WIDTH, ROW_HEIGHT)


func _update_highlight() -> void:
	if _cursor < 0 or _cursor >= _ids.size():
		_highlight.visible = false
		return
	var rect := _row_rect(_cursor)
	_highlight.position = rect.position
	_highlight.size = rect.size
	_highlight.visible = true
	var chapter_selected := current_id() == ID_CHAPTER_TWO
	_chapter_button_edge.color = CHAPTER_EDGE_ACTIVE_COLOR \
		if chapter_selected else CHAPTER_EDGE_COLOR
	_chapter_button_fill.color = CHAPTER_FILL_ACTIVE_COLOR \
		if chapter_selected else CHAPTER_FILL_COLOR
	# 高亮要压在背景上、文字下。背景现在是「纯色 + 一张图」两层，
	# **不能写死「`_bg` 后面那一格」** —— 那样会把高亮插到图前面去，
	# 被图盖住。认最后一层背景。
	var behind: Control = _bg_picture if _bg_picture != null else _bg
	_root.move_child(_highlight, behind.get_index() + 1)


func _layout() -> void:
	var view := _view_size()
	_root.position = Vector2.ZERO
	_root.size = view

	_bg.position = Vector2.ZERO
	_bg.size = view

	if _bg_picture != null:
		_bg_picture.position = Vector2.ZERO
		_bg_picture.size = view

	_title.text = "IF：如果之间"
	_title.position = Vector2(0.0, TITLE_Y)
	_title.size = Vector2(view.x, 22.0)

	_subtitle.text = "带 IF 分支的剧情 RPG"
	_subtitle.position = Vector2(0.0, SUBTITLE_Y)
	_subtitle.size = Vector2(view.x, 12.0)

	for i: int in _row_labels.size():
		var rect := _row_rect(i)
		_row_labels[i].position = rect.position
		_row_labels[i].size = rect.size

	var chapter_index := _ids.find(ID_CHAPTER_TWO)
	_chapter_button_edge.visible = chapter_index >= 0
	_chapter_button_fill.visible = chapter_index >= 0
	if chapter_index >= 0:
		var chapter_rect := _row_rect(chapter_index)
		_chapter_button_edge.position = chapter_rect.position
		_chapter_button_edge.size = chapter_rect.size
		_chapter_button_fill.position = chapter_rect.position + Vector2.ONE
		_chapter_button_fill.size = chapter_rect.size - Vector2(2.0, 2.0)

	_hint.text = "↑↓ 选择　ENTER 确认"
	_hint.position = Vector2(0.0, HINT_Y)
	_hint.size = Vector2(view.x, HINT_LINE_HEIGHT)

	# 第二行专门写**游戏里的**键。第一次来的人只看这一行就够了 ——
	# 标题界面上没有 ESC 这个键，写在那儿反而让人以为按了会有反应。
	_hint_play.text = "游戏内：ESC 菜单　F4 图鉴　F5 存档　F9 读档"
	_hint_play.position = Vector2(0.0, HINT_Y + HINT_LINE_HEIGHT)
	_hint_play.size = Vector2(view.x, HINT_LINE_HEIGHT)


func _view_size() -> Vector2:
	# 不查 viewport，理由同 DialogueBox：`--script` 模式下取不准
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
