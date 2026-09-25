## 过场黑幕：黑屏上还要显示台词和旁白，所以它**压在对话框下面**。
##
## 跟 `ScreenFade` 不是一回事，别合并：
##   - `ScreenFade`（第 30 层）是切场景用的，盖住**所有**东西，包括界面。
##     它的语义是「这几帧画面不算数」。
##   - 这一层（第 5 层）是演出用的「黑幕」。梦里说话、天黑、转场旁白，
##     都需要黑着底、但**台词得看得见** —— 所以它在对话框（第 10 层）之下。
##
## 两者都会出黑，但一个要盖住界面、一个要让界面露出来，层次正好相反。
class_name StageCurtain
extends CanvasLayer

const COLOR := Color(0.015, 0.015, 0.022, 1.0)

var _rect: ColorRect
var _tween: Tween = null


func _ready() -> void:
	setup()


## 建遮罩。抽成显式方法，理由同 main.gd 的 boot()：
## `--script` 模式下 add_child 不会触发 `_ready`。重复调用安全。
func setup() -> void:
	if _rect != null:
		return

	layer = 5
	_rect = ColorRect.new()
	_rect.name = "Curtain"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = COLOR
	_rect.visible = false
	add_child(_rect)
	_rect.position = Vector2.ZERO
	_rect.size = _view_size()


func is_down() -> bool:
	return _rect != null and _rect.visible and _rect.color.a > 0.99


func alpha() -> float:
	return _rect.color.a if _rect != null else 0.0


## 立刻黑掉，不做动画。开局的「一开始就是黑屏」用。
func snap_down() -> void:
	setup()
	_rect.color.a = 1.0
	_rect.visible = true


## 立刻揭开。
func snap_up() -> void:
	setup()
	_kill()
	_rect.color.a = 0.0
	_rect.visible = false


## 拉黑，可以 await。
func cover(time: float) -> void:
	await _to(1.0, time, true)


## 揭开，可以 await。
func lift(time: float) -> void:
	await _to(0.0, time, false)


## 演出被打断时收干净，别留一块黑的在场上。
func reset() -> void:
	if _rect == null:
		return
	_kill()
	_rect.color.a = 0.0
	_rect.visible = false


func _to(target: float, time: float, keep: bool) -> void:
	setup()
	_kill()
	_rect.visible = true
	if time <= 0.0:
		_rect.color.a = target
		_rect.visible = keep
		return

	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", target, time)
	await _tween.finished
	if is_instance_valid(_rect):
		_rect.visible = keep


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _view_size() -> Vector2:
	# 尺寸取自项目设置的固定分辨率，**不去查 viewport**
	# —— viewport 尺寸在 `--script` 模式下取不准（节点刚进树时是 0）。
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
