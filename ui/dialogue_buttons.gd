## 对话框底部那条按钮：自动 / 记录 / 跳过。
##
## 从 `dialogue_box.gd` 拆出来的理由：三个按钮各自要建 Label、算矩形、
## 摆位置、判命中、改颜色，拢在一起是一百来行，跟「放哪一句台词」
## 这件事一点关系都没有。
##
## 它**不知道按钮按下去要干什么** —— 只回答「点到第几个」，
## 由对话框自己把序号翻译成 `skip()` / `log.open()` / 切自动。
##
## 不是节点，持有三个 Label，挂在调用方给的父控件下。
class_name DialogueButtons
extends RefCounted

## 命中判定返回的序号。用常量而不是裸数字，
## 「第 0 个是跳过」这种事不该靠记。
const SKIP := 0
const LOG := 1
const AUTO := 2

const WIDTH := 30.0
const HEIGHT := 12.0
const GAP := 3.0
## 距面板右边与底边的留白
const MARGIN_RIGHT := 5.0
## 贴在面板**上沿**：跟说话人名字同一行。
##
## 早先贴在右下角，结果是**跟正文的最后一行打架** —— 正文一宽过来，
## 那一行就从按钮底下穿过去（截图里看得见「地球仪停在西边不」和「自动」并排）。
## 挪到名字那一行就没这个问题：左边写名字、右边放按钮，
## 正文从名字下面一整条铺开，宽高都是整的。
const MARGIN_TOP := 4.0

const BUTTON_COLOR := Color("#9aa8a0")
const BUTTON_ACTIVE_COLOR := Color("#e8c07a")

var skip: Label
var log: Label
var auto: Label


static func create(parent: Control) -> DialogueButtons:
	var bar := DialogueButtons.new()
	bar.auto = _make_label(parent, "Auto", "自动")
	bar.log = _make_label(parent, "Log", "记录")
	bar.skip = _make_label(parent, "Skip", "跳过")
	return bar


static func _make_label(parent: Control, node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", BUTTON_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## 整条按钮条占多宽（含右侧留白）。说话人名字那行要避开它。
static func reserved_width() -> float:
	return WIDTH * 3.0 + GAP * 2.0 + MARGIN_RIGHT


## 三个按钮的矩形，顺序同 `SKIP` / `LOG` / `AUTO`。
##
## 接的是**正文区右上角**那个点（`right` 是正文区的右沿，`y` 是面板上沿）。
## 早先这里接 `view / panel_top / panel_height / panel_width` 四个参数自己
## 去算右上角 —— 那是「按钮贴在面板右上角」的年代。现在面板右边那一块
## 归立绘，按钮只能待在正文那一列里，位置该由正文区说了算。
func rects(right: float, y: float) -> Array[Rect2]:
	var top := y + MARGIN_TOP
	var edge := right - MARGIN_RIGHT
	var out: Array[Rect2] = []
	# 从右往左排：跳过、记录、自动
	out.append(Rect2(edge - WIDTH, top, WIDTH, HEIGHT))
	out.append(Rect2(edge - WIDTH * 2.0 - GAP, top, WIDTH, HEIGHT))
	out.append(Rect2(edge - WIDTH * 3.0 - GAP * 2.0, top, WIDTH, HEIGHT))
	return out


func layout(right: float, y: float) -> void:
	var boxes := rects(right, y)
	skip.position = boxes[SKIP].position
	skip.size = boxes[SKIP].size
	log.position = boxes[LOG].position
	log.size = boxes[LOG].size
	auto.position = boxes[AUTO].position
	auto.size = boxes[AUTO].size


## 点到第几个按钮。没点到返回 -1。
func hit_index(point: Vector2, right: float, y: float) -> int:
	var boxes := rects(right, y)
	for i: int in boxes.size():
		if boxes[i].has_point(point):
			return i
	return -1


## 自动开着时那个按钮要高亮 —— 不开的话玩家不知道自己正处在自动模式。
func set_auto(on: bool) -> void:
	auto.add_theme_color_override("font_color", BUTTON_ACTIVE_COLOR if on else BUTTON_COLOR)


## 整条收起来。等玩家选选项时用：它就贴在面板右下角，
## 和摆在中间的选项会撞在一起。
func set_visible(on: bool) -> void:
	skip.visible = on
	log.visible = on
	auto.visible = on
