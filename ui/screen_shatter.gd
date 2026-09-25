## 屏幕破碎特效：把一张黑底的碎玻璃图叠到画面上，从正中炸开。
##
## **它自己不带黑幕** —— 只负责「玻璃碎掉」这一层。压黑由 `StageCurtain` 管，
## 两者分开是因为顺序有讲究：先裂开、再黑下去，反了就是「黑屏上冒出一道裂痕」，
## 看不出是屏幕碎了（旧的那套瓦片方案也是同一个道理，见 `shatter_begin()`）。
##
## 素材是**纯黑底、没有透明通道**的（`art/fx/screen_shatter.png`）。
## 黑底靠 shader 的 `blend_add` 消掉，理由写在那个 shader 的注释里。
##
## 动效全在 shader 里：它按「像素离画面中心多远」做遮罩，把 `spread` 从 0
## 推到 1 就是「裂纹从正中往外炸开」。光靠缩放整张图做不出这个 ——
## 那样是「一张图变大」，不是「玻璃从受力点裂开」。
class_name ScreenShatter
extends TextureRect

const TEXTURE_PATH := "res://art/fx/screen_shatter.png"
const SHADER_PATH := "res://ui/screen_shatter.gdshader"

## 炸开用多久。再快就只看见闪一下，再慢就不像「一下子碎的」。
const BURST_TIME := 0.16
## 正中那一下白光的余韵。
const FLASH_TIME := 0.26
## `spread` 推到底的值。1.15 时最外圈的裂纹也出来了。
const SPREAD_FULL := 1.15

var _mat: ShaderMaterial
var _playing := false


## 建材质、铺满屏幕。抽成显式方法，理由同别处：
## `--script` 模式下 `add_child` 不触发 `_ready`。重复调用安全。
func setup() -> void:
	if _mat != null:
		return
	if not ResourceLoader.exists(TEXTURE_PATH) or not ResourceLoader.exists(SHADER_PATH):
		push_warning("[特效] 破碎素材缺失：%s / %s" % [TEXTURE_PATH, SHADER_PATH])
		return

	texture = load(TEXTURE_PATH)
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	material = _mat

	name = "ScreenShatter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# 铺满、不变形。素材是 16:9，和视口一致，所以 covered 等于铺满。
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# 细裂纹在原图上是几个像素宽，缩到 320 宽之后会闪成一片雪花 ——
	# 必须走 mipmap（素材导入时也开了 `mipmaps/generate`）。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	position = Vector2.ZERO
	size = _view_size()
	visible = false
	modulate.a = 1.0
	_set_param("spread", SPREAD_FULL)
	_set_param("flash", 0.0)


## 放一次：炸开 → 停一会儿 → 淡掉。整段跑完才返回。
##
## **即时模式别走这条**（无头测试里没有帧循环，tween 不推进，会挂在这儿）。
## 那种场合用 `show_burst()`。
func play(hold: float = 0.6, fade: float = 0.5) -> void:
	setup()
	if _mat == null:
		return  # 素材不在，当成没有这个特效，别把演出卡住

	_playing = true
	visible = true
	modulate.a = 1.0
	_set_param("spread", 0.0)
	_set_param("flash", 0.0)

	# 炸开和闪光同时起：裂纹往外冲的同时正中亮一团
	var burst := create_tween()
	burst.set_parallel(true)
	burst.tween_method(_set_spread, 0.0, SPREAD_FULL, BURST_TIME).set_ease(Tween.EASE_OUT)
	burst.tween_method(_set_flash, 0.0, 1.0, BURST_TIME * 0.55)
	await burst.finished

	var flash_out := create_tween()
	flash_out.tween_method(_set_flash, 1.0, 0.0, FLASH_TIME).set_ease(Tween.EASE_IN_OUT)
	await flash_out.finished

	if hold > 0.0:
		await _sleep(hold)

	if fade > 0.0:
		var out := create_tween()
		out.tween_property(self, "modulate:a", 0.0, fade)
		await out.finished

	stop()


## 立刻摆到「炸开完成、停在场上」的样子，不做动画。
##
## 两处用它：即时模式下演出的截图，以及测试 —— 那两种场合都没有帧循环。
func show_burst() -> void:
	setup()
	if _mat == null:
		return
	visible = true
	modulate.a = 1.0
	_set_param("spread", SPREAD_FULL)
	_set_param("flash", 0.0)
	_playing = false


## 收干净。演出被打断、切场景时调用。
func stop() -> void:
	if _mat == null:
		return
	visible = false
	modulate.a = 1.0
	_playing = false


## 现在正放着没有。场上有碎玻璃时也该为真 —— 测试和调试用。
func is_playing() -> bool:
	return _playing or visible


## 裂纹扩散到哪儿了。测试用它守「炸开」这一步真的在推。
func spread() -> float:
	if _mat == null:
		return 0.0
	return float(_mat.get_shader_parameter("spread"))


## 直接摆到某个扩散位置，不做动画。截图要拍「炸到一半」的样子时用它 ——
## 一帧一帧等动画推过去太慢，而且抓不准。
func set_spread(v: float) -> void:
	setup()
	_set_param("spread", v)


## 整块特效是不是「有东西可显示」。素材缺失时为 false。
func ready_to_play() -> bool:
	setup()
	return _mat != null


# ---------------------------------------------------------------- 内部

func _set_spread(v: float) -> void:
	_set_param("spread", v)


func _set_flash(v: float) -> void:
	_set_param("flash", v)


func _set_param(key: String, value: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter(key, value)


func _sleep(seconds: float) -> void:
	# 先问在不在树里 —— 直接拿 `get_tree()`，不在树时它会一边返回 null
	# 一边喷 `Parameter "data.tree" is null`（那行报错跟特效无关）。
	if not is_inside_tree():
		push_warning("[特效] 不在树里，这一步的等待被跳过")
		return
	# `false` = 暂停时不走：特效也是演出，按了 ESC 该跟着停。
	await get_tree().create_timer(seconds, false).timeout


func _view_size() -> Vector2:
	# 尺寸取自项目设置的固定分辨率，不去查 viewport（`--script` 模式下取不准）
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
