## 游戏中的暂停菜单（ESC）。
##
## 做它的理由：存档、读档、设置、回主菜单、退出**全都只有快捷键或者根本没有**。
## 玩家不知道 F5 能存，想退出游戏只能点窗口右上角那个叉。
##
## **它不认识存档也不认识设置**：选了什么只发一个 id 出去，由外面解释。
## 理由同 TitleScreen 与 ChoiceMenu。
##
## 它跟 TitleScreen 最大的不同是**有「上一层」**：从这儿开出来的设置面板、
## 存档菜单都画在它上面（层号比它高），关掉之后人还留在暂停菜单里，
## 不会直接掉回游戏。所以有三项选完之后**自己不关**，见 `STAY_OPEN`。
##
## 挂 CanvasLayer，布局用绝对坐标，分辨率固定 320x180。
class_name PauseMenu
extends CanvasLayer

## 选了某一项。id 是 `resume` / `settings` / ... ，由外面解释。
signal chosen(id: StringName)

## 菜单项的 id。外面靠它分辨选了什么，别写成散在的字符串。
const ID_RESUME: StringName = &"resume"
const ID_SETTINGS: StringName = &"settings"
const ID_SAVE: StringName = &"save"
const ID_LOAD: StringName = &"load"
const ID_TITLE: StringName = &"title"
const ID_QUIT: StringName = &"quit"

## 菜单行的顺序。**写死在这里**，每次打开都一样 ——
## 位置会变的菜单，玩家的肌肉记忆就废了。
const ORDER: Array[StringName] = [
	ID_RESUME, ID_SETTINGS, ID_SAVE, ID_LOAD, ID_TITLE, ID_QUIT,
]

## 选完**停在这一层不关**的几项。
##
## 它们开出来的是画在暂停菜单上面的子面板（设置 17、存档菜单 16，
## 都比暂停菜单的 14 高），关掉子面板之后玩家还在暂停菜单里。
## 其余几项是「离开这一层」（回游戏 / 回标题 / 退出），选完就关。
const STAY_OPEN: Array[StringName] = [ID_SETTINGS, ID_SAVE, ID_LOAD]

const PANEL_WIDTH := 140.0
const HEADER_HEIGHT := 22.0
const PAD_TOP := 2.0
const ROW_HEIGHT := 15.0
const FOOTER_HEIGHT := 14.0
const PAD_BOTTOM := 4.0

const DIM_COLOR := Color(0.03, 0.04, 0.07, 0.82)
const PANEL_COLOR := Color(0.06, 0.07, 0.10, 0.97)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const TITLE_COLOR := Color("#f0e2c0")
const ROW_COLOR := Color("#c8ccd2")
const ROW_ACTIVE_COLOR := Color("#ffffff")
const ROW_DISABLED_COLOR := Color("#5c6166")
const FOOTER_COLOR := Color("#7f858c")

const TITLE := "暂停"
const FOOTER := "↑↓ 选择　ENTER 确定　ESC 继续"

var _root: Control
var _dim: ColorRect
var _edge: ColorRect
var _panel: ColorRect
var _title: Label
var _footer: Label
var _row_labels: Array[Label] = []
var _ids: Array[StringName] = []
var _enabled: Array[bool] = []
var _cursor := 0
var _open := false


func _ready() -> void:
	setup()


## 抽成显式方法，理由同 DialogueBox.setup()。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	# 15：盖得住对话框（10）、悬停提示（12）、选项框（13），
	# 也盖得住**演出层**（`stage_overlay` 14 —— 猫照片、碎玻璃、
	# 屏幕正中那两行字），但要**低于**存档菜单（16）和设置面板（17）——
	# 从这儿开出去的面板得画在它上面，不然「开出来的东西看不见，
	# 键盘却已经不在自己手里了」。这几个数是配着 `UiHost._top()` 排的。
	layer = 15
	# 暂停时也得活着：**接键、重画都要**。理由见 `open()` 里那句 `paused`。
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	_dim = _make_rect("Dim", DIM_COLOR)
	_edge = _make_rect("Edge", EDGE_COLOR)
	_panel = _make_rect("Panel", PANEL_COLOR)

	_title = _make_label("Title", 10, TITLE_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 底部提示**左对齐**，居中靠 `_layout()` 里自己量宽度摆 ——
	# 原因见那边。这里先不要给它居中。
	_footer = _make_label("Footer", 6, FOOTER_COLOR)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

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

## `can_load` 为 false 时「加载」那一项灰掉 —— 一个存档都没有，
## 点下去只会得到一句「槽位还是空的」。理由同 TitleScreen 的「继续」。
func open(can_load: bool) -> void:
	setup()
	_ids = ORDER.duplicate()
	_enabled = [true, true, true, can_load, true, true]
	# 光标每次都回到「继续游戏」：暂停菜单是 Ctrl+Z 那种东西，
	# 打开它的默认意图就是「没事，接着玩」。
	_cursor = 0
	_open = true
	_root.visible = true
	_rebuild_rows()
	_layout()
	_set_paused(true)


func close() -> void:
	if _root != null:
		_root.visible = false
	_open = false
	_set_paused(false)


## 暂停整个世界。**这是这个菜单存在的一半意义。**
##
## 光挡住画面不叫暂停：演出的 NPC 会继续走、立绘会继续浮动、
## 补间会继续跑，玩家按了 ESC 却看着世界照转（2026-09-24 报的）。
##
## 交给 `SceneTree.paused` 做，而不是逐个去停：演出是 `await` 和补间堆起来的，
## 要停的是一大串，还得记着别漏。引擎一个开关，把该冻的全冻住。
##
## **界面不受影响** —— `main` 自己和几个面板设了 `PROCESS_MODE_ALWAYS`，
## 见 `main._set_process_modes()`。不然菜单开着就接不到键、也关不掉。
##
## **先问在不在树里，再去拿 `get_tree()`。**
##
## 这两句的顺序不能换：节点不在树里时 `get_tree()` 会走 `ERR_FAIL_NULL_V` ——
## 返回 null 的**同时往控制台喷一行**
## `ERROR: Parameter "data.tree" is null.`（`scene/main/node.h:559`）。
## `--script` 刚启动那会儿正好是这个处境：`boot()` → `enter_map()` →
## `ui_host.close_overlays()` → 这里，节点还没被引擎挂进树。
## 那种错误不会让游戏出错，但会在日志里冒充真问题（2026-09-24 抓到）。
func _set_paused(value: bool) -> void:
	if not is_inside_tree():
		return
	get_tree().paused = value


func is_open() -> bool:
	return _open


# ---------------------------------------------------------------- 查询

func item_count() -> int:
	return _ids.size()


func cursor() -> int:
	return _cursor


func current_id() -> StringName:
	if _cursor < 0 or _cursor >= _ids.size():
		return &""
	return _ids[_cursor]


## 某一行的文字。**不带光标那个 ▸** ——
## 它是个装饰，测试和外面要的是「这一行写着什么」。
func row_text(index: int) -> String:
	if index < 0 or index >= _ids.size():
		return ""
	return _label_for(_ids[index])


## 某一项能不能选。「加载」在没有存档时会是 false。
func is_enabled(index: int) -> bool:
	if index < 0 or index >= _enabled.size():
		return false
	return _enabled[index]


# ---------------------------------------------------------------- 操作

## 键盘操作。上下移动、回车确认、**ESC 当作「继续游戏」**。
##
## ESC 在这里是「返回上一层」的含义：这一层就是最外面，所以等于回游戏。
## 玩家按 ESC 打开菜单、再按 ESC 关掉，是最顺手的路径，
## 不该逼他去把光标挪到第一行。
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
			_confirm_id(ID_RESUME)
			return true
	return false


func select_index(index: int) -> void:
	if index < 0 or index >= _ids.size() or not _enabled[index]:
		return
	_cursor = index
	_update_rows()


func _move(step: int) -> void:
	if _ids.is_empty():
		return
	var count := _ids.size()
	var index := _cursor
	# 跳过不能选的那一项，跟 ChoiceMenu / TitleScreen 一个道理
	for _i: int in count:
		index = (index + step + count) % count
		if _enabled[index]:
			_cursor = index
			_update_rows()
			return


func _confirm() -> void:
	if not _open or not is_enabled(_cursor):
		return
	_confirm_id(current_id())


## 按 id 确认。ESC 那条路直接走这里，不经过光标位置。
func _confirm_id(id: StringName) -> void:
	if not _open:
		return
	var index := _ids.find(id)
	if index < 0 or not _enabled[index]:
		return
	_cursor = index
	_update_rows()
	# 开子面板的那几项**不关**，关掉子面板后人还在这一层
	if not STAY_OPEN.has(id):
		close()
	chosen.emit(id)


func _on_gui_input(event: InputEvent) -> void:
	if not _open:
		return

	# 鼠标划过哪一行，光标就跟到哪一行 —— **悬停因此有高亮**。
	# 借的是光标那一行自己的绘制（▸ 加亮色），不另做一套 hover 样式：
	# 两套样式迟早会走样，而且哪些行可选还得判两遍。
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

	# **点一下就生效。** 以前是「第一次点只选中、第二次才确认」，
	# 而鼠标划过来的时候光标其实已经跟到那一行了，再要求点两下就是别扭。
	# `select_index` 会挡掉不能选的行，`_confirm` 自己也会再查一遍。
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
		var label := _make_label("Row", 9, ROW_COLOR)
		_row_labels.append(label)
	_update_rows()


## 光标那一行前面挂个 ▸，看得出在选哪个 —— 和设置面板同一套。
func _update_rows() -> void:
	for i: int in _row_labels.size():
		var active := i == _cursor
		var text := _label_for(_ids[i])
		_row_labels[i].text = ("▸ %s" % text) if active else ("　%s" % text)
		var color := ROW_COLOR
		if not _enabled[i]:
			color = ROW_DISABLED_COLOR
		elif active:
			color = ROW_ACTIVE_COLOR
		_row_labels[i].add_theme_color_override("font_color", color)


func _label_for(id: StringName) -> String:
	match id:
		ID_RESUME:
			return "继续游戏"
		ID_SETTINGS:
			return "设置"
		ID_SAVE:
			return "保存"
		ID_LOAD:
			return "加载"
		ID_TITLE:
			return "返回主菜单"
		ID_QUIT:
			return "退出游戏"
	return str(id)


func _row_rect(index: int) -> Rect2:
	var box := _panel_rect()
	return Rect2(box.position.x + 8.0, box.position.y + HEADER_HEIGHT + PAD_TOP
		+ float(index) * ROW_HEIGHT, PANEL_WIDTH - 16.0, ROW_HEIGHT)


func _panel_height() -> float:
	return HEADER_HEIGHT + PAD_TOP + ROW_HEIGHT * float(ORDER.size()) \
		+ PAD_BOTTOM + FOOTER_HEIGHT


func _panel_rect() -> Rect2:
	var view := _view_size()
	var height := _panel_height()
	return Rect2((view.x - PANEL_WIDTH) * 0.5, (view.y - height) * 0.5,
		PANEL_WIDTH, height)


func _layout() -> void:
	var view := _view_size()
	_root.position = Vector2.ZERO
	_root.size = view

	_dim.position = Vector2.ZERO
	_dim.size = view

	var box := _panel_rect()
	_edge.position = box.position
	_edge.size = box.size
	_panel.position = box.position + Vector2.ONE
	_panel.size = box.size - Vector2(2.0, 2.0)

	_title.text = TITLE
	_title.position = box.position + Vector2(0.0, 4.0)
	_title.size = Vector2(PANEL_WIDTH, 14.0)

	for i: int in _row_labels.size():
		var rect := _row_rect(i)
		_row_labels[i].position = rect.position
		_row_labels[i].size = rect.size

	# 底部提示：**自己量文字宽度再摆**，不用 Label 的居中。
	#
	# 为什么不能让它自己居中：`Control.size` 不能小于它自身的**最小尺寸**，
	# 而 Label 的最小尺寸就是那一整行字。给它一个比字窄的框让它居中，
	# 它会先被撑到字的宽度，字再居到那个被撑宽的框里 ——
	# 实测过：面板 140，这行提示把标签撑成 235，字就整行跑到面板外面去了。
	#
	# 顺带，中文在回退字体里的宽度跟字号不是倍数关系，也只能实测。
	# 标签最终的高度（23）也大于这里的字号，但文字是**顶端对齐**画在
	# 标签顶部的，所以按量出来的高度摆就是准的。
	_footer.text = FOOTER
	var font := _footer.get_theme_font("font")
	var font_size := _footer.get_theme_font_size("font_size")
	var text_size := Vector2.ZERO
	if font != null:
		text_size = font.get_string_size(FOOTER, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_footer.position = Vector2(
		box.get_center().x - text_size.x * 0.5,
		box.end.y - PAD_BOTTOM - text_size.y
	)
	_footer.size = Vector2(text_size.x, text_size.y)


func _view_size() -> Vector2:
	# 不查 viewport，理由同 DialogueBox：`--script` 模式下取不准
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
