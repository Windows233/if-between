## 相机：跟着角色走，但被夹在场景边界内，不露出场景外面。
##
## **不用 `Camera2D` 的 `limit_*`** —— 那些值只在相机移动的那一帧重算，
## 切场景之后容易留下一帧错位。自己算位置更省心，也更好调。
##
## 逻辑做成静态纯函数，是为了能脱离场景单测：
## 相机算错位置这种事，靠肉眼看截图很难查出来。
class_name GameCamera
extends Camera2D


## 算出相机该停在哪。
##
## 场景不比视口大时锁在场景中心，画面不动，整个房间尽收眼底；
## 场景更大时跟着焦点走，但夹在边界内。
static func position_for(focus: Vector2, world: Vector2, view: Vector2) -> Vector2:
	if view.x <= 0.0 or view.y <= 0.0:
		return focus

	var half := view * 0.5
	var pos := focus

	if world.x <= view.x:
		pos.x = world.x * 0.5
	else:
		pos.x = clampf(focus.x, half.x, world.x - half.x)

	if world.y <= view.y:
		pos.y = world.y * 0.5
	else:
		pos.y = clampf(focus.y, half.y, world.y - half.y)

	return pos


## 把整张图缩进视口需要的缩放。
##
## 取两个方向里**更小**的那个比例，保证整张图都进得来（另一个方向留边）。
## **不放大** —— 场景比视口小的时候（房间正好 320×180）保持 1:1，
## 放大只会把画面糊掉，而且她明确说过「画面不需要放大」（2026-09-24）。
##
## 大地图 640×360 是视口的两倍，这里算出 0.5，整张图正好铺满。
static func zoom_for(world: Vector2, view: Vector2) -> Vector2:
	if world.x <= 0.0 or world.y <= 0.0 or view.x <= 0.0 or view.y <= 0.0:
		return Vector2.ONE
	var scale := minf(view.x / world.x, view.y / world.y)
	if scale >= 1.0:
		return Vector2.ONE
	return Vector2(scale, scale)


## 视口多大。**从项目设置里取固定值，不要问 viewport。**
##
## 这条是踩出来的（2026-09-24）：`get_viewport().get_visible_rect()` 返回的是
## **已经算过相机 zoom 之后**的尺寸。上一帧把 zoom 设成 0.5，这一帧它就变成
## 两倍大，于是 `zoom_for` 又算回 1.0，下一帧再翻回去 —— 来回震，
## 而且委托屋那种「和视口一样大」的房间会被莫名其妙地拉成全图视角。
##
## 项目里别的界面（`stage_overlay` / `screen_shatter`）取尺寸也是这么写的，
## 理由一样：`--script` 模式下 viewport 还不准。
static func view_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0)))


## 这个场景要不要缩成全景。**只有大地图要。**
##
## 单独拎出来是因为这件事太容易搞错（2026-09-24 就给所有场景都缩了，
## 委托屋当场变成一张全景图）。写成一个能单独调的函数，测试才盯得住。
static func should_shrink(kind: int) -> bool:
	return kind == MapDef.Kind.OVERWORLD


## 地图坐标中的人物比例只标定美术密度；镜头取其倒数，让可控主角始终等高。
## 不改地图、剧情和存档坐标；背景、物件、碰撞与演出人物共享同一个等比投影。
static func room_zoom_for(player_scale: float) -> Vector2:
	if not is_finite(player_scale) or player_scale <= 0.0:
		return Vector2.ONE
	return Vector2.ONE / player_scale


## 震屏：还剩多久、多轻、总时长（算衰减用）。
##
## 抖动是**加在 `offset` 上的**，不是去改焦点 —— 夹边界那套照旧，
## 抖完自然回原位。**也别去动 `zoom`**，那个每帧都在重算。
var _shake_left := 0.0
var _shake_total := 0.0
var _shake_strength := 0.0


## 轻轻摇一下镜头。给「这句话要把人镇住」那种行用。
##
## 同时来两下时取**更重更久**的那个，不叠加 —— 叠起来会晃得像地震。
func shake(strength: float = 2.0, time: float = 0.3) -> void:
	if strength <= 0.0 or time <= 0.0:
		return
	_shake_strength = maxf(_shake_strength, strength)
	_shake_total = maxf(_shake_total, time)
	_shake_left = maxf(_shake_left, time)


func _process(delta: float) -> void:
	if _shake_left <= 0.0:
		return
	_shake_left = maxf(0.0, _shake_left - delta)
	if _shake_left <= 0.0:
		# **抖完必须归零。** 不复位的话画面会永远偏着那么一点，
		# 而且每次震一下都会再偏一点。
		offset = Vector2.ZERO
		_shake_strength = 0.0
		_shake_total = 0.0
		return
	var amount := _shake_strength * (_shake_left / maxf(_shake_total, 0.001))
	# offset 是地图单位；强度按逻辑屏幕像素标定，不能随地图密度翻倍。
	offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount)) / zoom


## 对准一个焦点。视口尺寸取不到就不动。
##
## `shrink` 为真时才把整张图缩进视口 —— **只有大地图要这样**。
##
## 可行走地图按人物标尺投影，超出视口的部分随焦点移动；不按地图大小适配全图。
func follow(focus: Vector2, world: Vector2, shrink: bool = false,
		player_scale: float = 1.0) -> void:
	var view := GameCamera.view_size()
	if view.x <= 0.0 or view.y <= 0.0:
		return
	zoom = zoom_for(world, view) if shrink else room_zoom_for(player_scale)
	# **夹边界要用「缩放之后能看见多大世界」**，不是视口像素尺寸 ——
	# 拿像素尺寸去夹，缩到 0.5 之后相机会以为只能看见半张图，位置就偏了。
	global_position = GameCamera.position_for(focus, world, view / zoom)
