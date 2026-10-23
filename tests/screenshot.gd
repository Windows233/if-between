## 跑起主场景，截一张图，然后退出。
##
## 无头模式用的是 dummy 渲染器，截出来是空的，所以可视验证必须开真实窗口。
## 窗口会一闪而过，不影响别的程序。
##
## 用法：
##   "<godot>" --path "<项目>" --script res://tests/screenshot.gd
##
## 输出：user://shot.png，也就是
##   %APPDATA%\Godot\app_userdata\<config name>\shot.png
extends SceneTree

## 等几帧再截，给场景构建和相机就位留时间
const WARMUP_FRAMES := 12
const SHOT_PATH := "user://shot.png"
var _frames := 0
## 已经跑了多少秒。真窗口里的帧率不是固定的（有时候几百帧一秒），
## 所以要「等十秒看开场演到哪」这种，只能按秒算。
var _elapsed := 0.0
## 这一张要等几帧再截。默认 `WARMUP_FRAMES`，
## 要抓「动画进行到一半」的画面（比如破碎飞散）就把它调大。
var _warmup := WARMUP_FRAMES
## 这一张要等**多少秒**再截。要抓「演出演到某一步」的画面时用这个，
## 按帧算会随帧率飘。见 `title_newgame_real`。
var _wait_seconds := 0.0
## 第几帧启动破碎。-1 表示不用。
## **现在没有模式用它了** —— 分支②的碎屏换成了夜间卧室里的 `glass`
## （见 `ch1_glass`）。留着是因为 `shatter` 这条指令还在引擎里，
## 以后哪段剧情要用，这个口子直接接得上。
## **不能在 `_initialize()` 里就启动** —— 那时一帧都还没画过，
## 视口还取不到画面，破碎会拿不到截图直接跳过。
var _shatter_at := -1
## 章标题 / 大图 / 屏幕正中的字在第几帧放。-1 表示不用。
## 和破碎同理：树还没就绪的时候放了，字会上不去。
var _banner_at := -1
var _photo_at := -1
## 屏幕正中那几行字（`caption`）在第几帧放，以及放的是哪几行。
## 放的是 `_caption_lines` 里的内容 —— 免得为了截一张图去写一段剧本。
var _caption_at := -1
## 碎玻璃特效排到第几帧摆上去。-1 表示不用。
var _glass_at := -1
## 摆上去时裂纹扩到哪儿。负数 = 用默认的「炸开完成」。
var _glass_spread := -1.0
## 睡前那段走位排到第几帧开演（**真实播放**，不即时）。-1 表示不用。
##
## 走的是剧本里那几条 `place_player`，不是这里另抄一份 —— 抄了就会跟剧本走偏。
## 2026-09-25 起量的是「躺到床上」那一次摆位：进卧室不再自动走路了，
## 玩家自己走到床前按交互才睡。
var _walk_at := -1
## 「躺床上」那一幕要不要等节点就绪后重摆一次（见 `_process` 开头）。
var _night_restage := false
var _caption_lines: Array = []
## 截完之后要删掉的存档槽位，-1 表示不用管
var _cleanup_slot := -1
## fade 模式用：第几帧触发传送、传到哪。-1 表示不触发。
var _travel_at := -1
var _travel_map: StringName = &""
var _travel_spawn: StringName = &"default"
## 这次切场景要不要**同步切**（不走转场）。
##
## 转场靠补间推进，截图那一刻很可能还停在黑屏里 ——
## 只想看「切过去之后是什么样」的场合要同步切。
var _travel_direct := false
var _main: Node2D = null


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		push_error("主场景加载失败")
		quit(1)
		return

	var main: Node2D = packed.instantiate()
	# 截图不要标题挡着 —— 真窗口模式下 `_ready` 会同步触发并打开标题。
	# 想截标题的模式自己调 `main.show_title()`。
	main.start_at_title = false
	# 截图拍的都是**正常流程**的画面，把「新游戏直接落进测试图」的调试开关关掉
	# （它现在是开着的，见 `scenes/main.gd` 的 `debug_start_map`；门卫室有
	# 自己的探针 `probe_gatehouse.gd`）。
	main.debug_start_map = ""
	# 截图拍的都是**正常流程**的画面，所以关掉「结局之后交还控制权」那个调试开关
	# （它现在是开着的，给布洛文走去卧室试碰撞箱用，见 `scenes/main.gd`）。
	main.free_roam_after_ending = false
	root.add_child(main)
	_main = main
	# --script 模式下 _ready 不会同步触发，显式拉起来
	main.boot()

	# 可选参数，依次是：场景 id、角色坐标、要不要先按一次交互键
	#   ... --script res://tests/screenshot.gd -- overworld
	#   ... --script res://tests/screenshot.gd -- desk_shop 152,82 talk
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and str(args[0]) != "":
		main.enter_map(StringName(args[0]), &"default")
	if args.size() > 1 and str(args[1]) != "":
		var parts: PackedStringArray = str(args[1]).split(",")
		if parts.size() == 2:
			main.player.global_position = Vector2(float(parts[0]), float(parts[1]))
	if args.size() > 2:
		match str(args[2]):
			"talk":
				main.interact()
			"choice":
				# 开场跑到底：选项框浮在对话框上方，两个人站在框里，
				# 中线上方还飘着「此处建议存档」
				main.cutscene.instant = true
				main.new_game()
				# 即时模式下 `caption` 是「摆上就不收」的（它算状态，不算演出），
				# 真实播放时那三句心声会自己淡掉。这一帧要看的是选项框，
				# 所以手动收一下 —— 真窗口烟测管的就是「真实那条路对不对」。
				main.stage_overlay.clear_caption()
			"ch1_title":
				# 章标题：黑幕 + 屏中央那行大字。
				# hold 给一个大数，字就停在屏上不走（不 await，让它自己挂着）。
				main.stage_curtain.snap_down()
				_banner_at = 4
			"rescue_scene":
				main.enter_map(&"school_yard", &"from_gate")
				main.stage_curtain.snap_up()
				main.player.global_position = Vector2(158, 186)
				main.cutscene.add_actor("c", "res://art/npc/c",
					Vector2(186, 88), 32.0, 12, "side")
			"rescue_panel":
				main.enter_map(&"school_yard", &"from_gate")
				main.stage_curtain.snap_up()
				main.player.global_position = Vector2(158, 186)
				main.cutscene.add_actor("c", "res://art/npc/c",
					Vector2(186, 88), 32.0, 12, "side")
				main.rescue_panel.allow_background_process = true
				main.rescue_panel.open()
			"rescue_portrait":
				main.enter_map(&"school_yard", &"from_gate")
				main.stage_curtain.snap_up()
				main.player.global_position = Vector2(158, 186)
				main.dialogue.play(Dialogue.from_array([{
					"speaker": "C", "text": "这样子啊~ 在下C，白塔分部下的一名专案员。",
					"side": "right", "portrait": "c_base",
				}]))
				main.dialogue.advance()
			"ch1_hearts":
				# 章标题之后浮出来的三句心声。**不走对话框** ——
				# 那会儿没有人在说话，底下冒一块面板像有人在念旁白。
				main.stage_curtain.snap_down()
				_caption_at = 6
				_caption_lines = [
					{"text": "如果那天我没有接那个委托……"},
					{"text": "你会不会回来……"},
					{"text": "不要走进那个黑夜……"},
				]
			"ch1_death":
				# end1：黑屏正中两行字，第二行小两号（稿子：「中心对称」）
				main.stage_curtain.snap_down()
				_caption_at = 6
				_caption_lines = [
					{"text": "end 1 平静即死亡", "size": 16},
					{"text": "你没有做错什么。你只是没有去", "size": 14},
				]
			"fx_glass":
				# 碎玻璃特效：黑底素材叠加，裂纹从正中炸开。
				# 第三个参数（可选）是裂纹扩到哪儿 —— 0.35 刚炸开、1.15 全铺满。
				# 不写就拍炸开完成的样子。
				#
				# **幕不压下来**：要看的正是「黑底消掉了、裂纹叠在画面上」，
				# 压黑就成了一片黑上几道亮纹，看不出黑底到底有没有消掉。
				main.enter_map(&"desk_shop", &"start")
				main.stage_curtain.snap_up()
				_glass_spread = float(args[3]) if args.size() > 3 else -1.0
				_glass_at = 4
			"ch1_wake":
				# 醒来：人站在桌后面朝下，左上角注明日期地点，主角在框左侧说话
				_stage_wake(main)
				main.dialogue.play(Dialogue.from_array([{
					"speaker": "我", "text": "……又是这个梦，好烦。",
					"side": "left", "portrait": "protagonist/puzzled",
				}]))
				main.dialogue.advance()
			"ch1_elder":
				# 老人从门口走到桌前站着说话。他站在**会挡人的书桌前面**，
				# 层级要给到桌子之上（z=12），不然被桌子切掉半截。
				_stage_wake(main)
				_focus_scene(main)
				main.cutscene.add_actor("elder", "res://art/portrait/elder.png",
					Vector2(224, 160), 45.0, 12)
				main.dialogue.play(Dialogue.from_array([{
					"speaker": "老人", "text": "……你这里，接找猫的活吗？",
					"side": "right", "portrait": "elder",
				}]))
				main.dialogue.advance()
			"ch1_photo":
				# 那张模糊的猫的照片
				_stage_wake(main)
				_photo_at = 4
			"ch1_walk":
				# 睡前走向床边那一段（**真实播放**）。要盯两件事：
				# 人走的时候**露的是不是该露的那一面**（往右走不该露背面 ——
				# 那是 2026-09-24 策划报的那条），以及路线有没有贴着墙走断。
				#
				# 第 4 个参数是「等几秒再截」，对上走位里的某一刻：
				#   0.2 秒 = 刚起步（往右一步）、1.0 秒 = 正在往上走（该露背面）、
				#   2.6 秒 = 正在往右走（该露侧面）
				main.enter_map(&"bedroom_night", &"from_desk")
				main.stage_curtain.snap_up()
				# 截图工具里没有剧情在跑，`story.is_active()` 是 false ——
				# 物理还开着，每帧都会把动画压回站立。真实剧情里这一步是
				# 由它挡住的，工具里得自己按住。
				main.player.pinned = true
				main.update_player_control()
				_walk_at = 4
				if args.size() > 3:
					_wait_seconds = float(str(args[3]))
			"ch1_night":
				# 夜里那场梦：切到夜间卧室，人仰面躺在床上（猫叫之前那一瞬）。
				# 要看的正是「头有没有躺进枕头里」。
				_stage_night(main)
			"ch1_glass":
				# 紧接着猫叫就是碎屏：黑底玻璃素材从正中炸开。
				# **幕不压** —— 压黑是剧本里的下一步，这一张要看的是玻璃本身。
				_stage_night(main)
				_glass_at = 4
			"choice_esc":
				# 剧情等着选的时候按 ESC：暂停菜单**压在选项框上面**，
				# 选项还在底下留着。
				#
				# 旧的样子是反的（选项框 layer 15 > 暂停菜单 14），
				# 菜单开出来了却被选项框盖住，看着像「按了没反应」。
				main.cutscene.instant = true
				main.new_game()
				main.stage_overlay.clear_caption()
				main._unhandled_input(_key(KEY_ESCAPE))
			"ch1_hud_gone":
				# 醒来那一幕再过几秒：左上角那行状态该自己收掉了。
				# 跟 `39_ch1_wake_newlayout.png` 对着看 —— 同一个位置，
				# 那张有「xx月x日 傍晚 委托屋」，这张没有。
				_stage_wake(main)
				_wait_seconds = LocationHud.LIFE + 1.5
			"bag":
				# 背包：三件东西，右下角那个图标常驻
				main.enter_map(&"desk_shop", &"start")
				main.stage_curtain.snap_up()
				ItemTable.add(main.flags, &"cat_photo")
				ItemTable.add(main.flags, &"pendant")
				ItemTable.add(main.flags, &"night_tear", 3)
				main.toggle_inventory()
			"hover":
				# 模拟鼠标停在地图上的某个地点上，把详情截下来。
				#
				# **参数位置看文件头**：`args[0]` 是地图名、`args[1]` 占位、
				# `args[2]` 才是模式，再往后各模式自己用。
				# 大地图要这么传：
				#   ... -- overworld 0 hover 246.7,218.3
				# （坐标不传就停在左起第一个地点。）
				#
				# 用 hover_point_override 而不是自己每帧钉：
				# 那样会被 main 自己的 _process 用真实鼠标覆盖掉。
				var at := Vector2(28.3, 186.7)
				var raw := str(args[3]) if args.size() > 3 else ""
				var xy: PackedStringArray = raw.split(",")
				if xy.size() == 2:
					at = Vector2(float(xy[0]), float(xy[1]))
				main.hover_point_override = at

			"ifpanel":
				# IF 条件框。**默认摆成教学那一步的样子** —— 这样截出来的就是
				# 玩家会看到的东西（块的位置、名字在不在方块里、确定按钮歪不歪）。
				#   参数 3 传 `empty`    → 空白的标准状态
				#   参数 3 传 `readonly` → 老人那一步（两块固定的纯展示框）
				main.if_panel.setup()
				var mode := str(args[3]) if args.size() > 3 else ""
				if mode == "empty":
					main.if_panel.open()
				elif mode == "readonly":
					main.if_panel.open("", "来找主角帮忙", "猫不见了")
					for i: int in 4:
						main.if_panel.set_slot_block(i, "")
					main.if_panel.set_read_only(true)
					main.if_panel.remember_layout()
				else:
					main.if_panel.open("", "观察", "发现异常")
					main.if_panel.set_slot_block(0, "")
					main.if_panel.set_slot_block(1, "立即离开")
					main.if_panel.set_slot_block(2, "")
					main.if_panel.set_slot_block(3, "")
					main.if_panel.remember_layout()
			"line":
				# 触发交互，然后把对话推到指定行，用来截某一句的画面。
				# 行号用参数 3（从 0 起算），朝向用参数 4（up/down/left/right，默认 down）。
				# **朝向不对就点不到东西** —— 交互只认角色面前那一个方向，
				# 所以想截哪件东西的台词，得先站到它南边并说清朝哪儿看。
				var dir := str(args[4]) if args.size() > 4 else "down"
				match dir:
					"up":
						main.player.facing = Vector2.UP
					"left":
						main.player.facing = Vector2.LEFT
					"right":
						main.player.facing = Vector2.RIGHT
					_:
						main.player.facing = Vector2.DOWN
				main.interact()
				var target := 0
				if args.size() > 3:
					target = int(str(args[3]))
				var guard := 0
				while main.dialogue.is_open() and guard < 40:
					if main.dialogue.current_index() >= target:
						break
					main.dialogue.advance()
					main.dialogue.advance()
					guard += 1
				# 让这行的字显示完，不然截到的是半句话
				if main.dialogue.is_revealing():
					main.dialogue.advance()
			"fade":
				# 截转场中途：画面应该正黑下去。
				# 转场依赖补间、补间靠帧推进，所以触发要**排到第 N 帧**再发生，
				# 不能写在 _initialize 里 —— 那时一帧都还没跑。
				_travel_at = 8
				_travel_map = StringName(args[3]) if args.size() > 3 else &"desk_shop"
				_travel_spawn = &"default"
			"save":
				# 先做出一点值得一存的状态，再存档，把提示条截下来。
				# 存档按了之后画面上看不出变化，全靠这条提示告诉玩家存上了。
				main.cutscene.instant = true
				main.new_game()
				main.choice_menu.select_id(&"accept")
				main.choice_menu.confirm()
				_drain(main)
				# 用测试槽位，截完删掉，不弄脏玩家自己的存档
				main.save_game(2)
				_cleanup_slot = 2
			"ending":
				# 开场走到底：选「不接受委托」，一路到 end1 的结局画面。
				# 走的是即时演出 —— 截的是结局文字那一帧，不用真等二十秒。
				main.cutscene.instant = true
				main.new_game()
				main.choice_menu.select_id(&"decline")
				main.choice_menu.confirm()
				_drain_until(main, "结局")
				# 翻到简介那句再截，比光秃秃的标题有味道。
				# 注意 advance() 第一次只把字显示完，第二次才翻页。
				if main.dialogue.is_revealing():
					main.dialogue.advance()
				main.dialogue.advance()
				if main.dialogue.is_revealing():
					main.dialogue.advance()
			"after":
				# 开场走完、选①，用来看「选完之后场景变成什么样」
				main.cutscene.instant = true
				main.new_game()
				main.choice_menu.select_id(&"accept")
				main.choice_menu.confirm()
				_drain(main)
			"ending_title":
				# 分支②走到底：结局文字念完之后**回主界面**，
				# 不是把控制权还给玩家。截的是标题这一帧。
				main.cutscene.instant = true
				main.new_game()
				main.choice_menu.select_id(&"decline")
				main.choice_menu.confirm()
				_drain(main)
			"title_newgame":
				# 标题 → 点「新游戏」，走的是**跳过开场**那条路（调试开关打开时
				# 的路径）。用来盯 2026-09-23 那次「开游戏黑屏，只剩背包图标」：
				# 幕要是没揭开，这张图就是全黑的。
				main.skip_opening = true
				main.show_title()
				main.title_screen.select_index(0)
				main.title_screen.handle_key(KEY_ENTER)
			"title_newgame_real":
				# 标题 → 新游戏，走**真实默认**那条路：开场照演。
				#
				# 2026-09-23 晚踩过第二次：调试开关 `skip_opening` 忘了改回来，
				# 点新游戏直接落进场景，看着像「剧情没触发」。
				# 这条把时间等够（十秒上下），拍到的应该是醒来那一幕；
				# 拍出来是空房间就说明开场没演。
				main.show_title()
				main.title_screen.select_index(0)
				main.title_screen.handle_key(KEY_ENTER)
				_wait_seconds = 10.0
			"title":
				# 标题界面本身。底部那行按键说明是它的重点 ——
				# 「游戏里到底有哪些键」只有这儿会告诉玩家。
				main.show_title()
			"desk_back":
				# 站在书桌**后面**：桌子该盖住腰以下。
				# 站到哪由参数 4 给（默认按实测的最北 147），
				# 用来比较「脚再往南挪多少才不会被整个盖住」。
				_desk_shot(main, float(str(args[3])) if args.size() > 3 else 147.0)
			"desk_front":
				# 站在书桌**前面**：人该盖住桌子。
				_desk_shot(main, float(str(args[3])) if args.size() > 3 else 166.0)
			"pause":
				# 游戏中的暂停菜单（ESC）：中间一个面板，后面能看见房间
				main.enter_map(&"desk_shop", &"start")
				main.stage_curtain.snap_up()
				main.open_pause_menu()
			"settings_volume":
				# 设置面板最下面那两根音量滑块。光标停在音乐那根上 ——
				# 要看的正是「光标行、槽、填充长度、右边那个百分比」四样对不对。
				main.enter_map(&"desk_shop", &"start")
				main.stage_curtain.snap_up()
				main.open_settings()
				var panel: SettingsPanel = main.settings_panel
				panel.handle_key(KEY_DOWN)
				panel.handle_key(KEY_DOWN)
				panel.handle_key(KEY_DOWN)
			"pause_settings":
				# 从暂停菜单开设置 —— 看的是**层号对不对**：
				# 设置面板得画在暂停菜单上面，而暂停菜单还在下面留着
				main.enter_map(&"desk_shop", &"start")
				main.stage_curtain.snap_up()
				main.open_pause_menu()
				main.pause_menu.select_index(1)
				main.pause_menu.handle_key(KEY_ENTER)


## 从剧本里捞出指定的那几条指令，照原样演一遍。
##
## **不在这个工具里另抄一份坐标。** 抄了就一定会跟剧本走偏 ——
## 截图看到的和游戏里看到的成了两张画，而这个项目在这上面栽过好几次
## （`_stage_wake` / `_stage_night` 那两处就是为了对齐剧本，注释里写着「改一边要改两边」）。
##
## `with_path` 为真时只挑带路径点的那一条（「一段路走过去」的写法）。
## 2026-09-25 起剧本里没有这种写法了 —— 进卧室不再自动走路，
## 这个开关先留着，将来谁再用路径点走位可以直接要。
func _steps_of(event_id: StringName, node_id: StringName, kind: StringName,
		with_path: bool) -> Array[StageStep]:
	var out: Array[StageStep] = []
	var event := DataLoader.load_event(event_id)
	if event == null:
		push_error("截图：读不到剧本 %s" % event_id)
		return out
	var node := event.node(node_id)
	if node == null:
		push_error("截图：剧本 %s 里没有节点 %s" % [event_id, node_id])
		return out
	for step: StageStep in node.stage:
		if step.kind != kind:
			continue
		if with_path and step.points("path").is_empty():
			continue
		out.append(step)
	if out.is_empty():
		push_error("截图：%s.%s 里没找到 %s" % [event_id, node_id, kind])
	return out


## 摆出「主角在委托屋桌上醒来」那一幕：屋子亮着、人站在桌子后面朝下，
## 左上角注明日期地点。
##
## 坐标跟剧本里 `wake` 节点写的是同一个（`ch1_opening.json`）—— 改剧本时
## 这里要跟着改，不然截图和游戏里看到的不是一回事。
##
## 不跑整段演出 —— 截图只想看这一帧长什么样，
## 把二十秒的过场跑一遍纯属浪费时间，而且中间还看不了。
func _stage_wake(main: Node2D) -> void:
	main.enter_map(&"desk_shop", &"start")
	main.stage_curtain.snap_up()
	main.player.global_position = Vector2(224, 130)
	main.player.facing = Vector2.DOWN
	main.player.play_animation(false)
	main.show_location("3036年9月24日　16:40　委托屋")
	main.update_cover()
	main.update_camera()


## 把镜头框在「两个人都在画面里」的位置，和过场里那一段一致。
##
## 人站在桌后（脚 130）、老人站在桌前（脚 160），镜头压到 141 时两个人
## 都在对话框上沿之上 —— 这个数跟着剧本里的 `focus` 走。
func _focus_scene(main: Node2D) -> void:
	main.camera_focus = Vector2(224, 141)
	main.update_camera()


## 夜里那场梦：切到「床上躺着人」那张图、**把玩家藏起来**、镜头推到床上。
##
## **2026-09-25 策划改的**：不再往床上摆小人 —— 场景图直接换成
## `bedroom_night_sleep`（图上本来就画着躺的人），人藏起来，镜头推过去。
##
## **别再退回「摆小人」那套。** 那套要按头定位、要 `pinned` 按住不让物理
## 把他推出来，还得让 `update_player_control()` 过一遍 —— 一堆讲究；
## 换图之后这些都不需要。要改两边一起改：剧本 `declined` / `ch1_bed` 的 `bed`。
func _stage_night(main: Node2D, restage: bool = true) -> void:
	if restage:
		# 这次是在 `_initialize` 里跑的，摆完可能被第一个物理步顶掉 ——
		# 让 `_process` 等节点就绪后再摆一次（详见 `_process` 开头那段）。
		_night_restage = true
		main.enter_map(&"bedroom_night_sleep", &"from_desk")
		main.stage_curtain.snap_up()
	# 重摆的时候**不要再 `enter_map`** —— 那会重建整个场景，
	# 顺带把幕布重新动一遍，截出来整张图是暗的（踩过）。
	main.player.visible = false
	main.camera_focus = Vector2(336, 100)
	main.update_camera()


## 站在书桌前后的画面。`feet_y` 是**实测**能站到的位置
## （`tests/probe_desk.gd` 推着角色撞住为止），不是手算的 ——
## 手算会漏掉脚底方块那 16 个像素。
func _desk_shot(main: Node2D, feet_y: float) -> void:
	main.enter_map(&"desk_shop", &"start")
	main.stage_curtain.snap_up()
	main.player.global_position = Vector2(224, feet_y)
	main.player.facing = Vector2.UP
	main.player.pinned = true
	main.player.play_animation(false)
	main.update_cover()
	main.update_camera()


## 一路推到某句台词出现为止，或者对话关掉、选项弹出。
##
## 结局演出是**接着**上一段对话自动播的，用 `_drain` 会把它一起推没，
## 所以这里只推到目标那句就停。
func _drain_until(main: Node2D, prefix: String) -> void:
	var guard := 0
	while guard < 60:
		if not main.dialogue.is_open():
			return
		if main.dialogue.current_text().begins_with(prefix):
			return
		if main.choice_menu.is_open():
			return
		main.dialogue.advance()
		guard += 1


## 造一个「按下去」的键盘事件，喂给 `main._unhandled_input()`。
## 截图里要复现「按键之后画面长什么样」时用它。
func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


## 把对话一路推到底（每行要按两下：先显示完，再翻页）。
## 加次数上限，免得剧情有环的时候把截图卡死。
func _drain(main: Node2D) -> void:
	var guard := 0
	while main.dialogue.is_open() and guard < 40:
		main.dialogue.advance()
		main.dialogue.advance()
		guard += 1


func _process(delta: float) -> bool:
	_frames += 1
	_elapsed += delta

	# 「躺床上」那一幕要等节点就绪之后重摆一次。
	#
	# `_stage_night` 是在 `_initialize` 里跑的，那会儿节点还没 ready ——
	# `set_physics_process(false)` 落不了地，脚本里那句「物理在跑吗」照样报 false，
	# 但第一个物理步一跑，落在床箱里的人就被分离修正顶出去了：
	# 实测 x 从 336 变 317.3，画面上人站到床左沿去了。
	# 剧情里没这毛病（演出时节点早就 ready），只有这个 `--script` 工具会踩到。
	if _night_restage and _frames >= 2 and _main != null:
		_night_restage = false
		_stage_night(_main, false)

	# 排到第几帧才做的那些动作（转场、破碎、插图、屏中央的字）先跑 ——
	# 它们跟「什么时候截图」是两件事，不该被等待时间挡住。
	if _travel_at >= 0 and _frames == _travel_at and _main != null:
		# 排到第 N 帧才切：在 `_initialize` 里直接切会被 `boot()` 之后的
		# 流程覆盖掉，截出来还是起始场景。
		if _travel_direct:
			_main.enter_map(_travel_map, _travel_spawn)
		else:
			_main.travel_to(_travel_map, _travel_spawn)
	if _shatter_at >= 0 and _frames == _shatter_at and _main != null:
		_main.stage_overlay.shatter(2.0)
	if _banner_at >= 0 and _frames == _banner_at and _main != null:
		var overlay: StageOverlay = _main.stage_overlay
		overlay.show_banner("第一章　猫", 999.0, 0.0)
	if _photo_at >= 0 and _frames == _photo_at and _main != null:
		var overlay: StageOverlay = _main.stage_overlay
		overlay.show_image("res://art/item/cat_photo.png", 0.0)
	if _caption_at >= 0 and _frames == _caption_at and _main != null:
		_main.stage_overlay.show_caption(_caption_lines, 0.0)
	if _glass_at >= 0 and _frames == _glass_at and _main != null:
		var glass: StageOverlay = _main.stage_overlay
		glass.glass_show()
		if _glass_spread >= 0.0:
			glass.set_glass_spread(_glass_spread)
	if _walk_at >= 0 and _frames == _walk_at and _main != null:
		_main.cutscene.run(_steps_of(&"ch1_bed", &"bed", &"place_player", false))

	if _frames < _warmup or _elapsed < _wait_seconds:
		return false

	# 对位用：把「世界坐标 -> 屏幕像素」要用的几个量打出来。
	# 有一次为了查「人躺到床头板上去了」绕着这个换算折腾了很久 ——
	# 有这几行，一眼就能算出某个世界坐标该落在屏幕的哪个像素上。
	var vp: Viewport = root.get_viewport()
	var view_size: Vector2 = vp.get_visible_rect().size if vp != null else Vector2.ZERO
	print("[截图] 视口 %s   窗口 %s" % [view_size, root.size])
	if _main != null and _main.player != null:
		var feet: Vector2 = _main.player.global_position
		print("[截图] 相机 %s   角色脚 %s   头心 %s"
			% [_main.camera.global_position, feet,
				feet + _main.player.head_offset()])
		if view_size.x > 0.0:
			var origin: Vector2 = _main.camera.global_position - view_size * 0.5
			print("[截图] 世界原点 %s   每世界单位 %.3f 物理像素"
				% [origin, root.size.x / view_size.x])

	# 多等一帧再截图：get_texture() 拿的是**上一帧**已经渲染完的画面，
	# 这一帧刚改的东西还看不到。
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("拿不到画面")
		quit(1)
		return true

	var err := image.save_png(SHOT_PATH)
	if err != OK:
		push_error("截图保存失败，错误码 %s" % err)
		quit(1)
		return true

	print("截图已保存：", ProjectSettings.globalize_path(SHOT_PATH))
	# 截图已经落盘，这时候再清掉测试用的存档
	if _cleanup_slot >= 0:
		SaveStore.delete(_cleanup_slot)
	quit(0)
	return true
