## 结局图鉴：跨存档的全局记录，以及看它的那个面板。
##
## 图鉴记录要回答的是「你一共见过几个结局」，跟「当前这条路线走到了哪」
## 是两件事。所以这里一半的用例在盯**删档之后记录还在不在**。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
class_name TestGallery
extends RefCounted


static func run(h: TestHarness) -> void:
	test_gallery_records(h)
	test_gallery_file(h)
	test_gallery_outlives_save(h)
	test_gallery_panel(h)
	test_gallery_from_play(h)


# ---------------------------------------------------------------- 记录

static func test_gallery_records(h: TestHarness) -> void:
	var gallery := EndingGallery.new()
	gallery.clear()

	h.check("一开始是空的", gallery.count(), 0)
	h.check("没记过", gallery.has(&"end1_calm"), false)

	h.check("记一个是新增", gallery.unlock(&"end1_calm"), true)
	h.check("记了一个", gallery.count(), 1)
	h.check("查得到", gallery.has(&"end1_calm"), true)

	# 重复走到同一个结局不算新
	h.check("再记一次不算新增", gallery.unlock(&"end1_calm"), false)
	h.check("还是只有一个", gallery.count(), 1)

	# 时间记下来了，而且重复达成不会覆盖首次时间
	var first := gallery.first_at(&"end1_calm")
	h.check("记了首次达成时间", first != "", true)
	gallery.unlock(&"end1_calm")
	h.check("重复达成不改首次时间", gallery.first_at(&"end1_calm"), first)

	# 别的结局照记
	gallery.unlock(&"end2_sweet")
	h.check("记了第二个", gallery.count(), 2)
	h.check("空 id 不记", gallery.unlock(&""), false)

	# 顺序稳定：界面上的列表不该乱跳
	var ids := gallery.ids()
	h.check("倒出来两个", ids.size(), 2)
	h.check("按字典序", ids[0], &"end1_calm")

	gallery.clear()
	h.check("清空之后没了", gallery.count(), 0)


static func test_gallery_file(h: TestHarness) -> void:
	var gallery := EndingGallery.new()
	gallery.clear()

	h.check("没文件时读出来是空的", gallery.count(), 0)
	gallery.load_records()
	h.check("读空的也不报错", gallery.count(), 0)

	gallery.unlock(&"end1_calm")
	gallery.unlock(&"end2_sweet")

	# 换一个实例读，才是真的落了盘
	var again := EndingGallery.new()
	again.load_records()
	h.check("换实例读回来两个", again.count(), 2)
	h.check("读回来有重逢", again.has(&"end1_calm"), true)
	h.check("首次时间也回来了", again.first_at(&"end1_calm"), gallery.first_at(&"end1_calm"))

	# 坏文件不该让游戏起不来，读出来就是空记录
	_write_raw("{ 这不是 JSON")
	var broken := EndingGallery.new()
	broken.load_records()
	h.check("坏文件读出来是空的", broken.count(), 0)

	_write_raw("\"只是个字符串\"")
	var junk := EndingGallery.new()
	junk.load_records()
	h.check("不是对象也读成空", junk.count(), 0)

	gallery.clear()


## 图鉴记录**不在** `saves/` 里，删档扫不到它。这是它存在的理由。
static func test_gallery_outlives_save(h: TestHarness) -> void:
	var gallery := EndingGallery.new()
	gallery.clear()
	var main := h.new_main()
	const SLOT := 2
	SaveStore.delete(SLOT)

	# 走到一个结局
	_play_to_ending(h, main)
	h.check("达成了一个结局", main.unlocked_endings().size(), 1)
	h.check("图鉴记下来了", main.gallery.has(&"end1_calm"), true)
	h.check("图鉴里有一个", main.gallery.count(), 1)

	# 存个档，再把档删掉
	h.check("存成功", main.save_game(SLOT), true)
	h.check("删档成功", SaveStore.delete(SLOT), true)
	h.check("档真没了", SaveStore.exists(SLOT), false)

	# 图鉴记录不受影响
	var after := EndingGallery.new()
	after.load_records()
	h.check("删档之后图鉴还在", after.count(), 1)
	h.check("还在的是重逢", after.has(&"end1_calm"), true)

	# 重新开一局：flags 是空的（这条路线没走过），但图鉴记得
	var fresh := h.new_main()
	h.check("新游戏没达成结局", fresh.unlocked_endings().size(), 0)
	h.check("新游戏读得到图鉴", fresh.gallery.count(), 1)
	h.check("图鉴里是重逢", fresh.gallery.has(&"end1_calm"), true)

	fresh.queue_free()
	main.queue_free()
	gallery.clear()


# ---------------------------------------------------------------- 界面

static func test_gallery_panel(h: TestHarness) -> void:
	var table := EndingTable.from_array([
		{"id": "end1_calm", "title": "平静即死亡", "summary": "你没有做错什么。", "kind": "bad"},
		{"id": "end2_sweet", "title": "甜蜜的咬痕", "summary": "你也不是故意的。", "kind": "bad"},
		{"id": "end3_nothing", "title": "碌碌而无为", "kind": "true"},
	])
	var gallery := EndingGallery.new()
	gallery.clear()
	gallery.unlock(&"end1_calm")

	var panel := EndingGalleryPanel.new()
	h.root.add_child(panel)
	panel.setup()

	h.check("一开始关着", panel.is_open(), false)
	panel.open(table, gallery)
	h.check("开着了", panel.is_open(), true)

	# 列表按结局表走，没见过的也要占一行
	h.check("三项都列出来了", panel.row_count(), 3)
	h.check("见过的一行是标题", panel.row_text(0), "平静即死亡")
	h.check("没见过的是问号", panel.row_text(1), "？？？")

	h.check("光标在第一行", panel.cursor(), 0)
	h.check("第一行是见过的", panel.current_unlocked(), true)
	h.check("详情是简介", panel.detail_text().begins_with("你没有做错什么。"), true)
	h.check("详情里有首次时间", panel.detail_text().find("首次达成") >= 0, true)

	# 往下走一格，落到没见过的那项
	h.check("下键被吃掉", panel.handle_key(KEY_DOWN), true)
	h.check("光标走到第二行", panel.cursor(), 1)
	h.check("第二行没见过", panel.current_unlocked(), false)
	h.check("没见过的详情", panel.detail_text(), "还没走到这个结局。")

	# 转一圈回来
	panel.handle_key(KEY_DOWN)
	h.check("走到第三行", panel.cursor(), 2)
	panel.handle_key(KEY_DOWN)
	h.check("回到第一行", panel.cursor(), 0)
	panel.handle_key(KEY_UP)
	h.check("往上绕到第三行", panel.cursor(), 2)

	# 不认识的键不吞
	h.check("别的键不吞", panel.handle_key(KEY_A), false)

	h.check("ESC 被吃掉", panel.handle_key(KEY_ESCAPE), true)
	h.check("关掉了", panel.is_open(), false)

	panel.queue_free()
	gallery.clear()


## 走完整条主线，图鉴应当记下它，面板也该看得到。
static func test_gallery_from_play(h: TestHarness) -> void:
	var main := h.new_main()
	main.gallery.clear()
	SaveStore.delete(2)

	h.check("一开始图鉴是空的", main.gallery.count(), 0)
	_play_to_ending(h, main)

	h.check("走到结局了", main.unlocked_endings().size(), 1)
	h.check("图鉴记了一个", main.gallery.count(), 1)
	h.check("图鉴里是重逢", main.gallery.has(&"end1_calm"), true)
	h.check("图鉴提示弹了", main.toast.is_open(), true)
	h.check("提示说的是图鉴", main.toast.current_text().begins_with("新结局已记入图鉴"), true)

	# 开图鉴看看
	main.toggle_gallery()
	h.check("图鉴打开了", main.gallery_panel.is_open(), true)
	h.check("四个结局都列出来了", main.gallery_panel.row_count(), 4)
	h.check("第一行是 end1", main.gallery_panel.row_text(0), "平静即死亡")
	h.check("第二行还没见过", main.gallery_panel.row_text(1), "？？？")

	# 图鉴开着时角色不该动。控制状态是每帧算的，同步测试要自己拉一次。
	main.update_player_control()
	h.check("图鉴开着角色停住", main.player.is_physics_processing(), false)

	main.toggle_gallery()
	h.check("再按一次关掉", main.gallery_panel.is_open(), false)

	main.queue_free()
	main.gallery.clear()


# ---------------------------------------------------------------- 工具

## 把第一章走到一个结局：新游戏 → 开场 → 不接受委托 → end1。
static func _play_to_ending(h: TestHarness, main: Node2D) -> void:
	h.play_to_end1(main)


## 绕过 EndingGallery 直接写一份原始内容，用来造「坏掉的记录文件」。
static func _write_raw(text: String) -> void:
	var file := FileAccess.open(EndingGallery.PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()
