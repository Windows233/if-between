## 窗口显示模式：窗口 / 全屏，以及窗口模式下用多大。
##
## 放在 `scenes/`：它要调显示服务器，而 core 层只许算逻辑。
##
## **默认全屏** —— 这游戏是给人看画面的，一上来就铺满屏幕比较对路。
## 不想全屏的从设置里切，或者按 F11。
class_name WindowMode
extends RefCounted

## 可选模式。存进设置的是这里的字符串，另外一份是给人看的名字。
const MODES: Array[String] = ["window", "fullscreen"]
const MODE_LABELS: Array[String] = ["窗口", "全屏"]
## 默认全屏：一上来就把画面铺开
const DEFAULT_MODE := "fullscreen"

## 窗口模式下的几档尺寸。
##
## 都是 16:9 —— 视口是 320x180，比例对不上会留黑边。
## 超过屏幕的档位也不拦：Godot 自己会摆不下多少算多少。
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const SIZE_LABELS: Array[String] = ["1280 × 720", "1600 × 900", "1920 × 1080"]
const DEFAULT_SIZE := Vector2i(1280, 720)


## 现在是不是全屏。
static func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


## 按模式和尺寸摆好窗口。
static func apply(mode: String, size: Vector2i) -> void:
	if mode == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# 从全屏切回窗口时，窗口会保持全屏时的大小，得手动收回目标尺寸
	DisplayServer.window_set_size(size)
	center(size)


## 当前模式的字符串（存设置用）。
static func current_mode() -> String:
	return "fullscreen" if is_fullscreen() else "window"


## 切一下模式，返回切换后的字符串。
static func toggle(size: Vector2i) -> String:
	var next := "window" if is_fullscreen() else "fullscreen"
	apply(next, size)
	return next


## 模式给人看的名字。
static func label_of(mode: String) -> String:
	var index := MODES.find(mode)
	return MODE_LABELS[index] if index >= 0 else mode


## 尺寸给人看的名字。
static func size_label_of(size: Vector2i) -> String:
	var index := SIZES.find(size)
	return SIZE_LABELS[index] if index >= 0 else "%d × %d" % [size.x, size.y]


## 把窗口摆到屏幕中间。从全屏切回窗口时它常常停在左上角。
static func center(size: Vector2i) -> void:
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0:
		return
	DisplayServer.window_set_position(Vector2i(
		maxi(0, (screen.x - size.x) / 2),
		maxi(0, (screen.y - size.y) / 2)
	))
