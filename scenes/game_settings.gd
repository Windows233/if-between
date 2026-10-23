## 游戏设置：跨存档、跨局保留的那几个偏好。
##
## 跟存档分开的理由同 `EndingGallery`：设置不是「这一局走到哪了」，
## 删档、开新局都不该把玩家调好的文字速度冲掉。所以自己一份文件，
## 放在 `user://` 根目录。
##
## 四项：显示模式、窗口尺寸、文字速度、音乐音量。**接口按「会有好几项」写的** ——
## 加第五项时只要补一组常量、一个字段、一次读写。
##
## 放 `scenes/`：它要碰文件系统，而 core 层不许。
class_name GameSettings
extends RefCounted

const PATH := "user://settings.json"
## 设置格式版本。将来字段变了靠它判断还能不能读。
const VERSION := 1

## 打字速度的三档（字/秒）。
##
## 中速 42 是原来写死的那个值，手感已经调过；
## 慢档给想细看的人，快档给二周目重看的人。
const SPEED_SLOW := 24.0
const DEFAULT_SPEED := 42.0
const SPEED_FAST := 90.0
## 切换时按这个顺序走
const SPEED_STEPS := [SPEED_SLOW, DEFAULT_SPEED, SPEED_FAST]
const SPEED_LABELS := ["慢", "中", "快"]

## 音量滑条的档距（一次按左右走这么多）。音乐、音效共用。
const VOLUME_STEP := 0.05
## 音量滑条的默认位置，25%。
##
## **它不等于「原音量」。** 原音量在 75%（见 `AudioBuses.BASE_SLIDER`），
## 默认刻意压得很低：起步音量低一点不吵人，想要响的自己去拉。
##
## 2026-09-24 策划从 50% 再降到 25%（往下两档）。
##
## 两个常量分开写、各是各的数 —— 常量里引用另一个类的常量，GDScript 有时
## 解析不过（`test_walkable.gd` 里那三个脚底常量就是这么抄成字面值的）。
## 另配一条断言守着「差正好 50 个百分点」。
const DEFAULT_VOLUME := 0.25

## 显示模式（"window" / "fullscreen"），默认全屏
var display := WindowMode.DEFAULT_MODE
## 窗口模式下用多大
var window_size := WindowMode.DEFAULT_SIZE
## 每秒显示多少个字
var speed := DEFAULT_SPEED
## 音乐音量，0..1 的滑条位置。0.5 = 原音量。
var music_volume := DEFAULT_VOLUME
## 音效音量，同上。和音乐**分开**存 —— 两条总线，两根滑条。
var sfx_volume := DEFAULT_VOLUME
## 开发者测试入口。正式默认关闭，保存在跨存档设置中。
var developer_options_enabled := false


## 读设置。文件不在或者坏了就用默认值 —— 设置丢了最多是速度回到中档，
## 不该让游戏起不来。原因已经打进日志。
func load_settings() -> void:
	display = WindowMode.DEFAULT_MODE
	window_size = WindowMode.DEFAULT_SIZE
	speed = DEFAULT_SPEED
	music_volume = DEFAULT_VOLUME
	sfx_volume = DEFAULT_VOLUME
	developer_options_enabled = false

	if not FileAccess.file_exists(PATH):
		return

	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("[设置] 读不了文件：%s" % PATH)
		return
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("[设置] 不是合法的 JSON 对象：%s" % PATH)
		return

	var data := parsed as Dictionary

	var raw_display: Variant = data.get("display", WindowMode.DEFAULT_MODE)
	if raw_display is String and WindowMode.MODES.has(str(raw_display)):
		display = str(raw_display)

	# 尺寸存成 "1280x720" 这样的字符串，读不懂就退回默认值
	var raw_size: Variant = data.get("window_size", "")
	if raw_size is String:
		var parts: PackedStringArray = str(raw_size).split("x")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			window_size = Vector2i(int(parts[0]), int(parts[1]))

	var raw_speed: Variant = data.get("speed", DEFAULT_SPEED)
	if raw_speed is float or raw_speed is int:
		speed = clampf(float(raw_speed), 8.0, 240.0)

	var raw_music: Variant = data.get("music_volume", DEFAULT_VOLUME)
	if raw_music is float or raw_music is int:
		music_volume = clampf(float(raw_music), 0.0, 1.0)

	var raw_sfx: Variant = data.get("sfx_volume", DEFAULT_VOLUME)
	if raw_sfx is float or raw_sfx is int:
		sfx_volume = clampf(float(raw_sfx), 0.0, 1.0)

	var raw_developer_options: Variant = data.get("developer_options_enabled", false)
	if raw_developer_options is bool:
		developer_options_enabled = raw_developer_options


func save_settings() -> bool:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("[设置] 写不了文件：%s" % PATH)
		return false
	file.store_string(JSON.stringify({
		"version": VERSION,
		"display": display,
		"window_size": "%dx%d" % [window_size.x, window_size.y],
		"speed": speed,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"developer_options_enabled": developer_options_enabled,
	}, "\t"))
	file.close()
	return true


## 切到下一档，到头了绕回来。返回新的速度。
func cycle_speed() -> float:
	var index := _speed_index()
	index = (index + 1) % SPEED_STEPS.size()
	speed = SPEED_STEPS[index]
	save_settings()
	return speed


## 切到下一个显示模式。返回新的模式字符串。
func cycle_display() -> String:
	var index := WindowMode.MODES.find(display)
	display = WindowMode.MODES[(index + 1) % WindowMode.MODES.size()]
	save_settings()
	return display


## 切到下一档窗口尺寸。返回新的尺寸。
func cycle_window_size() -> Vector2i:
	var index := WindowMode.SIZES.find(window_size)
	window_size = WindowMode.SIZES[(index + 1) % WindowMode.SIZES.size()]
	save_settings()
	return window_size


## 调一格音乐音量滑条。`step` 负数往左、正数往右。返回新的位置。
##
## 到两头就停住（不绕回来）—— 滑条绕回去是反直觉的。
func adjust_music(step: int) -> float:
	music_volume = clampf(music_volume + VOLUME_STEP * float(signi(step)), 0.0, 1.0)
	save_settings()
	return music_volume


## 调一格音效音量滑条。
func adjust_sfx(step: int) -> float:
	sfx_volume = clampf(sfx_volume + VOLUME_STEP * float(signi(step)), 0.0, 1.0)
	save_settings()
	return sfx_volume


## 切换开发者测试入口。返回新的开关状态。
func toggle_developer_options() -> bool:
	developer_options_enabled = not developer_options_enabled
	save_settings()
	return developer_options_enabled


## 把音乐音量**直接设到某个位置**（鼠标把滑条拖到哪儿就是哪儿）。
##
## 和 `adjust_music` 的分工：那个是「调一格」，键盘用；这个是「设到某个值」，鼠标拖用。
## 拖拽要是也拿「调一格」去凑，鼠标甩快一点就跟不上了。
##
## `save` 为 false 时**只改内存、不写盘** —— 拖动过程中每一帧都会调它，
## 每帧写一次文件没必要；松手那一下才存（面板负责）。
func set_music_volume(value: float, save: bool = true) -> float:
	music_volume = clampf(value, 0.0, 1.0)
	if save:
		save_settings()
	return music_volume


## 把音效音量直接设到某个位置。理由同 `set_music_volume()`。
func set_sfx_volume(value: float, save: bool = true) -> float:
	sfx_volume = clampf(value, 0.0, 1.0)
	if save:
		save_settings()
	return sfx_volume


## 音乐音量给人看的名字，形如「60%」。
func music_label() -> String:
	return _percent(music_volume)


## 音效音量给人看的名字。
func sfx_label() -> String:
	return _percent(sfx_volume)


static func _percent(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))


## 显示模式给人看的名字。
func display_label() -> String:
	return WindowMode.label_of(display)


## 窗口尺寸给人看的名字。全屏时它没意义，面板会自己标出来。
func window_size_label() -> String:
	return WindowMode.size_label_of(window_size)


## 当前档位的名字（慢 / 中 / 快）。给设置面板显示。
func speed_label() -> String:
	return SPEED_LABELS[_speed_index()]


func _speed_index() -> int:
	var nearest := 0
	var best_gap := INF
	for i: int in SPEED_STEPS.size():
		var gap := absf(SPEED_STEPS[i] - speed)
		if gap < best_gap:
			best_gap = gap
			nearest = i
	return nearest
