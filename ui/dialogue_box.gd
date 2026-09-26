## 对话框：屏幕下三分之一的一块深色面板，里面站着立绘、写着名字和正文。
##
## ## 版式（2026-09-23 按稿子定的）
##
## ```
## ┌─────────────── 屏幕 320 ───────────────┐
## │                    场景                 │
## ├──────────┬────────────────┬───────────┤
## │ 主角立绘  │   名字 / 正文   │ 其他立绘   │  ← 面板高 = 屏幕 1/3
## │（贴左沿） │  （左端对齐）   │（贴右沿）  │
## └──────────┴────────────────┴───────────┘
## ```
##
## 三条规矩的来源是文档里那句「主角立绘在方框左侧…其他人物立绘统一在方框
## 右侧，文字在中间」。所以**立绘在面板里面**，正文那一列固定 148 宽。
##
## 一屏一屏放的是 `Dialogue` 里的行。一次交互 = 一段对话，
## 所以「自动放下一句」和「跳过这一段」才有操作对象。
##
## 立绘那一块（摆放、滑入、呼吸、换表情）在 `ui/dialogue_portrait.gd`，
## **不在这里** —— 以前混在一起，这个文件到过 607 行。
##
## 挂 CanvasLayer，不受相机影响。布局用绝对坐标，分辨率固定 320x180。
class_name DialogueBox
extends CanvasLayer

## 整段对话放完时发出。外面据此做「对话结束后继续做什么」。
signal finished
## 某一行的 `shake` 大于 0，这一行开始显示时报一下。**谁去摇镜头不归它管** ——
## `main` 接这个信号去摇相机（对话框不认识相机，也不该认识）。
signal shook(strength: float)

const MARGIN := 8.0

## 面板高度**随正文行数浮动**，上下限在下面「框贴图」那一节里 ——
## 那两个数现在是跟着**面板贴图**推出来的，不再写死在这儿。
## 一行的高度。字号 10，行距按这个算。
const LINE_HEIGHT := 13.0
## 正文区之外的固定开销：名字行 + 上下留白
const BOX_EXTRA := 30.0

## 面板**里面**两侧各留给立绘的带子有多宽，以及正文跟带子之间留多少空。
##
## 数值要跟 `DialoguePortrait.BOX_WIDTH` 一致。这里写字面值而不是引用它 ——
## 常量里引用别的类的常量，解析器不认（试过，报的是找不到标识符）。
const PORTRAIT_WIDTH := 70.0
const PORTRAIT_GAP := 6.0

## ---- 框贴图（2026-09-25 换的真美术）----
##
## 两张都是 1584x435，由 `tools/make_dialog_frames.gd` 从「对话框/」里那两张
## **没有透明通道**的原图抠出来的。left 给主角用（名字标签在左上），
## right 给其他角色用（标签在右上）。
const FRAME_LEFT := "res://art/ui/dialog_frame_left.png"
const FRAME_RIGHT := "res://art/ui/dialog_frame_right.png"
const FRAME_TEX_W := 1584.0
const FRAME_TEX_H := 435.0

## **贴图里实体面板那一块**（贴图像素，x/y/宽/高）。
##
## 名字标签挂在面板**上面**、花饰挂在**下面**，两个都是伸出面板外的装饰。
## 所以布局必须围着**实体面板**算 —— 早先把整张贴图的高度当成面板高度，
## 面板就被压扁了：立绘探出框外、正文和名字都对不上，三个毛病同一个原因。
const BODY_TEX := Rect2(7.0, 22.0, 1554.0, 389.0)

## 面板内容区的四条内沿（绝对贴图像素）。框线往里让开这么多才是能放东西的地方。
const INNER_LEFT_TEX := 22.0
const INNER_TOP_TEX := 45.0
const INNER_RIGHT_TEX := 1545.0
const INNER_BOTTOM_TEX := 395.0

## 九宫格的四条切边（贴图像素）。**名字标签必须整个落在不拉伸的那块角里**，
## 花饰同理；否则横向拉伸时标签会被压扁、花饰会走形。
## 左右两张是镜像的，所以两边的左右切边数值互换了。
const PATCH_LEFT_LEFT := 690.0
const PATCH_LEFT_RIGHT := 215.0
const PATCH_RIGHT_LEFT := 215.0
const PATCH_RIGHT_RIGHT := 690.0
const PATCH_TOP := 52.0
const PATCH_BOTTOM := 45.0

## 名字标签在贴图里的位置（贴图像素，左上为原点）。名字要摆进这块里 ——
## 它是**跨在面板上沿**上的一个凸起，比内容区还高，所以单独给一块矩形。
const TAB_LEFT := Rect2(238.0, 6.0, 444.0, 46.0)
const TAB_RIGHT := Rect2(902.0, 6.0, 408.0, 46.0)

## 正文那一列最少要多宽。窄到两三个字就换行的话，长台词会把面板撑爆 ——
## `test_presentation` 里那条「正文不窄于 120」守的就是它。
## 多写 1 像素是给浮点留余量（下面那个式子是乘加出来的，正好等于 120 时
## 可能算出 119.999…，那条断言就假红）。
const TEXT_MIN_WIDTH := 121.0

## 框的高和宽（逻辑像素）。**高度指的是实体面板的高度**，
## 不含上面凸出来的名字标签、也不含下面挂着的花饰。
##
## 下限从 60 抬到 72 是这次修的重点：60 的时候面板内容区只剩 48 高，
## 立绘整条腿都在框外面。72 起内容区有 65 上下，立绘装得进；
## 名字标签也跟着涨到 8.5 高，8 号字的名字正好待在里面。
const BOX_MIN_HEIGHT := 72.0
const BOX_MAX_HEIGHT := 92.0

## 框宽。**固定铺满屏幕**（320 减左右边距），不跟着文字长短缩 ——
## 人类 2026-09-26 明确说了：要的是「**文字的排版自动对齐对话框**」，
## 不是「把对话框缩短去凑文字」。我先前把「长度自适应文字」读成了后者，撤掉。
const BOX_MAX_WIDTH := 320.0 - MARGIN * 2.0

## 名字那一号字。比正文（10）小一号 —— 名字标签只有 9 上下高，再大就冒出去了。
const NAME_FONT_SIZE := 8
## 按钮条离框内沿再往里收一点（逻辑像素），别贴着框线。
const BUTTONS_INSET := 4.0

## 主角的名字在框上显示成什么。
##
## 数据里主角的 `speaker` 写的是「我」，但框上要显示「主角」——
## 这是**显示层的映射，不动 `data/`**（改数据等于改剧情内容，还会连带
## 影响对话记录面板）。判定见 `_is_protagonist()`。
const PROTAGONIST_LABEL := "主角"
const PROTAGONIST_SPEAKERS: Array[String] = ["我", "主角"]
const PROTAGONIST_PORTRAIT_PREFIX := "protagonist"

## 自动模式下，一句显示完之后停多久
const AUTO_DELAY := 1.6

## 正文那一号字。**数据里的 `size_delta` 是加在它上面的**（+2 就是大两号）。
## 想整体调字号就在这儿改，别去改数据。
const FONT_SIZE := 10

## 等玩家选选项时面板撑到多高。
##
## 选项框现在**浮在面板上方**（`ChoiceMenu.open_above()`），不占面板里面，
## 所以这里就取最小高度 —— 两个人站在框里，留个空面板当背景。
const CHOICE_BOX_HEIGHT := BOX_MIN_HEIGHT

const TEXT_COLOR := Color("#eaeaea")
const NAME_COLOR := Color("#e8c07a")
const HINT_COLOR := Color("#8a9a8e")

var _root: Control
var _frame: NinePatchRect
var _name: Label
var _label: Label
## 只用来量「这段文本会占几行」的隐藏标签，不显示。
## 用它是因为逐字显示时 `_label.text` 是半句话，量出来的行数会跳。
var _measure: Label
## 底部按钮条：自动 / 记录 / 跳过。摆放与命中判定都在它那里。
var _buttons: DialogueButtons
var _slots: Array[DialoguePortrait] = []
var _log: DialogueLog

var _dialogue: Dialogue = null
var _index := -1
var _open := false
## 当前面板高度。按这一行的行数算，见 `_update_box()`。
var _box_height := BOX_MIN_HEIGHT
## 当前面板宽度。按这段对话里最长的一句算，见 `_update_box()`。
var _box_width := BOX_MAX_WIDTH
## 这一句是谁说的 —— 决定用哪张框（left/right）、框贴屏幕哪一边。
## 数据里 `DialogueLine.side` 已经把主角标成 LEFT、其他人标成 RIGHT。
var _box_side := DialogueLine.Side.LEFT

## 这一段播完**不收起面板**，留在场上等玩家选选项。
## 由 `play()` 的第二个参数决定 —— 对话框自己不认识选项，
## 是导演在「这个节点有 options」时告诉它的。
var _hold_at_end := false
## 播完**留着面板**（最后一句原地不动）。给「台词还在说、右上角弹了个提示」
## 那种场合用 —— 提示不该把正在说的话抹掉。
## 和 `_hold_at_end` 的区别：那个是转成「等选择」，这个什么都不做，只是不收。
var _keep_at_end := false
## 现在正处在「等选择」的状态：面板留着、正文清空、立绘留着。
var _holding := false

## 当前这一行的字号。默认就是正文那号，`size_delta` 会在 `_show_line` 里加。
var _line_size := FONT_SIZE
var _auto := false
var _auto_timer := 0.0
## 逐字显示进度，单位是「字符数」，做成浮点方便按速度累加
var _reveal := 0.0
var _revealing := false
## 呼吸动效的相位，只在这里累加
var _breath_time := 0.0
## 打字速度（字/秒）。由设置改，默认见 `GameSettings`。
var _speed := GameSettings.DEFAULT_SPEED


func _ready() -> void:
	setup()


## 建界面。抽成显式方法，理由同 main.gd 的 boot()：
## `--script` 模式下 add_child 不会触发 `_ready`，测试得能自己调。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	layer = 10

	_root = Control.new()
	_root.name = "Root"
	# 用 STOP 而不是 IGNORE：要靠 gui_input 拿到视口坐标下的点击位置，
	# 自己判断点到了按钮还是正文。Control 会自动做窗口坐标到本地坐标的换算。
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_gui_input)
	add_child(_root)

	_frame = NinePatchRect.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 中间那块拉伸，四角保持原尺寸 —— 名字标签和花饰都在角里，所以不走形。
	_frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	_frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	_set_frame_side(DialogueLine.Side.LEFT)
	_root.add_child(_frame)

	# 立绘站在面板**里面**，所以**必须建在面板之后** ——
	# 同层节点按加入顺序画，先加的被后加的盖住。早先立绘画在面板上方，
	# 顺序无所谓；搬进框里之后顺序反了就是「面板一片空、人像看不见」。
	_slots.append(DialoguePortrait.create(self, _root, DialogueLine.Side.LEFT))
	_slots.append(DialoguePortrait.create(self, _root, DialogueLine.Side.RIGHT))

	_name = Label.new()
	_name.name = "Name"
	_name.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name.add_theme_color_override("font_color", NAME_COLOR)
	_root.add_child(_name)

	_label = Label.new()
	_label.name = "Text"
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_root.add_child(_label)

	_measure = Label.new()
	_measure.name = "Measure"
	_measure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_measure.add_theme_font_size_override("font_size", FONT_SIZE)
	_measure.visible = false
	_measure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_measure)

	_buttons = DialogueButtons.create(_root)

	_log = DialogueLog.new()
	_log.name = "DialogueLog"
	add_child(_log)
	_log.setup()

	_root.visible = false
	_buttons.set_auto(false)


## 换成左款或右款框：贴图、九宫格切边、名字标签位置都要跟着换。
func _set_frame_side(side: DialogueLine.Side) -> void:
	_frame.texture = load(FRAME_RIGHT if side == DialogueLine.Side.RIGHT else FRAME_LEFT)
	if side == DialogueLine.Side.RIGHT:
		_frame.patch_margin_left = int(PATCH_RIGHT_LEFT)
		_frame.patch_margin_right = int(PATCH_RIGHT_RIGHT)
	else:
		_frame.patch_margin_left = int(PATCH_LEFT_LEFT)
		_frame.patch_margin_right = int(PATCH_LEFT_RIGHT)
	_frame.patch_margin_top = int(PATCH_TOP)
	_frame.patch_margin_bottom = int(PATCH_BOTTOM)
	# 缩放和位置都在 `_layout()` 里按当前框尺寸算（横向纵向比例是分开推的）。


## 当前这一侧名字标签在贴图里的位置。
func _tab_rect() -> Rect2:
	return TAB_RIGHT if _box_side == DialogueLine.Side.RIGHT else TAB_LEFT


## 这一句是不是主角说的。speaker 对得上（数据里写「我」）算，
## 立绘路径以 `protagonist` 开头也算 —— 两条都指向同一个人，多一条兜底。
func _is_protagonist(line: DialogueLine) -> bool:
	if PROTAGONIST_SPEAKERS.has(line.speaker):
		return true
	return line.portrait.begins_with(PROTAGONIST_PORTRAIT_PREFIX)


# ---------------------------------------------------------------- 播放

## 播一段对话。已经开着的话会被顶掉（重新开始）。
##
## `hold_at_end` 为真时，**最后一句播完不收面板**，转为「等选择」状态：
## 正文和名字清掉、高度固定、左右立绘留着，选项就摆在空出来的中间。
## 为什么由外面传而不是这里自己判断：对话框不认识剧情，也不该认识。
func play(dialogue: Dialogue, hold_at_end: bool = false,
		keep_at_end: bool = false) -> void:
	setup()
	if dialogue == null or dialogue.is_empty():
		return

	_holding = false
	_label.visible = true
	_buttons.set_visible(true)
	_dialogue = dialogue
	_hold_at_end = hold_at_end
	_keep_at_end = keep_at_end
	_index = -1
	_open = true
	_auto_timer = 0.0
	_root.visible = true
	_advance()


## 推进：正在逐字显示就先显示完，否则下一行。
func advance() -> void:
	if not _open or _holding:
		return
	if _log.is_open():
		_log.close()
		return
	if _revealing:
		_finish_reveal()
		return
	_advance()


## 跳过这一整段：剩下的行一次性记进历史，然后收尾。
func skip() -> void:
	if not _open or _holding or _dialogue == null:
		return
	var last := _dialogue.lines.size() - 1
	while _index < last:
		_index += 1
		_record(_dialogue.lines[_index])
	_finish()


## 把这一段**当成已经播完**摆出来：内容进历史、立绘照最后一行摆好，
## 然后按 `hold_at_end` 停在「等选择」上，或者收起来继续往下演。
##
## 读档专用。和 `skip()` 的差别在立绘：`skip()` 是玩家主动跳过，
## 那几行他根本没看，眨眼间立绘跳来跳去只会乱；这里是**还原** ——
## 玩家本来就看过，画面得对得上存档那一刻。
##
## 正文和名字**不显示**：存档时对话框正停在「等选择」，
## 那时候正文本来就是空的（`_begin_hold()` 会清掉）。
##
## 已经在历史里的行不重复记 —— 同一个进程里读档两次，历史不该变成两份。
func restore_played(p_dialogue: Dialogue, hold_at_end: bool = false) -> void:
	setup()
	if p_dialogue == null or p_dialogue.is_empty():
		return

	for line: DialogueLine in p_dialogue.lines:
		if not has_read(line):
			_record(line)

	_holding = false
	_hold_at_end = hold_at_end
	_dialogue = p_dialogue
	_open = true
	_root.visible = true
	_apply_portraits(p_dialogue.lines[p_dialogue.lines.size() - 1])
	_finish()


func close() -> void:
	if not _open:
		return
	# 收尾时不再留在场上等选择 —— 关掉就是关掉
	_hold_at_end = false
	_finish()


func is_open() -> bool:
	return _open


## 正等着玩家选选项吗。导演靠它决定「选项摆进对话框里还是单独弹一个面板」。
func is_holding() -> bool:
	return _holding


## 摆好两边的人，停在「等选择」的状态上。
##
## `cast` 形如 `{"left": {"speaker": "老人", "portrait": "elder"}}`，
## 没给的那一侧会收掉。**这一步不带台词** —— 面板空着留在场上，
## 选项由导演摆进 `hold_rect()`。
##
## 为什么不让 `play()` 兼职：`play()` 的语义是「念这一段」，
## 念完还要不要留着是另一回事。开场的照片那一段就是先收起、
## 放完照片再回来把两个人摆上 —— 中间夹着别的东西，硬塞进 play 会很别扭。
func hold_open(cast: Dictionary, animate: bool = true) -> void:
	setup()
	_hold_at_end = false
	_holding = true
	_dialogue = null
	_index = -1
	_revealing = false
	_auto_timer = 0.0
	_open = true
	_root.visible = true
	_label.text = ""
	_label.visible = false
	_name.text = ""
	_name.visible = false
	_buttons.set_visible(false)
	_box_height = CHOICE_BOX_HEIGHT
	# 等选择时正文清空了，框按最小宽度摆着当背景 —— 留着上一句的宽度
	# 会是一块空荡荡的大板子，后面选项框压上来更挤。
	_box_width = BOX_MAX_WIDTH

	for slot: DialoguePortrait in _slots:
		var key := "left" if slot.side == DialogueLine.Side.LEFT else "right"
		var raw: Variant = cast.get(key)
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			# 借 DialogueLine 解析一次：立绘路径的补全规则只写在那儿
			var line := DialogueLine.from_dictionary(raw)
			slot.show_speaker(line.speaker, line.portrait_path(), false)
		else:
			slot.hide()

	_layout()
	if animate:
		slide_in(0.24)


## 等选择时留给选项的那块地方。
##
## 2026-09-23 版式改了之后**选项不再摆进面板里** —— 面板只剩屏幕下三分之一，
## 里面还站着两个人，塞不下两行选项。现在选项框浮在面板上方（稿子③：
## 「选项框直接出现在对话框上方一点」），所以这里改成把面板上沿报出去。
func hold_top() -> float:
	setup()
	return _box_top()


## 整条对话层向下收起。演出里「先把对话收掉，再放别的东西」用。
##
## 收的是**整层**（面板加立绘一起往下走），不是只收面板 ——
## 只收面板的话立绘还杵在那儿，看着像收了半截。
func slide_out(time: float = 0.28) -> void:
	setup()
	if not _open:
		return
	if time <= 0.0:
		# 即时模式：不做动画，直接收掉。为 0 的补间也要等一帧，测试里等不到。
		_hold_at_end = false
		_finish()
		return
	var shift := _view_size().y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_root, "modulate:a", 0.0, time)
	tween.tween_property(_root, "position:y", shift, time)
	await tween.finished
	_hold_at_end = false
	_finish()
	_reset_root_transform()


## 从下面回来。跟在一句 `play()` 之后调用，和逐字显示同时进行。
##
## 不 await：它是「进来」的动效，不该拖住这句台词。
func slide_in(time: float = 0.24) -> void:
	setup()
	if not _open or time <= 0.0:
		return
	_root.position.y = _view_size().y * 0.12
	_root.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_root, "modulate:a", 1.0, time)
	tween.tween_property(_root, "position:y", 0.0, time)


func _reset_root_transform() -> void:
	if _root == null:
		return
	_root.modulate.a = 1.0
	_root.position.y = 0.0
	_layout()


## 收起「等选择」的面板。**不发 finished** ——
## 选了之后剧情要继续往下走，这时候再发一次会让导演把同一个节点走两遍。
func release_hold() -> void:
	if not _holding:
		return
	_hide_panel()


func is_auto() -> bool:
	return _auto


## 当前行的序号、说话人、文本。给测试与调试用。
func current_index() -> int:
	return _index


func current_speaker() -> String:
	return _name.text if _name != null else ""


func current_text() -> String:
	return _label.text if _label != null else ""


## 正在逐字显示吗。测试要靠它区分「推进」和「先显示完」两种状态。
func is_revealing() -> bool:
	return _revealing


## 当前面板高度。三行的台词比一行高，测试与调试用。
func box_height() -> float:
	return _box_height


## 某一侧当前挂着的立绘。没有图（退回占位色块）返回 null。
## 测试和调试用 —— 画面上分不出「载到图了」和「缺图退回色块」，得能问。
func slot_portrait(side: DialogueLine.Side) -> Texture2D:
	setup()
	for slot: DialoguePortrait in _slots:
		if slot.side == side:
			return slot.sprite.texture
	return null


## 给外面看的历史记录，测试和调试会用。
func log_panel() -> DialogueLog:
	setup()
	return _log


## 打字速度（字/秒）。由设置面板改，默认见 `GameSettings`。
func set_speed(value: float) -> void:
	_speed = maxf(8.0, value)


func speed() -> float:
	return _speed


## 这一行以前播过吗。跳过已读靠它 —— 已读判定用历史记录，
## 因为历史是全局累积的，同一个存档里第二次经过同一句也认得出来。
func has_read(line: DialogueLine) -> bool:
	if line == null or _log == null:
		return false
	return _log.has_seen(line.speaker, line.text)


## 按路径载立绘。**转发给 `DialoguePortrait`** —— 立绘归哪个类管是实现细节，
## 外面（以及测试）不该因为它搬了家就改调用。
static func load_portrait(path: String) -> Texture2D:
	return DialoguePortrait.load_portrait(path)


## 按说话人名字生成稳定颜色。同样只是转发，理由同上。
static func tint_for(speaker: String) -> Color:
	return DialoguePortrait.tint_for(speaker)


## 当前这一行是不是已经读过的。跳过已读时用它决定能不能继续快进。
func current_is_read() -> bool:
	if _dialogue == null or _index < 0 or _index >= _dialogue.lines.size():
		return false
	return has_read(_dialogue.lines[_index])


## 跳过已读：把**看过的**部分快进掉，遇到没看过的就停。
##
## 停在哪：停在最后一句看过的上面，不在没看过的那句上 ——
## 往前多送一句的话，连按几下就会把新内容一路吞掉，玩家什么都没看到。
## 想看下一句按空格，那才是「我在看」。
##
## 当前这句本身没看过时**什么都不做**：它还没显示完就被跳过去，等于白播。
func skip_read() -> bool:
	if not _open or _holding or _dialogue == null:
		return false
	if not current_is_read():
		return false

	var jumped := false
	while _index + 1 < _dialogue.lines.size():
		var next: DialogueLine = _dialogue.lines[_index + 1]
		if not has_read(next):
			break
		_index += 1
		_record(next)
		jumped = true
	if jumped:
		# 这些行本来就在历史里，不再重复记一遍把记录面板撑长
		_show_line(_dialogue.lines[_index], false)
	return jumped


func _advance() -> void:
	_index += 1
	if _dialogue == null or _index >= _dialogue.lines.size():
		_finish()
		return
	_show_line(_dialogue.lines[_index], true)


## `log_first` 为 false 表示这一行是快进带过的，不重复记进历史
## （它本来就在历史里，再记一次只会让记录面板变长）。
func _show_line(line: DialogueLine, log_first: bool) -> void:
	if log_first:
		_record(line)
	_apply_portraits(line)

	# 这一句谁说的，决定用哪张框、框贴屏幕哪一边，以及名字标签摆在哪头
	_box_side = line.side
	_set_frame_side(_box_side)

	# 主角在框上显示「主角」，不是数据里的「我」—— 只改显示，不动 `data/`
	_name.text = PROTAGONIST_LABEL if _is_protagonist(line) else line.speaker
	_name.visible = _name.text != ""
	# 字号**每行都要重设**：上一行是加大号的话，不重设这一行会跟着变大。
	#（主题覆盖是留在 Label 上的。）
	_line_size = FONT_SIZE + line.size_delta
	_label.add_theme_font_size_override("font_size", _line_size)
	_label.text = line.text
	_label.visible_characters = 0
	_reveal = 0.0
	_revealing = true
	_auto_timer = 0.0
	_update_box()
	_layout()
	if line.shake > 0.0:
		shook.emit(line.shake)


## 框宽固定，高度按这一行的折行数走。
##
## **先定宽、再按这个宽度量行数** —— 顺序反了的话，量出来的是上一帧的宽度
## 折的行，面板高度会慢一拍。
func _update_box() -> void:
	_box_width = BOX_MAX_WIDTH
	# 高度按这一行实际占几行算。三行的台词用两行的面板会溢出。
	var lines := _line_count(_label.text, _text_width(), _line_size)
	var wanted := BOX_EXTRA + float(lines) * LINE_HEIGHT
	_box_height = clampf(wanted, BOX_MIN_HEIGHT, BOX_MAX_HEIGHT)


## 这段文本在给定宽度下会占几行。
##
## **自己一个字一个字量**，不去问 `_measure.get_line_count()`：
## 那个值要等布局跑过一轮才准，而无头模式（测试、CI）里没有渲染，
## 一律返回 1 —— 表现就是面板永远不长高，正好是这次要治的毛病。
func _line_count(text: String, width: float, size: int) -> int:
	if text == "":
		return 1

	var font := _measure.get_theme_default_font()
	var lines := 1
	var used := 0.0
	for i: int in text.length():
		var char_width := _char_width(text.unicode_at(i), font, size)
		if used > 0.0 and used + char_width > width:
			lines += 1
			used = char_width
			continue
		used += char_width
	return maxi(1, lines)


## 一个字多宽。有字体就问字体，问不出来（没字体、或者量出 0）就按
## 「全角一个字号、半角半个」估 —— 误差最多一行，有 min/max 兜着。
func _char_width(code: int, font: Font, size: int) -> float:
	if font != null:
		var measured := font.get_char_size(code, size).x
		if measured > 0.0:
			return measured
	return float(size) if code > 0x2000 else float(size) * 0.5


func _record(line: DialogueLine) -> void:
	if _log != null:
		_log.add_entry(line.speaker, line.text)


func _finish_reveal() -> void:
	_reveal = float(_label.text.length())
	_label.visible_characters = -1
	_revealing = false
	_auto_timer = 0.0


func _finish() -> void:
	var holding := _hold_at_end
	var keeping := _keep_at_end
	_hold_at_end = false
	_keep_at_end = false
	_dialogue = null
	_index = -1
	_revealing = false
	_auto_timer = 0.0
	if holding:
		_begin_hold()
	elif keeping:
		# 播完**不收面板**，最后一句留在原地。
		# 玩家再点一下会走 `advance()` → `_advance()` → 回到这里（那次 keeping 已经是假）→ 收掉。
		_open = true
	else:
		_hide_panel()
	finished.emit()


## 转为「等选择」：面板留着，正文和名字清掉，立绘不动，按钮条收起来。
##
## 按钮条要收：它就贴在面板右下角，和中间那两行选项会撞在一起；
## 而且这期间玩家按的是选项，不是「自动 / 记录 / 跳过」。
func _begin_hold() -> void:
	_holding = true
	_open = true
	_name.text = ""
	_name.visible = false
	_label.text = ""
	_label.visible = false
	_buttons.set_visible(false)
	_box_height = CHOICE_BOX_HEIGHT
	# 等选择时正文清空了，框按最小宽度摆着当背景 —— 留着上一句的宽度
	# 会是一块空荡荡的大板子，后面选项框压上来更挤。
	_box_width = BOX_MAX_WIDTH
	_root.visible = true
	_layout()


func _hide_panel() -> void:
	_root.visible = false
	_open = false
	_holding = false
	_label.visible = true
	_buttons.set_visible(true)
	_box_height = BOX_MIN_HEIGHT
	for slot: DialoguePortrait in _slots:
		slot.hide()


func _process(delta: float) -> void:
	if not _open:
		return

	# 呼吸：说话的那侧轻微起伏。两侧都喂，不是说话的那侧自己归零。
	_breath_time += delta
	var offset := sin(_breath_time * DialoguePortrait.BREATH_SPEED) \
		* DialoguePortrait.BREATH_AMOUNT
	for slot: DialoguePortrait in _slots:
		slot.apply_breath(offset)

	# 等选择的时候没有正文可逐字显示，也不该自动往下翻
	if _holding:
		return

	if _revealing:
		_reveal += _speed * delta
		_label.visible_characters = int(_reveal)
		if _reveal >= float(_label.text.length()):
			_finish_reveal()
		return

	# 自动模式：显示完停一会儿就往下走
	if _auto:
		_auto_timer += delta
		if _auto_timer >= AUTO_DELAY:
			_advance()


# ---------------------------------------------------------------- 立绘

## 摆两个立绘槽：说话的那侧亮，另一侧压暗；不说话的一侧不出现。
##
## **不管位置** —— 这里只决定谁亮谁暗。位置归 `_layout()`，每个说话人换过
## 之后 `_show_line()` 都会紧跟着调它一次，那一趟才落位。
func _apply_portraits(line: DialogueLine) -> void:
	for slot: DialoguePortrait in _slots:
		var is_speaker := line.speaker != "" and slot.side == line.side
		var is_other := line.speaker != "" and line.side != DialogueLine.Side.NONE \
			and slot.side != line.side

		if is_speaker:
			slot.show_speaker(line.speaker, line.portrait_path(), false)
		elif is_other and slot.speaker != "":
			# 上一次说过话的那一侧留着，只是压暗，表示「他在场但不是他在说」
			slot.dim()
		elif not is_other:
			slot.hide()


# ---------------------------------------------------------------- 布局

func _view_size() -> Vector2:
	# 尺寸取自项目设置的固定分辨率，**不去查 viewport**
	# —— viewport 尺寸在 `--script` 模式下取不准（节点刚进树时是 0），
	# 表现出来就是对话框缩成一条、文字竖排。
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)


## 面板上沿的 y
func _box_top() -> float:
	return _view_size().y - _box_height - MARGIN


## 面板左沿的 x。**主角那句贴屏幕左边、往右长；其他角色的贴右边、往左长** ——
## 框往哪边长得看是谁在说话，贴图上的名字标签本来就是照这个方向画的。
func _box_left() -> float:
	if _box_side == DialogueLine.Side.RIGHT:
		return _view_size().x - MARGIN - _box_width
	return MARGIN


## 框内沿的左右两条。立绘和正文都排在这两条之间，不压到框线上。
## 贴图 -> 逻辑像素的缩放。**横竖分开推**：横向把面板贴图的宽度映射到框宽，
## 纵向把面板贴图的高度映射到框高。
##
## 不能用一个统一比例 —— 面板贴图是 1554x389（比例 4:1），而框的宽高是各自
## 按内容算的，两者对不上。分开推的好处是面板**永远不变形**，
## 名字标签和花饰因为挂在面板外，按各自的贴图尺寸跟着缩。
func _scale() -> Vector2:
	return Vector2(_box_width / BODY_TEX.size.x, _box_height / BODY_TEX.size.y)


func _inner_left() -> float:
	return _box_left() + (INNER_LEFT_TEX - BODY_TEX.position.x) * _scale().x


func _inner_right() -> float:
	return _box_left() + (INNER_RIGHT_TEX - BODY_TEX.position.x) * _scale().x


## 正文和按钮离框线内沿的那点余量（逻辑像素）。
##
## **一点都不能省。** 不留的话正文会直接顶在框线上 —— 右款（立绘在右、
## 左侧没有东西挡着）尤其明显，字贴着线甚至压着线，看着像「凸出去」了
## （人类 2026-09-26 报的）。左款因为本来就隔着一条立绘带子，看不出来。
const TEXT_PAD := 6.0


## 正文区的左沿。
##
## **只在说话人那一侧让开立绘带子**，另一侧不留 —— 另一边通常根本没立绘，
## 空着 76 像素等于把正文挤成一条窄缝（人类 2026-09-26 的要求：
## 「文本部分从文字框最左边开始」）。让位宽度仍然**按侧固定**，
## 不按「这一刻有没有立绘」算，否则同一个说话人的几句之间宽度会跳、行数跟着跳。
func _text_left() -> float:
	if _box_side == DialogueLine.Side.LEFT:
		return _inner_left() + PORTRAIT_WIDTH + PORTRAIT_GAP
	return _inner_left() + TEXT_PAD


## 正文区的右沿。同上，只让开说话人那一侧。
func _text_right() -> float:
	if _box_side == DialogueLine.Side.RIGHT:
		return _inner_right() - PORTRAIT_WIDTH - PORTRAIT_GAP
	return _inner_right() - TEXT_PAD


## 正文区的宽度。**就是两条立绘带子中间那一列。**
##
## 立绘现在站在面板**里面**（`slot.place(top, _box_height)`），所以正文必须
## 让开它 —— 这点跟 2026-09-23 之前的版本正相反，那一版立绘画在面板上方，
## 正文铺满整条（304 宽）。现在的宽度是 148 上下。
##
## 为什么不按当前挂着的立绘算实际宽度：正文一变宽，行数就变，面板高度跟着跳，
## 换一个说话人抖一下。让位宽度固定，正文宽度就固定。
func _text_width() -> float:
	return _text_right() - _text_left()


func _layout() -> void:
	var view := _view_size()
	_root.position = Vector2.ZERO
	_root.size = view

	var left := _box_left()
	var top := _box_top()
	var s := _scale()

	# 九宫格节点的 size 写**贴图像素**（它和贴图 1:1），缩放挂在该死的 scale 上；
	# 位置要**倒着**减去面板左上角在贴图里的偏移，面板那一块才对得上 (left, top)，
	# 名字标签也就正好凸在面板上沿外面。
	_frame.size = Vector2(FRAME_TEX_W, FRAME_TEX_H)
	_frame.scale = s
	_frame.position = Vector2(left - BODY_TEX.position.x * s.x,
		top - BODY_TEX.position.y * s.y)

	# 内容区：正文、立绘、按钮都在这一块里活动
	var inner_top := top + (INNER_TOP_TEX - BODY_TEX.position.y) * s.y
	var inner_bottom := top + (INNER_BOTTOM_TEX - BODY_TEX.position.y) * s.y
	var inner_h := inner_bottom - inner_top

	# 立绘站在面板**里面**：主角那侧贴内沿左边，其他人贴内沿右边，各占一条带子。
	# **高度给的是内容区，不是整张贴图** —— 按整张给的话人会探出框外。
	for slot: DialoguePortrait in _slots:
		slot.rest_x = _inner_left() if slot.side == DialogueLine.Side.LEFT \
			else _inner_right() - PORTRAIT_WIDTH
		slot.place(inner_top, inner_h)

	var text_left := _text_left()
	var text_right := _text_right()

	# 名字摆进那个小标签里、居中。标签凸在面板上沿**外面**，矩形单独算，
	# 不能拿内容区去推。
	var tab := _tab_rect()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.position = Vector2(left + (tab.position.x - BODY_TEX.position.x) * s.x,
		top + (tab.position.y - BODY_TEX.position.y) * s.y + _name_vertical_fix())
	_name.size = Vector2(tab.size.x * s.x, tab.size.y * s.y)

	# 正文要从按钮条那一行**下面**开始，不然第一行字被按钮压住
	var text_top := inner_top + _buttons_row_height()
	_label.position = Vector2(text_left, text_top)
	_label.size = Vector2(text_right - text_left, inner_bottom - text_top - 2.0)

	# 按钮条贴**名字标签的另一边**：标签占了上沿的一头，按钮只能去另一头。
	# 同侧会叠在一起（标签宽约 85、按钮条宽 101，正文那一列装不下两个）。
	if _box_side == DialogueLine.Side.RIGHT:
		# 右款：标签在右上，按钮条从内容区左边起往右排 —— 见 `_buttons_left_edge()`。
		_buttons.layout(_buttons_left_edge() + BUTTONS_INSET
			+ DialogueButtons.reserved_width() - DialogueButtons.MARGIN_RIGHT, inner_top)
	else:
		_buttons.layout(_inner_right() - BUTTONS_INSET, inner_top)


## 上面那套按字体度量算完之后，还差最后一丁点 —— 往上抬这么多（逻辑像素）。
##
## `ascent` / `descent` 描述的是**行盒**，字面的实际上下沿和它并不完全重合
## （中文字体尤其，字面在行盒里通常偏上）。度量那套负责把行盒居中变成大致
## 字面居中，剩下这点儿靠肉眼收尾。**要微调只动这一个数**，别去改
## `_name_vertical_fix()` 里的公式 —— 那是推导出来的，不是试出来的。
const NAME_NUDGE := 4.0


## 名字在标签里要往下补多少（逻辑像素），好让**字面**而不是行盒落在小框正中。
##
## `VERTICAL_ALIGNMENT_CENTER` 居中的是**行盒**（ascent + descent + 行距），
## 而行盒比字面高一截 —— 居中的结果是字看着**偏上**（人类连着提了两次）。
## 这里按字体自己的 ascent / descent 把差的那半截算出来：
##
##   字面中心在行盒里比行盒中心高出 (ascent − descent)/2 − 字号/2，
##   所以把名字那个框整体往下挪同样多，字面就落到小框正中了。
func _name_vertical_fix() -> float:
	var font := _name.get_theme_default_font()
	if font == null:
		return -NAME_NUDGE
	var asc := font.get_ascent(NAME_FONT_SIZE)
	var desc := font.get_descent(NAME_FONT_SIZE)
	return (desc - asc) * 0.5 + float(NAME_FONT_SIZE) * 0.5 - NAME_NUDGE


## 按钮条那一行占多高。正文要从它下面开始。
func _buttons_row_height() -> float:
	return DialogueButtons.MARGIN_TOP + DialogueButtons.HEIGHT + 2.0


## 右款框（标签在右上）时，按钮条要贴框内沿的**左**边。
## `DialogueButtons.layout()` 只认右边沿，所以这里把左沿换算成等价的右边沿：
## 它从 right 往左排三个按钮、最左那个的左边正好落在 right - (reserved - MARGIN_RIGHT)。
func _buttons_left_edge() -> float:
	return _inner_left() + TEXT_PAD


## 正文那一列占的地方。测试与调试用 —— 版式一改，靠它守
## 「正文没有窄到两三个字就换行」。
##
## 直接报 `_label` 摆完的位置，不再自己重算一遍：版式一改就是两处要跟着改，
## 迟早对不上（这个文件已经栽过好几次）。
func text_rect() -> Rect2:
	setup()
	return Rect2(_label.position, _label.size)


## 点到了哪个按钮。没点到返回 -1。
func _hit_button(point: Vector2) -> int:
	return _buttons.hit_index(point, _text_right(), _box_top())


## 切自动模式。按钮的高亮跟着走。
func _toggle_auto() -> void:
	_auto = not _auto
	_auto_timer = 0.0
	_buttons.set_auto(_auto)


# ---------------------------------------------------------------- 输入

func _on_root_gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return

	# gui_input 给的已经是本控件的局部坐标，可以直接跟布局用的坐标比
	var point := click.position

	if _log.is_open():
		_log.close()
		return

	match _hit_button(point):
		DialogueButtons.SKIP:
			skip()
			return
		DialogueButtons.LOG:
			_log.open()
			return
		DialogueButtons.AUTO:
			_toggle_auto()
			return

	advance()


## 键盘操作。空格/回车推进，A 自动，L 记录，S 跳过，R 快进已读。
##
## 快进已读单独一个键：它是「快进到没读过的地方」，跟 S「跳过整段」
## 是两件事，共用一个键的话玩家没法只要其中一种。
func handle_key(keycode: int) -> bool:
	if not _open:
		return false

	if _log.is_open():
		if keycode == KEY_L or keycode == KEY_ESCAPE or keycode == KEY_SPACE:
			_log.close()
			return true
		return false

	match keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			advance()
			return true
		KEY_A:
			_toggle_auto()
			return true
		KEY_L:
			_log.open()
			return true
		KEY_S:
			skip()
			return true
		KEY_R:
			return skip_read()
	return false
