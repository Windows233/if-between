## 对话里的一行：说话人、内容、立绘站哪边。
##
## 单独做成顶层类，而不是塞在 `Dialogue` 里面 ——
## GDScript 对 `外层.内层.枚举` 这种三层嵌套引用支持不好，
## 会报「Could not resolve external class member」，两层就没事。
class_name DialogueLine
extends RefCounted

## 立绘站哪边。旁白用 NONE，两边都不亮。
enum Side {
	NONE,
	LEFT,
	RIGHT,
}

var speaker: String = ""
var text: String = ""
## 立绘站哪边。**这里不能手写类型标注。**
##
## 写 `var side: Side = Side.LEFT` 会报
## 「Cannot assign a value of type DialogueLine.Side as Side」——
## GDScript 把标注位置的 `Side` 和取值位置的 `Side` 当成了两个不同类型。
## 交给推断（`:=`）就没这个问题。
var side := Side.LEFT
## 立绘图片路径。留空就用占位色块。
var portrait: String = ""
## 这一行的字号比正文**大几个号**（0 = 跟正文一样）。
##
## 给「这句话要把人镇住」那种行用：`真的 是我吗？？？？！` 比正文大两号。
var size_delta: int = 0
## 这一行浮出来的时候，画面震多轻（0 = 不震，单位是游戏像素）。
##
## 这里只带**数值**，真正去摇镜头的是 `main`（它接了对话框的信号）——
## 对话框不认识相机，也不该认识。
var shake: float = 0.0


## 从字典构造：
## `{"speaker": "邻居", "text": "今天天气不错。", "side": "left"}`
##
## 不写 `speaker` 就是旁白。没有说话人还硬占着一侧立绘会很怪。
static func from_dictionary(raw: Variant) -> DialogueLine:
	var line := DialogueLine.new()
	if not (raw is Dictionary):
		return line

	line.speaker = str(raw.get("speaker", ""))
	line.text = str(raw.get("text", ""))
	line.portrait = str(raw.get("portrait", ""))
	line.size_delta = int(raw.get("size_delta", 0))
	line.shake = float(raw.get("shake", 0.0))

	var side := str(raw.get("side", "")).to_lower()
	if side == "right":
		line.side = Side.RIGHT
	elif side == "none":
		line.side = Side.NONE
	else:
		line.side = Side.LEFT

	if line.speaker == "":
		line.side = Side.NONE

	return line


## 立绘的完整资源路径。
##
## 数据里可以只写 `protagonist/quiet`，自动补成
## `res://art/portrait/protagonist/quiet.png`；写全路径也行。
## 留空表示这个说话人没有立绘，界面会退回色块占位。
func portrait_path() -> String:
	if portrait == "":
		return ""
	if portrait.begins_with("res://"):
		return portrait
	return "res://art/portrait/%s.png" % portrait
