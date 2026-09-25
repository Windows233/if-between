## IF 条件框：画面正中那个「if "…" then "…"」加一排选项块。
##
## 版式照策划那份示意：
##
##     ┌──────────────────────────────────┐
##     │   if "▢" then "▢"                │   ← 条件（固定文字）/ 结果（一个块位）
##     │   ──────────────────────────     │   ← 分隔线
##     │   [块] [块] [块] [块]             │   ← 四个选项块，横向铺开
##     └──────────────────────────────────┘
##
## 框底是素材包里的「悬浮框_透明度72」（1048x568）。**不九宫格** ——
## 素材四角要 96 源像素才成形，上下各 96 就是 192，而视口只有 180 高，
## 装不下（硬上会把边框挤成菱形，2026-09-24 踩过）。好在**比例正好一致**，
## 整张等比缩放不变形，只是描边软一点。
##
## `if` 后面是**固定文字**（剧情给死的条件），`then` 后面是**块位**：
## 空着画虚线方块示意「这儿能拖东西进来」，有东西就贴着那块。
##
## 选项块 = **方块图 + 方块下方的名字**（素材包 README：「方块内可放序号或图标，
## 方块下方放选项名」）。四种状态（常态 / 悬停 / 选中 / 禁用）各一张 214x214。
##
## **层号由外面那层 `CanvasLayer` 给**（`main` 里套的），这个类自己是个
## `Control`。别让它直接 `extends CanvasLayer` —— 那样里面的 `_draw()`
## 不肯跑，分隔线和虚线方块一个都出不来（2026-09-24 踩的）。
class_name IfPanel
extends Control

## 选项块的状态。和素材包里那四张图一一对应。
enum SlotState {
	NORMAL,
	HOVER,
	ACTIVE,
	DISABLED,
}

## 框显示多大（游戏单位）。比例照素材成图（1048:568）。
const BOX_SIZE := Vector2(282.0, 153.0)
## 框内的留白（相对 BOX_SIZE）。
const PAD := Vector2(15.0, 11.0)
## 分隔线在框高的哪个位置。
const DIVIDER_RATIO := 0.45
## 选项块显示多大、块与块之间留多少。
const SLOT_SIZE := 34.0
const SLOT_GAP := 18.0
## 填空处那个虚线方块：**和选项块一样大、一样切角**。
##
## 策划说的「虚线框的大小应该能和选项框重合」就是这个意思：
## 玩家得一眼看出「下面那几块能拖进这个洞」。切角比例照素材来（切角 24 / 方块 170）。
const SLOT_CUT_RATIO := 0.14
## 块名写在**方块里面**。
##
## 素材包 README 建议「方块下方放选项名」，但那是给「一块一块竖着排」的场合写的。
## 这儿是四个块横向铺开，名字放下面会挤成一长条、也离块太远（2026-09-25
## 策划看了截图说的「字尽量写进方块里面」）。字号因此压到 6，长一点的名字折两行。
const BLOCK_LABEL_SIZE := 6

## 「确定」按钮。摆在四个选项栏**右边**（2026-09-25 策划要的）——
## 玩家拖完了总得有个东西可以按。
##
## **它同时修了「关不掉窗口」那个卡关**：面板要收鼠标才能拖，
## 收进来（`MOUSE_FILTER_STOP`）之后，原来那套「点一下继续」就够不着面板
## 背后的东西了。有了这个按钮，收尾不再依赖鼠标穿透。
const CONFIRM_SIZE := Vector2(44.0, 19.0)
const CONFIRM_TEXT := "确定"
## 「确定」两个字多大。
const CONFIRM_FONT_SIZE := 9
const CONFIRM_EDGE := Color(0.78, 0.82, 0.90)
const CONFIRM_EDGE_HOVER := Color(0.92, 0.86, 0.66)
const CONFIRM_FILL := Color(0.06, 0.10, 0.22, 0.90)
## 离框右内边多远。**要比 `PAD.x` 再往里收一截** —— 框底那张素材自己带一圈
## 外留白，按 `PAD.x` 摆看着还是贴着右边框（2026-09-25 策划说的）。
const CONFIRM_RIGHT_PAD := 30.0

## 拖拽的来源 / 目标。`from >= 0` 表示下方第几格。
const FROM_THEN := -1
const FROM_IF := -2

## 按「确定」时这一下算哪种结果。**剧本照它决定往下演、跳「又一遍」、还是重排。**
##
## 抽成纯函数是有意的：判定原来夹在 `cutscene._if_panel` 的协程里，测试够不着 ——
## 而 2026-09-25 策划报的「什么都不做按确定就能往下演」正是这条判定的问题。
enum Verdict {
	SOLVED,      ## 排对了
	UNTOUCHED,   ## 什么都没改（`then` 还是开局那个值）
	WRONG,       ## 排了别的组合
}

## if / then 那行的分段：**固定文字 / 条件 / 固定文字 / 结果 / 固定文字**。
##
## **两个填空处左右都得有双引号** —— 一开始只给了左边的，看着像单引号，
## 策划当场就指出来了（2026-09-24）。
const SEG_FIXED: Array[String] = ["if \"", "\" then \"", "\""]

## 框底素材。
const FRAME_TEXTURE := "res://art/ui/info_panel.png"

## 选项块的四张图。
const SLOT_TEXTURES: Array[String] = [
	"res://art/ui/place_normal.png",
	"res://art/ui/place_hover.png",
	"res://art/ui/place_active.png",
	"res://art/ui/place_locked.png",
]

const TEXT_COLOR := Color(0.86, 0.89, 0.96)
const DIVIDER_COLOR := Color(0.78, 0.82, 0.90, 0.55)
const BLANK_COLOR := Color(0.62, 0.70, 0.86, 0.85)
const BLOCK_LABEL_COLOR := Color(0.88, 0.91, 0.97)

## 玩家挪动过块了。剧本靠它知道「拖完了」——
## 教学那段就是等这个信号，再看 `then_block()` 对不对（见 `cutscene.gd` 的
## `_if_panel`）。
signal arranged

## 玩家按了「确定」。**这是收尾信号** —— 剧本等它，不等鼠标点空白处。
signal confirmed

var _frame: TextureRect = null
## if / then 那行的五段文字，按顺序摆。中间两段（下标 1、3）是**值** ——
## 条件那格是固定文字，结果那格是块位。
var _segs: Array[Label] = []
## 两个填空方块的位置，`_layout_text()` 算出来的，画的时候来取。
var _blank_at: Array[Vector2] = []
## 下方四个位置各放着什么（空字符串 = 空位）。
var _tray: Array[String] = ["", "", "", ""]
## 「if」后面放着什么。**也是个块位** —— 2026-09-25 策划要的：
## A 那个「发现异常」原本是第三格（C），摆到 `if` 上来之后 C 就空了。
var _if_block := ""
## 「then」里放着什么。
var _then := ""
## 下方四块的状态。**只有「能不能拖」看它** —— 禁用的拖不动。
var _states: Array[SlotState] = []

## 拖着的那块：`{"from": ..., "at": Vector2}`。`from` 是下方格子下标，
## 或者 `FROM_IF` / `FROM_THEN`（从块位里往外拖）。空字典 = 没在拖。
var _drag: Dictionary = {}
## 开局那套摆法。`reset_blocks()` 回到它。
var _initial_tray: Array[String] = ["", "", "", ""]
var _initial_if := ""
var _initial_then := ""
## 每一块的两个节点：方块（TextureRect）和名字（Label）。
var _tray_nodes: Array[Dictionary] = []
var _then_nodes: Dictionary = {}
var _if_nodes: Dictionary = {}
## 「确定」按钮。**必须是子节点，不能画在 `_draw()` 里** ——
## 框底（`_frame`）是子节点，而父节点的 `_draw()` 永远画在子节点**下面**，
## 画在 `_draw()` 里的按钮会被框底半透明地盖住（2026-09-25 策划看截图说的）。
var _confirm: Panel = null
var _confirm_label: Label = null
## 鼠标停在「确定」上没有。
var _confirm_hover := false
## 补布局做过没有。见 `_refresh()` 末尾。
var _relayout_done := false
## **只读**：纯展示的框（`disabled: true`）用它。挡的是拖动 ——
## 两个块位里的块也不许拽走（2026-09-25：策划说老人那框两块是固定的，
## 但当时还能左右对调）。
var _read_only := false
var _condition := ""
var _open := false


func _ready() -> void:
	setup()


## 抽成显式方法，理由同别的界面：`--script` 模式下 `add_child` 不触发 `_ready`。
## 重复调用安全。
func setup() -> void:
	if _frame != null:
		return

	# **要收鼠标输入才能拖。** 原来这里是 IGNORE（纯展示），
	# 2026-09-25 加了拖动之后必须改成 STOP，不然 `_gui_input()` 一次都不来。
	mouse_filter = Control.MOUSE_FILTER_STOP
	# **尺寸得手动给。** 这个 `Control` 挂在 `CanvasLayer` 下面，
	# 不是挂在另一个 `Control` 里，锚点算不出尺寸 —— 不给的话 size 是 0，
	# `_draw()` 画了也看不见（2026-09-24 踩的：分隔线一个都没出来）。
	size = _view_size()

	_frame = TextureRect.new()
	_frame.name = "Frame"
	if ResourceLoader.exists(FRAME_TEXTURE):
		_frame.texture = load(FRAME_TEXTURE)
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	# if / then 那行**拆成五段**：中间夹着两处值（条件 / 结果），
	# 拼成一个字符串的话方块就插不进字中间了。
	for i: int in 5:
		_segs.append(_make_label(11))

	for i: int in 4:
		_tray_nodes.append(_make_block())
		_states.append(SlotState.NORMAL)

	_then_nodes = _make_block()
	_if_nodes = _make_block()

	# 「确定」按钮。**加在最后** —— 同层按加入顺序画，这样它压在框底之上。
	_confirm = Panel.new()
	_confirm.name = "Confirm"
	var style := StyleBoxFlat.new()
	style.bg_color = CONFIRM_FILL
	style.border_color = CONFIRM_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	_confirm.add_theme_stylebox_override("panel", style)
	_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_confirm)

	_confirm_label = Label.new()
	_confirm_label.name = "ConfirmLabel"
	_confirm_label.text = CONFIRM_TEXT
	_confirm_label.add_theme_font_size_override("font_size", CONFIRM_FONT_SIZE)
	_confirm_label.add_theme_color_override("font_color", CONFIRM_EDGE)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# **文字居中靠 Label 自己**，不靠 `draw_string` 估基线 ——
	# 上一版拿 `get_string_size()` 算偏移，字顶着框的上边缘（2026-09-25 策划说的）。
	_confirm.add_child(_confirm_label)

	visible = false


## 一块 = 方块图 + 方块下方的名字。两块节点一起造，位置在 `_refresh()` 里摆。
func _make_block() -> Dictionary:
	var block := TextureRect.new()
	block.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	block.stretch_mode = TextureRect.STRETCH_SCALE
	# **方块本身不收输入** —— 命中判定统一走 `_hit_*`（拿矩形比），
	# 免得子节点把事件吃掉、拖到一半断掉。
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(block)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", BLOCK_LABEL_SIZE)
	label.add_theme_color_override("font_color", BLOCK_LABEL_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 名字写在方块**里面**，长一点的名字（「来找主角帮忙」）折行
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	return {"block": block, "label": label}


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


## 打开 / 收起。
##
## `p_condition` 是 `if` 后面**没摆块时**显示的固定文字（老数据用）；
## `p_then` 是 `then` 里先放着的那块；`p_if_block` 是 `if` 后面先放着的那块。
## 块非空时以块为准、`p_condition` 就不显示了。
func open(p_condition: String = "", p_then: String = "",
		p_if_block: String = "") -> void:
	setup()
	_condition = p_condition
	_then = p_then
	_if_block = p_if_block
	_drag.clear()
	_read_only = false
	# 新开一次就允许再补一遍布局（那次补过之后它就置真了）
	_relayout_done = false
	_open = true
	visible = true
	# 先按参数记一份开局摆法兜底；剧本后面用 `set_slot_block()` 摆完位
	# 应该再调一次 `remember_layout()` 把它定下来。
	remember_layout()
	_refresh()


## 把现在这套摆法记成「开局」。剧本摆完位调一次 ——
## 之后 `reset_blocks()` 回到的就是这儿。
func remember_layout() -> void:
	_initial_tray = _tray.duplicate()
	_initial_if = _if_block
	_initial_then = _then


func close() -> void:
	setup()
	_drag.clear()
	_open = false
	visible = false


func is_open() -> bool:
	return _open


## 现在填的条件。空字符串表示还没填。
func condition_text() -> String:
	return _condition


## `then` 里现在放着的那块。**老名字 `result_text()` 还留着** ——
## 外面（测试、以前的剧本）按那个叫。
func result_text() -> String:
	return _then


func then_block() -> String:
	return _then


func slot_count() -> int:
	return _tray.size()


func slot_state(index: int) -> SlotState:
	if index < 0 or index >= _states.size():
		return SlotState.DISABLED
	return _states[index]


## 下方第 `index` 块里放着什么。
func slot_block(index: int) -> String:
	if index < 0 or index >= _tray.size():
		return ""
	return _tray[index]


## 摆一个选项块的状态。四种状态各对应素材包里的一张图。
##
## **只影响「能不能拖」和外观** —— 禁用状态在上面四种里是"拖不动"那档。
func set_slot_state(index: int, state: SlotState) -> void:
	if index < 0 or index >= _states.size():
		return
	_states[index] = state
	_refresh()


## `if` 后面现在放着的那块。
func if_block() -> String:
	return _if_block


## 往 `if` 后面放一块（不经过拖动）。剧本开场摆位用。
func set_if_block(text: String) -> void:
	_if_block = text
	_refresh()


## 往 `then` 里放一块（不经过拖动）。剧本开场摆位用。
func set_then_block(text: String) -> void:
	_then = text
	_refresh()


## 往下方某一块里放东西（不经过拖动）。剧本开场摆位用。
##
## 空字符串 = 这个位置空着。**空了照样画方块**（禁用态的图），
## 不然玩家看不出「这儿本来能放东西」。
func set_slot_block(index: int, text: String) -> void:
	if index < 0 or index >= _tray.size():
		return
	_tray[index] = text
	_refresh()


## **把某一块搬到 `then` 上，不经过鼠标。** 测试和「自动演示」用。
##
## 和拖动走的是同一条路（`_swap_with_then`）—— 两套逻辑会分叉，
## 所以只有这一个入口。
func move_to_then(from_index: int) -> bool:
	return move_to_slot(from_index, FROM_THEN)


## **把下面某一格搬到某个块位上**（`FROM_THEN` 或 `FROM_IF`），不经过鼠标。
##
## 拖动和测试都走这一条 —— 两套逻辑迟早分叉，所以只留一个入口。
func move_to_slot(from_index: int, kind: int) -> bool:
	# **只读的框搬不动** —— 连两个块位里的块也不许动（纯展示就该是死的）
	if _read_only:
		return false
	if from_index < 0 or from_index >= _tray.size():
		return false
	if _tray[from_index] == "" or _states[from_index] == SlotState.DISABLED:
		return false
	_swap_slots(from_index, kind)
	_refresh()
	arranged.emit()
	return true


## 视口多大。取自项目设置里那个固定值（理由同别的界面：
## `--script` 模式下 viewport 取不准）。
func _view_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0)))


## 框的矩形（游戏单位）。所有内部位置都从它算，改尺寸只改 `BOX_SIZE`。
func box_rect() -> Rect2:
	return Rect2((_view_size() - BOX_SIZE) * 0.5, BOX_SIZE)


## 分隔线的两个端点。
func divider_points() -> PackedVector2Array:
	var box := box_rect()
	var y := box.position.y + box.size.y * DIVIDER_RATIO
	return PackedVector2Array([
		Vector2(box.position.x + PAD.x, y),
		Vector2(box.end.x - PAD.x, y),
	])


## 第 `index` 个选项块的位置（左上角）。
##
## 四个块在分隔线下面**横向均匀铺开**：两边各留 PAD，剩下的宽度减去
## 四块和三个间距，格子再均分，块居中在自己的格子里。框宽改了这儿不用动。
func slot_position(index: int) -> Vector2:
	var box := box_rect()
	# **右边要给「确定」让出位置**，四格整体往左收
	var usable := box.size.x - PAD.x * 2.0 - SLOT_GAP * 3.0 \
		- CONFIRM_SIZE.x - SLOT_GAP
	var step := usable / 4.0
	var x := box.position.x + PAD.x + step * float(index) + (step - SLOT_SIZE) * 0.5
	var top := box.position.y + box.size.y * DIVIDER_RATIO
	var bottom := box.end.y - PAD.y
	var y := (top + bottom - SLOT_SIZE) * 0.5
	return Vector2(x, y)


func _refresh() -> void:
	if _frame == null:
		return
	var box := box_rect()
	_frame.position = box.position
	_frame.size = box.size
	for i: int in _tray_nodes.size():
		_place_block(_tray_nodes[i], _tray[i], slot_position(i), i)
	_layout_text()
	_place_block(_if_nodes, _if_block, _slot_at(FROM_IF), FROM_IF)
	_place_block(_then_nodes, _then, _slot_at(FROM_THEN), FROM_THEN)
	if _confirm != null:
		var rect := confirm_rect()
		_confirm.position = rect.position
		_confirm.size = rect.size
		_confirm.visible = _open
		_confirm_label.position = Vector2.ZERO
		_confirm_label.size = rect.size
	queue_redraw()

	# **补一遍布局。**
	#
	# 第一次进来的时候字体可能还没就绪，`Label.get_minimum_size()` 拿到的是错的
	# 宽度 —— 表现是框里那行字**往下偏**，出去再进来一次就正了
	#（2026-09-25 策划报的：「加载进入时框内文字有可能会往下偏，
	# 已知再加载一次文字能回到正确位置上」）。
	#
	# 得等下一帧，所以 `call_deferred`。**只补一次** —— `_relayout_done`
	# 挡住第二次，否则 `_refresh` 里再调 `_refresh` 就是无限循环。
	if _open and not _relayout_done:
		_relayout_done = true
		_refresh.call_deferred()


## 悬停时描边和字都提亮 —— 和选项块的悬停是同一个意思。
func _sync_confirm_color() -> void:
	if _confirm == null:
		return
	var edge := CONFIRM_EDGE_HOVER if _confirm_hover else CONFIRM_EDGE
	var style := _confirm.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		(style as StyleBoxFlat).border_color = edge
	if _confirm_label != null:
		_confirm_label.add_theme_color_override("font_color", edge)


## `if` / `then` 那两个块位的位置（用 `FROM_IF` / `FROM_THEN` 取）。
## `_layout_text()` 算好后放进 `_blank_at`，摆块和命中判定都来这儿拿。
func _slot_at(kind: int) -> Vector2:
	var index := 0 if kind == FROM_IF else 1
	return _blank_at[index] if _blank_at.size() > index else Vector2.ZERO


## 摆一块：方块 + 下方名字。
##
## `index >= 0` 时用它自己的状态图；`index < 0`（`then` 那块）**永远画常态** ——
## `then` 里放的是"当前结果"，不是"选项列表里的一项"。
func _place_block(nodes: Dictionary, text: String, at: Vector2, index: int) -> void:
	var block: TextureRect = nodes["block"]
	var label: Label = nodes["label"]
	if at == Vector2.ZERO:
		block.visible = false
		label.visible = false
		return
	block.visible = _open
	label.visible = _open

	# 用哪张图由 `block_state()` 说了算（那儿写了四种各自的用法）
	var state := block_state(index)

	var path := SLOT_TEXTURES[int(state)]
	block.texture = load(path) if ResourceLoader.exists(path) else null
	block.position = at
	block.size = Vector2(SLOT_SIZE, SLOT_SIZE)

	var shown := text if text != "" else ""
	label.text = shown
	# **名字摆在方块正中**（理由见 `BLOCK_LABEL_SIZE` 那段）
	label.position = at
	label.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	label.visible = _open and shown != ""


## 摆 if / then 那一行：五段横排，整体居中。
##
## **`then` 那格永远留出 `SLOT_SIZE`**（哪怕填了东西）—— 它是一个**块位**，
## 宽度得和下面那几块一样，拖上去才看得出"填进那个洞了"。
## `if` 那格是固定文字，宽度跟字走。
##
## **宽度问 `Label.get_minimum_size()` 要**，别拿「字数 × 字号」估：
## 中文一字的宽度不等于字号，估小了字会从左边溢出去（踩过一次）。
func _layout_text() -> void:
	var box := box_rect()
	var y := box.position.y + box.size.y * DIVIDER_RATIO * 0.5

	# 五段：固定 / if 位 / 固定 / then 位 / 固定
	#
	# **两格都是块位**（2026-09-25 起 `if` 后面也能摆块）。
	# 老数据只给了 `condition` 文字、没给块，那就把文字摆在 if 位上兜底。
	var texts_full: Array[String] = []
	for i: int in 5:
		if i % 2 == 0:
			texts_full.append(SEG_FIXED[i / 2])
		elif i == 1:
			texts_full.append("" if _if_block != "" else _condition)
		else:
			texts_full.append("")      # 第 3 段（then）由块占位

	# **先把文字全设进去，再问宽度。**
	#
	# `get_minimum_size()` 是照着 Label **当前**的 `text` 算的 —— 先问后设的话
	# 拿到的是空的（或上一帧的），摆出来的位置整个错位：
	# 引号会跑进方块里、最后一段直接看不见（2026-09-24 踩的）。
	for i: int in 5:
		_segs[i].text = texts_full[i]

	var widths: Array[float] = []
	for i: int in 5:
		if i % 2 == 0:
			widths.append(_segs[i].get_minimum_size().x)
		elif i == 1 and _if_block == "":
			# if 位没摆块：老数据那串固定文字（至少留一个块位那么宽）
			widths.append(maxf(SLOT_SIZE + 4.0, _segs[i].get_minimum_size().x))
		else:
			# 两个块位：和下面那几块同宽，拖上去才看得出「填进那个洞了」
			widths.append(SLOT_SIZE + 4.0)

	var total := 0.0
	for w: float in widths:
		total += w
	var cursor := box.get_center().x - total * 0.5

	_blank_at.clear()
	for i: int in 5:
		var h := _segs[i].get_minimum_size().y
		_segs[i].position = Vector2(cursor, y - h * 0.5)
		_segs[i].size = Vector2(widths[i], h)
		# **只给两个值位各记一个块位锚点**（固定段不记！）。
		#
		# 2026-09-25 踩过：原来每个 i 都 `append`（固定段塞 `ZERO`），
		# `_blank_at` 变成 5 个元素，而 `_slot_at()` 按「第 0 个是 if、
		# 第 1 个是 then」去取 —— 取到的是两个 `ZERO`，
		# 于是两个块全被当成「没位置」藏起来，框里只剩两个虚线洞。
		if i % 2 == 1:
			_blank_at.append(Vector2(cursor + 2.0, y - SLOT_SIZE * 0.5))
		cursor += widths[i]


## 填空方块的位置。`_layout_text()` 算好后放在这儿，画的时候来取。
func blank_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for at: Vector2 in _blank_at:
		if at != Vector2.ZERO:
			out.append(at)
	return out


# ---------------------------------------------------------------- 拖动

## 鼠标按下 / 移动 / 松开都走这儿。
##
## **放开之后一律发 `arranged`** —— 哪怕原地放回（数据没变）。剧本等的是
## 「玩家做过一次动作」，不是「数据变了没有」；漏发的话教学那段会卡住。
func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			# **「确定」优先判** —— 它压在四格右边，判定排前面免得被拖动抢走
			if confirm_rect().has_point(mb.position):
				confirmed.emit()
				accept_event()
				return
			_begin_drag(mb.position)
		elif not _drag.is_empty():
			_end_drag(mb.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if not _drag.is_empty():
			_drag["at"] = mm.position
			_move_dragged_visual()
			accept_event()
			return
		var hover := confirm_rect().has_point(mm.position)
		if hover != _confirm_hover:
			_confirm_hover = hover
			_sync_confirm_color()


## 「确定」按钮的矩形：框内右下角，**竖着和四个选项块一条线**。
##
## 原来 y 是贴框底算的（`box.end.y - PAD.y`），而四格是垂直居中的 ——
## 结果按钮歪在格子下面一截（2026-09-25 策划指出来的）。这里和
## `slot_position()` 用同一个 y。
func confirm_rect() -> Rect2:
	var box := box_rect()
	var top := box.position.y + box.size.y * DIVIDER_RATIO
	var bottom := box.end.y - PAD.y
	var row_y := (top + bottom - SLOT_SIZE) * 0.5
	return Rect2(
		Vector2(box.end.x - CONFIRM_RIGHT_PAD - CONFIRM_SIZE.x,
			row_y + (SLOT_SIZE - CONFIRM_SIZE.y) * 0.5),
		CONFIRM_SIZE)


func _begin_drag(at: Vector2) -> void:
	# **只读的框拖不动**（纯展示那种）：连两个块位里的块也不许拽走。
	if _read_only:
		return
	# 两个块位里的那块都能拖出来（拖回下面）—— 「被顶掉的那块自动回到原本位置」
	# 是拖动本身的规则，反过来也成立。
	if _then != "" and _hit(_slot_at(FROM_THEN), at):
		_drag = {"from": FROM_THEN, "at": at, "grab": at - _slot_at(FROM_THEN)}
		return
	if _if_block != "" and _hit(_slot_at(FROM_IF), at):
		_drag = {"from": FROM_IF, "at": at, "grab": at - _slot_at(FROM_IF)}
		return
	for i: int in _tray.size():
		if _tray[i] == "" or _states[i] == SlotState.DISABLED:
			continue
		if _hit(slot_position(i), at):
			_drag = {"from": i, "at": at, "grab": at - slot_position(i)}
			return


func _end_drag(at: Vector2) -> void:
	var from: int = int(_drag["from"])
	_drag.clear()
	# 落在哪个块位上，就和那块换位置
	for kind: int in [FROM_IF, FROM_THEN]:
		if _hit(_slot_at(kind), at):
			_swap_slots(from, kind)
			_refresh()
			arranged.emit()
			return
	var to := _slot_hit(at)
	if to >= 0 and from >= 0 and to != from:
		var held := _tray[from]
		_tray[from] = _tray[to]
		_tray[to] = held
	_refresh()
	arranged.emit()


## 把某一块搬到某个块位上：**和那块换位置**。
##
## 被顶掉的那块回到拖出来那一格 —— 策划要的「自动回到原本位置」就是这么来的。
## 从一个块位拖到另一个块位，就是两个块位对调。
func _swap_slots(from: int, kind: int) -> void:
	if from >= 0:
		var brought := _tray[from]
		_tray[from] = current_slot(kind)
		set_slot_value(kind, brought)
		return
	if from == kind:
		return
	var held := current_slot(from)
	set_slot_value(from, current_slot(kind))
	set_slot_value(kind, held)


## 某个块位上现在放着什么（用 `FROM_IF` / `FROM_THEN` 取）。
func current_slot(kind: int) -> String:
	return _if_block if kind == FROM_IF else _then


func set_slot_value(kind: int, text: String) -> void:
	if kind == FROM_IF:
		_if_block = text
	else:
		_then = text


## **只读**：纯展示的框。
##
## 挡的是拖动 —— 连两个块位里的块也不许拽走。2026-09-25 策划说的：
## 老人那框两块是固定的，但当时还能左右对调，对调完照样往下演。
func set_read_only(value: bool) -> void:
	_read_only = value


func is_read_only() -> bool:
	return _read_only


## 某一格现在该用**哪张图**（`SlotState`）。
##
## **四种图各司其职**（2026-09-25 策划专门重新明确过，值得钉住）：
##
##   禁用 = 空着、不能用的格子
##   常态 = 待选列表里能拿的块
##   选中 = 已经放到位置上的（`if` / `then` 那两格）
##   悬停 = 正在被拖着走的（在 `_move_dragged_visual()` 里换）
##
## `index >= 0` 是下面四格；`FROM_IF` / `FROM_THEN` 是两个块位。
## **显示逻辑抽出来就是为了能断言** —— 原来埋在 `_place_block()` 里，测不到。
func block_state(index: int) -> SlotState:
	if index < 0:
		return SlotState.ACTIVE if current_slot(index) != "" else SlotState.DISABLED
	if _tray[index] == "":
		return SlotState.DISABLED
	return SlotState.NORMAL


## 按确定时这一下算哪种结果。见 `Verdict`。
##
## `solve` 是剧本要的答案（`then` 位该是什么）；空字符串表示这一步没有答案（纯展示）。
##
## **只有两种组合是合规的**（2026-09-25 策划明确）：
##
##     if 发现异常 then 观察        ← 没改，等于没听懂 → 走「又一遍」
##     if 发现异常 then 立即离开     ← 改对了 → 过关
##
## 其余一律算排错，**块丢回原处重排**。
##
## **`if` 位必须一直是开局那个值。** 第一版只判了 `then` ——
## 于是把「立即离开」拖到 `if` 上、`then` 没动，照样能蒙混过去
##（策划试出来的：「把立即离开填到 if 框也能过关」）。
func judge(solve: String) -> Verdict:
	if _if_block != _initial_if:
		return Verdict.WRONG
	if solve != "" and _then == solve:
		return Verdict.SOLVED
	if _then == _initial_then:
		return Verdict.UNTOUCHED
	return Verdict.WRONG


## 把块全部丢回开局的位置。
##
## 玩家排出预设之外的组合、又按了确定时用它 —— 让他重新排（2026-09-25 策划要的）。
## 回到的是 `open()` 那一刻那套摆法，`_initial_*` 记着。
func reset_blocks() -> void:
	_tray = _initial_tray.duplicate()
	_if_block = _initial_if
	_then = _initial_then
	_refresh()


func _hit(top_left: Vector2, at: Vector2) -> bool:
	return Rect2(top_left, Vector2(SLOT_SIZE, SLOT_SIZE)).has_point(at)


func _slot_hit(at: Vector2) -> int:
	for i: int in _tray.size():
		if _hit(slot_position(i), at):
			return i
	return -1


## 拖动中：让被拖的那块（方块 + 名字）跟着鼠标走。
func _move_dragged_visual() -> void:
	var from: int = int(_drag["from"])
	var grab: Vector2 = _drag.get("grab", Vector2(SLOT_SIZE, SLOT_SIZE) * 0.5)
	var nodes: Dictionary = _tray_nodes[from]
	if from == FROM_THEN:
		nodes = _then_nodes
	elif from == FROM_IF:
		nodes = _if_nodes
	var block: TextureRect = nodes["block"]
	var label: Label = nodes["label"]
	# 拖着走的时候用「悬停」那张图（策划明确的状态用法）
	var hover_path := SLOT_TEXTURES[int(SlotState.HOVER)]
	if ResourceLoader.exists(hover_path):
		block.texture = load(hover_path)
	var at: Vector2 = _drag["at"] - grab
	block.position = at
	label.position = at


# ---------------------------------------------------------------- 画

## 分隔线 + 填空方块。
##
## **画的，不贴素材**：这两样没有对应的图，而且线宽、虚线间隔都得跟着
## 框的大小走 —— 画出来的在任何分辨率下都干净（规矩见开发纪要 53.9）。
func _draw() -> void:
	if not _open:
		return
	var line := divider_points()
	draw_line(line[0], line[1], DIVIDER_COLOR, 1.4)
	for at: Vector2 in _blank_at:
		_draw_blank(at)


## 一个虚线方块：示意「这儿可以填东西进来」。
##
## **尺寸和形状都照选项块来**（`SLOT_SIZE` + 同一个切角比例）——
## 玩家看到的应当是「下面那块能拖进这个洞」，大小不一样就看不出来了。
##
## 虚线是拿几段短横拼的：没有对应的素材，而且间隔得跟着框走。
func _draw_blank(at: Vector2) -> void:
	var s := SLOT_SIZE
	var cut := s * SLOT_CUT_RATIO
	var p := at
	var e := at + Vector2(s, s)
	var pts := PackedVector2Array([
		p + Vector2(cut, 0.0), Vector2(e.x - cut, p.y),
		Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y),
		Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut),
	])
	var dash := 4.0
	for i: int in pts.size():
		var from := pts[i]
		var to := pts[(i + 1) % pts.size()]
		var span := from.distance_to(to)
		var dir := from.direction_to(to)
		var walked := 0.0
		while walked < span - 0.01:
			var seg := minf(dash * 0.6, span - walked)
			draw_line(from + dir * walked, from + dir * (walked + seg),
				BLANK_COLOR, 1.2)
			walked += dash
