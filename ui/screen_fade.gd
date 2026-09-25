## 全屏遮罩：切场景时黑一下，把「画面突然变了」藏起来。
##
## 两半用法不一样，别混：
##   - `fade_out(回调)` —— 切场景**之前**用。淡到全黑再回调，由回调去切。
##     这半段期间 `is_busy()` 为 true，外面据此挡住输入。
##   - `reveal()` —— 切场景**之后**用。先盖黑再淡开，露出新场景。
##     这半段**不算 busy**：画面已经在亮起来了，玩家不该被继续挡着。
##
## 为什么分开：如果把「淡入」也算成忙碌，那所有同步调用 `enter_map()` 的地方
## （测试、读档）都会在淡入没跑完时被卡住。淡入是给眼睛看的，不是状态。
class_name ScreenFade
extends CanvasLayer

const FADE_OUT_TIME := 0.13
const FADE_IN_TIME := 0.18
const COLOR := Color(0.02, 0.02, 0.03, 1.0)

var _rect: ColorRect
var _tween: Tween = null
var _busy := false


func _ready() -> void:
	setup()


## 建遮罩。抽成显式方法，理由同 main.gd 的 boot()：
## `--script` 模式下 add_child 不会触发 `_ready`。重复调用安全。
func setup() -> void:
	if _rect != null:
		return

	layer = 30
	_rect = ColorRect.new()
	_rect.name = "Fade"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = COLOR
	_rect.visible = false
	add_child(_rect)
	_layout()


## 正在淡出吗。**只有淡出算忙碌**，淡入不算 —— 理由见文件头。
func is_busy() -> bool:
	return _busy


func is_covering() -> bool:
	return _rect != null and _rect.visible


## 当前不透明度。测试与调试用，0 是全透、1 是全黑。
func alpha() -> float:
	return _rect.color.a if _rect != null else 0.0


## 立刻盖黑，不做动画。用于「没有上一幕可淡出」的场合：
## 开局、读档。这些时候画面本来就该直接换掉。
func cover_now() -> void:
	setup()
	_rect.color.a = 1.0
	_rect.visible = true


## 淡出到全黑，然后回调（由回调去切场景）。
func fade_out(then: Callable) -> void:
	setup()
	if _busy:
		return
	_busy = true
	_rect.visible = true
	_rect.color.a = 0.0

	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", 1.0, FADE_OUT_TIME)
	_tween.tween_callback(func() -> void:
		_busy = false
		if then.is_valid():
			then.call()
	)


## 盖黑再淡开。切完场景调用，新场景从黑里亮出来。
func reveal() -> void:
	setup()
	_kill_tween()
	_rect.color.a = 1.0
	_rect.visible = true

	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", 0.0, FADE_IN_TIME)
	_tween.tween_callback(func() -> void:
		_rect.visible = false
	)


## 淡到指定不透明度，**可以 await**。
##
## 上面那两个是「切场景」用的，各自带回调/自带节奏；演出要的是
## 「淡完再做下一件事」，所以给它一个能等的版本 —— 黑屏、章标题、
## 梦里醒来，都靠这一条串起来。
##
## 淡到黑时算 busy（这期间不该让角色动），淡回画面时不算，理由同文件头。
func fade_to(target: float, time: float) -> void:
	setup()
	_kill_tween()
	_rect.visible = true

	if time <= 0.0:
		_rect.color.a = target
		_rect.visible = target > 0.001
		return

	_busy = target > 0.001
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", target, time)
	await _tween.finished
	# 补间被 `_kill_tween()` 掐掉时不会醒过来 —— 演出是一条直线，
	# 半路插进来另一段淡入淡出本来就是编排错了，所以不为此加复杂度。
	_busy = false
	if is_instance_valid(_rect):
		_rect.visible = target > 0.001


## 闪几下。**这个和普通的淡出不是一回事** —— 淡出是「画面暗下去」，
## 闪是「被打断」：白闪像电击、黑闪像眼前一黑，梦醒那一下用白闪。
##
## `colors` 是**依次要闪的颜色**，一个颜色一次。要「黑白交替」就在数组里
## 白、黑、白地排 —— 交替本身是编排的事，这里只管按顺序闪。
##
## 一次闪 = `time/2` 亮起 + `hold` + `time/2` 暗回。**`hold` 是给
## 「亮着的那一瞬」留的时间** —— 亮起和暗回各只有零点几秒，眼睛容易错过，
## 亮着停一下才看得清（2026-09-24 策划报「闪太快，没反应过来」）。
##
## 和 `fade_to` 共用同一层，所以进来先把上一次的补间掐掉 ——
## 不掐的话两个补间抢同一个 `color:a`，画面会跳。
##
## **进来要自己把遮罩打开**（`_rect.visible = true`）：`reveal()` 收尾时
## 会把它藏起来，而「闪」平时都排在切场景之后 —— 不打开的话，
## 这一条指令什么都不会发生，画面上完全看不出闪没闪。
##
## 闪完把颜色还原成原来那个近黑，**但不透明度归零、遮罩收起**：
## 不归零的话，那一层的 alpha 是 1（`COLOR` 本来就是不透明的），
## 闪完画面会一直黑着。
func flash(colors: PackedColorArray, time: float = 0.12,
		hold: float = 0.0) -> void:
	setup()
	_kill_tween()
	_rect.visible = true

	var first := colors[0] if not colors.is_empty() else Color.WHITE
	_rect.color = Color(first.r, first.g, first.b, 0.0)
	_tween = create_tween()
	if colors.is_empty():
		_tween.tween_property(_rect, "color:a", 1.0, time * 0.5)
		_tween.tween_property(_rect, "color:a", 0.0, time * 0.5)
	else:
		for c: Color in colors:
			_tween.tween_property(_rect, "color", Color(c.r, c.g, c.b, 1.0), time * 0.5)
			if hold > 0.0:
				_tween.tween_interval(hold)
			_tween.tween_property(_rect, "color", Color(c.r, c.g, c.b, 0.0), time * 0.5)
	await _tween.finished
	_rect.color = Color(COLOR.r, COLOR.g, COLOR.b, 0.0)
	_rect.visible = false


## 掐掉上一次的补间。不掐的话两个补间会抢同一个 `color:a`，画面会跳。
func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _layout() -> void:
	var view := _view_size()
	_rect.position = Vector2.ZERO
	_rect.size = view


func _view_size() -> Vector2:
	# 尺寸取自项目设置的固定分辨率，**不去查 viewport**
	# —— viewport 尺寸在 `--script` 模式下取不准（节点刚进树时是 0）。
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
