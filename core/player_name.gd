## 玩家给主角起的昵称，以及剧情正文里 `{name}` 占位符的替换。
##
## 剧情稿里的 `yn`（your name）在数据里统一写成 `{name}`；台词、旁白、
## 地图文字都能用。替换发生在 `DataLoader` 读剧情/地图 JSON 的那一刻，
## 所以对话框、字幕、IF 面板、对话记录拿到的都是已经替换好的文字。
##
## 名字本身存在世界状态 `player/name` 里，跟着存档走；
## 这里的 `current` 只是「当前这一局」的缓存，开新局/读档时由 main 同步。
## 说话人标签「我」不替换 —— 只替换第三人称提到主角的地方。
class_name PlayerName
extends RefCounted

## 世界状态里的键。
const FLAG := &"player/name"
## 剧情数据里的占位符。
const TOKEN := "{name}"
## 老存档、跳章入口等没有起过名的情况用它。
const DEFAULT := "无名"
## 最多几个字（中文一字、英文一个字母都算一个）。
const MAX_LENGTH := 8

static var current: String = DEFAULT


## 校验并规整玩家输入：去掉首尾空白、英文单词之间的多余空格并为一个。
## 合法时返回规整后的名字，不合法返回空串（原因用 `problem()` 查）。
static func normalize(raw: String) -> String:
	var text := raw.strip_edges()
	while text.contains("  "):
		text = text.replace("  ", " ")
	return text if problem(text) == "" else ""


## 名字哪里不合规。合规返回空串。
##
## 只收中文（基本区汉字与「·」间隔号）和英文字母；英文名可以有空格。
static func problem(text: String) -> String:
	var name := text.strip_edges()
	if name == "":
		return "请输入昵称"
	if name.length() > MAX_LENGTH:
		return "最多 %d 个字" % MAX_LENGTH
	for i: int in name.length():
		var code := name.unicode_at(i)
		var latin := (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A)
		var han := code >= 0x4E00 and code <= 0x9FFF
		var dot := code == 0x00B7
		var space := code == 0x20
		if not (latin or han or dot or space):
			return "只能使用中文或英文字母"
	if name.begins_with("·") or name.ends_with("·"):
		return "间隔号不能放在开头或结尾"
	return ""


## 当前局的名字。读档/开局后由 main 调用。
static func sync_from(flags: WorldState) -> void:
	var stored: Variant = flags.get_value(FLAG) if flags != null else null
	var name := normalize(str(stored)) if stored is String else ""
	current = name if name != "" else DEFAULT


## 把名字写进本局世界状态并更新缓存。
static func assign(flags: WorldState, name: String) -> void:
	var clean := normalize(name)
	if clean == "":
		clean = DEFAULT
	current = clean
	if flags != null:
		flags.set_value(FLAG, clean)


## 把文字里的占位符换成当前名字。
static func apply(text: String) -> String:
	if not text.contains(TOKEN):
		return text
	return text.replace(TOKEN, current)
