## 背包：物品表、界面、以及两个入口（B 键与右下角那个图标）。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
class_name TestInventory
extends RefCounted


static func run(h: TestHarness) -> void:
	test_item_table(h)
	test_panel_lists_items(h)
	test_panel_open_close(h)
	test_button_opens_panel(h)
	test_main_wiring(h)


static func test_item_table(h: TestHarness) -> void:
	var flags := WorldState.new()
	h.check("一件都没有", ItemTable.count_of(flags, &"cat_photo"), 0)
	h.check("没有就是没有", ItemTable.has(flags, &"cat_photo"), false)

	ItemTable.add(flags, &"cat_photo")
	h.check("加一件", ItemTable.count_of(flags, &"cat_photo"), 1)
	h.check("再加一件", ItemTable.add(flags, &"cat_photo"), 2)
	h.check("有这么多件", ItemTable.has(flags, &"cat_photo", 2), true)
	h.check("不够就是不够", ItemTable.has(flags, &"cat_photo", 3), false)

	# 不够就一件不动 —— 静默扣成负数比失败难查得多
	h.check("不够时拿不走", ItemTable.remove(flags, &"cat_photo", 3), false)
	h.check("数量没被改", ItemTable.count_of(flags, &"cat_photo"), 2)
	h.check("够的时候拿得走", ItemTable.remove(flags, &"cat_photo", 2), true)
	h.check("拿完就是 0", ItemTable.count_of(flags, &"cat_photo"), 0)

	# 键名带前缀是为了跟普通剧情变量分开
	h.check("物品键认得出来", ItemTable.is_item_flag(&"item/cat_photo"), true)
	h.check("剧情变量不是物品", ItemTable.is_item_flag(&"quest_cat"), false)
	h.check("从键反推 id", ItemTable.id_from_flag(&"item/cat_photo"), &"cat_photo")
	var items := DataLoader.load_items()
	h.check("旧 charm 存档显示为决策币", items.name_of(&"charm"), "决策币")


static func test_panel_lists_items(h: TestHarness) -> void:
	var items := DataLoader.load_items()
	var flags := WorldState.new()

	h.check("空背包列出来是空的", InventoryPanel.collect(items, flags).size(), 0)

	ItemTable.add(flags, &"cat_photo")
	ItemTable.add(flags, &"pendant")
	ItemTable.add(flags, &"cat_photo", 1)
	# 用光的（归零）不该留在列表里 —— 背包里挂一串 0 很怪
	ItemTable.add(flags, &"charm")
	ItemTable.remove(flags, &"charm")

	var entries := InventoryPanel.collect(items, flags)
	h.check("列出两件", entries.size(), 2)
	h.check("按 id 排序，位置不跳", entries[0]["id"], &"cat_photo")
	h.check("第二件是吊坠", entries[1]["id"], &"pendant")
	h.check("名字从物品表来", entries[0]["name"], "猫的照片")
	h.check("数量对", entries[0]["count"], 2)
	h.check("有图标", entries[0]["icon"], "res://art/item/cat_photo.png")

	# 没有图的东西不该让格子空掉
	h.check("没图就返回空路径", InventoryPanel.icon_path(&"不存在的物品"), "")
	h.check("正式决策币沿用charm存档ID并显示已交圆币图",
		InventoryPanel.icon_path(&"charm"), "res://art/item/charm.png")


static func test_panel_open_close(h: TestHarness) -> void:
	var items := DataLoader.load_items()
	var flags := WorldState.new()
	ItemTable.add(flags, &"cat_photo")

	var panel := InventoryPanel.new()
	h.root.add_child(panel)
	panel.setup()

	h.check("一开始是关的", panel.is_open(), false)
	panel.open(items, flags)
	h.check("开着了", panel.is_open(), true)
	h.check("列了一件", panel.entry_count(), 1)
	h.check("开着的时候右下角图标收起", panel.is_button_visible(), false)

	h.check("B 键关了它", panel.handle_key(KEY_B), true)
	h.check("关上了", panel.is_open(), false)
	h.check("图标又出来了", panel.is_button_visible(), true)
	h.check("关着的时候按键不管", panel.handle_key(KEY_B), false)

	panel.queue_free()


static func test_button_opens_panel(h: TestHarness) -> void:
	var panel := InventoryPanel.new()
	h.root.add_child(panel)
	panel.setup()

	var asked := [0]
	panel.open_requested.connect(func() -> void:
		asked[0] += 1
	)

	panel.press_button()
	h.check("点了图标会请求打开", asked[0], 1)

	# 图标收起来的时候点不动 —— 过场里它本来就不该在
	panel.set_button_visible(false)
	panel.press_button()
	h.check("收起时点不动", asked[0], 1)

	panel.set_button_visible(true)
	panel.press_button()
	h.check("放出来又点得动", asked[0], 2)

	panel.queue_free()


static func test_main_wiring(h: TestHarness) -> void:
	var main := h.new_main()

	# 一开始没东西，按 B 也能开（面板会说「还没有东西」）
	h.check("背包关着", main.inventory.is_open(), false)
	main.toggle_inventory()
	h.check("B 键那条路开得了", main.inventory.is_open(), true)

	# 开着的时候角色停下、界面调度认得它
	main.update_player_control()
	h.check("背包开着角色停住", main.player.is_physics_processing(), false)
	h.check("调度认为有界面占着", main.ui_host.is_busy(), true)
	h.check("键盘先给背包", main.ui_host.handle_key(KEY_B), true)
	h.check("按 B 关掉", main.inventory.is_open(), false)

	main.update_player_control()
	h.check("关掉角色能动", main.player.is_physics_processing(), true)

	# 走过开场之后，拿到的那张照片就在背包里
	h.start_opening(main)
	h.pick(main, &"accept")
	h.drain_dialogue(main.dialogue)
	main.toggle_inventory()
	h.check("背包里有一件", main.inventory.entry_count(), 1)
	h.check("就是猫的照片", main.inventory.entries()[0]["name"], "猫的照片")
	main.toggle_inventory()

	# 过场里右下角那个图标要收起来 —— 那时候画面上的东西都归演出管
	main.stage_curtain.snap_down()
	main.start_story(&"ch1_opening")
	main.update_player_control()
	h.check("过场里图标收起", main.inventory.is_button_visible(), false)
	main.story.cancel()
	main.stage_curtain.snap_up()
	main.update_player_control()
	h.check("过场结束图标回来", main.inventory.is_button_visible(), true)

	main.queue_free()
