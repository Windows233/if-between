## 按键兼容的小工具。
##
## Godot 有两种键码：`physical_keycode`（键盘上的**物理位置**）和 `keycode`
## （当前输入法/布局映射出来的字符）。有的按键压根没有字符含义（方向键、
## F 区），它们的 `keycode` 是 0；反过来某些合成事件的 physical 是 0。
##
## 全项目统一走这一个地方取「该拿这个值去判断」的键码，别各处自己岔开。
class_name InputUtil
extends RefCounted


## 取键码。优先用物理键码，没有再退回虚拟键码。
static func keycode_of(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != 0 else event.keycode
