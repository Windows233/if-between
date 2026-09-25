## 左上角的「日期 / 时间 / 地点」。
##
## 稿子里写的是【xx月x日 傍晚 委托屋】，后面还有一句演出指导：
## 「需要于左上角注明状态，字体不用很小」。
##
## **摆出来几秒就自己收掉**，不是常驻 —— 她是这么要的：一行状态一直挂在
## 角落里，看久了像屏幕上粘了块脏东西。进场从左边滚出来、淡入，
## 停一会儿，再淡下去。
##
## **层级摆在黑幕下面**（`StageCurtain` 是 layer 5，这里是 4）。
## 黑屏时场景已经不在了，还留着一行「委托屋」是错的；
## 而章标题、结局文字都是画在黑幕上的，压在它上面才对。
class_name LocationHud
extends CanvasLayer

## 字号。稿子说「字体不用很小」，但也不能跟正文一样大 ——
## 它是状态，不该抢台词的戏，所以比正文（10）小两号。
const FONT_SIZE := 8
const MARGIN_X := 6.0
const MARGIN_Y := 4.0
const TEXT_COLOR := Color("#e6dcc2")
## 描边。底下的场景有亮有暗（窗子、灯），不加描边会有一段字吃进背景里。
const OUTLINE_COLOR := Color(0, 0, 0, 0.8)
const OUTLINE_SIZE := 4

## 摆出来之后停多久（秒）。加上进出场，一行字总共占屏幕五秒上下。
const LIFE := 4.0
## 进场：从左边「滚」进来这么多像素，同时淡入。
const SLIDE := 18.0
const FADE_IN := 0.45
## 收尾用最后这么久淡下去
const FADE_OUT := 0.5

var _root: Control
var _label: Label
var _open := false
## 还剩多久自己收。`tick()` 每帧减。
var _timer := 0.0
var _slide: Tween = null


func _ready() -> void:
	setup()


## 建界面。抽成显式方法，理由同 `DialogueBox.setup()`：
## `--script` 模式下 add_child 不会触发 `_ready`。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	layer = 4

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_label = Label.new()
	_label.name = "Text"
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_label)

	_root.visible = false


## 换一行字。**空字符串就是收起** —— 演出里想让它消失时写个空 text 就行，
## 不用再开一条「隐藏」的指令。
##
## 摆出来之后 `LIFE` 秒自己淡下去（见 `tick()`）。
func show_text(text: String) -> void:
	setup()
	if text == "":
		hide_now()
		return

	_label.text = text
	_open = true
	_timer = LIFE
	_root.visible = true
	_layout()

	# 进场：从左边滚进来，同时淡入
	if _slide != null:
		_slide.kill()
	_label.position.x = MARGIN_X - SLIDE
	_root.modulate.a = 0.0
	_slide = create_tween()
	_slide.set_parallel(true)
	_slide.tween_property(_label, "position:x", MARGIN_X, FADE_IN)
	_slide.tween_property(_root, "modulate:a", 1.0, FADE_IN)


func hide_now() -> void:
	if _slide != null:
		_slide.kill()
		_slide = null
	if _root != null:
		_root.visible = false
		_root.modulate.a = 1.0
	_open = false
	_timer = 0.0


## 走时间。`_process` 每帧调一次，**单独开出来是为了能被测试推着走** ——
## 无头测试里没有帧循环，「摆出来四秒之后该收掉」这件事只能靠它验。
##
## 最后 `FADE_OUT` 秒淡下去，到点收掉。
func tick(delta: float) -> void:
	if not _open:
		return
	_timer -= delta
	if _timer <= 0.0:
		hide_now()
		return
	if _timer < FADE_OUT:
		_root.modulate.a = _timer / FADE_OUT


func _process(delta: float) -> void:
	tick(delta)


func is_open() -> bool:
	return _open


func current_text() -> String:
	return _label.text if _label != null else ""


func _layout() -> void:
	var view := _view_size()
	_root.position = Vector2.ZERO
	_root.size = view
	_label.position = Vector2(MARGIN_X, MARGIN_Y)
	_label.size = Vector2(view.x - MARGIN_X * 2.0, FONT_SIZE + 4.0)


func _view_size() -> Vector2:
	# 尺寸取自项目设置的固定分辨率，不去查 viewport —— 理由同 DialogueBox。
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
