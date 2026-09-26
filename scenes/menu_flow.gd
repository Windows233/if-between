## 标题、存档菜单、设置面板这套流程：谁在哪儿开、选完了干什么。
##
## 从 `main.gd` 抽出来的理由跟 `UiHost` 是同一条，但切的是另一刀：
## `UiHost` 管「**现在**谁开着、按键先给谁」；这里管「**开菜单**这件事
## 本身要走的几步」—— 组装槽位条目、把菜单上的选择翻译成存还是读、
## 删完重开一次菜单。加完这三样菜单，`main.gd` 到了 704 行，所以拆。
##
## 它**持有 main 的引用**，直接调 `save_game()` / `load_game()` / `enter_map()`
## 这些动作。用引用而不是信号，是因为这些回调本来就是「替 main 干活」，
## 再绕一层信号只会让读的人多点一次跳转。
class_name MenuFlow
extends RefCounted

var main: Node2D = null


func setup(p_main: Node2D) -> void:
	main = p_main


# ---------------------------------------------------------------- 开

## 显示标题界面。「继续」有没有存档决定。
func show_title() -> void:
	if main == null or main.title_screen == null:
		return
	main.title_screen.open(not SaveStore.list_all().is_empty())


## 打开存档菜单（存）。转场中不给开。
func open_save_menu() -> void:
	if main == null:
		return
	if not main.can_save():
		main.toast.show_text("转场中，等一下")
		return
	if main.ui_host != null:
		main.ui_host.open_save_menu(save_entries(), SaveMenu.Mode.SAVE)


## 打开读档菜单（读）。转场中同样不给开。
func open_load_menu() -> void:
	if main == null:
		return
	if main.fade != null and main.fade.is_busy():
		main.toast.show_text("转场中，等一下")
		return
	if main.ui_host != null:
		main.ui_host.open_save_menu(save_entries(), SaveMenu.Mode.LOAD)


## 打开设置面板。图鉴开着的话先收起来，两个全屏面板不叠着开。
func open_settings() -> void:
	if main == null or main.settings_panel == null:
		return
	if main.gallery_panel != null:
		main.gallery_panel.close()
	main.settings_panel.open(main.settings)


# ---------------------------------------------------------------- 菜单上的选择

## 菜单上的三行。空槽也要占位，并写明它是空的 ——
## 玩家得知道这个槽能用。
func save_entries() -> Array[SaveMenu.Entry]:
	var out: Array[SaveMenu.Entry] = []
	for slot: int in SaveStore.SLOT_COUNT:
		var data := SaveStore.read(slot)
		if data == null:
			out.append(SaveMenu.Entry.make(slot, "", "", true))
			continue
		out.append(SaveMenu.Entry.make(
			slot, data.summary(main.endings), data.saved_at, false
		))
	return out


## 菜单上选了一个槽位。`mode` 告诉这次是存还是读。
func on_save_menu_chosen(slot: int, mode: int) -> void:
	if main == null:
		return
	if mode == SaveMenu.Mode.LOAD:
		main.load_game(slot)
		return
	main.save_game(slot)


## 菜单上删了一个槽位。删完重开一次菜单，
## 那一行要变回「（空）」，不然玩家以为没删掉。
func on_save_menu_deleted(slot: int) -> void:
	if main == null:
		return
	main.delete_save(slot)
	if main.ui_host != null:
		main.ui_host.open_save_menu(save_entries(), SaveMenu.Mode.SAVE)


func on_title_chosen(id: StringName) -> void:
	if main == null:
		return
	match id:
		TitleScreen.ID_NEW:
			new_game()
		TitleScreen.ID_CONTINUE:
			# **开加载界面，不自动读最近那个档。**
			#
			# 自动读最近档看着省事，其实是在替玩家做选择：他点了「继续」，
			# 想看的是「我有哪些档」，而不是「最近那个是什么」。
			# 存档不止一个的时候，自动读还会把人送进他本来不想进的那一局。
			open_load_menu()
		TitleScreen.ID_GALLERY:
			main.toggle_gallery()
		TitleScreen.ID_SETTINGS:
			open_settings()
		TitleScreen.ID_QUIT:
			main.quit_game()


## 暂停菜单上选了一项。
##
## 「继续游戏」什么也不用做 —— 菜单自己已经把界面收了（`PauseMenu` 里
## 只有开子面板的那三项会留着），回到这儿就等于回到游戏。
func on_pause_chosen(id: StringName) -> void:
	if main == null:
		return
	match id:
		PauseMenu.ID_RESUME:
			pass
		PauseMenu.ID_SETTINGS:
			open_settings()
		PauseMenu.ID_SAVE:
			open_save_menu()
		PauseMenu.ID_LOAD:
			open_load_menu()
		PauseMenu.ID_TITLE:
			main.return_to_title()
		PauseMenu.ID_QUIT:
			main.quit_game()


## 设置改了：把新值喂给需要它的地方。
##
## 打字速度交给对话框；音量交给两条总线（音乐、音效各一根滑块）。
func on_settings_changed() -> void:
	if main == null:
		return
	main.dialogue.set_speed(main.settings.speed)
	AudioBuses.apply(main.settings.music_volume, main.settings.sfx_volume)


# ---------------------------------------------------------------- 动作

## 新开一局：清空世界状态，回到起始场景。
##
## **图鉴不动** —— 那是跨存档的全局记录，开新局不该把「你见过几个结局」清掉。
func new_game() -> void:
	if main == null:
		return
	# 开场演出。`skip_opening` 是调试开关，正常流程是 false（见 `main.gd`）。
	# 打开着就别让人以为「剧情没触发」，所以吼一声。
	# 类型得写死：`main` 声明成 `Node2D`，`skip_opening` 是它脚本上的变量，
	# 静态看来是 Variant，`:=` 推不出来（会直接编译不过）。
	var play_opening: bool = not main.skip_opening and main.debug_start_map == ""
	if not play_opening:
		print("[调试] 新游戏不演开场：skip_opening=%s debug_start_map=%s"
			% [main.skip_opening, main.debug_start_map])
	# 幕布跟着开场走，两种方向都要摆正：
	#
	# - 演开场：**先压黑**。开场头几步就是「黑屏 + 章标题」，
	#   不先盖住的话会先闪一下屋子。
	# - 不演开场：**必须揭开**。不能只是「不压」——
	#   走到结局会回标题，而 `return_to_title()` 是故意把幕留着的
	#   （标题在黑幕上面，看得见），从那儿再点「新游戏」时幕还是压着的。
	#   不揭就是一片黑，只剩背包图标挂在上面。
	if main.stage_curtain != null:
		if play_opening:
			main.stage_curtain.snap_down()
		else:
			main.stage_curtain.snap_up()
	main.flags.clear()
	# 测试开关：`debug_start_map` 非空就落进那张图（见 `main.gd` 的开关说明）。
	# 类型写死的原因同上：`main` 静态是 `Node2D`，`:=` 推不出来。
	var start_map: String = main.debug_start_map if main.debug_start_map != "" else main.START_MAP
	main.enter_map(start_map, main.START_SPAWN)
	# 测试图：出生在门口、面向屋内。正常流程的出生朝向归开场演出管，不动。
	if main.debug_start_map != "":
		main.player.facing = Vector2.UP
	if play_opening:
		main.start_story(main.OPENING_EVENT)


## 最近存过的那个槽位。「继续」用它。
##
## 存档时间是 `YYYY-MM-DD HH:MM:SS`，字符串直接比大小就是时间先后，
## 不用再解析一遍。
func latest_slot() -> int:
	var all := SaveStore.list_all()
	if all.is_empty():
		return 0
	var best: SaveData = all[0]
	for data: SaveData in all:
		if data.saved_at > best.saved_at:
			best = data
	return best.slot
