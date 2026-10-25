## 游戏入口：组装各个部件，管场景切换、相机、交互、输入。
##
## 场景切换用的是「重建可视、保留角色」：MapView 重来一遍，Player 只挪位置。
## 这样角色身上挂的状态（速度、以后的存档标记）不用搬来搬去。
##
## **别往这里塞新东西。** 已经拆出去的五块：
##   剧情推进与演出 → `core/story_director.gd`
##   存档的组装与反馈 → `scenes/save_manager.gd`（文件读写在 `scenes/save_store.gd`）
##   读数据文件 → `scenes/data_loader.gd`
##   相机怎么夹边界 → `scenes/game_camera.gd`
##   角色长什么样 → `scenes/player.gd` 的 `Player.create()`
##
## 这里只留「谁跟谁连起来」这种活：状态给谁、信号转给谁、按键先问谁。
extends Node2D

const START_MAP: StringName = &"desk_shop"
## 新开一局要演的那段。开场的黑屏、章标题、醒来、上门委托都在里面，
## 见 `data/events/ch1_opening.json`。
const OPENING_EVENT: StringName = &"ch1_opening"
const START_SPAWN: StringName = &"start"
const PERSONAL_ANCHOR_SCRIPT = preload("res://core/personal_anchor.gd")
const CHASE_OVERLAY_SCRIPT = preload("res://ui/chase_overlay.gd")
const CHASE_SESSION_SCRIPT = preload("res://scenes/ch2_chase_session.gd")
## 从「出门」连接进入的大地图
const OVERWORLD_MAP: StringName = &"overworld"

## 标题界面的曲子。**现在是一秒静音，占位。**
##
## 策划还没给菜单曲，先拿静音文件顶着：**「标题有音乐」这条路已经通了**，
## 真曲子到位时只换文件内容，代码一行不用动。
##
## 为什么不干脆留空（`""`）：那等于「标题没有音乐」，`show_title()` 会去停音乐，
## 将来加曲子还得回来改这里。留个文件占着位子最省事。
##
## 标题是「还没有进任何场景」的状态，所以它不挂在任何地图数据上，
## 就写在这儿；`show_title()` 每次都会把它换上去。
## 标题界面上放的那首。
##
## **不跟着地图走** —— 标题不是一张地图，它没有 `music` 字段可填，
## 所以这一首写死在代码里。要换曲子改这一行。
##
## 2026-09-24 从《主菜单占位》换成正式那首（池頼広的《災いの樹》home 编曲版），
## 占位那个文件已经删了 —— 名字里带「占位」的东西留在仓库里，
## 迟早会有人以为那还是现在用的。
const TITLE_MUSIC := "res://audio/bgm/主菜单.mp3"
## 按交互键时，离多近的角色算「够得着」
const INTERACT_RANGE := 24.0

var map_view: MapView
var player: Player
## 相机是独立节点，不挂在角色下面。怎么夹边界见 `scenes/game_camera.gd`。
var camera: GameCamera
var dialogue: DialogueBox
var choice_menu: ChoiceMenu
var rescue_panel: RescuePanel
var chase_overlay: ChaseOverlay
var chase_session: Ch2ChaseSession
var tooltip: MapTooltip

## IF 条件框。剧情里「观察」之后弹出来的那个。
##
## **不挂进 `ui_host`**：它不是「玩家要操作的界面」，是剧情里的一个展示 ——
## 剧情演着的时候角色本来就动不了，用不着参与 `is_busy()` / `_top()` 那套。
var if_panel: IfPanel
## IF 框那层画布（15：盖在演出层 14 上面）。
var if_panel_layer: CanvasLayer
var toast: Toast
var fade: ScreenFade
## 结局图鉴界面。跨存档的全局记录在 `gallery`，这里是看它的那个面板。
var gallery_panel: EndingGalleryPanel
## 存读档菜单：选槽位、存、读、删
var save_menu: SaveMenu
## 标题界面：新游戏 / 继续 / 图鉴 / 设置
var title_screen: TitleScreen
## 游戏中的暂停菜单（ESC）：继续 / 设置 / 保存 / 加载 / 回主菜单 / 退出
var pause_menu: PauseMenu
## 设置面板。设置本身在 `settings`。
var settings_panel: SettingsPanel
## 过场里临时出现的东西（老人这种）。换场景时会清空。
## 单独一层而不是塞进 `map_view`：那个一 `build()` 就整块重来，
## 临时角色会被顺手清掉。
var stage_view: Node2D
## 过场黑幕。**在对话框下面** —— 黑屏上还要显示台词。
var stage_curtain: StageCurtain
## 过场覆盖层：章标题、屏幕中央的大图、画面碎掉。在对话框上面。
var stage_overlay: StageOverlay
## 演出执行器：把演出指令翻成实际动作。
var cutscene := Cutscene.new()
## 左上角的日期 / 时间 / 地点，一行常驻的小字。
var location_hud: LocationHud
## 音效播放器。挂 `SFX` 总线，音量归设置里那根音效滑块。
## 演出里的 `play_sound` 走它。**只有一个** —— 后一条会顶掉前一条。
##
## 脚步和开门也走它。这两样都能容忍被打断：脚步音本来就只有零点几秒，
## 而开门声在它响的同一瞬间就开始转场了，没人会去分辨有没有播完。
var sfx: AudioStreamPlayer

## 进出门时响的那一声。**所有门共用** —— 现在只有这一个素材，
## 以后要给不同的门配不同的声音，得先让 `Portal` 能带字段。
const DOOR_SOUND := "res://audio/sfx/door_open.wav"

## 每走这么远响一次脚步（像素）。
##
## 按**走过的距离**触发，不按时间：走快走慢，步子该是一个一个踩出来的，
## 而不是按秒表响。角色 96 像素/秒，24 像素大约 0.25 秒一步，接近真人步频。
##
## 具体响什么由地图的 `footstep` 字段决定，**留空就是没有**（户外不响）。
const FOOTSTEP_DISTANCE := 24.0

## 上一次响脚步时，主角站在哪儿。
var _footstep_at := Vector2.ZERO

## 背景音乐播放器。挂 `Music` 总线，曲子由地图数据的 `music` 字段决定。
var bgm: AudioStreamPlayer
## 现在挂上的是哪首曲子。切场景时靠它判断要不要换 ——
## 同一首还在播就别从头再来。
var _bgm_path := ""
## 背包。身上有什么、各有几件，内容在 `flags` 里（`item/<id>` 键）。
var inventory: InventoryPanel

## 菜单是给谁弹的。选完之后靠它找到对应的动作。
var pending_actor: MapDef.Actor = null

## 玩家的选择与剧情状态。跨场景、跨事件一直累积，也是存档要存的东西。
var flags := WorldState.new()
## 剧情导演。推进与演出都在它那里，这里只负责把信号转过去。
var story := StoryDirector.new()
var map_triggers := preload("res://scenes/map_trigger_runner.gd").new()
## 整个游戏有哪些结局。达成进度存在 `flags` 里，键是 `ending/<id>`。
var endings := EndingTable.new()
## 游戏里有哪些物品。数量就存在 `flags` 里，键是 `item/<id>`，跟结局一个路子。
var items := ItemTable.new()
var personal_anchor = PERSONAL_ANCHOR_SCRIPT.new()
var ch2_checkpoints: Dictionary = {}
## 结局图鉴的**全局记录**：跨存档、只增不减。跟存档分开，删档不带走它。
var gallery := EndingGallery.new()
## 游戏设置：跨存档、跨局保留的偏好（目前只有文字速度）。
var settings := GameSettings.new()
## 存档。文件读写在 `SaveStore`，这里只是把状态与提示串起来。
var save_mgr := SaveManager.new()
## 界面调度：现在谁开着、按键先给谁、谁开着时角色该停。
## 「加一个界面要改两处」这件事就是它接过去的，见 `scenes/ui_host.gd` 的文件头。
var ui_host := UiHost.new()
## 标题 / 存档菜单 / 设置的流程：开哪个、选完了干什么。
## 见 `scenes/menu_flow.gd` —— 加完这三个菜单 main 到了 704 行，所以拆出去。
var menu_flow := MenuFlow.new()

## 启动时要不要先显示标题界面。
##
## 只在 `_ready()` 里用：测试与截图工具是**显式调 `boot()`** 的
## （`--script` 模式下 `_ready` 不触发），所以它们落在房间里，
## 不会被标题挡住。真实运行才会走这条路。
var start_at_title := true

## 新开一局时**跳过开场演出**，直接落进场景自由走动。
##
## **调试开关，正常流程是 false。** 打开它是为了试碰撞箱、试遮挡这类
## 「想自己走两步」的场合 —— 演一遍要二十秒，每开一局都看一遍太碍事。
##
## 打开着的时候点「新游戏」会直接落在委托屋里，看着像「剧情没触发」。
## 所以两条出口都在提醒：这里 `print` 一行，`tests/test_harness.gd`
## 也不再替它兜底 —— 测试跑的就是这个默认值，谁把它留成 true 就等着测试红。
##
## 只影响「新游戏」；读档、地图上的交互剧情都不看这个开关。
##
## **2026-09-24 临时开过一整天**（试新集市那张图），当天就关回来了 ——
## 开着的时候测试会红 77 条（全是「开场没演」的下游，那是守卫在叫）。
## 详见开发纪要第六十一节。
var skip_opening := false

## 新游戏直接落进的测试地图。**调试开关，现在是 `""`（正常流程）**。
##
## - 设成地图 id（如 `"gatehouse"`）时，新游戏跳过开场直接落进那张图，
##   出生朝向由 `menu_flow.new_game()` 的调试分支给；
## - 门卫室（gatehouse）用它做过遮挡与碰撞的验收，2026-09-26 验完已关回；
## - 只影响「新游戏」；读档、地图上的交互剧情都不看这个开关；
## - 测试侧在 `test_harness.new_main()`、`smoke_run.gd`、`screenshot.gd`
##   三处显式关掉，套件不跟着这个开关走。
var debug_start_map := ""

## 门卫室是**独立测试场景，还没有接进任何流程**：
## 大地图没有指向它的传送点，第一章也不会经过。
## 策划要接的时候两条路：① `overworld.json` 加一个 `"to": "gatehouse"`
## 的传送点（gatehouse.json 里已备好 `from_overworld` 出生点）；
## ② 剧情里用 `goto` 指过去。详见 `docs/开发纪要.md` 第八十八节。

## 走到结局之后**不回主界面**，把控制权交还玩家。
##
## **调试开关，现在是 `false`**（正常流程）。曾经开过一阵子：委托屋那段演完
## 就是 end1、直接回标题，而卧室新地图的碰撞箱得自己走两步才算验过 ——
## 演完之后能走，人才能从委托屋走到卧室去。2026-09-23 那天卧室验完了，
## 且新稿子的分支②自己就会切到卧室，这条口子用不着了。
##
## 它和 `skip_opening` 是两件事：那个管「演不演开场」，这个管「演完交不交还控制权」。
##
## 只影响「走到结局」这一条路；没走到结局的照旧交还控制权。
var free_roam_after_ending := false

## 鼠标左键点地图**让人走过去**（`walk_to`）。
##
## **暂时关着。** 这个功能现在还不够好（点偏了会绕远、贴着家具和墙角走），
## 2026-09-24 策划说先收起来，以后有时间再完善。
##
## 关着的时候在房间里点左键**什么都不会发生** —— 鼠标还剩一个用处：
## 悬停时把门和可互动物件框出来（`map_view` 那边）。空格照旧是互动键。
##
## **不退回「左键 = 互动」那种写法。** 那正是当初把两者分开的原因：
## 点哪儿都在跟面前的东西说话，鼠标在场景里等于没有（见 `_unhandled_input`
## 房间那一段的注释）。
##
## **只关鼠标那一下绑定，`walk_to()` 本身没关** —— 那是程序接口，
## 测试（`tests/test_map.gd::test_walk_to`）和将来要接的快捷键照样调它。
##
## 大地图上的点选传送**不受这个开关管**：那是「选一个地点」，不是寻路。
var mouse_walk := false

## 过场指定的镜头位置。非 null 时 `update_camera()` 用它，不跟角色。
##
## 为什么需要：对话框盖住屏幕最下面七十个像素，而委托屋那张桌子在屋子
## 偏下的位置 —— 镜头跟着站在桌后的主角拍，走到桌前的人正好被对话框挡住。
## 过场自己知道这一幕该框住谁，就让过场说了算。
## 换场景、剧情结束时清掉，回到「跟着角色」。
var camera_focus: Variant = null
## 结局文字正在念，念完要回主界面。
##
## 为什么要这个标记：回标题是**挂在 `dialogue.finished` 上的**，
## 而对话框被关掉（`close()`）也会发同一个信号。要是玩家在结局文字念到
## 一半时读档，`enter_map()` 会把对话框收掉 —— 那一下会把人顶回标题，
## 而且是读完档之后。所以换场景时先把这个标记清掉，读了档就老老实实读档。
var awaiting_title := false
## 大地图的悬停点覆盖。非 null 时 `update_overworld_hover()` 用它，
## 不问真实鼠标。将来接手柄要用，截图和测试也用它。
var hover_point_override: Variant = null

## 点着某个能互动的东西走过去时，到了要不要顺手替玩家按一下交互键。
##
## 走路是异步的（要几帧到几十帧），所以「到了要干什么」得记下来，等到了再做。
var walk_and_use := false
## 当前场景定义。为 null 表示加载失败。
var current_map: MapDef = null
## 当前场景用的出生点名字。存档要记它，不然读档会落到默认位置。
var current_spawn: StringName = &"default"


func _ready() -> void:
	boot()
	# 只有真实运行会走到这里 —— 测试与截图显式调 `boot()`，不经过 `_ready`
	if start_at_title:
		show_title()


## 把游戏拉起来：建视图、建角色、建相机、建对话框、进起始场景。
##
## 抽成显式方法，是为了让测试能自己调用，而不是去赌 `_ready` 的触发时机
## —— 在 `--script` 模式下实例化场景时，`_ready` 不会同步跑。
## 重复调用是安全的。
func boot() -> void:
	if map_view != null:
		return

	map_view = MapView.new()
	map_view.name = "MapView"
	add_child(map_view)

	stage_view = Node2D.new()
	stage_view.name = "StageView"
	# 世界人物共用像素采样；UI/立绘保留自己的显示方式。
	stage_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(stage_view)

	player = Player.create()
	add_child(player)

	camera = GameCamera.new()
	camera.name = "Camera"
	add_child(camera)

	dialogue = DialogueBox.new()
	dialogue.name = "Dialogue"
	add_child(dialogue)
	# `--script` 模式下 add_child 不触发 _ready，显式拉一次（幂等）
	dialogue.setup()
	dialogue.finished.connect(_on_dialogue_finished)

	choice_menu = ChoiceMenu.new()
	choice_menu.name = "ChoiceMenu"
	add_child(choice_menu)
	choice_menu.setup()
	choice_menu.chosen.connect(_on_choice_chosen)
	rescue_panel = RescuePanel.new()
	rescue_panel.name = "RescuePanel"
	add_child(rescue_panel)
	rescue_panel.setup()
	rescue_panel.feedback.connect(_on_rescue_feedback)

	chase_overlay = CHASE_OVERLAY_SCRIPT.new()
	chase_overlay.name = "ChaseOverlay"
	add_child(chase_overlay)
	chase_session = CHASE_SESSION_SCRIPT.new()
	chase_session.name = "Ch2ChaseSession"
	add_child(chase_session)
	chase_session.setup(self, chase_overlay)

	tooltip = MapTooltip.new()
	tooltip.name = "MapTooltip"
	add_child(tooltip)
	tooltip.setup()

	# 层号只能由 `CanvasLayer` 给，所以套一层 —— `IfPanel` 自己是 `Control`，
	# 因为分隔线和虚线方块要它来画（`CanvasLayer` 没有 `_draw`）。
	if_panel_layer = CanvasLayer.new()
	if_panel_layer.name = "IfPanelLayer"
	if_panel_layer.layer = 15
	add_child(if_panel_layer)
	if_panel = IfPanel.new()
	if_panel.name = "IfPanel"
	if_panel_layer.add_child(if_panel)
	if_panel.setup()

	toast = Toast.new()
	toast.name = "Toast"
	add_child(toast)
	toast.setup()

	fade = ScreenFade.new()
	fade.name = "Fade"
	add_child(fade)
	fade.setup()

	gallery_panel = EndingGalleryPanel.new()
	gallery_panel.name = "GalleryPanel"
	add_child(gallery_panel)
	gallery_panel.setup()

	save_menu = SaveMenu.new()
	save_menu.name = "SaveMenu"
	add_child(save_menu)
	save_menu.setup()
	menu_flow.setup(self)
	save_menu.chosen.connect(menu_flow.on_save_menu_chosen)
	save_menu.deleted.connect(menu_flow.on_save_menu_deleted)

	title_screen = TitleScreen.new()
	title_screen.name = "TitleScreen"
	add_child(title_screen)
	title_screen.setup()
	title_screen.chosen.connect(menu_flow.on_title_chosen)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.setup()
	pause_menu.chosen.connect(menu_flow.on_pause_chosen)

	settings_panel = SettingsPanel.new()
	settings_panel.name = "SettingsPanel"
	add_child(settings_panel)
	settings_panel.setup()
	settings_panel.changed.connect(menu_flow.on_settings_changed)

	stage_curtain = StageCurtain.new()
	stage_curtain.name = "StageCurtain"
	add_child(stage_curtain)
	stage_curtain.setup()

	stage_overlay = StageOverlay.new()
	stage_overlay.name = "StageOverlay"
	add_child(stage_overlay)
	stage_overlay.setup()
	# CG 摆上/收起来的时候重算一遍「谁能看见」—— 主要是右下角那个背包图标。
	# 图挂在第 9 层、图标在 19 层，压不住它，只能靠这条把它收起来。
	stage_overlay.picture_changed.connect(_on_picture_changed)

	# 左上角的日期/地点。**不进 `ui_host`** —— 它不吃输入，
	# 也不是「要收起来的界面」，只是一行常驻状态。
	location_hud = LocationHud.new()
	location_hud.name = "LocationHud"
	add_child(location_hud)
	location_hud.setup()

	# 音频总线：音乐和音效各一条，设置里那两根滑块各管一条。
	# 建一次就够（总线是全局的，不挂在节点上）。
	AudioBuses.setup()

	# 音效。
	sfx = AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = AudioBuses.SFX
	add_child(sfx)

	# 背景音乐。曲子跟着地图走，没写 `music` 的地图就是静着。
	bgm = AudioStreamPlayer.new()
	bgm.name = "Bgm"
	bgm.bus = AudioBuses.MUSIC
	add_child(bgm)

	inventory = InventoryPanel.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.setup()
	inventory.open_requested.connect(_on_inventory_button)

	ui_host.setup(
		dialogue, choice_menu, gallery_panel, save_menu, settings_panel, title_screen,
		inventory, pause_menu
	)

	# 某一行台词要震屏时，对话框只报一声，摇镜头的事在这儿做
	#（对话框不认识相机，也不该认识）。
	dialogue.shook.connect(_on_dialogue_shook)
	cutscene.setup(self)
	story.setup(dialogue, choice_menu, cutscene)
	story.ended.connect(_on_story_ended)

	endings = DataLoader.load_endings()
	items = DataLoader.load_items()
	gallery.load_records()
	save_mgr.setup(flags, toast, endings)

	# 设置要在对话框建好之后再灌进去：文字速度是它自己的事，
	# 但玩家调的是「对话框打字的快慢」，所以最终落到对话框上。
	settings.load_settings()
	dialogue.set_speed(settings.speed)
	# 音量按设置摆好。音乐和音效两条总线各归各的滑块。
	AudioBuses.apply(settings.music_volume, settings.sfx_volume)
	# 窗口按设置摆好。默认是全屏 —— 这游戏是给人看画面的。
	WindowMode.apply(settings.display, settings.window_size)

	# 暂停（ESC 菜单）要真的冻住世界，可**输入是从这里分发出去的** ——
	# `main` 一跟着暂停，就没人管 ESC 了：菜单开得出来、关不回去。
	# 所以 main 自己设成 ALWAYS，再把该冻的节点显式点名，
	# 理由和名单都在 `_set_process_modes()` 里。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_process_modes()

	enter_map(START_MAP, START_SPAWN)


## 点名「什么算游戏内容、什么算界面」。
##
## 为什么非要有这一步：暂停菜单要把世界真的冻住（`SceneTree.paused`），
## 而 Godot 的 `process_mode` 是**继承**的 —— `main` 为了保住输入通路
## 设成了 `ALWAYS`，底下所有节点就都跟着 `ALWAYS`，一个也冻不住。
##
## 显式设过会盖掉继承，所以下面两类各设一次就够，不用管层级。
func _set_process_modes() -> void:
	# 游戏内容：暂停时冻住。
	#
	# **`cutscene` 不在这里面** —— 它是 `RefCounted`，不是节点，根本没有
	# `process_mode`（当初写成 `Array[Node]` 硬塞进去，直接编译不过，
	# 整个 main.gd 加载失败，游戏黑屏。2026-09-24 踩的）。
	# 它的推进靠 `await`，要停得另想办法，见 `Cutscene` 里的 `_sleep`。
	for node: Node in [map_view, stage_view, player, camera,
			stage_overlay, stage_curtain, dialogue, choice_menu, tooltip, rescue_panel,
			chase_overlay, chase_session]:
		if node != null:
			node.process_mode = Node.PROCESS_MODE_PAUSABLE

	# 界面和声音：暂停时照常。
	#
	# 面板要能接键、要能重画；`fade` 要能淡（读档换场景时它在动）；
	# 音乐不停 —— 暂停菜单上飘着曲子是常态，停了反而像出错了。
	for node: Node in [title_screen, save_menu, settings_panel, pause_menu,
			gallery_panel, inventory, toast, fade, location_hud, sfx, bgm]:
		if node != null:
			node.process_mode = Node.PROCESS_MODE_ALWAYS


## 进入一个场景：重建可视，把角色放到指定出生点。
##
## `keep_story` 为真时**不把剧情收尾** —— 过场自己要换场景时用。
## 不带这个参数的调用（普通出门、读档）照旧收尾：那些时候场景是玩家
## 走过去的，剧情不该跨场景继续。
func enter_map(map_id: StringName, spawn_name: StringName,
		keep_story: bool = false) -> void:
	var def := DataLoader.load_map(map_id)
	if def == null:
		return

	var problems := def.validate()
	if not problems.is_empty():
		for problem: String in problems:
			push_error("[地图] " + problem)
		return

	if chase_session != null:
		chase_session.cancel()
	current_map = def
	map_triggers.configure(def.id, def.triggers, flags, _map_trigger_event_exists, _start_map_trigger)
	current_spawn = spawn_name
	map_view.build(def, flags)
	_sync_library_box_visual()
	player.global_position = def.spawn_point(spawn_name)
	# 保留地图坐标中的美术标尺及碰撞；相机以倒数投影，屏幕上的主角始终等高。
	player.scale = Vector2(def.player_scale, def.player_scale)
	player.configure_environment(def)
	player.velocity = Vector2.ZERO
	# 脚步的锚点跟着落地重置：不重置的话，从上一个场景攒下来的那一段距离
	# 会在进门的头一帧就凑够一次脚步（人刚站定就踩了一脚）。
	_footstep_at = player.global_position

	# 切场景时把剧情收尾，不然会带着上一场景的台词和状态进新场景。
	# 正常玩法里剧情进行中角色动不了、也就切不了场景，
	# 但测试、以及「过场里自己换场景」都会走到这条路上，得挡住。
	# 换场景就放开「按住」和镜头：那是上一个场景里的剧情安排，不该跟过来
	player.pinned = false
	camera_focus = null
	# 换场景多半是读档或开新局。这时候「念完结局回标题」的约定作废 ——
	# 见 `awaiting_title` 的注释。
	awaiting_title = false
	if not keep_story:
		story.cancel()
	# 上一张图上的临时角色是上一张图的东西，别跟过来
	if cutscene != null:
		cutscene.clear_actors()
		if current_map.id == &"school_yard":
			cutscene.restore_school_yard_c()
			if spawn_name == &"from_gate" and flags.get_value(&"ch2/yard_entry_seen") != true:
				_pending_ch2_entry_event = &"ch2_yard_entry"
		elif current_map.id == &"school_gate" \
				and spawn_name in [&"near_yard", &"near_classroom"] \
				and flags.get_value(&"ch2/c_at_school_gate") == true:
			cutscene.place_c_at_school_gate_wait_spawn()
		elif current_map.id == &"school_gate" and spawn_name == &"from_alley" \
				and flags.get_value(&"ch2/gate_entry_seen") != true and not story.is_active():
			_pending_ch2_entry_event = &"ch2_gate_entry"
	pending_actor = null
	# 覆盖在上面的界面也一起收掉：它们显示的是上一个场景的事，
	# 跳完了还在就对不上（读档时尤其明显 —— 菜单还开着，场景已经换了）。
	if ui_host != null:
		ui_host.close_overlays()
	# 屏幕正中那几行字也一样。它按设计会**留在场上**等人接手（见 `caption`），
	# 所以换场景要主动收 —— 不然会飘到新场景上（2026-09-23 踩过）。
	if stage_overlay != null:
		stage_overlay.clear_caption()

	# 某一幕可能把「世界」藏起来过（`bg_blink` 那种：背景在闪、只留主角）。
	# 换场景就把两边都恢复 —— 那是上一幕的安排，不该跟过来。
	if map_view != null:
		map_view.visible = true
	if stage_view != null:
		stage_view.visible = true

	update_camera()
	update_player_control()
	update_cover()
	_play_map_music(def)

	# 新场景从黑里亮出来。同步调用 `enter_map()` 的地方（测试、读档）
	# 不会卡在这里 —— 淡入不算忙碌，见 `ScreenFade` 的文件头。
	#
	# **它属于 `enter_map`，不要挪进 `_play_map_music`。** 那边会因为
	# 「同一首还在播」提前返回，幕就没人揭了（2026-09-23 踩到）。
	if fade != null:
		fade.reveal()


## 现在配着的是哪首曲子（空串 = 没有音乐）。测试与调试用。
##
## 「有没有在响」听不出来也看不出来，只能问这一处。
func current_music() -> String:
	return _bgm_path


## 切换当前地图中一个 Actor 的命名贴图变体。
## 变体只替换主贴图，不改变物件位置、碰撞、交互或遮挡。
func set_actor_sprite_variant(actor_id: StringName, variant_id: StringName) -> bool:
	return map_view != null and map_view.set_actor_sprite_variant(actor_id, variant_id)


func _sync_library_box_visual() -> void:
	if current_map != null and current_map.id == &"library" \
			and flags.get_value(&"ch2/library/box_opened") == true:
		set_actor_sprite_variant(&"box", &"open")


## 换场景时切背景音乐。曲子在 `data/maps/*.json` 的 `music` 字段里。
##
## **留空就是没有音乐** —— 卧室白天黑夜都没有，是策划定的，不是漏了。
## 所以「没写」和「写了但文件找不到」是两回事：前者安静地停，
## 后者会 `push_warning`。
func _play_map_music(def: MapDef) -> void:
	play_music(def.music)


## 换一首曲子。`path` 为空就停。**剧本里的 `music` 指令也走这条。**
##
## **同一首还在播就不动它。** 从委托屋走到集市再走回来、
## 或者在标题上反复调 `show_title()`，都不该每次从头响一遍。
##
## 换曲是硬切，没做淡入淡出：曲子之间本来就没有过渡，
## 加一段静音淡出反而像「声音卡了一下」。
##
## **这里只管声音，不碰画面。** 上一轮把 `enter_map` 末尾那句
## `fade.reveal()` 夹进过这个函数，于是「同一首不重放」提前返回时
## 幕就不揭了 —— 两张地图配同一首曲子的时候，画面会停在黑上。
func play_music(path: String) -> void:
	# 同一首、而且还在播 → 什么都不用做。
	# （`path` 为空时也走这条：静着的地图之间来回走，不用反复 stop。）
	if path == _bgm_path and (path == "" or (bgm != null and bgm.playing)):
		return

	_bgm_path = path

	if bgm == null:
		return

	if path == "" or not ResourceLoader.exists(path):
		bgm.stop()
		bgm.stream = null
		return

	var res: Resource = load(path)
	if not (res is AudioStream):
		push_warning("[音乐] 不是音频：%s" % path)
		return

	var track := res as AudioStream
	# 曲子得循环。MP3 和 WAV 的字段不一样，各设各的。
	if track is AudioStreamMP3:
		(track as AudioStreamMP3).loop = true
	elif track is AudioStreamWAV:
		var wav := track as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# **终点也要设。** 只设 `loop_mode` 的话循环区间是空的（`loop_end` 还是 0），
		# 曲子播一遍就停 —— 一秒的占位文件当场就露，三分钟的那首在测试里看不出来
		# （烟测只跑三十秒）。2026-09-24 被占位文件抓出来的。
		#
		# 帧数用「时长 × 采样率」算，别自己去数字节：位深和声道数一组合就有四种算法。
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))

	bgm.stream = track
	# 不在树里就播不了 —— 硬播引擎会抛一行 ERROR 刷屏。
	#
	# 两种「不在树里」：`--script` 模式的截图/探针（根本播不出声，状态落实就行），
	# 以及**烟测**（它在 `_initialize` 里就 `boot()`，那会儿节点还没进树，
	# 但再过一帧就在了）。后者要补播，不然委托屋整段是静音的。
	if bgm.is_inside_tree():
		bgm.play()
	else:
		bgm.call_deferred("play")


## 玩家主动换个场景：先淡出，黑了之后再切。
##
## `enter_map()` 是同步的、立刻生效；这一层是给眼睛看的。
## 分成两个入口是为了让测试能同步切场景 —— 转场依赖补间，
## 而补间要靠帧推进，同步断言等不到它。
##
## **开门声挂在这里**，因为「玩家主动换场景」只有这一条路：
## 在屋里按交互键走门（`_take_portal`）和在大地图上点地点
## （`_travel_through_portal`）最后都落到这儿。
##
## 2026-09-24 报过「进出卧室没音效」：声音原来只挂在 `_travel_through_portal` 上，
## 而**屋里根本走不到那个函数** —— 它只管大地图点选。同一个坑当天第二次踩：
## 上一次是把测试写在内部函数上、没走入口，这次是把逻辑挂在了一个
## 玩家走不到的入口上。
##
## **不放在 `enter_map()` 里**：那个是同步切场景的底层入口，读档、开新局、
## 演出里换场景都直接调它，那些都不是「推门」。
func travel_to(map_id: StringName, spawn_name: StringName) -> void:
	_play_door_sound(map_id)
	if fade == null:
		enter_map(map_id, spawn_name)
		return
	if fade.is_busy():
		return
	fade.fade_out(func() -> void:
		enter_map(map_id, spawn_name)
	)


## 玩家当前停在哪个 `auto_menu` 物件的 reach 里（防止菜单关了又开）。
var _auto_menu_actor := StringName(&"")
var _pending_ch2_entry_event := StringName(&"")


func _process(_delta: float) -> void:
	update_camera()
	update_player_control()
	update_overworld_hover()
	update_cover()
	_check_auto_menu()
	_announce_items()
	_check_walk_arrival()
	_update_footsteps()
	_update_map_triggers()
	_start_pending_ch2_entry_event()


func _start_pending_ch2_entry_event() -> void:
	if _pending_ch2_entry_event == &"" or current_map == null or story.is_active():
		return
	if fade != null and fade.is_busy():
		return
	if ui_host != null and ui_host.is_busy():
		return
	var event_id := _pending_ch2_entry_event
	_pending_ch2_entry_event = &""
	start_story(event_id)


func _map_trigger_busy() -> bool:
	return story.is_active() or (ui_host != null and ui_host.is_busy()) \
		or (fade != null and fade.is_busy()) or (player != null and player.pinned)


func _map_trigger_event_exists(event_id: StringName) -> bool:
	if str(event_id).is_empty() or str(event_id).get_file() != str(event_id) \
			or str(event_id).contains(".."):
		return false
	if not FileAccess.file_exists(DataLoader.EVENT_DIR + str(event_id) + ".json"):
		return false
	var event := DataLoader.load_event(event_id, endings.ids())
	return event != null and event.validate(endings.ids()).is_empty()


func _start_map_trigger(event_id: StringName) -> bool:
	if _map_trigger_busy() or (is_inside_tree() and get_tree().paused):
		return false
	start_story(event_id)
	update_player_control()
	return true


func _update_map_triggers() -> void:
	if current_map == null or player == null or not is_inside_tree():
		return
	map_triggers.update(player.global_position, _map_trigger_busy(), get_tree().paused)


## 玩家走进 `auto_menu` 物件的 `reach` 时，自动弹出它的动作菜单。
##
## 死巷铁门专用交互：走到蓝色框里，右上角浮出「推开铁门」，点一下进门。
## 菜单复用 `choice_menu`（右上角独立面板），和 `begin_interaction`
## 多动作那条路同一个规矩 —— 点了哪个就跑哪个。
## **离开 `reach` 之后才允许再次弹出**，不然站在原地菜单关了又开。
func _check_auto_menu() -> void:
	if current_map == null or player == null or choice_menu == null:
		return
	if choice_menu.visible or story.is_active() or fade.is_busy():
		return
	var inside: MapDef.Actor = null
	for actor: MapDef.Actor in current_map.actors:
		if not actor.auto_menu or not actor.is_active(flags):
			continue
		if actor.reach.has_point(player.global_position):
			inside = actor
			break
	if inside == null:
		_auto_menu_actor = &""
		return
	if _auto_menu_actor == inside.id or inside.interactions.is_empty():
		return
	_auto_menu_actor = inside.id
	var options: Array[ChoiceOption] = []
	for inter: MapDef.Interaction in inside.interactions:
		options.append(ChoiceOption.make(inter.id, inter.label))
	pending_actor = inside
	choice_menu.open("", options)


## 木地板上的脚步。**只在该场景指定了 `footstep` 时才响**（见地图 json）。
##
## 判据是「主角这一帧挪了多远」，不是 `velocity` ——
## 被剧情摆位、被补间推走这些情况 `velocity` 也是零，但人确实在动。
##
## 只在人能操控时算：菜单开着、剧情演着、被按住的时候人本来就不该动。
## 那种时候把锚点跟着人走，免得恢复操控那一帧因为攒了一大段距离而连响几声。
func _update_footsteps() -> void:
	if player == null or current_map == null or current_map.footstep == "":
		return
	if not player.is_physics_processing():
		_footstep_at = player.global_position
		return
	if player.global_position.distance_to(_footstep_at) < FOOTSTEP_DISTANCE * player.scale.x:
		return
	_footstep_at = player.global_position
	play_sound(current_map.footstep)


## 点到东西走过去的那一趟：**走到了就替玩家按一下交互键**。
##
## 走路是异步的，所以「到了要干什么」是出发前记下的（`walk_and_use`），
## 走完这一步才轮到它。每帧看一眼路径空没空，比给角色挂回调简单，
## 也不用管「半路被玩家接管了」这种情况 —— 那种时候路径已经被清掉了。
func _check_walk_arrival() -> void:
	if not walk_and_use:
		return
	if player == null or not player.walk_path.is_empty():
		return
	walk_and_use = false
	# 到了再判一次「能不能互动」—— 路上可能已经离开那个东西的够得着范围
	interact()


## 把角色站的位置告诉地图：会挡人的家具（书桌）靠它决定前后关系。
##
## 单独一步，不塞进 `update_camera()` —— 相机和遮挡是两回事，
## 混在一起以后想找「谁在改层级」就得先读一遍夹边界的算法。
func update_cover() -> void:
	if map_view != null and player != null:
		map_view.set_player_y(player.global_position.y)


## 这一轮里新拿到的东西，说一声。
##
## 提示不是「谁给的时候谁去调 toast」，而是**从状态变更里捞出来**的 ——
## 剧情节点的 `set`、选项的 `set`、交互的 `set` 三条路都得给东西，
## 让三处各自记得调提示，迟早漏一处。写成一处，谁给都覆盖得到。
##
## 变少（用掉）的不报：消耗是流程的一部分，提示会把节奏打断。
func _announce_items() -> void:
	if flags == null or toast == null:
		return

	var gained: Array[String] = []
	for change: Dictionary in flags.changes():
		var key := StringName(str(change.get("key", &"")))
		if not ItemTable.is_item_flag(key):
			continue
		if _as_int(change.get("to", 0)) <= _as_int(change.get("from", 0)):
			continue
		var item_id := ItemTable.id_from_flag(key)
		var item_name := items.name_of(item_id)
		if item_id == &"charm":
			var amount := _as_int(change.get("to", 0)) - _as_int(change.get("from", 0))
			item_name += "×%d" % amount
		gained.append(item_name)

	# 变更看完就清，不然下一帧会把同一次获得再报一遍
	flags.clear_changes()

	if gained.is_empty():
		return
	if gained.size() == 1:
		toast.show_text("获得 %s" % gained[0])
	else:
		toast.show_text("获得 %s" % "、".join(gained))


static func _as_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is bool:
		return 1 if value else 0
	return 0


# ---------------------------------------------------------------- 演出配套

## 左上角换一行状态（日期 / 时间 / 地点）。**空字符串就是收起。**
## 演出里的 `location` 指令走这条。
func show_location(text: String) -> void:
	if location_hud != null:
		location_hud.show_text(text)


## 弹一条提示。`at` 为 `center` 时落在画面中线上方，其余落在右上角。
##
## 演出里的 `hint` 指令走这条（「此处建议存档」用它）；
## 拿到东西那种提示是 `_announce_items()` 自己弹的，位置固定右上角。
func show_hint(text: String, at: String = "corner") -> void:
	if toast == null:
		return
	var place := Toast.Place.CENTER if at == "center" else Toast.Place.CORNER
	toast.show_text(text, place)


## 最近一次**要求播放**的音效路径。
##
## `play_sound()` 一进来就记，**在判空和判文件之前** —— 它管的是
## 「有没有人调过我、调的是哪个」，不是「到底出声了没有」。
##
## 为什么要它：无头测试里 `sfx` 没进树，`play_sound` 会静默跳过，
## 于是「声音挂在哪个入口上」这件事完全验不到 —— 2026-09-24 那个
## 「进出卧室没音效」就是这么漏过去的（声音挂在了一个玩家走不到的入口上，
## 而测试只调了内部函数）。
var last_sound := ""


## 放一段音效。
##
## 文件不在就**静默跳过** —— 音频素材还没到，剧本里那条指令现在就该能写、
## 能跑通，不至于因为一个文件没放而整段演出停住。
## 代价是路径写错也不会报错，所以 `tools/check_data.py` 会把
## 「写了路径但文件不存在」查出来。
func play_sound(path: String) -> void:
	last_sound = path
	if sfx == null or path == "" or not ResourceLoader.exists(path):
		return
	# 不在树里就播不了，硬播引擎会抛一行 ERROR 刷屏 —— 无头测试里的 `main`
	# 常常没挂进场景，那条错跟剧情对不对毫无关系，只是吵。
	if not sfx.is_inside_tree():
		return
	var res: Resource = load(path)
	if res is AudioStream:
		sfx.stream = res
		sfx.play()


func _on_rescue_feedback(kind: StringName) -> void:
	var path := ""
	match kind:
		&"success":
			path = "res://audio/sfx/rescue_success.wav"
		&"mistake":
			path = "res://audio/sfx/rescue_mistake.wav"
		&"complete":
			path = "res://audio/sfx/rescue_complete.wav"
	if path != "":
		play_sound(path)


## 大地图上的鼠标悬停：提亮脚下那块地点，并弹出它的详细介绍。
##
## 地点常驻显示的只有名字，详情挂在这里 —— 地点挨得近，
## 详情常驻会把整张地图糊住。
##
## `probe` 留空就用 `hover_point_override`，再留空才用真实鼠标位置。
## 留这个覆盖口子是为了将来接手柄：那时候悬停点是手柄指的，不是鼠标。
##
## **详情展开在地点的名字框下面**（`map_view` 画），不是跟在鼠标旁边的浮框 ——
## 策划 2026-09-24 定的：「详细信息在原本的名称框下面展开」。
## `tooltip` 那个组件现在不参与大地图了，留着是给别的界面用。
func update_overworld_hover(probe: Variant = null) -> void:
	if current_map == null or map_view == null:
		return

	if current_map.kind != MapDef.Kind.OVERWORLD or story.is_active() \
			or (ui_host != null and ui_host.is_busy()):
		map_view.set_hovered(&"")
		map_view.show_detail(&"")
		return

	var point: Vector2
	if probe != null:
		point = probe
	elif hover_point_override != null:
		point = hover_point_override
	else:
		point = get_global_mouse_position()

	var portal := current_map.portal_at(point, flags)
	var id: StringName = portal.id if portal != null else &""
	map_view.set_hovered(id)
	map_view.show_detail(id)


## 角色什么时候可见、什么时候能被操控。
##
## 集中在一处算，而不是散在 enter_map 和对话逻辑里 ——
## 分散写的话，迟早会出现「对话关了但人还是动不了」这种状态卡死。
func update_player_control() -> void:
	if player == null or current_map == null:
		return

	var on_room := current_map.kind == MapDef.Kind.ROOM
	# 「有界面开着吗」只问 `ui_host` 一处 —— 以前这里是一串 `or` 加界面名，
	# 每加一个界面都要来改一次，漏改就是「界面关了但人还是动不了」。
	var busy := ui_host != null and ui_host.is_busy()
	var fading := fade != null and fade.is_busy()
	# **过场期间不许动。** 黑屏那几段没有界面开着，
	# 光看 `ui_host` 会让角色在黑屏里走来走去。
	var cutscene_locked := story.is_active()
	var chase_movement := chase_session != null and chase_session.can_move_player()
	# 大图（CG）摆着 —— 背包图标要让开，理由见下面那一段。
	var picture_up := stage_overlay != null and stage_overlay.has_image()

	player.visible = on_room
	# 被按住的时候连物理都不给 —— 见 `Player.pinned`
	var movable := on_room and not busy and not fading \
		and (not cutscene_locked or chase_movement) and not player.pinned
	player.set_physics_process(movable)

	# 右下角那个背包图标：有界面开着、在演过场、或者黑幕压着时就收起来。
	#
	# 黑幕那一条单独列出来（不是靠 `cutscene_locked` 就够了）：
	# 结局文字是写在黑底上的，那时候场上根本没有「场景」，
	# 角落里杵一个按不动的背包图标，正好挤在结局文字旁边。
	#
	# **CG 摆着的时候也让开。** 大图是第 9 层、图标是第 19 层 ——
	# 压是压不住它的，只能主动收。过 CG 的时候画面上不该有个「背包」按钮。
	if inventory != null:
		var black := stage_curtain != null and stage_curtain.is_down()
		inventory.set_button_visible(
			on_room and not busy and not fading and not cutscene_locked
				and not black and not picture_up
		)


## 台词里带 `shake` 的那一行浮出来时报进来。摇一下镜头。
func _on_dialogue_shook(strength: float) -> void:
	if camera != null:
		camera.shake(strength)


## CG 摆上 / 收起来时报进来。重算一遍「谁能看见」就够了。
func _on_picture_changed(_showing: bool) -> void:
	update_player_control()


## 让相机跟着角色。怎么夹边界是 `GameCamera` 的事，这里只负责喂数据。
##
## 可行走地图以统一主角高度为标尺，相机跟随；只有无主角的大地图适配全图。
func update_camera() -> void:
	if camera == null or player == null or current_map == null:
		return
	# 大地图看的是整张图，不跟人走 —— 那上面本来也没有可操控的角色，
	# 跟着站在角落的 player 拍，画面会停在没内容的一角。
	var on_overworld := current_map.kind == MapDef.Kind.OVERWORLD
	var focus := player.global_position
	if on_overworld:
		focus = Vector2(current_map.size) * 0.5
	# 过场点名要看哪儿时就听它的
	if camera_focus != null:
		focus = camera_focus
	camera.follow(focus, Vector2(current_map.size),
		GameCamera.should_shrink(current_map.kind), current_map.player_scale)


## F11 / Alt+Enter：切全屏。返回 true 表示这个键我吃掉了。
func _handle_window_keys(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false

	var code := InputUtil.keycode_of(key)
	if code != KEY_F11 and not (code == KEY_ENTER and key.alt_pressed):
		return false

	# 快捷键切完要写回设置，不然下次启动又回去了
	var mode := WindowMode.toggle(settings.window_size)
	settings.display = mode
	settings.save_settings()
	if toast != null:
		toast.show_text("画面：%s" % WindowMode.label_of(mode))
	return true


func _unhandled_input(event: InputEvent) -> void:
	# 全屏切换要在「有没有地图」之前判断 —— 标题界面上也能按。
	if _handle_window_keys(event):
		return

	if current_map == null:
		return

	# 转场到一半时什么都别响应：玩家看不见画面，这时候的点击没有意义，
	# 而且能在黑屏里再触发一次传送。
	if fade != null and fade.is_busy():
		return

	# 暂停菜单开着时，键盘**只**给它那一摞 —— 它自己，或者它上面开着的
	# 设置面板 / 存档菜单（谁在上面由 `ui_host` 说了算）。
	#
	# 这一段必须排在下面的 F4/F5/F9 前面：那几个是「从游戏里直接开面板」的
	# 快捷键，而暂停菜单上本来就有「保存」和「加载」两行。
	# 两边同时生效就是从背后又叠出一个面板，叠完谁也收不掉 ——
	# 按 F5 开出存档菜单、关掉，人还在暂停菜单里，看着像按了没反应。
	if pause_menu != null and pause_menu.is_open():
		if event is InputEventKey:
			var paused_key := event as InputEventKey
			if paused_key.pressed and not paused_key.echo:
				ui_host.handle_key(paused_key.physical_keycode)
		return

	if rescue_panel != null and rescue_panel.is_open():
		var escape_pressed := event is InputEventKey \
				and InputUtil.keycode_of(event as InputEventKey) == KEY_ESCAPE
		if not escape_pressed:
			rescue_panel.handle_input(event)
			return

	if chase_overlay != null and chase_overlay.is_running() \
			and chase_overlay.handle_input(event):
		return
	if chase_session != null and chase_session.active and event is InputEventMouseButton:
		return

	# 全局快捷键放在最前面，免得被开着的界面先吃掉。
	# F4 图鉴、F5 存档菜单、F9 读档菜单。
	# 剧情演到一半也照存，读档从那个节点接着演。
	# 只有转场到一半时不给开，那时场景还没定下来。
	if event is InputEventKey:
		var hot_key := event as InputEventKey
		if hot_key.pressed and not hot_key.echo:
			match hot_key.physical_keycode:
				KEY_F4:
					toggle_gallery()
					return
				KEY_F5:
					menu_flow.open_save_menu()
					return
				KEY_F9:
					menu_flow.open_load_menu()
					return
				KEY_B:
					# 过场里不给开背包：那时候画面上的东西都该由演出说了算
					if not story.is_active():
						toggle_inventory()
					return

	# ESC 单独挑出来先办。
	#
	# 位置是挑过的：排在「暂停菜单自己开着」和全局快捷键之后，
	# 但**在「有界面开着就把键交给它」之前**。理由：
	# 对话框和选项框按 ESC 本来什么都不做，交给它们等于这个键在大半个
	# 游戏里失效 —— 一次对话从头到尾弹不出菜单，而屏幕上那句提示还在
	# 劝玩家「此处建议存档」。2026-09-23 就是这么咬人的。
	#
	# 三种去处：
	#   1. 最上面那个界面自己认 ESC（图鉴、存档菜单、设置…）→ 还给它；
	#   2. 标题界面上什么都不做（那上面没有「上一层」，见 `TitleScreen`）；
	#   3. 其余（对话框、选项框、什么都没有）→ 开暂停菜单。
	#
	# **「还给它」必须排在「标题什么都不做」前面。** 标题开子面板
	# （设置、图鉴）时**自己不收**（`TitleScreen.STAY_OPEN`），它一直开着；
	# 要是先判「标题开着就返回」，子面板里的 ESC 就永远被丢掉 ——
	# 表现是「主菜单进设置，按 ESC 没反应」（2026-09-24 踩的）。
	if event is InputEventKey:
		var esc_key := event as InputEventKey
		if esc_key.pressed and not esc_key.echo \
				and esc_key.physical_keycode == KEY_ESCAPE:
			if ui_host != null and ui_host.try_escape():
				return
			# 走到这儿说明最上面那个界面**不认** ESC。标题就是其中之一：
			# 它上面没有「上一层」，按了就该什么也不做，更不许掉出去开暂停菜单。
			if title_screen != null and title_screen.is_open():
				return
			open_pause_menu()
			return

	# 有界面开着时，键盘交给最上面那个（谁在谁上面由 `ui_host` 定），
	# 鼠标也不该穿透到地图上 —— 点一下把角色送走就太怪了。
	if ui_host != null and ui_host.is_busy():
		if event is InputEventKey:
			var ui_key := event as InputEventKey
			if ui_key.pressed and not ui_key.echo:
				ui_host.handle_key(ui_key.physical_keycode)
		return

	# 过场里**不接受动作输入**。只认「继续」那一下 ——
	# 演出可能正停在「点击一次」那一步上（比如那张猫的照片）。
	# 别的键一概不响应：黑屏的时候按着什么，玩家自己也看不见。
	#
	# ESC 也算在内：过场是**动着的**（计时器、补间都在跑），
	# 这时候弹菜单出来，演出会在菜单背后一路演完，等玩家回来场景已经变了。
	if story.is_active():
		if _is_advance_event(event) and cutscene != null:
			cutscene.consume_click()
		return

	# ESC：开暂停菜单。到这儿说明没界面开着、剧情也没在演。
	if event is InputEventKey:
		var plain_esc := event as InputEventKey
		if plain_esc.pressed and not plain_esc.echo \
				and plain_esc.physical_keycode == KEY_ESCAPE:
			open_pause_menu()
			return

	if event is InputEventMouseButton and not current_map.triggers.is_empty() and is_inside_tree():
		var trigger_click := event as InputEventMouseButton
		if trigger_click.pressed and trigger_click.button_index == MOUSE_BUTTON_LEFT \
				and map_triggers.click(get_global_mouse_position(), _map_trigger_busy(),
					is_inside_tree() and get_tree().paused):
			return

	# 大地图：鼠标点选地点
	if current_map.kind == MapDef.Kind.OVERWORLD:
		if _is_advance_event(event):
			_travel_through_portal(get_global_mouse_position())
		return

	# 房间：**鼠标左键点地图 = 走过去**，空格 = 跟脚边的东西互动。
	#
	# 以前这两样是一个功用（左键也走 `interact()`），结果鼠标在房间里
	# 除了当确认键没别的用 —— 人在哪儿、想点哪儿，鼠标一概不管。
	#
	# **这一下现在由 `mouse_walk` 管着，默认关着**（那个功能还没做好，
	# 见它的注释）。关着的时候点左键就是什么也不做 —— 不退回上面那种写法。
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			if mouse_walk:
				walk_to(get_global_mouse_position())
			return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_SPACE:
			interact()
			return


## 鼠标点地图：让人**走过去**。
##
## 点在墙上、家具上也照样走 —— `WalkGrid.path_to()` 会在「站得住、而且从这儿
## 真能走到」的格子里挑一个离它最近的。点下去没反应，比走错地方更让人困惑。
##
## 点到**能互动的东西**（门、家具、人）时，走到之后顺手互动一下：
## 那才是「点这里」的意思，不然人跑过去杵着，还得再按一次空格。
##
## **它是个程序接口，不受 `mouse_walk` 管** —— 那个开关关的是
## 「鼠标左键」那一下绑定（在 `_unhandled_input` 里）。这个函数本身照旧能调，
## 测试和将来要接的快捷键都从这儿走。
func walk_to(point: Vector2) -> void:
	if player == null or current_map == null:
		return
	if story.is_active() or (ui_host != null and ui_host.is_busy()):
		return

	var path := WalkGrid.path_to(current_map, player.global_position, point)
	if path.size() < 2:
		# 一步都迈不开（比如点在自己脚下那片墙里），别白记一个目标
		return
	# 第一个点是起点 —— 人就站在那儿，直接从第二个点开始走
	path.remove_at(0)
	player.walk_path = path
	walk_and_use = _interactable_at(point)


## 这一点上有没有能互动的东西。
##
## 判据跟 `interact()` 找身边目标时是同一套：看 **`reach`（够得着的范围）**，
## 不只看 `rect` —— 那个是贴图的位置，人得站在家具前面才够得着它。
func _interactable_at(point: Vector2) -> bool:
	if current_map == null:
		return false
	if current_map.portal_at(point, flags) != null:
		return true
	for actor: MapDef.Actor in current_map.actors:
		if actor.reach.has_point(point):
			return true
	return false


## 交互键或鼠标左键都算「继续」。
func _is_advance_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		return click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and key.physical_keycode == KEY_SPACE
	return false


## 按下交互键：找身边能交互的目标。
##
## 优先级是「身边的角色 > 脚下的连接」。反过来的话，
## 站在门口跟人说话会变成直接出门。
func interact() -> void:
	if current_map == null or _map_trigger_busy() or (is_inside_tree() and get_tree().paused):
		return

	# 站在传送点上就直接走，**先于**看附近有没有人能说话。
	# 门口那块地方总是紧挨着货架、花架，先查人就会出现
	# 「对着门按了半天出不去，反而在跟书架说话」。
	if _take_portal():
		return
	if map_triggers.interact(player.global_position):
		return

	# 只认朝向面前的东西。玩家的原点就在脚底。
	var actor := current_map.actor_near(player.global_position, INTERACT_RANGE, flags,
		player.facing)
	if current_map.id == &"school_yard":
		var actor_distance := INTERACT_RANGE
		if actor != null:
			actor_distance = MapDef.rect_distance(actor.reach, player.global_position)
		if _talk_to_transient(actor_distance):
			return
	if actor != null:
		begin_interaction(actor)
		return

	# **演出留下的临时角色也认。**
	#
	# 他们是「演到一半出场、演完之后留在场上」的人（第二遍集市里的 A、
	# 神秘人 B）：演出结束控制权交回玩家之后，人还站在那儿，
	# 玩家走过去按交互得能说话。判定和地图角色一个规矩 —— 距离 + 朝向。
	_talk_to_transient()


## 脚下有传送点就走过去。返回 true 表示这一步走的是门。
##
## 三种情况分得很清楚：
## - **被拦着**（`blocked_by` 那个 flag 为真）→ 弹一句话，人不动
## - **有事件**（`event_id`）→ 演那一段，进门之后的事由它自己 `goto` 接着演
## - 其余 → 照旧传送到目标场景
func _take_portal() -> bool:
	var portal := current_map.portal_at(player.global_position, flags)
	if portal == null:
		return false

	if current_map.id == &"school_gate" and portal.id == &"to_classroom":
		start_story(&"ch2_class_door")
		return true

	if _portal_blocked(portal):
		if portal.blocked_text != "" and toast != null:
			toast.show_text(portal.blocked_text)
		return true

	if portal.event_id != &"":
		# 门轴声照旧 —— 这也是一扇门，只是进去之后还有一段戏。
		_play_door_sound(&"bedroom_night")
		start_story(portal.event_id, &"")
		return true

	var dest := portal_destination(player.global_position)
	if dest.is_empty():
		return false
	travel_to(dest[0], dest[1])
	return true


## 这扇门现在是不是被拦着的。没写 `blocked_by` 的永远不拦。
##
## 判据是**那个 flag 现在为不为真** —— 剧本里靠设 flag 来开关它，
## 不用改地图数据（「今晚不让出门」是一晚上的事，不是这扇门的属性）。
func _portal_blocked(portal: MapDef.Portal) -> bool:
	if portal.blocked_by == "":
		return false
	return flags.get_value(StringName(portal.blocked_by)) == true


## 试一下玩家面前有没有「演出留下的临时角色」能搭话。
##
## 判定照 `MapDef.actor_near` 的规矩：距离在 `INTERACT_RANGE` 之内、
## 而且**朝着他**（他脚下那一小块当作 `reach`）。多个都在范围内就取最近的。
##
## 这一条是补「自由活动阶段碰到老人，发现那只是张贴图」那个缺口的
##（2026-09-24 策划报的）—— 演出放出来的临时角色，也是这个场景里的人。
func _talk_to_transient(max_distance: float = INTERACT_RANGE) -> bool:
	if cutscene == null or player == null:
		return false
	var best_event := StringName(&"")
	var best_distance := max_distance
	for item: Array in cutscene.talkable_list():
		var at: Vector2 = item[1]
		var feet := Rect2(at.x - TALK_FOOT_HALF, at.y - TALK_FOOT_HEIGHT,
			TALK_FOOT_HALF * 2.0, TALK_FOOT_HEIGHT)
		if not MapDef.faces_target(player.global_position, feet, player.facing):
			continue
		var distance := MapDef.rect_distance(feet, player.global_position)
		if distance < best_distance:
			best_distance = distance
			best_event = item[2]
	if best_event == &"":
		return false
	start_story(best_event, &"")
	return true


## 临时角色「站着占的那块地」：他脚底一小圈。
##
## 数值照 `Player.FOOT_SIZE`（16×16、原点在脚底）—— 那是这个项目里
## 「一个人站在地上占多大地方」的唯一口径，别在这儿另定一套。
const TALK_FOOT_HALF := 8.0
const TALK_FOOT_HEIGHT := 16.0


## 跟一个角色互动。
##
## 只有一个动作时直接执行 —— 大多数 NPC 只有「交谈」，
## 为此弹一个只有一项的菜单纯属添乱。有多个动作才弹菜单。
func begin_interaction(actor: MapDef.Actor) -> void:
	if actor == null:
		return
	if current_map.id == &"gatehouse" and actor.id == &"desk":
		start_story(&"ch2_register")
		return
	if current_map.id == &"school_yard" and actor.id == &"swing":
		var event_id: StringName = &"ch2_swing_repeat" if flags.get_value(&"ch2/rescued_c") == true else &"ch2_swing"
		start_story(event_id)
		return
	if current_map.id == &"classroom":
		var classroom_events := {
			&"blackboard": &"ch2_blackboard",
			&"diary_desk": &"ch2_diary",
		}
		if classroom_events.has(actor.id):
			start_story(classroom_events[actor.id])
			return
	if actor.interactions.is_empty():
		return

	if actor.interactions.size() == 1:
		play_interaction(actor.interactions[0])
		return

	var options: Array[ChoiceOption] = []
	for inter: MapDef.Interaction in actor.interactions:
		options.append(ChoiceOption.make(inter.id, inter.label))
	pending_actor = actor
	choice_menu.open(actor.label, options)


func play_interaction(inter: MapDef.Interaction) -> void:
	if inter == null:
		return
	# 一次性事件演过就不再触发。「演过」跟着存档走，读档也不会再送一遍。
	if inter.once and inter.event_id != &"" and has_seen(inter.event_id):
		return

	# 状态先写再演：捡到东西的提示要发生在「捡起来」那一刻，
	# 而不是等这段话说完 —— 话说完再冒提示，玩家已经不知道是谁给的了。
	_apply_effects(inter.effects)

	if inter.event_id != &"":
		start_story(inter.event_id)
		return
	dialogue.play(inter.dialogue)


## 把一组 `变量名 -> 值` 写进世界状态。写法跟剧情节点的 `set` 一致。
func _apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	for key: Variant in effects:
		flags.set_value(StringName(str(key)), effects[key])


# ---------------------------------------------------------------- 剧情事件

## 开始一段剧情。玩家的选择会一直累积在 `flags` 里，不随事件结束清空。
##
## 后三个参数都是**读档**用的：从哪个节点、节点里演到第几步、
## 那段台词说过没有。正常起一段剧情全用默认值，从头演。
##
## 读文件是 `DataLoader` 的事，推进是导演的事，这里只把两头接上。
func start_story(event_id: StringName, resume_node_id: StringName = &"",
		resume_step: int = 0, resume_spoke: bool = false) -> void:
	# 记下「这段剧情发生过」。存档带着它走，读档之后不会当成没发生过。
	flags.set_value(StringName("seen/" + str(event_id)), true)
	story.start(DataLoader.load_event(event_id, endings.ids()), flags,
		resume_node_id, resume_step, resume_spoke)


## 这段剧情玩家是否已经历过。一次性事件的判定靠它。
func has_seen(event_id: StringName) -> bool:
	return flags.get_value(StringName("seen/" + str(event_id)), false) == true


## 对话播完了。剧情在跑就交给导演，它自己知道下一步该播什么还是该弹选项。
func _on_dialogue_finished() -> void:
	if story.is_active():
		story.on_dialogue_finished()


func _on_choice_chosen(id: StringName) -> void:
	# 剧情的 IF 选项。导演返回 false 表示这次不是它的（比如被拒绝的选择），
	# 也不该落到角色动作那一路上去。
	if story.choose(id):
		return

	# 角色的动作菜单
	if pending_actor == null:
		return
	for inter: MapDef.Interaction in pending_actor.interactions:
		if inter.id == id:
			play_interaction(inter)
			break
	pending_actor = null


## 某个位置上的连接通向哪里。返回 `[场景, 出生点]`，没有连接就返回空数组。
##
## 抽出来是因为「踩过去」有两个版本（带转场的、不带转场的），
## 解析逻辑不该写两遍。
func portal_destination(point: Vector2) -> Array:
	if current_map == null:
		return []
	var portal := current_map.portal_at(point, flags)
	if portal == null:
		return []
	# **还没开放的地点**（大地图上摆着、有介绍，但场景还没做）。
	# 返回空数组让调用方当「这儿没有连接」处理，它那边会弹一句提示。
	if portal.outcome == MapDef.Portal.Outcome.NONE:
		return []
	if portal.outcome == MapDef.Portal.Outcome.TO_OVERWORLD:
		return [OVERWORLD_MAP, &"default"]
	return [portal.target_map, portal.target_spawn]


## 踩到/点到一个连接，走转场过去。玩家走的都是这一条。
##
## 大地图上点一个地点，走转场过去。
##
## 开门声**不在这儿** —— 它挂在 `travel_to()` 上，因为屋里走门走的是
## 另一条路（`_take_portal`），只挂这儿会漏掉一半。
##
## 点到**还没开放的地点**（有标签有介绍，但没写 `to`）时弹一句提示：
## 什么都不发生的话，玩家只会以为游戏卡了、或者以为自己点歪了。
func _travel_through_portal(point: Vector2) -> void:
	var portal: MapDef.Portal = null
	if current_map != null:
		portal = current_map.portal_at(point, flags)

	# **挂了事件的地点先演那一段**（进去之后的事由它自己 `goto`），
	# 和 `_take_portal` 一个规矩。2026-09-25 补上：集市那一段原来是挂在
	# 卧室门上的，现在由大地图这个地点自己接，两条路少一条就漏一半。
	if portal != null and portal.event_id != &"":
		start_story(portal.event_id, &"")
		return

	var dest := portal_destination(point)
	if dest.is_empty():
		if toast != null and portal != null and portal.label != "":
			toast.show_text("「%s」还没开放" % portal.label)
		return
	travel_to(dest[0], dest[1])


## 这一步算不算进门；算了就响一声。
##
## **只判目的地**：目的地是一间屋子就响，出到露天不响。
##
## 返回「响没响」是**给测试留的抓手** —— 无头里 `play_sound` 会因为
## 播放器没进树而静默跳过，光看它验不出东西来。
func _play_door_sound(to_map: StringName) -> bool:
	var to_def := DataLoader.load_map(to_map)
	if to_def == null:
		return false
	if to_def.kind != MapDef.Kind.ROOM or not to_def.indoor:
		return false
	play_sound(DOOR_SOUND)
	return true


## 踩过去，**不走转场**。
##
## 测试与「读档」这类凭空跳转用：转场要靠补间，而补间要靠帧推进，
## 同步执行的时候等不到它。测试里用它，才是在测「连接通向哪里」，
## 而不是在测「补间跑完了没有」。
func use_portal_at(point: Vector2) -> void:
	var dest := portal_destination(point)
	if dest.is_empty():
		return
	enter_map(dest[0], dest[1])


## 直接切过去并盖黑。只有读档用 ——
## 读档本来就是一次「凭空的跳转」，再淡一次纯属多余，但画面要黑一下再亮。
func _jump_to(map_id: StringName, spawn_name: StringName) -> void:
	if fade != null:
		fade.cover_now()
	# 读档是一次凭空跳转：上一局留在场上的黑幕和临时角色都该扔掉，
	# 不然读回来会是一片黑，或者床边站着上个场景的 NPC。
	if stage_curtain != null:
		stage_curtain.snap_up()
	if stage_overlay != null:
		stage_overlay.clear()
	if cutscene != null:
		cutscene.cancel()
	enter_map(map_id, spawn_name)


# ---------------------------------------------------------------- 结局

## 一段剧情走完。重画场景，然后演结局演出（如果这段走到了结局）。
##
## 重画放在演出前面 —— 有些结局会让场景里的东西消失，
## 玩家先看到场景变了，再看结局文字，顺序才对得上。
func _on_story_ended(ending_id: StringName) -> void:
	# 剧情演完了，镜头还给角色
	camera_focus = null
	refresh_scene()
	# 「按住」是**某一幕的安排**，剧情一完就该放开 —— 和 `enter_map` 里
	# 那句是同一个道理：上一个阶段的安排不该跟过来。
	# 剧本最后一幕把人按在床上（`place_player` 的 `pin`）；不松的话，
	# 后面那条「把控制权还给玩家」的调试口子就废了（人钉在床上走不动）。
	if player != null:
		player.pinned = false
		# **藏起来那一步也一样。** 「把玩家藏起来」是某一幕的安排
		#（场景图上画着人那种），剧情一完就该露回来 —— 不然后面
		# 自由走动的时候人看不见（和上面那句 `pinned` 同一个道理）。
		player.visible = true

	if ending_id != &"":
		# 走到结局**就回主界面**，不把控制权还回去。
		# 开场的分支②一路走到这儿人已经死了，死后再让他举着小人
		# 在黑屋子里走动没有意义。
		show_ending(ending_id)

		if free_roam_after_ending:
			# 调试口子：结局之后**不回主界面**，把画面交回玩家。
			#
			# 为什么需要：正常流程里委托屋那段演完就是 end1、直接回标题，
			# 人根本走不到卧室去 —— 而卧室的碰撞箱得亲眼走着看才算验过。
			# 黑幕揭开、结局那两行字收掉，人站在原地，想去哪去哪。
			# **正常流程要关掉**（`false`），它只影响「走到结局」这一条路。
			print("[调试] free_roam_after_ending 开着 —— 结局之后不回主界面，控制权还给玩家")
			if stage_overlay != null:
				stage_overlay.clear_caption()
			if stage_curtain != null and stage_curtain.is_down():
				# 用**瞬揭**不用淡出：调试口子不需要那半秒过渡，
				# 而且淡出要等帧推进 —— 无头测试里 tween 不动，
				# 「幕揭开了没有」这条断言会假红。
				stage_curtain.snap_up()
			return

		if dialogue != null and dialogue.is_open():
			# 结局文字是对话框念的：念完那一下才回标题
			awaiting_title = true
			dialogue.finished.connect(_back_to_title_after_ending, CONNECT_ONE_SHOT)
		else:
			# 剧本自己把结局文字演完了（黑屏正中那两行，见 `caption`）。
			# 这时候没有任何东西会发 `finished`，**必须当场回标题** ——
			# 不然后面挂着等一个永远不来的信号，人停在一片黑上。
			return_to_title()
		return

	# 没走到结局的（剧情还没定稿那种）照旧把控制权还回去。
	# 黑幕得揭掉，不然玩家停在一片黑上，除了关游戏没有别的出路。
	if stage_curtain != null and stage_curtain.is_down():
		dialogue.finished.connect(_lift_curtain_once, CONNECT_ONE_SHOT)


func _lift_curtain_once() -> void:
	if stage_curtain != null and stage_curtain.is_down():
		stage_curtain.lift(0.5)


## 结局文字念完那一下。
##
## 挂的是 `dialogue.finished`，而对话框被关掉也会发它 —— 所以先看标记。
## 读了档、开了新局就都不该回标题。
func _back_to_title_after_ending() -> void:
	if not awaiting_title:
		return
	awaiting_title = false
	return_to_title()


## 演结局：标题 + 简介，用对话框播。
##
## 结局界面（CG、回到标题）属于 M7 的表现层，到时替换这里即可，
## 标记与进度那部分不用动。
func show_ending(id: StringName) -> void:
	var def := endings.get_ending(id)
	var title := def.display_title() if def != null else str(id)
	var summary := def.summary if def != null else ""

	# 记进全局图鉴。**只有第一次走到才提示** —— 重复走同一条路不该反复弹。
	if gallery.unlock(id):
		toast.show_text("新结局已记入图鉴 · %d / %d" % [gallery.count(), endings.endings.size()])

	# 剧本把这句写在了黑屏正中间（`caption`）的时候不重复一遍：
	# 底下再冒出一个对话框写「结局达成 · 平静即死亡」，是把同一件事说两次。
	if stage_overlay != null and stage_overlay.caption_lines() > 0:
		print("[结局] 达成 %s（%s）· 文字由剧本自己演" % [id, title])
		return

	var lines: Array = [{"text": "结局达成 · %s" % title}]
	if summary != "":
		lines.append({"text": summary})

	dialogue.play(Dialogue.from_array(lines))
	print("[结局] 达成 %s（%s）" % [id, title])


## 已达成的结局。给测试和将来的结局列表用。
func unlocked_endings() -> Array[EndingDef]:
	return endings.unlocked_in(flags)


## 打开 / 关上图鉴。
func toggle_gallery() -> void:
	if gallery_panel == null:
		return
	if gallery_panel.is_open():
		gallery_panel.close()
		return
	gallery_panel.open(endings, gallery)


## 关上图鉴。读档、切场景这类「界面该收起来」的场合用。
func close_gallery() -> void:
	if gallery_panel != null:
		gallery_panel.close()


# ---------------------------------------------------------------- 背包

## 打开 / 关上背包。B 键和右下角那个图标都走这里。
func toggle_inventory() -> void:
	if inventory == null:
		return
	if inventory.is_open():
		inventory.close()
		return
	inventory.open(items, flags)


## 点了右下角的背包图标。面板不认识游戏状态，所以由这里把物品表和状态递过去。
func _on_inventory_button() -> void:
	toggle_inventory()


# ---------------------------------------------------------------- 标题与菜单

## 这几个入口只是转发，正主在 `scenes/menu_flow.gd`。
##
## 留转发而不是让外面直接调 `menu_flow`，是因为它们属于「游戏对外能做的事」
## —— 开标题、开存档菜单 —— 入口该有一个地方列全，而不是散在两个文件里。
## 每个转发三行，比让调用方先去查「这个在 menu_flow 还是 main」便宜。
func show_title() -> void:
	if chase_session != null:
		chase_session.cancel()
	# 标题放**它自己的曲子**，不是上一个场景的。
	# `boot()` 那会儿起始场景其实已经加载好了，不换一手的话，
	# 玩家还没进屋就听着屋里的曲子。
	play_music(TITLE_MUSIC)
	menu_flow.show_title()


## 回主界面。**走到结局之后走这条**。
##
## 这是一次**凭空跳转**，所以场上属于这一局的东西全扔掉：还在跑的剧情、
## 临时角色、覆盖层。黑幕反过来要盖着 —— 底下露着一个亮着的房间，
## 看着像没跳干净（标题本来也盖在黑幕上面）。
##
## 存档和图鉴一个都不动：那些是跨局的东西，回个标题不该顺手清掉。
## 玩家想接着看看这个结局，标题里就有图鉴。
func return_to_title() -> void:
	if story.is_active():
		story.cancel()
	if cutscene != null:
		cutscene.cancel()
	if stage_overlay != null:
		stage_overlay.clear()
	# 界面全收掉：结局文字是这一局的最后一句，不该跟着人到标题上
	if ui_host != null:
		ui_host.close_overlays()
	if stage_curtain != null:
		stage_curtain.snap_down()
	show_title()


func open_save_menu() -> void:
	menu_flow.open_save_menu()


func open_load_menu() -> void:
	menu_flow.open_load_menu()


func open_settings() -> void:
	menu_flow.open_settings()


## 打开暂停菜单（ESC 走这里）。
##
## 只留一道闸：**转场中不给开** —— 画面正在黑下去，这时候弹出菜单，
## 关掉之后人落在哪个场景是不确定的。
##
## 原来还有一道「已经有界面开着不给开」，现在撤了。撤得起是因为 ESC 的分发
## 挪到了「把键交给最上面那个界面」**之前**（见 `_unhandled_input`）：
## 谁接这个键已经排清楚了，不用再在门口挡一遍。
##
## 剧情正等着玩家选的时候按 ESC 就是要开它 —— 屏幕上那句提示还在劝人存盘，
## 而选项框压在暂停菜单**下面**（13 < 14），看得见逃不掉。
func open_pause_menu() -> void:
	if pause_menu == null:
		return
	if fade != null and fade.is_busy():
		return
	pause_menu.open(not SaveStore.list_all().is_empty())


## 退出游戏。
##
## **测试里别调这个** —— 它会把跑测试的进程一起关掉，而且看不出来是谁干的。
## 想验「菜单上确实有退出这一项」，断言 `PauseMenu` 发出来的 id 就够了。
func quit_game() -> void:
	get_tree().quit()


## 新开一局：清空世界状态，回到起始场景。
##
## **图鉴不动** —— 那是跨存档的全局记录，开新局不该把「你见过几个结局」清掉。
func new_game(start_map: StringName = &"", start_spawn: StringName = &"") -> void:
	if chase_session != null:
		chase_session.cancel()
	map_triggers.reset()
	personal_anchor = PERSONAL_ANCHOR_SCRIPT.new()
	ch2_checkpoints.clear()
	menu_flow.new_game(start_map, start_spawn)


# ---------------------------------------------------------------- 存档

## 现在能不能存档。
##
## 剧情进行中**也能存** —— 存档记下正在演的事件与节点，读档从那个节点接着演。
## 只有转场到一半时不行：那时场景还没定下来，存了是自相矛盾。
func can_save() -> bool:
	if current_map == null:
		return false
	return not (fade != null and fade.is_busy())


## 存到指定槽位。不传就用当前槽位。
##
## 存的是「当前全部状态」：场景、坐标、朝向、剧情进度、世界状态、结局进度。
## 读档要回到玩家离开的那一刻，不是把他丢回场景开头。
func capture_ch2_checkpoint(checkpoint_id: String) -> bool:
	if checkpoint_id not in ["rescue", "chase", "route"] or current_map == null or player == null:
		return false
	var saved_flags := flags.snapshot().duplicate(true)
	saved_flags.erase(StringName("ch2/retry_checkpoint/" + checkpoint_id))
	var serial_flags: Dictionary = {}
	for key: Variant in saved_flags:
		serial_flags[str(key)] = saved_flags[key]
	var checkpoint := {
		"map_id": str(current_map.id),
		"spawn": str(current_spawn),
		"player_position": [player.global_position.x, player.global_position.y],
		"facing": [player.facing.x, player.facing.y],
		"velocity": [player.velocity.x, player.velocity.y],
		"pinned": player.pinned,
		"visible": player.visible,
		"scale": [player.scale.x, player.scale.y],
		"flags": serial_flags,
		"actors": cutscene.snapshot_actors() if cutscene != null else [],
		"camera_focus": [camera_focus.x, camera_focus.y] if camera_focus is Vector2 else null,
		"time_scale": Engine.time_scale,
	}
	ch2_checkpoints[checkpoint_id] = checkpoint
	flags.set_value(StringName("ch2/retry_checkpoint/" + checkpoint_id), checkpoint.duplicate(true))
	return true


func restore_ch2_checkpoint(checkpoint_id: String) -> bool:
	if not ch2_checkpoints.has(checkpoint_id) or player == null:
		return false
	var checkpoint: Dictionary = ch2_checkpoints[checkpoint_id]
	var target_map := StringName(checkpoint.get("map_id", ""))
	var target_spawn := StringName(checkpoint.get("spawn", "default"))
	var saved_flags: Variant = checkpoint.get("flags", {})
	if not (saved_flags is Dictionary) or target_map == &"":
		return false
	_clear_player_motion_state()
	var persistent_flags: Dictionary = {}
	for key: StringName in flags.keys():
		if _is_ch2_persistent_flag(key):
			persistent_flags[key] = flags.get_value(key)
	flags.clear()
	flags.load_values(saved_flags as Dictionary)
	for key: Variant in persistent_flags:
		flags.set_value(StringName(key), persistent_flags[key])
	if current_map == null or current_map.id != target_map:
		enter_map(target_map, target_spawn, true)
	else:
		current_spawn = target_spawn
	player.global_position = _checkpoint_vector(checkpoint.get("player_position"), player.global_position)
	player.facing = _checkpoint_vector(checkpoint.get("facing"), Vector2.DOWN)
	player.velocity = _checkpoint_vector(checkpoint.get("velocity"), Vector2.ZERO)
	player.pinned = bool(checkpoint.get("pinned", false))
	player.visible = bool(checkpoint.get("visible", true))
	player.scale = _checkpoint_vector(checkpoint.get("scale"), player.scale)
	var saved_focus: Variant = checkpoint.get("camera_focus")
	camera_focus = _checkpoint_vector(saved_focus, Vector2.ZERO) if saved_focus is Array else null
	Engine.time_scale = float(checkpoint.get("time_scale", 1.0))
	flags.set_value(StringName("ch2/retry_checkpoint/" + checkpoint_id), checkpoint.duplicate(true))
	if rescue_panel != null:
		rescue_panel.close()
	if cutscene != null:
		cutscene.clear_actors()
		var saved_actors: Variant = checkpoint.get("actors", [])
		if saved_actors is Array:
			cutscene.restore_actors(saved_actors as Array)
	refresh_scene()
	update_camera()
	update_player_control()
	update_cover()
	return true


func _is_ch2_persistent_flag(key: StringName) -> bool:
	var name := str(key)
	return name.begins_with("memory/") \
		or name.begins_with("map_blood/") \
		or name.begins_with("ch2/personal/") \
		or name.begins_with("ending/") \
		or name in [
			"ch2/personal_anchor_snapshot",
			"ch2/personal_anchor_captured",
		]


func _checkpoint_vector(raw: Variant, fallback: Vector2) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	if raw is Vector2:
		return raw
	return fallback


func clear_ch2_checkpoint(checkpoint_id: String) -> void:
	ch2_checkpoints.erase(checkpoint_id)
	flags.unset_value(StringName("ch2/retry_checkpoint/" + checkpoint_id))


func _sync_ch2_checkpoints_from_flags() -> void:
	ch2_checkpoints.clear()
	for checkpoint_id: String in ["rescue", "chase", "route"]:
		var saved: Variant = flags.get_value(
			StringName("ch2/retry_checkpoint/" + checkpoint_id))
		if saved is Dictionary:
			ch2_checkpoints[checkpoint_id] = saved.duplicate(true)


func capture_personal_anchor() -> bool:
	if personal_anchor.is_captured() or current_map == null or player == null:
		return false
	var snapshot := SaveData.new()
	snapshot.map_id = current_map.id
	snapshot.spawn = current_spawn
	snapshot.player_position = player.global_position
	snapshot.facing = player.facing
	if not personal_anchor.capture_once(snapshot, flags):
		return false
	flags.set_value(&"ch2/personal_anchor_snapshot", personal_anchor.to_dictionary())
	flags.set_value(&"ch2/personal_anchor_captured", true)
	return true


func restore_personal_anchor() -> bool:
	if not personal_anchor.is_captured():
		_sync_personal_anchor_from_flags()
	if not personal_anchor.is_captured() or current_map == null or player == null:
		return false
	var snapshot := SaveData.new()
	if not personal_anchor.restore(snapshot, flags):
		return false
	if current_map.id != snapshot.map_id:
		enter_map(snapshot.map_id, snapshot.spawn, true)
		if current_map == null or current_map.id != snapshot.map_id:
			return false
	current_spawn = snapshot.spawn
	_clear_player_motion_state()
	player.global_position = snapshot.player_position
	player.facing = snapshot.facing
	player.velocity = Vector2.ZERO
	update_camera()
	update_cover()
	return true


func _clear_player_motion_state() -> void:
	walk_and_use = false
	pending_actor = null
	if player != null:
		player.walk_path.clear()


func _sync_personal_anchor_from_flags() -> void:
	personal_anchor = PERSONAL_ANCHOR_SCRIPT.new()
	var saved: Variant = flags.get_value(&"ch2/personal_anchor_snapshot")
	if saved != null and personal_anchor.load_dictionary(saved):
		flags.set_value(&"ch2/personal_anchor_captured", true)


func save_game(slot: int = -1) -> bool:
	if not can_save():
		toast.show_text("转场中，等一下")
		return false

	var data := SaveData.new()
	data.map_id = current_map.id
	data.spawn = current_spawn
	data.player_position = player.global_position
	data.facing = player.facing

	# 剧情进度：正在演的事件、节点，以及**节点内演到第几步**。
	#
	# 后两个数不能省。只记节点的话，在「等选择」那一步存档、读档回来，
	# 会把这一整节点的台词从头再演一遍 —— 玩家抱怨的就是这个。
	if story.is_active():
		data.story_event = story.event_id
		data.story_node = story.current_node_id()
		data.story_step = story.stage_step()
		data.story_spoke = story.spoke()
	# **场上站着的临时角色也记下来。** 他们是演出现造的，不属于地图数据 ——
	# 不记的话读档回来人就不见了（剧情正停在跟谁说话上，人却不在）。
	if cutscene != null:
		data.actors = cutscene.snapshot_actors()

	return save_mgr.save(data, slot)


## 从指定槽位读档。不传就用当前槽位。
##
## **读档成功要顺手把标题收掉。**
##
## 主菜单的「继续」开的是加载界面，而标题在那条路上**自己不收**
## （`TitleScreen.STAY_OPEN`，因为加载界面关掉时得能回到标题）。
## 于是「读档」这件事得由这边来收尾：不收的话标题会盖在游戏画面上
## （它层号 21，比游戏高），玩家看到的还是主菜单 ——
## 2026-09-24 报的「继续不能加载存档，而是返回主菜单」就是它。
##
## 游戏内读档（暂停菜单 → 加载）时标题本来就没开，收一下无害。
func load_game(slot: int = -1) -> bool:
	var data := save_mgr.load_state(slot)
	if data == null:
		return false
	_sync_personal_anchor_from_flags()
	_sync_ch2_checkpoints_from_flags()

	if title_screen != null:
		title_screen.close()
	_jump_to(data.map_id, data.spawn)

	# 回到当时站的坐标，而不是出生点。老存档没坐标时才退回出生点。
	if data.has_position():
		player.global_position = data.player_position
		player.facing = data.facing

	# 剧情接着演。存档时正演到一半，读回来从**那个节点的那一步**继续 ——
	# 只定位到节点是不够的，那样整段台词会重放一遍。
	if data.in_story():
		var resume_node: StringName = data.story_node
		var resume_step: int = data.story_step
		var resume_spoke: bool = data.story_spoke
		if data.story_event == &"ch2_diary" and resume_node in [&"run_q1", &"run_q2", &"arrive"]:
			resume_node = &"restart_chase"
			resume_step = 0
			resume_spoke = false
		start_story(data.story_event, resume_node, resume_step, resume_spoke)
	# **把场上的人摆回来。** 放在 `start_story` **之后** ——
	# 剧情自己会摆的（节点里的 `npc`）优先级更高，`restore_actors` 会跳过同名的人。
	# 反过来的话会先恢复一个、再被剧情摆的那个顶掉，白闪一下。
	if cutscene != null and not data.actors.is_empty():
		cutscene.restore_actors(data.actors)

	return true


## 删掉一个槽位的存档。
func delete_save(slot: int = -1) -> bool:
	return save_mgr.delete(slot)


## 按当前世界状态重画场景。
##
## 玩家做完选择之后，有些角色或连接就该出现、或者该消失了。
## 整个重画比增量更新简单得多，场景又小，不值得为它做优化。
func refresh_scene() -> void:
	if current_map == null or map_view == null:
		return
	map_view.build(current_map, flags)
	_sync_library_box_visual()
