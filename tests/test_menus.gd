## 标题界面、存读档菜单、以及把它们串起来的界面调度器。
##
## 这一组存在的理由，是**这些界面以前根本没有**：存档只能按 F5 打在固定槽位，
## 玩家看不见有几个槽、不能选、不能删；启动直接落进房间，没有「新游戏」。
## 所以这里盯的是「玩家到底能不能用上」。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
##
## **写这个文件时注意类型推断。** `h.new_main()` 返回的是 `Node2D`，
## 它身上没有 `player` / `current_map` / `menu_flow` 这些属性 —— 取出来是
## `Variant`，用 `:=` 会报 `Cannot infer the type`，而那个报错在 `--script` 下的
## 表现是**整轮测试卡住、没有任何输出**（不是报错，看着像死循环）。
##
## 一律写显式类型：
##
##     var slot: int = main.menu_flow.latest_slot()
##     var p: Player = main.player
##
## 这个坑 2026-09-24 一天踩了三次，别再有第四次。
class_name TestMenus
extends RefCounted

## 存档测试用一个专门的槽位，不碰玩家真正会用的槽位 0。
##
## **注意 0 号槽是空的** —— 从加载界面里挑槽读档时，挑到 0 号会「选了没反应」
## （空槽不给读，见 `SaveMenu._confirm`）。测试里用 `latest_slot()` 找有档那格。
const TEST_SLOT := 2


static func run(h: TestHarness) -> void:
	test_save_menu_entry(h)
	test_save_menu_panel(h)
	test_title_screen(h)
	test_chapter_two_developer_entry(h)
	test_ui_host(h)
	test_save_menu_in_game(h)
	test_title_in_game(h)
	test_pause_menu(h)
	test_pause_menu_in_game(h)
	test_pause_freezes_world(h)
	test_title_subpanel_returns(h)
	test_escape_from_title_subpanel(h)
	test_back_buttons(h)
	test_esc_routing(h)
	test_new_game_without_opening(h)


static func _entries() -> Array[SaveMenu.Entry]:
	return [
		SaveMenu.Entry.make(0, "room_a · 重逢", "2026-09-21 21:00", false),
		SaveMenu.Entry.make(1, "", "", true),
		SaveMenu.Entry.make(2, "overworld", "2026-09-21 21:30", false),
	]


# ---------------------------------------------------------------- 条目

static func test_save_menu_entry(h: TestHarness) -> void:
	var filled := SaveMenu.Entry.make(0, "room_a · 重逢", "2026-09-21 21:00", false)
	h.check("有内容的写摘要", filled.line(), "槽位 1　room_a · 重逢")
	h.check("有内容的不是空", filled.empty, false)
	h.check("时间带着", filled.saved_at, "2026-09-21 21:00")

	# 空槽也要占一行并写明是空的，不然玩家不知道这个槽能用
	var empty := SaveMenu.Entry.make(1, "", "", true)
	h.check("空槽写空", empty.line(), "槽位 2　（空）")
	h.check("空槽标记着", empty.empty, true)


static func test_save_menu_panel(h: TestHarness) -> void:
	var menu := SaveMenu.new()
	h.root.add_child(menu)
	menu.setup()
	SaveStore.delete(TEST_SLOT)

	h.check("一开始关着", menu.is_open(), false)
	menu.open(_entries(), SaveMenu.Mode.SAVE)
	h.check("开着了", menu.is_open(), true)
	h.check("三个槽都在", menu.entry_count(), 3)
	h.check("第一行是摘要", menu.row_text(0), "槽位 1　room_a · 重逢")
	h.check("第二行是空", menu.row_text(1), "槽位 2　（空）")

	# 选中的槽位在下面显示时间
	h.check("光标在第一行", menu.cursor(), 0)
	h.check("详情是时间", menu.detail_text(), "2026-09-21 21:00")

	# 选到空槽
	menu.handle_key(KEY_DOWN)
	h.check("走到第二行", menu.cursor(), 1)
	h.check("空槽详情", menu.detail_text(), "这个槽位还是空的。")

	# 信号回调用的**数组**装，不用单个变量：
	# GDScript 的 lambda 捕获是按值的，在里面给 `var x` 赋值传不到外面来。
	var got := [-1, -1, -1]  # [选中的槽位, 模式, 删掉的槽位]
	menu.chosen.connect(func(slot: int, mode: int) -> void:
		got[0] = slot
		got[1] = mode
	)
	menu.deleted.connect(func(slot: int) -> void:
		got[2] = slot
	)

	menu.handle_key(KEY_X)
	h.check("空槽删不掉", got[2], -1)
	h.check("空槽也不进确认", menu.is_confirming_delete(), false)

	menu.select_index(2)
	menu.handle_key(KEY_X)
	h.check("第一次只是标记", got[2], -1)
	h.check("在等第二次", menu.is_confirming_delete(), true)
	h.check("提示改成再按一次", menu.detail_text(), SaveMenu.CONFIRM_TEXT)

	# 换一行就等于放弃了刚才那次确认
	menu.handle_key(KEY_UP)
	h.check("换行走开就不算了", menu.is_confirming_delete(), false)

	menu.select_index(2)
	menu.handle_key(KEY_X)
	menu.handle_key(KEY_X)
	h.check("第二次真删", got[2], 2)

	# 确认存档
	menu.handle_key(KEY_ENTER)
	h.check("选了槽位 3", got[0], 2)
	h.check("模式是存", got[1], SaveMenu.Mode.SAVE)
	h.check("选完就关", menu.is_open(), false)

	# 读档模式下空槽不给选
	var load_menu := SaveMenu.new()
	h.root.add_child(load_menu)
	load_menu.setup()
	load_menu.open(_entries(), SaveMenu.Mode.LOAD)
	var loaded := [-2]
	load_menu.chosen.connect(func(slot: int, _mode: int) -> void:
		loaded[0] = slot
	)
	load_menu.select_index(1)
	load_menu.handle_key(KEY_ENTER)
	h.check("空槽读不出来", loaded[0], -2)
	h.check("空槽把菜单留着", load_menu.is_open(), true)

	load_menu.select_index(0)
	load_menu.handle_key(KEY_ENTER)
	h.check("有内容的能读", loaded[0], 0)

	load_menu.queue_free()
	menu.queue_free()


# ---------------------------------------------------------------- 标题

static func test_title_screen(h: TestHarness) -> void:
	var title := TitleScreen.new()
	h.root.add_child(title)
	title.setup()

	h.check("一开始关着", title.is_open(), false)
	title.open(false)
	h.check("开着了", title.is_open(), true)
	h.check("五项", title.item_count(), 5)

	# 主界面背景图（2026-09-25 加的）。素材在就建，不在就退回纯色 ——
	# 所以这条查的是「建出来了没有」，不是「必须有」。
	var picture := title.get_node_or_null("Root/BgPicture") as TextureRect
	h.check("主界面有背景图", picture != null, true)
	if picture != null:
		var root: Control = title.get_node("Root")
		h.check("背景图压在纯色那块之上",
			picture.get_index() > root.get_node("Bg").get_index(), true)
		# **高亮得在图上面。** 原来那句写的是「`_bg` 后面那一格」，
		# 加了图之后会把高亮插到图前面、被盖住 —— 所以改成认「最后一层背景」。
		var highlight: Control = root.get_node("Highlight")
		h.check("高亮又在背景图之上",
			highlight.get_index() > picture.get_index(), true)

	h.check("第一项是新游戏", title.current_id(), TitleScreen.ID_NEW)
	h.check("没存档时继续是灰的", title.is_enabled(1), false)
	h.check("图鉴一直能进", title.is_enabled(2), true)
	h.check("最后一项是退出游戏", title.row_text(4), "退出游戏")
	h.check("退出一直能选", title.is_enabled(4), true)

	# 上下移动会跳过灰掉的那一项
	title.handle_key(KEY_DOWN)
	h.check("跳过了继续", title.current_id(), TitleScreen.ID_GALLERY)
	title.handle_key(KEY_DOWN)
	h.check("再往下是设置", title.current_id(), TitleScreen.ID_SETTINGS)
	title.handle_key(KEY_DOWN)
	h.check("再往下是退出游戏", title.current_id(), TitleScreen.ID_QUIT)
	title.handle_key(KEY_DOWN)
	h.check("绕回新游戏", title.current_id(), TitleScreen.ID_NEW)

	# 灰项直接选不动
	title.select_index(1)
	h.check("灰项选不中", title.current_id(), TitleScreen.ID_NEW)

	var picked := [&""]
	title.chosen.connect(func(id: StringName) -> void:
		picked[0] = id
	)
	title.handle_key(KEY_ENTER)
	h.check("选了新游戏", picked[0], TitleScreen.ID_NEW)
	h.check("新游戏先不收标题（等起名确认）", title.is_open(), true)

	# 「退出游戏」也只发一个 id —— **测试绝不去执行它**，
	# `main.quit_game()` 会把跑测试的进程一起关掉。
	title.open(false)
	title.select_index(4)
	title.handle_key(KEY_ENTER)
	h.check("退出项发出 quit", picked[0], TitleScreen.ID_QUIT)
	h.check("选完也关了", title.is_open(), false)

	# 有存档时继续就能选了
	title.open(true)
	h.check("有存档时能继续", title.is_enabled(1), true)

	# ESC 在标题界面什么也不做：还没进游戏就谈退出没意义
	h.check("ESC 不被吃掉", title.handle_key(KEY_ESCAPE), false)
	h.check("ESC 不会把人扔出去", title.is_open(), true)

	# 开发者开关在标题页立即显示并排按钮，不增加垂直菜单行数。
	title.open(false, true)
	h.check("开启后标题多出第二章按钮", title.item_count(), 6)
	var chapter_index: int = title._ids.find(TitleScreen.ID_CHAPTER_TWO)
	var new_rect := title._row_rect(title._ids.find(TitleScreen.ID_NEW))
	var chapter_rect := title._row_rect(chapter_index)
	h.check("按钮与新游戏同一行", chapter_rect.position.y, new_rect.position.y)
	h.check("按钮在新游戏右侧", chapter_rect.position.x > new_rect.end.x, true)
	h.check("按钮文字清楚", title.row_text(chapter_index), "进入第二章")
	title.handle_key(KEY_RIGHT)
	h.check("右键聚焦第二章按钮", title.current_id(), TitleScreen.ID_CHAPTER_TWO)
	title.handle_key(KEY_LEFT)
	h.check("左键返回新游戏", title.current_id(), TitleScreen.ID_NEW)
	title.handle_key(KEY_DOWN)
	h.check("下键跳过并排按钮", title.current_id(), TitleScreen.ID_GALLERY)

	var chapter_click := InputEventMouseButton.new()
	chapter_click.button_index = MOUSE_BUTTON_LEFT
	chapter_click.pressed = true
	chapter_click.position = chapter_rect.get_center()
	title._on_gui_input(chapter_click)
	h.check("鼠标按钮发出第二章入口", picked[0], TitleScreen.ID_CHAPTER_TWO)
	h.check("选择跳章后标题等起名确认", title.is_open(), true)

	title.open(false)
	title.set_chapter_two_enabled(true)
	h.check("开启开关时标题按钮动态出现", title.item_count(), 6)
	title.set_chapter_two_enabled(false)
	h.check("关闭开关时标题按钮动态隐藏", title.item_count(), 5)

	title.queue_free()


static func test_chapter_two_developer_entry(h: TestHarness) -> void:
	var main := h.new_main()
	main.settings.developer_options_enabled = false
	main.menu_flow.show_title()
	h.check("开发者选项关闭时没有跳章入口",
		main.title_screen.item_count(), 5)

	main.settings_panel.open(main.settings)
	var developer_index: int = SettingsPanel.ROWS.find(&"developer")
	for _step: int in developer_index:
		main.settings_panel.handle_key(KEY_DOWN)
	main.settings_panel.handle_key(KEY_RIGHT)
	h.check("从设置开启跳章选项", main.settings.developer_options_enabled, true)
	h.check("标题页即时显示跳章按钮",
		main.title_screen.item_count(), 6)
	main.settings_panel.handle_key(KEY_ESCAPE)

	main.flags.set_value(&"test/stale", true)
	main.flags.set_value(&"item/charm", 1)
	var chapter_index: int = main.title_screen._ids.find(TitleScreen.ID_CHAPTER_TWO)
	main.title_screen.select_index(chapter_index)
	main.title_screen.handle_key(KEY_ENTER)
	h.check("跳章入口也先起昵称", main.name_entry.is_open(), true)
	h.check("起名时还没开局", main.current_map.id != MenuFlow.CHAPTER_TWO_START_MAP, true)
	main.name_entry.set_text("Alice")
	main.name_entry.submit()
	h.check("入口落在第二章第一场景",
		main.current_map.id, MenuFlow.CHAPTER_TWO_START_MAP)
	var expected_spawn := DataLoader.load_map(MenuFlow.CHAPTER_TWO_START_MAP) \
		.spawn_point(MenuFlow.CHAPTER_TWO_START_SPAWN)
	h.check("出生于后巷入口", main.player.global_position, expected_spawn)
	h.check("面向铁门", main.player.facing, Vector2.UP)
	h.check("新局状态与物品已清空（只剩昵称）", main.flags.snapshot().keys(), [PlayerName.FLAG])
	h.check("跳章入口记下昵称", main.flags.get_value(PlayerName.FLAG), "Alice")
	h.check("没有播放第一章开场", main.story.is_active(), false)
	h.check("跳章后画面揭开", main.stage_curtain.is_down(), false)
	h.check("跳章后标题关闭", main.title_screen.is_open(), false)

	main.settings.developer_options_enabled = false
	main.settings.save_settings()
	main.queue_free()


# ---------------------------------------------------------------- 调度器

static func test_ui_host(h: TestHarness) -> void:
	var host := UiHost.new()
	var dialogue := DialogueBox.new()
	var choice := ChoiceMenu.new()
	var gallery := EndingGalleryPanel.new()
	var save := SaveMenu.new()
	var settings := SettingsPanel.new()
	var title := TitleScreen.new()
	for node: CanvasLayer in [dialogue, choice, gallery, save, settings, title]:
		h.root.add_child(node)
	dialogue.setup()
	choice.setup()
	gallery.setup()
	save.setup()
	settings.setup()
	title.setup()

	host.setup(dialogue, choice, gallery, save, settings, title)
	h.check("都没开时不忙", host.is_busy(), false)

	dialogue.play(Dialogue.single("", "一句话"))
	h.check("对话开着就算忙", host.is_busy(), true)

	# 标题是最上层的：它开着时按键归它，不归对话框
	title.open(true)
	h.check("标题也开着还是忙", host.is_busy(), true)
	h.check("按键给了标题", host.handle_key(KEY_DOWN), true)
	h.check("对话框没被推进", dialogue.is_open(), true)

	# 关掉标题，按键回到对话框
	title.close()
	var before := dialogue.current_index()
	h.check("按键给了对话框", host.handle_key(KEY_SPACE), true)

	# 存档菜单比图鉴上
	gallery.open(EndingTable.new(), EndingGallery.new())
	save.open(_entries(), SaveMenu.Mode.SAVE)
	host.close_overlays()
	h.check("覆盖层全关了", gallery.is_open(), false)
	h.check("菜单也关了", save.is_open(), false)
	h.check("对话框也关了", dialogue.is_open(), false)
	h.check("关完就不忙了", host.is_busy(), false)
	h.check("没开界面时按键没人吃", host.handle_key(KEY_A), false)

	# 开菜单会先收起图鉴：两个全屏面板叠着开，关掉一个底下还压着一个
	gallery.open(EndingTable.new(), EndingGallery.new())
	host.open_save_menu(_entries(), SaveMenu.Mode.SAVE)
	h.check("开菜单时收起图鉴", gallery.is_open(), false)
	h.check("菜单开着", save.is_open(), true)
	save.close()

	for node2: CanvasLayer in [dialogue, choice, gallery, save, settings, title]:
		node2.queue_free()


# ---------------------------------------------------------------- 接线

static func test_save_menu_in_game(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)

	# 先做出一点值得一存的状态：开场演完，选①不走到结局
	h.start_opening(main)
	h.pick(main, &"accept")
	h.drain_dialogue(main.dialogue)

	# F5 开的是**菜单**，不再直接打在固定槽位上
	main.open_save_menu()
	h.check("菜单开了", main.save_menu.is_open(), true)
	h.check("模式是存", main.save_menu.mode(), SaveMenu.Mode.SAVE)
	h.check("三个槽都列着", main.save_menu.entry_count(), SaveStore.SLOT_COUNT)
	h.check("槽位是空的", main.save_menu.row_text(TEST_SLOT), "槽位 3　（空）")

	# 在菜单里选一个槽存
	main.save_menu.select_index(TEST_SLOT)
	main.save_menu.handle_key(KEY_ENTER)
	h.check("存进去了", SaveStore.exists(TEST_SLOT), true)
	h.check("存完菜单关了", main.save_menu.is_open(), false)

	# 菜单上那一行现在有内容了
	main.open_save_menu()
	h.check("不再是空槽", main.save_menu.row_text(TEST_SLOT).begins_with("槽位 3　"), true)
	h.check("摘要里带着场景", main.save_menu.row_text(TEST_SLOT).find("desk_shop") > 0, true)

	# 删档：按两次 X
	main.save_menu.select_index(TEST_SLOT)
	main.save_menu.handle_key(KEY_X)
	main.save_menu.handle_key(KEY_X)
	h.check("删掉了", SaveStore.exists(TEST_SLOT), false)
	h.check("删完菜单还开着", main.save_menu.is_open(), true)
	h.check("那一行变回空", main.save_menu.row_text(TEST_SLOT), "槽位 3　（空）")
	main.save_menu.close()

	# 存一个，再用 F9 的读档菜单读回来
	main.save_game(TEST_SLOT)
	h.check("存好了", SaveStore.exists(TEST_SLOT), true)

	main.enter_map(&"overworld", &"default")
	main.flags.clear()
	h.check("标记清掉了", ItemTable.count_of(main.flags, &"cat_photo"), 0)

	main.open_load_menu()
	h.check("读档菜单开着", main.save_menu.is_open(), true)
	h.check("模式是读", main.save_menu.mode(), SaveMenu.Mode.LOAD)
	main.save_menu.select_index(TEST_SLOT)
	main.save_menu.handle_key(KEY_ENTER)
	h.check("读回来了", main.current_map.id, &"desk_shop")
	h.check("标记也回来了", ItemTable.count_of(main.flags, &"cat_photo"), 1)
	h.check("读完菜单关了", main.save_menu.is_open(), false)

	SaveStore.delete(TEST_SLOT)
	main.queue_free()


static func test_title_in_game(h: TestHarness) -> void:
	var main := h.new_main()
	SaveStore.delete(TEST_SLOT)

	# 做出状态、存一个档。用开场之外的一个标记，
	# 这样「新游戏把它清掉了」才是有意义的 —— 开场本身会重写物品那一格。
	h.start_opening(main)
	h.pick(main, &"accept")
	h.drain_dialogue(main.dialogue)
	h.check("开场记下了", ItemTable.count_of(main.flags, &"cat_photo"), 1)
	main.flags.set_value(&"test_marker", true)
	main.save_game(TEST_SLOT)

	# 有存档时「继续」可选
	main.show_title()
	h.check("标题开着", main.title_screen.is_open(), true)
	h.check("能继续", main.title_screen.is_enabled(1), true)

	# 选「新游戏」：世界状态清空，回到起始场景，**并且重演开场**
	main.title_screen.select_index(0)
	main.title_screen.handle_key(KEY_ENTER)
	h.check("新游戏先弹起名面板", main.name_entry.is_open(), true)
	h.check("起名时标题还在底下", main.title_screen.is_open(), true)
	h.check("起名面板在最上层接键", main.ui_host._top() == main.name_entry, true)
	# 取消回到标题，旧局状态不动
	main.ui_host.handle_key(KEY_ESCAPE)
	h.check("取消起名回到标题", main.title_screen.is_open() and not main.name_entry.is_open(), true)
	h.check("取消不清旧局", main.flags.get_value(&"test_marker"), true)
	main.title_screen.handle_key(KEY_ENTER)
	# 非法输入留在面板上并提示
	main.name_entry.set_text("abc123")
	h.check("含数字不收", main.name_entry.submit(), false)
	h.check("非法时面板还开着", main.name_entry.is_open(), true)
	h.check("给出原因", main.name_entry.message(), "只能使用中文或英文字母")
	main.name_entry.set_text("  ")
	h.check("空名不收", main.name_entry.submit(), false)
	main.name_entry.set_text("林小满")
	h.check("中文名收下", main.name_entry.submit(), true)
	h.check("标题关了", main.title_screen.is_open(), false)
	h.check("昵称进了世界状态", main.flags.get_value(PlayerName.FLAG), "林小满")
	h.check("昵称缓存同步", PlayerName.current, "林小满")
	h.check("上一局的标记清掉了", main.flags.get_value(&"test_marker"), null)
	h.check("回到起始场景", main.current_map.id, &"desk_shop")
	h.check("开场重演了", main.story.is_active(), true)
	h.check("停在开场的选择上", main.choice_menu.is_open(), true)

	# 选「继续」：**开加载界面**，不自动读最近那个档。
	#
	# 自动读最近档是在替玩家做选择：他点「继续」想看的是「我有哪些档」，
	# 不是「最近那个是什么」；档不止一个的时候，还会把人送进他本来不想进的那一局。
	main.show_title()
	main.title_screen.select_index(1)
	main.title_screen.handle_key(KEY_ENTER)
	h.check("继续开的是加载界面", main.save_menu.is_open(), true)
	h.check("标题留着", main.title_screen.is_open(), true)
	h.check("没有自动读档（上一局的标记还没回来）",
		main.flags.get_value(&"test_marker"), null)

	# 从加载界面里挑**有档的那一格**，这才真的读回来。
	# （0 号槽是空的 —— 空槽不给读，选中了按回车也没反应。）
	var slot: int = main.menu_flow.latest_slot()
	h.check("最近那个档有槽号", slot >= 0, true)
	main.save_menu.select_index(slot)
	main.save_menu.handle_key(KEY_ENTER)
	h.check("挑完档读回来了", main.flags.get_value(&"test_marker"), true)
	h.check("读档把剧情收掉了", main.story.is_active(), false)
	# **标题也得收掉。** 上面刚断言过「标题留着」—— 那是给「关掉加载界面
	# 回到标题」用的。但读档是「离开标题」，所以由 `load_game()` 负责收尾。
	# 不收的话标题会盖在游戏画面上，玩家看到的还是主菜单
	# （2026-09-24 报的「继续不能加载存档，而是返回主菜单」）。
	h.check("读档之后标题收了", main.title_screen.is_open(), false)
	h.check("人进的是存档里那张图", main.current_map.id, &"desk_shop")

	# 选「结局图鉴」：图鉴打开，**标题留着不关**
	main.show_title()
	main.title_screen.select_index(2)
	main.title_screen.handle_key(KEY_ENTER)
	h.check("图鉴开了", main.gallery_panel.is_open(), true)
	# 图鉴是画在标题上面的子面板（24 > 21），关掉图鉴要回到标题 ——
	# **所以标题不能收。** 收了之后谁都不在，屏幕一片黑
	# （2026-09-24 报的：主菜单点设置、按 ESC 黑屏）。见 `TitleScreen.STAY_OPEN`。
	h.check("标题留着", main.title_screen.is_open(), true)

	# 界面占着屏幕时角色停住
	main.update_player_control()
	h.check("图鉴开着角色停住", main.player.is_physics_processing(), false)
	main.gallery_panel.close()
	main.update_player_control()
	# 图鉴关了，但**标题还开着** —— 人还在界面里，当然还是不动
	h.check("关掉图鉴回到标题，角色仍旧停着",
		main.player.is_physics_processing(), false)

	# 真离开界面（标题也收了）才轮得到走路
	main.title_screen.close()
	main.update_player_control()
	h.check("离开界面就能走了", main.player.is_physics_processing(), true)

	SaveStore.delete(TEST_SLOT)
	main.queue_free()


# ---------------------------------------------------------------- 暂停菜单

## 暂停菜单本身：六项、顺序、灰掉的那项、以及「选完留不留着」。
##
## 「选完留不留着」是它跟标题界面最不一样的地方，值得单测：
## 设置 / 保存 / 加载 开出来的是画在它上面的子面板，
## 关掉子面板后人得**还在暂停菜单里**；要是把菜单也关了，
## 玩家关掉设置就直接掉回游戏，想接着存档还得再按一次 ESC。
static func test_pause_menu(h: TestHarness) -> void:
	var menu := PauseMenu.new()
	h.root.add_child(menu)
	menu.setup()

	h.check("一开始关着", menu.is_open(), false)

	menu.open(true)
	h.check("开着了", menu.is_open(), true)
	h.check("六项", menu.item_count(), 6)
	h.check("第一项是继续游戏", menu.current_id(), PauseMenu.ID_RESUME)
	h.check("第二行是设置", menu.row_text(1), "设置")
	h.check("订单：设置排在保存前面", menu.row_text(2), "保存")
	h.check("第四行是加载", menu.row_text(3), "加载")
	h.check("第五行是返回主菜单", menu.row_text(4), "返回主菜单")
	h.check("最后是退出游戏", menu.row_text(5), "退出游戏")
	h.check("有存档时加载能选", menu.is_enabled(3), true)

	var picked := [&""]
	menu.chosen.connect(func(id: StringName) -> void:
		picked[0] = id
	)

	# 选「设置」：发出去了，但**菜单不关** —— 上面要开出设置面板来
	menu.select_index(1)
	menu.handle_key(KEY_ENTER)
	h.check("选了设置", picked[0], PauseMenu.ID_SETTINGS)
	h.check("开子面板时菜单留着", menu.is_open(), true)

	# ESC 等于「继续游戏」，不用把光标挪到第一行
	menu.handle_key(KEY_ESCAPE)
	h.check("ESC 就是继续游戏", picked[0], PauseMenu.ID_RESUME)
	h.check("选了继续就关掉", menu.is_open(), false)

	# 没有存档时「加载」灰掉，上下移动要跳过它
	menu.open(false)
	h.check("没存档时加载是灰的", menu.is_enabled(3), false)
	menu.select_index(3)
	h.check("灰项选不中", menu.current_id(), PauseMenu.ID_RESUME)
	menu.handle_key(KEY_DOWN)
	menu.handle_key(KEY_DOWN)
	h.check("下移落到保存", menu.cursor(), 2)
	menu.handle_key(KEY_DOWN)
	h.check("再下移跳过加载，落在返回主菜单", menu.cursor(), 4)

	# 退出也只发一个 id —— **测试绝不去执行它**，
	# `main.quit_game()` 会把跑测试的进程一起关掉。
	menu.select_index(5)
	menu.handle_key(KEY_ENTER)
	h.check("退出项发出 quit", picked[0], PauseMenu.ID_QUIT)
	h.check("退出之后菜单关了", menu.is_open(), false)

	menu.queue_free()


## ESC 打通之后：菜单真的开得出来、角色真的停住、键真的走它、
## 从它开出来的面板关掉之后**人还在菜单里**。
static func test_pause_menu_in_game(h: TestHarness) -> void:
	var main := h.new_main()

	h.check("主场景里有暂停菜单", main.pause_menu != null, true)
	h.check("没按之前是关的", main.pause_menu.is_open(), false)

	# 按 ESC（走的是 `main` 里那条真路径，不是直接调 open）
	main.open_pause_menu()
	h.check("菜单开了", main.pause_menu.is_open(), true)
	h.check("调度器认为有东西占着", main.ui_host.is_busy(), true)

	# 有界面开着，角色就得停下
	main.update_player_control()
	h.check("暂停时角色停住", main.player.is_physics_processing(), false)

	# 键归暂停菜单：从第一行往下走
	main.ui_host.handle_key(KEY_DOWN)
	h.check("键给了暂停菜单", main.pause_menu.cursor(), 1)

	# 开设置：设置在上面，暂停菜单**留着**
	main.pause_menu.handle_key(KEY_ENTER)
	h.check("设置开了", main.settings_panel.is_open(), true)
	h.check("暂停菜单还留着", main.pause_menu.is_open(), true)
	# 键这时候归设置面板
	h.check("键改归设置面板", main.ui_host.handle_key(KEY_DOWN), true)
	h.check("设置的光标动了", main.settings_panel.cursor(), 1)

	# 设置关掉，人回到暂停菜单
	main.settings_panel.close()
	h.check("设置关了", main.settings_panel.is_open(), false)
	h.check("人还在暂停菜单里", main.pause_menu.is_open(), true)

	# 再按 ESC：等于继续游戏
	main.ui_host.handle_key(KEY_ESCAPE)
	h.check("ESC 之后菜单关了", main.pause_menu.is_open(), false)
	h.check("调度器也清空了", main.ui_host.is_busy(), false)
	main.update_player_control()
	h.check("回到游戏就能走了", main.player.is_physics_processing(), true)

	# 回主菜单这一项：标题开出来，暂停菜单收掉
	main.open_pause_menu()
	main.pause_menu.select_index(4)
	main.pause_menu.handle_key(KEY_ENTER)
	h.check("标题开了", main.title_screen.is_open(), true)
	h.check("暂停菜单收掉了", main.pause_menu.is_open(), false)

	main.queue_free()


## ESC 菜单把世界**真的冻住**。
##
## 光挡住画面不叫暂停：演出里的 NPC 会继续走、立绘会继续浮、
## 补间会继续跑，玩家按了 ESC 却看着世界照转（2026-09-24 报的）。
##
## 这条守两件事：`SceneTree.paused` 那一手，以及「谁该停、谁该活着」的分工。
static func test_pause_freezes_world(h: TestHarness) -> void:
	var main := h.new_main()
	main.enter_map(&"desk_shop", &"start")

	# **`SceneTree.paused` 那一层在无头测试里验不了。**
	# `--script` 模式下 `SceneTree.root` 还没被引擎激活：节点 add_child 上去了
	# （父节点就是 root），但 `is_inside_tree()` 是 false、`get_tree()` 是 null
	# （2026-09-24 实测：inside_tree=false  parent=root:<Window>  tree=<null>）。
	# 所以「暂停真的把世界停住」那条放在**真窗口烟测**里（`smoke_run`）。
	# 这里验的是分工：谁该冻、谁该活着。

	# 游戏内容：暂停时该冻住。
	#
	# 这份名单和 `main._set_process_modes()` 是一对 —— 那边漏一个，
	# 这儿就会绿着而实际停不住，所以两边都得看一眼。
	h.check("角色冻得住",
		main.player.process_mode, Node.PROCESS_MODE_PAUSABLE)
	h.check("演出覆盖层冻得住",
		main.stage_overlay.process_mode, Node.PROCESS_MODE_PAUSABLE)
	h.check("对话框冻得住",
		main.dialogue.process_mode, Node.PROCESS_MODE_PAUSABLE)
	h.check("选项框冻得住",
		main.choice_menu.process_mode, Node.PROCESS_MODE_PAUSABLE)
	h.check("幕布冻得住",
		main.stage_curtain.process_mode, Node.PROCESS_MODE_PAUSABLE)

	# 界面和声音：暂停时该活着。
	# 面板要是也冻上，菜单接不到键、也关不掉 —— 那就成了死局。
	h.check("暂停菜单活着",
		main.pause_menu.process_mode, Node.PROCESS_MODE_ALWAYS)
	h.check("设置面板活着",
		main.settings_panel.process_mode, Node.PROCESS_MODE_ALWAYS)
	h.check("存档菜单活着",
		main.save_menu.process_mode, Node.PROCESS_MODE_ALWAYS)
	h.check("背景音乐不停",
		main.bgm.process_mode, Node.PROCESS_MODE_ALWAYS)
	# 转场黑幕也得活着：读档、换场景时它在动，冻住就是一片黑
	h.check("转场黑幕活着",
		main.fade.process_mode, Node.PROCESS_MODE_ALWAYS)

	# 开关一趟不该崩（拿不到 SceneTree 时 `_set_paused` 会安静跳过）
	main.open_pause_menu()
	h.check("菜单开得起来", main.pause_menu.is_open(), true)
	main.pause_menu.close()
	h.check("也关得掉", main.pause_menu.is_open(), false)

	main.queue_free()


## 主菜单点设置、再按 ESC：**回到主菜单**，不是黑屏、也不是掉进别的画面。
##
## 2026-09-24 报的，两处一起错：
##
## ① 标题开子面板时**把自己收起来了**（`_confirm()` 里无条件 `_open = false`），
##    于是设置一关，场上谁都不在 —— 黑屏；
## ② `UiHost._top()` 把标题排在最前，而标题的层号（21）比设置（17）**高**：
##    逻辑顺序和绘制顺序是反的。ESC 会落到标题手里，而标题对 ESC 是
##    「什么也不做」，于是又往外掉一层，开出暂停菜单来 ——
##    玩家看到的就是「按 ESC 卡进别的画面」。
##
## 现在三件事一起对了：标题不收、子面板画在标题上面、`_top()` 按层号从大到小排。
static func test_title_subpanel_returns(h: TestHarness) -> void:
	var main := h.new_main()
	main.show_title()
	main.title_screen.select_index(3)          # 第 4 项是「设置」
	main.title_screen.handle_key(KEY_ENTER)
	h.check("设置开了", main.settings_panel.is_open(), true)
	h.check("标题留着没收", main.title_screen.is_open(), true)
	h.check("设置画在标题上面",
		main.settings_panel.layer > main.title_screen.layer, true)
	h.check("ESC 该给设置", main.ui_host._top() == main.settings_panel, true)

	# ESC：关掉设置，人回到标题
	h.check("ESC 被设置吃掉了", main.ui_host.try_escape(), true)
	h.check("设置关了", main.settings_panel.is_open(), false)
	h.check("回到标题（不是一片黑）", main.title_screen.is_open(), true)

	# 再按一次 ESC：标题对 ESC 什么也不做，**也不该掉出界面去**
	h.check("标题不认 ESC", main.ui_host.try_escape(), false)
	h.check("人还在标题里", main.title_screen.is_open(), true)

	main.queue_free()


## 主菜单进设置、按 ESC：**要真的关掉设置、回到标题**。
##
## 上面 `test_title_subpanel_returns` 验的是 `ui_host.try_escape()` 那条路，
## **没有走真机的入口**。而 `main._unhandled_input()` 里
## 「标题开着就什么都不做」那条判断，曾经排在「把 ESC 还给最上面的界面」前面 ——
## 于是从标题开出来的设置面板，ESC 永远被丢掉：
## 表现是「按了没反应」，而单元测试全绿（2026-09-24 踩的）。
##
## 所以这条**必须从 `_unhandled_input()` 打进去**，模拟一次真的按键。
static func test_escape_from_title_subpanel(h: TestHarness) -> void:
	var main := h.new_main()
	main.show_title()
	main.title_screen.select_index(3)          # 第 4 项是「设置」
	main.title_screen.handle_key(KEY_ENTER)
	h.check("设置开着", main.settings_panel.is_open(), true)

	var esc := InputEventKey.new()
	esc.pressed = true
	esc.physical_keycode = KEY_ESCAPE
	main._unhandled_input(esc)

	h.check("ESC 之后设置关了", main.settings_panel.is_open(), false)
	h.check("人回到标题", main.title_screen.is_open(), true)
	h.check("没有顺手开出暂停菜单", main.pause_menu.is_open(), false)

	# 再按一次：标题不认 ESC，也不该掉出去
	main._unhandled_input(esc)
	h.check("标题里再按也不开暂停菜单", main.pause_menu.is_open(), false)
	h.check("标题还在", main.title_screen.is_open(), true)

	main.queue_free()


## 从主菜单开出去的三个子面板，右下角都有一个「返回」。
##
## 键盘有 ESC，鼠标原先没有出口 —— 进了设置 / 加载界面 / 图鉴，
## 想出去只能去够键盘。这三个按钮就是给鼠标的退路。
##
## 点了之后**只关自己**，不负责把上一层开回来：标题开子面板时自己不收
## （`TitleScreen.STAY_OPEN`），所以关掉自然就回到标题了。
static func test_back_buttons(h: TestHarness) -> void:
	var main := h.new_main()
	main.show_title()

	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT

	# 设置
	main.menu_flow.open_settings()
	h.check("设置开着", main.settings_panel.is_open(), true)
	click.position = main.settings_panel._back_rect().get_center()
	main.settings_panel._on_gui_input(click)
	h.check("点返回，设置关了", main.settings_panel.is_open(), false)
	h.check("人回到标题", main.title_screen.is_open(), true)

	# 加载界面
	main.menu_flow.open_load_menu()
	h.check("加载界面开着", main.save_menu.is_open(), true)
	click.position = main.save_menu._back_rect().get_center()
	main.save_menu._on_gui_input(click)
	h.check("点返回，加载界面关了", main.save_menu.is_open(), false)
	h.check("人还在标题", main.title_screen.is_open(), true)

	# 图鉴
	main.toggle_gallery()
	h.check("图鉴开着", main.gallery_panel.is_open(), true)
	click.position = main.gallery_panel._back_rect().get_center()
	main.gallery_panel._on_gui_input(click)
	h.check("点返回，图鉴关了", main.gallery_panel.is_open(), false)
	h.check("人还在标题", main.title_screen.is_open(), true)

	main.queue_free()


## ESC 的去向。
##
## 2026-09-23 那次「在 IF 选项上按 ESC，文字和选项全没了、菜单也不出来」
## 的复现与回归。旧的样子是：ESC 被交给最上面那个界面，而选项框收到 ESC
## 就把自己关掉（`cancelled` 那个信号没有人接）。场上于是只剩一个空对话框，
## 剧情卡在「等选择」那一格，点哪儿都没反应 —— 除了读档没有别的出路。
##
## 现在两条规矩：
##   1. 剧情的 IF 选项**不认** ESC，键落到外面的「开暂停菜单」；
##   2. 角色的动作菜单**认**（那是「我不想做这件事」）。
static func test_esc_routing(h: TestHarness) -> void:
	var main := h.new_main()

	# 造一个「剧情正等着玩家选」的局面
	h.start_opening(main)
	h.check("选项框开着", main.choice_menu.is_open(), true)
	h.check("对话框留着", main.dialogue.is_holding(), true)

	main._unhandled_input(_key(KEY_ESCAPE))
	h.check("ESC 开出暂停菜单", main.pause_menu.is_open(), true)
	h.check("选项没被关掉", main.choice_menu.is_open(), true)
	h.check("对话框还在等选择", main.dialogue.is_holding(), true)

	# 关掉暂停菜单：人回到选项上，还能接着选
	main.ui_host.handle_key(KEY_ESCAPE)
	h.check("暂停菜单收掉", main.pause_menu.is_open(), false)
	h.check("选项还在", main.choice_menu.is_open(), true)
	h.check("还能选", main.choice_menu.select_id(&"decline"), true)

	# 角色的动作菜单照旧能按 ESC 取消
	# （`open()` 要 `Array[ChoiceOption]`，字面量塞不进去 —— 见 test_cutscene 里那段注释）
	var options: Array[ChoiceOption] = [ChoiceOption.make(&"a", "甲")]
	main.choice_menu.open("选一个", options)
	main._unhandled_input(_key(KEY_ESCAPE))
	h.check("动作菜单被 ESC 关掉", main.choice_menu.is_open(), false)
	h.check("没顺手弹出暂停菜单", main.pause_menu.is_open(), false)

	main.queue_free()


## 造一个「按下去」的键盘事件。`main._unhandled_input()` 要的就是这个。
static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


## 不演开场的时候，新游戏必须把幕**揭开**。
##
## 这条是 2026-09-23 那次「开游戏黑屏，只剩背包图标」的复现。
## `new_game()` 为了开场那几步的黑屏会先把幕压下去，而演出被
## `skip_opening` 跳掉之后就没人揭幕 —— 玩家看到的是一片黑，
## 背包图标画在幕上面，所以只剩它。
##
## 第二条比第一条要紧：从结局回标题时幕是**故意留着的**（标题在黑幕上面，
## 看得见）。从那儿点「新游戏」时幕本来就是压着的，所以只做「不压」不够，
## 得主动揭。
static func test_new_game_without_opening(h: TestHarness) -> void:
	var main := h.new_main()

	# 一、直接开新局，跳过开场
	main.skip_opening = true
	main.new_game()
	h.check("跳过开场时幕是揭开的", main.stage_curtain.is_down(), false)
	h.check("没有剧情在演", main.story.is_active(), false)
	h.check("落在起始场景", main.current_map.id, main.START_MAP)

	# 二、先走到结局、回到标题（幕被留着），再从标题点「新游戏」
	main.skip_opening = false
	# 这一段要的是「回标题、幕留着」那个局面，所以把调试开关关掉
	# （它现在是开着的，见 `scenes/main.gd` 的 `free_roam_after_ending`）。
	main.free_roam_after_ending = false
	h.play_to_end1(main)
	h.check("结局之后回到标题", main.title_screen.is_open(), true)
	h.check("回标题时幕留着的", main.stage_curtain.is_down(), true)

	main.skip_opening = true
	main.title_screen.select_index(0)
	main.title_screen.handle_key(KEY_ENTER)
	main.name_entry.set_text("Tom Lee")
	main.name_entry.submit()
	h.check("从标题开新局，幕揭开了", main.stage_curtain.is_down(), false)
	h.check("标题也收了", main.title_screen.is_open(), false)

	main.queue_free()
