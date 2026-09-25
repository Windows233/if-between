## 对话框里的一个立绘槽：左或右，站着谁，挂哪张图，怎么进场。
##
## 从 `dialogue_box.gd` 拆出来的理由：那文件一度 607 行，管着面板、逐字、
## 按钮、历史、输入，立绘的摆放与动效只是其中一块，跟别的几块没有往来。
## 拆出来之后，对话框只管「这一行是谁说的」，长什么样归这里。
##
## 三件事都在这里，**不在对话框里**：
##
##   1. **摆放** —— 真立绘按面板高度等比缩放，底边贴着面板内沿放进带子里
##      （主角那侧贴左沿、其他人贴右沿）。所以美术给的差分尺寸不一致
##      （1145×1374 到 1374×1145 都有）摆出来位置也是齐的。
##   2. **进场** —— 说话人换了才从侧面滑进来；同一个人连着说几句不重复滑。
##   3. **动效** —— 说话的那侧轻微呼吸；换表情时有一小段过渡，不是硬切。
##
## 它不是节点（`RefCounted`），但**持有节点**：三个可见的东西挂在对话框的
## 根控件下。补间借对话框的 `create_tween()`，所以构造时要给它一个 owner。
class_name DialoguePortrait
extends RefCounted

## 面板**里面**一侧留给立绘的那条带子有多宽。正文从它右边开始。
##
## 这个数是「让位宽度」，不是立绘实际有多宽 —— 真立绘按面板高度等比缩，
## 宽的那个（1374×1145）缩出来 1.2 倍高，所以留 70 够用，剩下的空着。
## 写成常量而不是按当前立绘算：**正文宽度一变，行数就变，面板高度跟着跳**，
## 换一个说话人就抖一下。
const BOX_WIDTH := 70.0
## 立绘离面板内沿留多少。上下都留这一份 —— 呼吸是上下浮的，不留会蹭出去。
const INNER_PAD := 3.0
## 占位色块的「头」有多宽
const HEAD_WIDTH := 32.0

## 非说话者压暗的程度
const DIM_COLOR := Color(0.42, 0.44, 0.5, 1.0)
## 没有说话人（旁白）时的底色
const NARRATOR_TINT := Color("#6f7f8f")

## 从屏幕外滑进来的距离与时间
const SLIDE_DISTANCE := 26.0
const SLIDE_TIME := 0.16
## 占位色块上的名字。色块是**会说人名的方块**，字要压得住底色。
const NAME_TEXT_COLOR := Color(0.96, 0.96, 0.96, 0.92)
const NAME_BAR_HEIGHT := 13.0
## 换表情的过渡时间。做短一点，长了会变成「顿一下再说」
const SWAP_TIME := 0.14

## 呼吸：说话的那侧轻微上下浮动。幅度一大一快都会显得抖，
## 1 像素多一点、周期约 4 秒，是「还在呼吸」而不是「在抽搐」。
const BREATH_AMOUNT := 1.2
const BREATH_SPEED := 1.6

## 立绘站在面板**里面**（2026-09-23 版式改的）。
##
## 早先它画在面板**上方**，底边贴着面板上沿 —— 那时候要往下沉一截
## 才不会在呼吸时飘到面板外面（旧注释里叫 `SINK`）。现在整个都在框里，
## 上下各有 `INNER_PAD` 的余量，呼吸那 1.2 个像素跑不出去了。

var side: DialogueLine.Side = DialogueLine.Side.LEFT
## 真立绘。没有图的时候用下面两块色块占位。
var sprite: TextureRect
var head: ColorRect
var body: ColorRect
## 占位阶段写在色块上的名字。
##
## 美术没到位之前，两块色块只说明「这里站着个人」，说不出是谁。
## 主角开场就要跟四个人说话，全靠名字认人，所以一定得写上去。
## 真图到位后这块字自己消失（`_apply_geometry` 里判）。
var name_label: Label = null
var speaker: String = ""
## 当前挂着的立绘路径，用来判断要不要重新加载
var portrait: String = ""
## 静止时应处的 x —— 指的是**这条让位带子的左沿**，不是立绘的左边。
## 左槽的立绘贴着带子左沿，右槽的贴着带子右沿（见 `_apply_geometry`）。
var rest_x: float = 0.0
## 静止时应处的 y（立绘顶边）。呼吸在这上面叠加偏移。
## 由 `_apply_geometry()` 按「底边贴着面板内沿」算出来。
var rest_y: float = 0.0
## 这一侧正在说话吗。呼吸只给说话的那侧。
var speaking := false

var _owner: Node
## 上一次 `place()` 给的面板上沿。`_apply_geometry()` 要它才能把底边贴到面板内沿。
var _box_top := 0.0
## 摆好之后要不要滑进来。由 `show_speaker()` 决定 ——
## 位置得先算出来（`place()`）才滑得动，所以不能当场就滑。
var _needs_slide := false
var _slide: Tween = null
var _swap: Tween = null
var _breath := 0.0


## 建一个槽。`owner` 用来开补间，`parent` 是可见节点要挂到的地方。
static func create(owner: Node, parent: Control, p_side: DialogueLine.Side) -> DialoguePortrait:
	var slot := DialoguePortrait.new()
	slot._owner = owner
	slot.side = p_side

	# 真立绘和占位色块同时只会显示一个，谁在上面无所谓
	slot.sprite = TextureRect.new()
	slot.sprite.name = "Sprite%d" % p_side
	slot.sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot.sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.sprite.visible = false
	parent.add_child(slot.sprite)

	slot.head = _make_rect(parent, "Head%d" % p_side, NARRATOR_TINT)
	slot.body = _make_rect(parent, "Body%d" % p_side, NARRATOR_TINT)
	slot.head.visible = false
	slot.body.visible = false

	slot.name_label = Label.new()
	slot.name_label.name = "PlaceholderName%d" % p_side
	slot.name_label.text = ""
	slot.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.name_label.add_theme_font_size_override("font_size", 9)
	slot.name_label.add_theme_color_override("font_color", NAME_TEXT_COLOR)
	slot.name_label.visible = false
	parent.add_child(slot.name_label)
	return slot


static func _make_rect(parent: Control, node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


# ---------------------------------------------------------------- 出场

## 让这个人站在这一侧。`dimmed` 为真表示他在场但不是他在说。
func show_speaker(p_speaker: String, p_portrait: String, dimmed: bool) -> void:
	var tint := tint_for(p_speaker)
	head.color = tint
	body.color = tint

	var shade := DIM_COLOR if dimmed else Color.WHITE
	head.modulate = shade
	body.modulate = shade
	sprite.modulate = shade
	name_label.modulate = shade
	speaking = not dimmed

	# 立绘换了才重新加载，同一个人连着说几句不用反复读盘
	if portrait != p_portrait:
		portrait = p_portrait
		sprite.texture = load_portrait(p_portrait)
		_play_swap()

	# 说话人换了才滑进来 —— 同一个人连着说几句反复滑很晃眼
	if speaker != p_speaker:
		speaker = p_speaker
		_needs_slide = true
		return
	_needs_slide = false


## 压暗：人还在，但不是他在说。
func dim() -> void:
	head.modulate = DIM_COLOR
	body.modulate = DIM_COLOR
	sprite.modulate = DIM_COLOR
	speaking = false
	_needs_slide = false


func hide() -> void:
	head.visible = false
	body.visible = false
	sprite.visible = false
	speaker = ""
	portrait = ""
	sprite.texture = null
	speaking = false
	_needs_slide = false
	if _slide != null:
		_slide.kill()
		_slide = null
	if _swap != null:
		_swap.kill()
		_swap = null


# ---------------------------------------------------------------- 摆放

## 摆到位置上。**立绘站在面板里面**：`box_top` 是面板上沿，
## `box_height` 是面板高度。底边贴着面板内沿，往上长。
##
## 高度是**跟着面板走**的：对话框正文变高时面板长高，立绘也长高；
## 面板矮下去时立绘跟着矮，而不是被裁掉头顶 —— 头顶没了比小一点难看得多。
func place(box_top: float, box_height: float) -> void:
	_box_top = box_top
	_apply_geometry(box_height)

	if _needs_slide:
		_needs_slide = false
		_slide_in(box_height)


func _apply_geometry(box_height: float) -> void:
	var has_speaker := speaker != ""
	var has_texture := sprite.texture != null

	# 没有真图就不占位。
	#
	# 早先这里会画一块「头 + 身体」的纯色方块，意思是「美术没到位，先看这个」。
	# 但**家具的交互也是带说话人的**（点书架会说「书架：……」），它们永远没有
	# 立绘，于是每看一件家具就在对话框上方糊一块颜色，很难看，也没多说明什么 ——
	# 谁在说话，对话框上的名字已经写了。
	head.visible = false
	body.visible = false
	sprite.visible = has_speaker and has_texture
	if not sprite.visible:
		return

	var tex := sprite.texture.get_size()
	var ratio := tex.x / maxf(tex.y, 1.0)
	var h := maxf(12.0, box_height - INNER_PAD * 2.0)
	var w := h * ratio
	# 太宽的立绘也得留在带子里 —— 挤到正文上比矮一点难看得多
	var max_w := BOX_WIDTH - 4.0
	if w > max_w:
		w = max_w
		h = w / ratio

	sprite.size = Vector2(w, h)
	rest_y = _box_top + box_height - INNER_PAD - h
	# 左槽贴带子左沿、右槽贴带子右沿，人像就不会挤在正文那一侧
	var x := rest_x
	if side == DialogueLine.Side.RIGHT:
		x = rest_x + BOX_WIDTH - w
	sprite.position = Vector2(x, rest_y + _breath)


## 从侧面滑进来。左进右出，方向按 side 定。
func _slide_in(box_height: float) -> void:
	if _owner == null:
		return
	if _slide != null:
		_slide.kill()

	var direction := -1.0 if side == DialogueLine.Side.LEFT else 1.0
	var shift := SLIDE_DISTANCE * direction

	# 先记住静止位置，把三个东西一起推出去，再补间回来
	_apply_geometry(box_height)
	var sprite_x := sprite.position.x
	var head_x := head.position.x
	var body_x := body.position.x
	sprite.position.x = sprite_x - shift
	head.position.x = head_x - shift
	body.position.x = body_x - shift

	_slide = _owner.create_tween()
	_slide.set_parallel(true)
	_slide.tween_property(sprite, "position:x", sprite_x, SLIDE_TIME)
	_slide.tween_property(head, "position:x", head_x, SLIDE_TIME)
	_slide.tween_property(body, "position:x", body_x, SLIDE_TIME)


# ---------------------------------------------------------------- 动效

## 呼吸偏移。由对话框每帧喂进来。**只有说话的那侧才真的动**，
## 另一侧的偏移归零 —— 不然它停在上一次的某个位置上，看着像歪着。
func apply_breath(offset: float) -> void:
	if not speaking:
		offset = 0.0
	if _breath == offset:
		return
	_breath = offset
	sprite.position.y = rest_y + offset
	head.position.y = rest_y + offset
	body.position.y = rest_y + HEAD_WIDTH + offset


## 立绘当前的下边界。真图看图，占位看色块。
##
## 给「底边不许露到面板外面」这条约定用 —— 测试靠它守（见 `SINK`）。
func bottom() -> float:
	if sprite != null and sprite.visible:
		return sprite.position.y + sprite.size.y
	if body != null and body.visible:
		return body.position.y + body.size.y
	return rest_y


## 换表情时的一小段过渡：新图从半透明、略小一点弹到正常。
## 硬切的话，同一个人换个表情会像被替换了一次，很跳。
func _play_swap() -> void:
	if _owner == null or sprite.texture == null:
		return
	if _swap != null:
		_swap.kill()

	# 目标透明度要在压暗之前读出来：补齐的目标是「该有的亮度」，
	# 不是当前这个临时值
	var target := sprite.modulate.a
	sprite.modulate.a = 0.45
	_swap = _owner.create_tween()
	_swap.set_parallel(true)
	_swap.tween_property(sprite, "modulate:a", target, SWAP_TIME)


# ---------------------------------------------------------------- 工具

## 按路径载立绘。路径为空、文件不存在、或者不是图，都返回 null，
## 外面会退回色块占位 —— 美术没给全的立绘不该让对话框整个空掉。
static func load_portrait(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is Texture2D:
		return res
	return null


## 按说话人名字生成稳定又不刺眼的颜色。同一个名字永远同一个颜色，不用写进数据。
static func tint_for(p_speaker: String) -> Color:
	if p_speaker == "":
		return NARRATOR_TINT
	var hue := float(absi(hash(p_speaker)) % 360) / 360.0
	return Color.from_hsv(hue, 0.30, 0.72)
