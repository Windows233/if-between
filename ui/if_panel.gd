## IF 条件框：画面正中那个「if "…" then "…"」加一排选项块。
##
## 版式照策划那份示意：
##
##     ┌──────────────────────────────────┐
##     │   if "▢" then "▢"                │   ← 条件 / 结果
##     │   ──────────────────────────     │   ← 分隔线
##     │   [块] [块] [块] [块]             │   ← 四个选项块，横向铺开
##     └──────────────────────────────────┘
##
## 框底是素材包里的「悬浮框_透明度72」（1048x568）。九宫格参数见常量 ——
## **四角 96、四条边 6**，别把四个方向写成一样（上下各 96、加起来 192
## 超过框高，边框会塌成一堆菱形，这个坑踩过）。
##
## 「条件填空处」现在**没有美术素材**，所以按策划说的画一个**虚线方块**
## 示意「这儿可以拖选项块进来」。
##
## 选项块四种状态（常态 / 悬停 / 选中 / 禁用）用的是素材包里那套，
## 各一张 214x214 的图。**这一版是「标准状态」**：四块都是常态。
##
## **层号由外面那层 `CanvasLayer` 给**（`main` 里套的），这个类自己是个
## `Control`。之前试过让本类直接 `extends CanvasLayer`、里面再开一个内层类
## 负责画 —— 那个内层类的 `_draw()` 不肯跑，分隔线和虚线方块一个都没出来。
## 别绕那一圈：**`_draw` 就写在能用它的那个类上**。
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
## 框显示多大（游戏单位）。**比例必须和素材一致**（1048:568 ≈ 1.845），
## 不然整张缩放会把它压扁。
##
## **为什么不用九宫格**：素材的四角要 96 源像素才成形，上下各 96 就是 192 ——
## 而这个游戏的视口只有 180 高，框高不可能超过它。九宫格在这儿装不下，
## 硬上会像 2026-09-24 那次一样，上下边被挤成一堆菱形。
## 好在**比例正好一致**，整张等比缩放不变形，只是描边会软一点。
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
## 尺寸直接引用 `SLOT_SIZE`，不另写一个数 —— 策划说的「虚线框的大小应该能和
## 选项框重合」就是这个意思：玩家得一眼看出「下面那几块能拖进这个洞」。
## 切角比例也照选项块素材来（切角 24 / 方块 170）。
const SLOT_CUT_RATIO := 0.14

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


var _frame: TextureRect = null
## if / then 那行的五段文字，按顺序摆。中间两段（下标 1、3）是**值** ——
## 没填的时候那儿画虚线方块，填了就显示填进去的字。
var _segs: Array[Label] = []
## 两个填空方块的位置，`_layout_text()` 算出来的，画的时候来取。
var _blank_at: Array[Vector2] = []
var _slots: Array[TextureRect] = []
var _states: Array[SlotState] = []
var _condition := ""
var _result := ""
var _open := false


func _ready() -> void:
	setup()


## 抽成显式方法，理由同别的界面：`--script` 模式下 `add_child` 不触发 `_ready`。
## 重复调用安全。
func setup() -> void:
	if _frame != null:
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	# if / then 那行**拆成五段**：中间夹着两处填空（方块 / 填进去的字），
	# 拼成一个字符串的话方块就插不进字中间了。
	for i: int in 5:
		_segs.append(_make_label(11))
	for i: int in 4:
		var slot := TextureRect.new()
		slot.name = "Slot%d" % i
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_SCALE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
		_slots.append(slot)
		_states.append(SlotState.NORMAL)

	visible = false


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


## 打开 / 收起。不带参数 = 标准状态（填空处空着、四块常态）。
func open(p_condition: String = "", p_result: String = "") -> void:
	setup()
	_condition = p_condition
	_result = p_result
	_open = true
	visible = true
	_refresh()


func close() -> void:
	setup()
	_open = false
	visible = false


func is_open() -> bool:
	return _open


## 现在填的条件 / 结果。空字符串表示还没填。
func condition_text() -> String:
	return _condition


func result_text() -> String:
	return _result


func slot_count() -> int:
	return _slots.size()


func slot_state(index: int) -> SlotState:
	if index < 0 or index >= _states.size():
		return SlotState.DISABLED
	return _states[index]


## 摆一个选项块的状态。四种状态各对应素材包里的一张图。
func set_slot_state(index: int, state: SlotState) -> void:
	if index < 0 or index >= _states.size():
		return
	_states[index] = state
	_sync_slot(index)


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
	var usable := box.size.x - PAD.x * 2.0 - SLOT_GAP * 3.0
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
	for i: int in _slots.size():
		_slots[i].position = slot_position(i)
		_slots[i].size = Vector2(SLOT_SIZE, SLOT_SIZE)
		_sync_slot(i)
	_layout_text()
	queue_redraw()


## 第 `index` 块该用哪张图。
func _sync_slot(index: int) -> void:
	var slot := _slots[index]
	var path := SLOT_TEXTURES[int(_states[index])]
	slot.texture = load(path) if ResourceLoader.exists(path) else null


## 摆 if / then 那一行：五段横排，整体居中。
##
## 中间两段是**值**：空着就留出 `SLOT_SIZE` 给虚线方块，填了就把文字摆上、
## 宽度跟着字走。
##
## **宽度问 `Label.get_minimum_size()` 要**，别拿「字数 × 字号」估：
## 中文一字的宽度不等于字号，估小了字会从左边溢出去（踩过一次）。
func _layout_text() -> void:
	var box := box_rect()
	var y := box.position.y + box.size.y * DIVIDER_RATIO * 0.5
	var values: Array[String] = [_condition, _result]

	# 五段：固定 / 值 / 固定 / 值 / 固定
	var texts: Array[String] = []
	for i: int in 5:
		texts.append(SEG_FIXED[i / 2] if i % 2 == 0 else values[(i - 1) / 2])

	# **先把文字全设进去，再问宽度。**
	#
	# `get_minimum_size()` 是照着 Label **当前**的 `text` 算的 —— 先问后设的话
	# 拿到的是空的（或上一帧的），摆出来的位置整个错位：
	# 引号会跑进方块里、最后一段直接看不见（2026-09-24 踩的）。
	for i: int in 5:
		_segs[i].text = texts[i]

	var widths: Array[float] = []
	for i: int in 5:
		if i % 2 == 0 or texts[i] != "":
			widths.append(_segs[i].get_minimum_size().x)
		else:
			# 没填的那一段：留出虚线方块的地方
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
		if i % 2 == 1 and texts[i] == "":
			_blank_at.append(Vector2(cursor + 2.0, y - SLOT_SIZE * 0.5))
		cursor += widths[i]


## 填空方块的位置。`_layout_text()` 算好后放在这儿，画的时候来取。
func blank_positions() -> Array[Vector2]:
	return _blank_at


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

