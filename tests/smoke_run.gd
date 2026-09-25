## 真窗口跑一遍第一章开场，看有没有哪里不对。
##
## 无头那套测试里，演出走的是**即时模式**：不等动画、不等计时器、不等点击。
## 真跑起来完全是另一条路 —— 黑幕是淡出来的、老人是走过去的、
## 破碎要截当前画面。所以给人玩之前，必须在真窗口上真跑一遍。
##
## 用法（**必须开真窗口**，无头是 dummy 渲染器）：
##   "<godot>" --path "<项目>" --script res://tests/smoke_run.gd
##
## **只跑到「选完 IF」那一步（十来秒），到那儿就收。**
## 选完之后的碎玻璃、结局文字、回主界面那一截**不在真窗口上验** ——
## 那些无头测试（`test_cutscene` / `test_ending_save`）照样验得到，
## 每跑一遍多花二十秒不值。**别再给它加一档「完整版」**
##（2026-09-24 真有过一档 `--full`，策划看过之后说那半段没意义，删了）。
##
## 退出码 0 = 全程没报错，1 = 中途出问题。
extends SceneTree

## 整段最多跑这么久（秒）。真时间是真跑的，超过就是哪儿卡住了。
const TIME_LIMIT := 60.0

## 选完 IF 之后再看这么久就收。
##
## 留这两秒是为了**让选择的结果真的演出来一下**（对话框重新出现、演出接着推），
## 而不是选完立刻断言 —— 那样等于没验「选完以后还活着」。
const TAIL := 2.0

## 收尾计时。选完之后开始数。
var _tail := 0.0

var _main: Node2D = null
var _problems: Array[String] = []
var _elapsed := 0.0
## 一路上看见过什么。演出是一次性的，只看最后的状态看不出中间演没演。
var _seen: Dictionary = {}


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		print("[烟测] 主场景加载失败")
		quit(1)
		return

	var main: Node2D = packed.instantiate()
	# 烟测自己控制什么时候开标题，别让 `_ready` 抢先
	main.start_at_title = false
	# 这一路走到的是「选完 IF」，碰不到结局那条路；把结局之后的调试口子关掉，
	# 免得哪天它开着把这一路的落点搅了（那条路见 `test_free_roam_after_ending`）。
	main.free_roam_after_ending = false
	root.add_child(main)
	_main = main
	main.boot()

	print("")
	print("=== 烟测 · 第一章开场（真窗口）===")
	print("[烟测] 视口 %dx%d" % [
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	])
	print("[烟测] 新开一局，开演")
	# 走真实那条入口：黑屏 -> 章标题 -> 独白 -> 醒来 -> 老人上门 -> ...
	main.new_game()


func _process(delta: float) -> bool:
	_elapsed += delta
	var main := _main
	_watch(main)

	# 替玩家按键：对话框开着就把这几句推过去，
	# 演出停在「点击一次」上就替他点一下。
	if main.dialogue.is_open():
		main.dialogue.advance()
		main.dialogue.advance()
	if main.cutscene.is_waiting_click():
		main.cutscene.consume_click()

	# 开场的 IF：选「不接受委托」，走 end1 那条线
	if main.choice_menu.is_open() and not _seen.has("picked"):
		_seen["picked"] = true
		print("[烟测] 选择框出现了，选「不接受委托」")
		main.choice_menu.select_id(&"decline")
		main.choice_menu.confirm()

	# 选完之后再演两秒就收（理由见 `TAIL`）
	if _seen.has("picked"):
		_tail += delta
		if _tail >= TAIL:
			return _report(main)

	if _elapsed > TIME_LIMIT:
		print("  × 超时：跑了 %.1f 秒还没走完，停在 %s"
			% [_elapsed, main.story.current_node_id()])
		_problems.append("超时")
		return _report(main)
	return false


## 把「演到过什么」记下来。演出是一次性的，等跑完再看状态就晚了。
func _watch(main: Node2D) -> void:
	# 成员取出来是 Variant，派生的类型要自己标 —— 不标就推断不出来
	var overlay: StageOverlay = main.stage_overlay
	if overlay != null:
		var banner := overlay.banner_text()
		if banner != "":
			_seen["banner"] = banner
		if overlay.has_image():
			_seen["photo"] = true
		if overlay.is_glass():
			_seen["glass"] = true
		# 黑屏正中那几行字：开场的三句心声走它
		if overlay.caption_lines() > 0:
			_seen["caption"] = true
	var hud: LocationHud = main.location_hud
	if hud != null and hud.is_open():
		_seen["location"] = hud.current_text()
	# 提示条上的每一句话都记下来 —— 它是几秒就没的，
	# 跑完再看状态什么都问不到
	if main.toast.is_open():
		_seen["toast_" + main.toast.current_text()] = true
	if main.dialogue.is_holding():
		_seen["hold"] = true
	if main.stage_curtain.is_down():
		_seen["black"] = true
	# 老人上场之后是**会走路**的那种（`AnimatedSprite2D`），
	# 不是一张立绘在场上滑过去。真窗口才验得到 —— 演出得真跑一遍。
	#
	# 注意函数名是 `actor_ids()`。写错一个名字的话，`_watch` 每帧抛异常，
	# **这一段后面的采样全都不会执行** —— 表现是「音乐那条也跟着红了」，
	# 而真正的原因在两行之外（2026-09-24 踩过：刷了九千多行 SCRIPT ERROR）。
	if main.cutscene != null and main.cutscene.actor_ids().has("elder"):
		_seen["elder_animated"] = main.cutscene._actors["elder"] is AnimatedSprite2D
	# 背景音乐**真在响没有**：无头测试和截图都听不见，只有真窗口能问这一句。
	# 记的是「哪一首在响」—— 一路会换好几首，光记「响过」分不出是哪首。
	if main.bgm != null and main.bgm.playing:
		_seen["music_" + main.current_music()] = true


func _expect(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  ✓ %s" % label)
		return
	print("  × %s —— 期望 %s，实际 %s" % [label, var_to_str(expected), var_to_str(actual)])
	_problems.append(label)


func _report(main: Node2D) -> bool:
	print("")
	print("[烟测] 一共跑了 %.1f 秒" % _elapsed)
	_expect("黑过屏", _seen.has("black"), true)
	_expect("章标题上过屏", _seen.get("banner", ""), "第一章　猫")
	_expect("黑屏正中的字浮过", _seen.has("caption"), true)
	_expect("左上角注过日期地点", _seen.get("location", ""), "xx月x日　傍晚　委托屋")
	_expect("大图亮过", _seen.has("photo"), true)
	_expect("拿到东西报了喜", _seen.has("toast_获得 猫的照片"), true)
	_expect("选项前提示过存档", _seen.has("toast_此处建议存档"), true)
	_expect("选项框出现过（对话框留着等选择）", _seen.has("hold"), true)
	# 委托屋该有曲子，而且在响（真窗口里能验 —— 无头模式播不出来）
	_expect("委托屋的曲子在放",
		_seen.has("music_res://audio/bgm/主角店内.mp3"), true)
	# 老人是动画小人，不是在滑一张贴纸
	_expect("老人会走路（是动画角色）", _seen.get("elder_animated", false), true)
	# 选完之后演出还活着（这两秒里没有报错、也没卡死）
	_expect("选完之后剧情还在跑", main.story.is_active(), true)

	# 这一路没换过场景、也没强制落位，人不该被按住
	_expect("人没被按住", main.player.pinned, false)

	# 暂停真的把世界停住没有。**只有真窗口能验** ——
	# `--script` 模式下 SceneTree 还没被引擎激活，`get_tree()` 是 null
	# （`test_menus` 那边的注释里有实测数据）。
	#
	# 放在最后：前面那几条是**现查**当前状态的，先在这儿换场景会把它们看的状态搅掉。
	var tree := main.get_tree()
	_expect("拿得到 SceneTree", tree != null, true)
	if tree != null:
		main.enter_map(&"desk_shop", &"start")
		main.open_pause_menu()
		_expect("开菜单后世界真的暂停", tree.paused, true)
		# 菜单自己不能被冻上，不然接不到键、关不掉，就成了死局
		_expect("暂停菜单自己还活着", main.pause_menu.is_open(), true)
		main.pause_menu.close()
		_expect("关菜单后世界恢复", tree.paused, false)

	print("")
	if _problems.is_empty():
		print("=== 烟测通过：真窗口上这一路没有问题 ===")
		quit(0)
		return true
	print("=== 烟测有问题 %d 条 ===" % _problems.size())
	quit(1)
	return true
