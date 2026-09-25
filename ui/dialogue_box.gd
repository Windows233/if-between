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

## 面板高度**随正文行数浮动**，在这两个数之间。
##
## 下限取屏幕高度的**三分之一**（180 / 3 = 60）—— 这是版式规格：
## 「对话框只占屏幕的 1/3，一个深色方框」。上限 82 是给长台词留的余地，
## 再高就要把场景压没了。
const BOX_MIN_HEIGHT := 60.0
const BOX_MAX_HEIGHT := 82.0
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
const PANEL_PAD := 2.0

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

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.92)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const TEXT_COLOR := Color("#eaeaea")
const NAME_COLOR := Color("#e8c07a")
const HINT_COLOR := Color("#8a9a8e")

var _root: Control
var _edge: ColorRect
var _panel: ColorRect
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
## 当前面板高度。按这一行的行数算，见 `_update_box_height()`。
var _box_height := BOX_MIN_HEIGHT

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

	_edge = _make_rect("Edge", EDGE_COLOR)
	_panel = _make_rect("Panel", BG_COLOR)

	# 立绘站在面板**里面**，所以**必须建在面板之后** ——
	# 同层节点按加入顺序画，先加的被后加的盖住。早先立绘画在面板上方，
	# 顺序无所谓；搬进框里之后顺序反了就是「面板一片空、人像看不见」。
	_slots.append(DialoguePortrait.create(self, _root, DialogueLine.Side.LEFT))
	_slots.append(DialoguePortrait.create(self, _root, DialogueLine.Side.RIGHT))

	_name = Label.new()
	_name.name = "Name"
	_name.add_theme_font_size_override("font_size", 9)
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


func _make_rect(node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


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

	_name.text = line.speaker
	_name.visible = line.speaker != ""
	# 字号**每行都要重设**：上一行是加大号的话，不重设这一行会跟着变大。
	#（主题覆盖是留在 Label 上的。）
	_line_size = FONT_SIZE + line.size_delta
	_label.add_theme_font_size_override("font_size", _line_size)
	_label.text = line.text
	_label.visible_characters = 0
	_reveal = 0.0
	_revealing = true
	_auto_timer = 0.0
	_update_box_height()
	_layout()
	if line.shake > 0.0:
		shook.emit(line.shake)


## 面板高度按这一行实际占几行算。三行的台词用两行的面板会溢出。
func _update_box_height() -> void:
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


## 正文区的左沿：面板左边往内一格，再让开立绘那条带子。
func _text_left() -> float:
	return MARGIN + PANEL_PAD + PORTRAIT_WIDTH + PORTRAIT_GAP


## 正文区的右沿。
func _text_right() -> float:
	return _view_size().x - MARGIN - PANEL_PAD - PORTRAIT_WIDTH - PORTRAIT_GAP


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

	var width := view.x - MARGIN * 2.0
	var top := _box_top()

	_edge.position = Vector2(MARGIN, top)
	_edge.size = Vector2(width, _box_height)
	_panel.position = Vector2(MARGIN + 1.0, top + 1.0)
	_panel.size = Vector2(width - 2.0, _box_height - 2.0)

	# 立绘站在面板**里面**：主角那侧贴面板左沿，其他人贴右沿，各占一条带子。
	for slot: DialoguePortrait in _slots:
		slot.rest_x = MARGIN + PANEL_PAD if slot.side == DialogueLine.Side.LEFT \
			else view.x - MARGIN - PANEL_PAD - PORTRAIT_WIDTH
		slot.place(top, _box_height)

	var text_left := _text_left()
	var text_right := _text_right()

	# 名字那一行的右边要让给按钮条（自动 / 记录 / 跳过），
	# 名字再长也不该压到它们上面。
	_name.position = Vector2(text_left, top + 5.0)
	_name.size = Vector2(
		maxf(24.0, text_right - text_left - DialogueButtons.reserved_width()), 12.0
	)

	_label.position = Vector2(text_left, top + 17.0)
	_label.size = Vector2(text_right - text_left, _box_height - 30.0)

	_buttons.layout(text_right, top)


## 正文那一列占的地方。测试与调试用 —— 版式一改，靠它守
## 「正文没有窄到两三个字就换行」。
func text_rect() -> Rect2:
	setup()
	return Rect2(_text_left(), _box_top() + 17.0,
		_text_width(), _box_height - 30.0)


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
