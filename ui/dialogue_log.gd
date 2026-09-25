## 对话记录面板：盖在对话框上方，列出这一局里说过的所有话。
##
## 记录是**全局累积**的，不随单次对话结束而清空 —— 玩家点「记录」是想回看
## 前面说过什么，只有当前这段的话，这个功能就没用了。
##
## 用 RichTextLabel 而不是自己拼滚动列表：它自带滚动和自动跟随到底部。
class_name DialogueLog
extends CanvasLayer

const MARGIN := 12.0
const TOP := 14.0
const BOTTOM_MARGIN := 8.0
const BG_COLOR := Color(0.04, 0.05, 0.07, 0.96)
const EDGE_COLOR := Color(0.34, 0.46, 0.38, 1.0)
const NAME_COLOR := "#e8c07a"
const TEXT_COLOR := "#dcdcdc"

var _root: Control
var _edge: ColorRect
var _panel: ColorRect
var _view: RichTextLabel
var _hint: Label
var _open := false
## 自己数一遍条数，不去问 RichTextLabel 的行数
## —— 它的行数依赖字体排版，`--script` 模式下没渲染过，取不准。
var _count := 0
## 已经播过哪些行。**单独记一份**而不是去翻 RichTextLabel 的正文 ——
## 正文是排过版的（带颜色标签），从里面反查既慢又不牢靠。
## 「跳过已读」靠它判断。
var _seen: Dictionary = {}


func _ready() -> void:
	setup()


## 抽成显式方法，理由同 DialogueBox.setup()。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	layer = 20

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_edge = _make_rect("Edge", EDGE_COLOR)
	_panel = _make_rect("Panel", BG_COLOR)

	_view = RichTextLabel.new()
	_view.name = "Entries"
	_view.bbcode_enabled = true
	_view.scroll_following = true
	_view.add_theme_font_size_override("normal_font_size", 9)
	_view.add_theme_font_size_override("bold_font_size", 9)
	_root.add_child(_view)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "记录 · 按 L 或点这里关掉"
	_hint.add_theme_font_size_override("font_size", 8)
	_hint.add_theme_color_override("font_color", Color("#8a9a8e"))
	_root.add_child(_hint)

	_root.visible = false


func _make_rect(node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


## 追加一条。说话人为空时按旁白排版。
func add_entry(speaker: String, text: String) -> void:
	setup()
	_count += 1
	_seen[_key(speaker, text)] = true
	if speaker == "":
		_view.append_text("[color=%s]%s[/color]\n" % [TEXT_COLOR, _escape(text)])
	else:
		_view.append_text("[color=%s]%s[/color]  [color=%s]%s[/color]\n" % [
			NAME_COLOR, _escape(speaker), TEXT_COLOR, _escape(text),
		])


func clear() -> void:
	setup()
	_view.clear()
	_count = 0
	_seen.clear()


## 这一行以前播过吗。「跳过已读」用它决定能不能继续快进。
func has_seen(speaker: String, text: String) -> bool:
	setup()
	return _seen.has(_key(speaker, text))


static func _key(speaker: String, text: String) -> String:
	# 用一个正文里几乎不会出现的分隔符，免得「甲：好」和「甲：好吧」撞上
	return "%s%s%s" % [speaker, char(0x1F), text]


func open() -> void:
	setup()
	_layout()
	_root.visible = true
	_open = true
	# 打开时直接翻到最新一条
	_view.scroll_to_line(maxi(_view.get_line_count() - 1, 0))


func close() -> void:
	_root.visible = false
	_open = false


func is_open() -> bool:
	return _open


func entry_count() -> int:
	return _count


## BBCode 里的方括号要转义，否则台词里出现 `[` 会把排版吃坏。
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


## 同 DialogueBox：尺寸取自项目设置，不查 viewport。
func _layout() -> void:
	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)

	_root.position = Vector2.ZERO
	_root.size = view

	var width := view.x - MARGIN * 2.0
	var height := view.y - TOP - BOTTOM_MARGIN

	_edge.position = Vector2(MARGIN, TOP)
	_edge.size = Vector2(width, height)
	_panel.position = Vector2(MARGIN + 1.0, TOP + 1.0)
	_panel.size = Vector2(width - 2.0, height - 2.0)

	_view.position = Vector2(MARGIN + 5.0, TOP + 5.0)
	_view.size = Vector2(width - 10.0, height - 22.0)

	_hint.position = Vector2(MARGIN + 5.0, TOP + height - 15.0)
