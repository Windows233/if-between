## 音频总线：把声音分成「音乐」和「音效」两类，各自一条。
##
## 为什么要分：设置里有一根音乐音量滑块，它只该管音乐，不能连猫叫一起拉下去。
## 总线是引擎自带的分组方式，改一次增益，挂在这条线上的所有播放器一起生效。
##
## **总线是全局的**（挂在 `AudioServer` 上，不属于任何节点），所以这个类
## 全是静态方法。启动时 `setup()` 一次，之后谁都别再加。
##
## 头一回是代码建的，没用 `.tres` 总线资源：手写那个格式容易错，
## 而这里要的只是两条通往 Master 的空线。将来要在编辑器里调效果器，
## 再把它们存成资源也不迟 —— `_ensure()` 见到已存在就跳过，不会重复建。
class_name AudioBuses
extends RefCounted

const MASTER := &"Master"
## 背景音乐。地图自带的那首曲子挂这条线。
const MUSIC := &"Music"
## 音效。演出里的 `play_sound`、将来的脚步、开箱之类。
const SFX := &"SFX"

## 滑条拉到这个位置时，增益正好是 1.0，也就是**音频文件的原始音量**。
##
## 这个数改过一次。一开始是 0.5，2026-09-24 策划把基准挪到了 **0.75** ——
## 原音量那根刻度更靠上，上半段留作余量。于是现在的对应是：
##
##  | 滑条 | 增益 | 听感 |
##  | 0%    | 0        | 静音 |
##  | 50%（默认） | 2/3 | 约 -3.5 dB |
##  | 75%   | 1.0      | **原音量** |
##  | 100%  | 4/3      | 约 +2.5 dB |
##
## 注意**默认位置和基准不再是同一个数**：默认停在 50%，比基准低 25 个百分点。
## 它俩是两个独立的常量，改一个不会带着另一个走。
const BASE_SLIDER := 0.75


## 建好两条总线。重复调用安全。
static func setup() -> void:
	_ensure(MUSIC)
	_ensure(SFX)


## 没有就建一条，返回它的下标。
static func _ensure(bus_name: StringName) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	index = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, MASTER)
	return index


## 滑条位置（0..1）换算成**增益倍数**。
##
## 75% → 1.0（原音量）、50% → 2/3、100% → 4/3、0% → 静音。
## 这是纯函数，测试直接调它 —— 省得为了验一个换算去建总线。
static func slider_to_gain(slider: float) -> float:
	return maxf(slider, 0.0) / BASE_SLIDER


# ---------------------------------------------------------------- 音乐 / 音效

## 按滑条位置设音乐音量。
##
## 归零时用 `mute` 而不是一个很小的 dB：`linear_to_db(0)` 是负无穷，
## 写进总线会变成 -inf dB，虽然听感一样，但读回来是个垃圾值。
static func set_music_slider(slider: float) -> void:
	set_bus_slider(MUSIC, slider)


## 音乐总线现在的滑条位置（0..1）。设过之后读回来应该一样。
static func music_slider() -> float:
	return bus_slider(MUSIC)


## 按滑条位置设音效音量。和音乐那条**各管各的** ——
## 拉音乐不该把猫叫一起带走。
static func set_sfx_slider(slider: float) -> void:
	set_bus_slider(SFX, slider)


static func sfx_slider() -> float:
	return bus_slider(SFX)


## 一次把两条总线都按设置摆好。开新局、读档、改设置之后都调它。
static func apply(music: float, sfx: float) -> void:
	set_music_slider(music)
	set_sfx_slider(sfx)


static func set_bus_slider(bus_name: StringName, slider: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	var gain := slider_to_gain(slider)
	if gain <= 0.0001:
		AudioServer.set_bus_mute(index, true)
		return
	AudioServer.set_bus_mute(index, false)
	AudioServer.set_bus_volume_db(index, linear_to_db(gain))


static func bus_slider(bus_name: StringName) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0 or AudioServer.is_bus_mute(index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index)) * BASE_SLIDER
