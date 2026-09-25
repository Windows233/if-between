## 睁眼：一层黑幕中间抠出一个椭圆，椭圆里能看见场景。
##
## 椭圆**先压扁再伸展**两下（眨眼），最后撑开到整个画面，彻底亮起来。
## 用在「从黑屏里醒来」那一幕：梦的结尾黑下去、再睁眼回到委托屋。
##
## **它只管这一层黑。** 剧本里得先把幕布（`StageCurtain`）揭开 ——
## 幕还压着的话，椭圆里看见的也是黑的。写法是：
##
##     { "do": "fade", "to": "clear", "time": 0.0 },   // 幕瞬揭，不淡
##     { "do": "eye_open", "blinks": 2 }
##
## 中间那一下不能让画面闪出来：幕瞬揭和眼罩建立是**同一帧**里连着做的
##（`_perform` 一句一句同步走，中间没有 await），所以看不到破绽。
##
## 形状在 shader 里算（见 `screen_eye.gdshader` 的文件头），这里只管动画：
## 推 `aperture` 这个 uniform。
class_name ScreenEye
extends ColorRect

const SHADER_PATH := "res://ui/screen_eye.gdshader"

## 闭眼：一条缝。
const SHUT := Vector2(0.30, 0.012)
## 睁着：能看见画面中间这一块。
const OPEN := Vector2(0.34, 0.26)
## 全睁开：大到整个画面都落进椭圆里，黑被推出屏幕。
const WIDE := Vector2(1.6, 1.3)

## 一次伸展用多久。快了像闪一下，慢了不像眼皮。
const STRETCH_TIME := 0.34
## 眨回去用多久。**比伸展快** —— 眨眼本来就是合得快、张得慢。
const BLINK_BACK_TIME := 0.16
## 最后撑开用多久。
const OPEN_TIME := 0.45

var _mat: ShaderMaterial


func setup() -> void:
	if _mat != null:
		return
	if not ResourceLoader.exists(SHADER_PATH):
		push_warning("[特效] 睁眼的 shader 缺失：%s" % SHADER_PATH)
		return

	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	material = _mat

	name = "ScreenEye"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(1, 1, 1, 1)
	visible = false
	_fit()


## 演一次睁眼。`blinks` 是眨几下（压扁 → 伸展算一下）。
##
## 从「闭着」起手，演完**完全透明并藏起来** —— 后面那一步看到的就是正常的场景。
func play(blinks: int = 2) -> void:
	setup()
	if _mat == null:
		return

	_set_aperture(SHUT)
	visible = true

	var tween := create_tween()
	var rounds := maxi(1, blinks)
	for i: int in rounds:
		tween.tween_method(_set_aperture, SHUT, OPEN, STRETCH_TIME)
		if i < rounds - 1:
			tween.tween_method(_set_aperture, OPEN, SHUT, BLINK_BACK_TIME)
	tween.tween_method(_set_aperture, OPEN, WIDE, OPEN_TIME)
	await tween.finished
	visible = false


## 立刻当成「已经睁完了」。即时模式（无头测试）走这条 —— 那边没有帧循环，
## 推不动补间，留在半路测试就卡住了。
func finish() -> void:
	setup()
	visible = false


func _set_aperture(v: Vector2) -> void:
	if _mat != null:
		_mat.set_shader_parameter("aperture", v)


## 铺满一屏。尺寸取项目设置里的固定分辨率，不去问 viewport
##（`--script` 模式下取不准）—— 和别处一个道理，见 `GameCamera.view_size()`。
func _fit() -> void:
	position = Vector2.ZERO
	size = GameCamera.view_size()
