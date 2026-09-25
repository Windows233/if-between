## 表现层那一块：对话框按行数长高、跳过已读、文字速度、立绘动效。
##
## 这几样都是「画面上能看出来」的，但用无头测试一样能盯住 ——
## 高度、当前停在第几行、速度值、立绘的偏移，都是能问出来的数。
##
## 由 `tests/run_tests.gd` 统一调用。断言与公共工具在 `TestHarness`。
class_name TestPresentation
extends RefCounted


static func run(h: TestHarness) -> void:
	test_box_height_grows(h)
	test_box_layout(h)
	test_skip_read(h)
	test_speed_settings(h)
	test_settings_panel(h)
	test_toast_and_hud(h)
	test_portrait_motion(h)
	test_screen_shatter(h)


## 对话框的版式：面板占屏幕下三分之一，立绘站在面板**里面**，
## 正文缩到两条立绘带子中间那一列。
##
## 这几条是稿子①的原文：「对话框只占屏幕的1/3」「主角立绘在方框左侧1/3处，
## 文字在中间浮现，其他人物立绘统一在方框右侧」。
static func test_box_layout(h: TestHarness) -> void:
	var box := DialogueBox.new()
	h.root.add_child(box)
	box.setup()

	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
	h.check("面板是屏幕高度的三分之一",
		DialogueBox.BOX_MIN_HEIGHT * 3.0, view.y)

	box.play(Dialogue.from_array([{"speaker": "我", "text": "一句话。"}]))
	h.check("短句就是那三分之一", box.box_height(), DialogueBox.BOX_MIN_HEIGHT)
	# 面板上沿报的是 `hold_top()`（给选项框定位用的那一个公开口子）——
	# `_box_top()` 是私有的，测试直接调它会在运行时抛错，
	# 结果这之后一长串断言**一条都不执行**（看着还是全绿）。
	h.check("面板贴着屏幕下方",
		box.hold_top(), view.y - DialogueBox.BOX_MIN_HEIGHT - DialogueBox.MARGIN)

	# 正文那一列：左右各让开一条立绘带子
	var text := box.text_rect()
	h.check("正文左边让开立绘",
		text.position.x >= DialogueBox.PORTRAIT_WIDTH, true)
	h.check("正文右边也让开立绘",
		text.position.x + text.size.x <= view.x - DialogueBox.PORTRAIT_WIDTH, true)
	# 窄到两三个字就换行的话，长台词会把面板撑爆 —— 这条守着那个下限
	h.check("正文不窄于 120", text.size.x >= 120.0, true)

	box.queue_free()


## 提示的位置和时长（稿子②），以及左上角那行状态。
static func test_toast_and_hud(h: TestHarness) -> void:
	var main := h.new_main()

	# 稿子②：「提示出现在画面右上角，在3秒后渐渐消失」
	h.check("显示三秒", Toast.LIFE, 3.0)
	main.toast.show_text("获得 猫的照片")
	h.check("默认落在右上角", main.toast.place(), Toast.Place.CORNER)

	# 稿子单独给「此处建议存档」指了画面中线上方
	main.show_hint("此处建议存档", "center")
	h.check("建议存档落在中线上方", main.toast.place(), Toast.Place.CENTER)
	h.check("还是那句话", main.toast.current_text(), "此处建议存档")

	# 左上角的状态：摆出来、几秒后自己收掉、换一行、空字符串也收。
	#
	# **不是常驻** —— 一行状态一直挂在角落里，看久了像屏幕上粘了块脏东西。
	# 时间靠 `tick()` 推，无头测试里没有帧循环。
	main.show_location("xx月x日　傍晚　委托屋")
	h.check("左上角摆出来了", main.location_hud.is_open(), true)
	h.check("写的是日期地点", main.location_hud.current_text(), "xx月x日　傍晚　委托屋")

	var hud: LocationHud = main.location_hud
	hud.tick(LocationHud.LIFE * 0.5)
	h.check("半途还看得见", hud.is_open(), true)
	hud.tick(LocationHud.LIFE)
	h.check("到点自己收掉", hud.is_open(), false)

	main.show_location("第二行")
	h.check("换一行还能再摆出来", hud.is_open(), true)
	main.show_location("")
	h.check("空字符串就是收起", hud.is_open(), false)

	main.queue_free()


## 面板高度随正文行数浮动。写死 56 的时候，结局简介一长就露出面板。
static func test_box_height_grows(h: TestHarness) -> void:
	var box := DialogueBox.new()
	h.root.add_child(box)
	box.setup()

	box.play(Dialogue.from_array([{"text": "一句话。"}]))
	h.check("短句用最小高度", box.box_height(), DialogueBox.BOX_MIN_HEIGHT)

	# 长到要占好几行
	var long := ""
	for _i: int in 12:
		long += "这一句很长很长很长，长到必须换行才放得下。"
	box.play(Dialogue.from_array([{"text": long}]))
	h.check("长句把面板撑高了", box.box_height() > DialogueBox.BOX_MIN_HEIGHT, true)
	h.check("但不超过上限", box.box_height() <= DialogueBox.BOX_MAX_HEIGHT, true)

	# 回到短句要缩回去：面板只长不缩的话，看完一段长的之后全都是高面板
	box.play(Dialogue.from_array([{"text": "又短了。"}]))
	h.check("短句缩回去", box.box_height(), DialogueBox.BOX_MIN_HEIGHT)

	# 上限是为了不压到立绘：面板上沿之下还得留得下立绘的头顶
	var view := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
	var top := view.y - box.box_height() - DialogueBox.MARGIN
	box.play(Dialogue.from_array([{"text": long}]))
	var tall_top := view.y - box.box_height() - DialogueBox.MARGIN
	h.check("最高的面板也没顶到天", tall_top > 0.0, true)
	h.check("长面板确实比短的高", tall_top < top, true)

	box.queue_free()


## 跳过已读：一路快进到**没读过的那一行**为止。
static func test_skip_read(h: TestHarness) -> void:
	var box := DialogueBox.new()
	h.root.add_child(box)
	box.setup()

	var three := Dialogue.from_array([
		{"text": "第一句。"},
		{"text": "第二句。"},
		{"text": "第三句。"},
	])

	# 第一次经过：一句一句播完，三句都进了历史
	box.play(three)
	box.skip()
	h.check("第一次走完了", box.is_open(), false)

	# 第二次经过：三句都读过，快进应当直接跳到最后一句
	box.play(three)
	h.check("回到第一句", box.current_index(), 0)
	h.check("第一句是读过的", box.current_is_read(), true)
	h.check("快进成功", box.handle_key(KEY_R), true)
	h.check("跳到最后一句", box.current_index(), 2)
	h.check("停在第三句", box.current_text(), "第三句。")

	# 掺了没读过的：快进要被没看过的内容挡住。
	# 挡在**前一句**而不是送过去 —— 送过去的话连按几下就把新内容吞掉了。
	var mixed := Dialogue.from_array([
		{"text": "第一句。"},
		{"text": "从没见过的一句。"},
	])
	box.play(mixed)
	h.check("混合段从头开始", box.current_index(), 0)
	h.check("没读过的内容挡住快进", box.handle_key(KEY_R), false)
	h.check("停在看过的地方", box.current_index(), 0)
	h.check("停的是看过的那句", box.current_text(), "第一句。")

	# 全都是新句子时，快进什么也不做
	var fresh := Dialogue.from_array([{"text": "全新的甲。"}, {"text": "全新的乙。"}])
	box.play(fresh)
	h.check("全新的不该快进", box.handle_key(KEY_R), false)
	h.check("还停在第一句", box.current_index(), 0)

	box.queue_free()


## 文字速度：三档循环，存盘，跨局还在。
static func test_speed_settings(h: TestHarness) -> void:
	var settings := GameSettings.new()
	settings.speed = GameSettings.DEFAULT_SPEED
	h.check("默认是中速", settings.speed, GameSettings.DEFAULT_SPEED)
	h.check("默认那一档叫中", settings.speed_label(), "中")

	settings.cycle_speed()
	h.check("切到快", settings.speed, GameSettings.SPEED_FAST)
	settings.cycle_speed()
	h.check("到头绕回慢", settings.speed, GameSettings.SPEED_SLOW)
	h.check("慢档名字对", settings.speed_label(), "慢")
	settings.cycle_speed()
	h.check("再切回中", settings.speed, GameSettings.DEFAULT_SPEED)

	# 落盘：换一个实例读，才是真的存住了
	settings.speed = GameSettings.SPEED_FAST
	settings.save_settings()
	var again := GameSettings.new()
	again.load_settings()
	h.check("换实例读回来", again.speed, GameSettings.SPEED_FAST)

	# 坏文件不该让游戏起不来，读出来是默认值
	_write_raw("{ 这不是 JSON")
	var broken := GameSettings.new()
	broken.load_settings()
	h.check("坏文件退回默认", broken.speed, GameSettings.DEFAULT_SPEED)

	# 速度真的喂给了对话框
	var box := DialogueBox.new()
	h.root.add_child(box)
	box.setup()
	box.set_speed(GameSettings.SPEED_SLOW)
	h.check("对话框收到速度", box.speed(), GameSettings.SPEED_SLOW)
	# 给个离谱的值也要兜住，不然一行字要打一年
	box.set_speed(-100.0)
	h.check("离谱的速度被夹住", box.speed() > 0.0, true)

	box.queue_free()
	settings.speed = GameSettings.DEFAULT_SPEED
	settings.save_settings()


static func test_settings_panel(h: TestHarness) -> void:
	var settings := GameSettings.new()
	settings.display = WindowMode.DEFAULT_MODE
	settings.window_size = WindowMode.DEFAULT_SIZE
	settings.speed = GameSettings.DEFAULT_SPEED

	var panel := SettingsPanel.new()
	h.root.add_child(panel)
	panel.setup()

	h.check("一开始关着", panel.is_open(), false)
	panel.open(settings)
	h.check("开着了", panel.is_open(), true)

	# 五行：显示模式 / 分辨率 / 文字速度 / 音乐音量 / 音效音量
	h.check("五行都在", SettingsPanel.ROWS.size(), 5)
	h.check("后两行是滑条", SettingsPanel.SLIDER_ROWS.size(), 2)
	h.check("第一根管音乐", SettingsPanel.SLIDER_ROWS[0], &"music")
	h.check("第二根管音效", SettingsPanel.SLIDER_ROWS[1], &"sfx")
	h.check("光标停在第一行", panel.cursor(), 0)
	h.check("第一行是显示模式", panel.row_value(0), settings.display_label())

	var changes := [0]
	panel.changed.connect(func() -> void:
		changes[0] += 1
	)

	# 第一行：显示模式，窗口 ↔ 全屏
	panel.handle_key(KEY_RIGHT)
	h.check("切了显示模式", settings.display != WindowMode.DEFAULT_MODE, true)
	h.check("发了变更信号", changes[0], 1)
	h.check("面板上的字跟着变", panel.row_value(0), settings.display_label())

	# 第二行：分辨率
	panel.handle_key(KEY_DOWN)
	h.check("光标走到第二行", panel.cursor(), 1)
	var before_size := settings.window_size
	panel.handle_key(KEY_RIGHT)
	h.check("尺寸换了一档", settings.window_size != before_size, true)

	# 第三行：文字速度
	panel.handle_key(KEY_DOWN)
	h.check("光标走到第三行", panel.cursor(), 2)
	h.check("显示当前档位", panel.value_text().find("中") >= 0, true)
	panel.handle_key(KEY_RIGHT)
	h.check("右键切了一档", settings.speed, GameSettings.SPEED_FAST)
	h.check("面板上的字也变了", panel.value_text().find("快") >= 0, true)
	panel.handle_key(KEY_LEFT)
	h.check("左键也能切", settings.speed, GameSettings.SPEED_SLOW)

	# 第四行：音乐音量。滑条 —— 左右是**调大小**，不是换档。
	#
	# **先把两根滑条摆到 50%**：下面几条算的是「按一格走多远」，
	# 得有个确定的起点。拿默认值当起点的话，默认值一改（50% → 25%）
	# 这几条就全红，而它们本来跟默认值没有关系。
	settings.music_volume = 0.5
	settings.sfx_volume = 0.5
	panel.handle_key(KEY_DOWN)
	h.check("光标走到第四行", panel.cursor(), 3)
	h.check("显示的是百分比", panel.row_value(3), "50%")
	panel.handle_key(KEY_LEFT)
	h.check("往左调小一格", panel.row_value(3), "45%")
	panel.handle_key(KEY_RIGHT)
	panel.handle_key(KEY_RIGHT)
	h.check("往右调大两格", panel.row_value(3), "55%")

	# 第五行：音效音量。**和音乐各走各的** —— 拉这根不该动那根。
	panel.handle_key(KEY_DOWN)
	h.check("光标走到第五行", panel.cursor(), 4)
	panel.handle_key(KEY_LEFT)
	h.check("音效调小了", panel.row_value(4), "45%")
	h.check("音乐那根没被带上", panel.row_value(3), "55%")

	# 上下是循环的
	panel.handle_key(KEY_DOWN)
	h.check("走到底绕回第一行", panel.cursor(), 0)
	panel.handle_key(KEY_UP)
	h.check("往上绕到最后一行", panel.cursor(), 4)

	h.check("ESC 被吃掉", panel.handle_key(KEY_ESCAPE), true)
	h.check("关掉了", panel.is_open(), false)
	h.check("关着的时候按键没人吃", panel.handle_key(KEY_RIGHT), false)

	# 收尾：`adjust_*` 是写盘的，恢复默认，别把后面的用例带跑
	settings.music_volume = GameSettings.DEFAULT_VOLUME
	settings.sfx_volume = GameSettings.DEFAULT_VOLUME
	settings.save_settings()

	panel.queue_free()

	# 别把玩家自己的设置改坏
	settings.display = WindowMode.DEFAULT_MODE
	settings.window_size = WindowMode.DEFAULT_SIZE
	settings.speed = GameSettings.DEFAULT_SPEED
	settings.save_settings()
static func test_portrait_motion(h: TestHarness) -> void:
	var owner := Control.new()
	h.root.add_child(owner)

	var slot := DialoguePortrait.create(owner, owner, DialogueLine.Side.LEFT)
	slot.rest_x = 2.0
	slot.show_speaker("邻居", "", false)
	h.check("记下说话人", slot.speaker, "邻居")
	h.check("这一侧在说话", slot.speaking, true)
	slot.place(100.0, 60.0)
	h.check("没图就不占位（不糊色块）", slot.head.visible, false)
	h.check("没图不显示真图", slot.sprite.visible, false)

	# 换表情会重放一遍过渡（这里只确认它不崩、图还在）。
	# 路径要写完整 —— `protagonist/quiet` 这种简写是 `DialogueLine` 补的，
	# 直接传给载图函数并不存在。
	slot.show_speaker("邻居", "res://art/portrait/protagonist/quiet.png", false)
	slot.place(100.0, 60.0)
	h.check("换上了真图", slot.sprite.visible, true)
	h.check("有色块就不显示了", slot.head.visible, false)

	# 立绘站在面板**里面**：底边贴着面板内沿往上留一个 `INNER_PAD`。
	# 这个位置跟图片比例无关（`_apply_geometry()` 里算出来的），能直接比。
	h.check("底边贴着面板内沿", slot.bottom(), 157.0)
	h.check("顶边在面板里", slot.rest_y > 100.0, true)

	# 呼吸：说话的那侧上下浮。**测真图的位置** —— 没有立绘的一侧根本不显示，
	# 去测它等于什么都没测。
	var rest := slot.rest_y
	slot.apply_breath(1.2)
	h.check("呼吸把人顶起来一点", slot.sprite.position.y, rest + 1.2)
	slot.apply_breath(0.0)
	h.check("偏移归零就回原位", slot.sprite.position.y, rest)

	# 压暗之后就不呼吸了，而且偏移要归零 ——
	# 停在上一次的某个位置上看着像歪着
	slot.apply_breath(1.2)
	slot.dim()
	slot.apply_breath(1.2)
	h.check("不说话的一侧不动", slot.sprite.position.y, rest)

	# 呼吸不许把人像顶出面板，上下都不行。
	#
	# 早先立绘画在面板**上方**，往上浮就飘离对话框、下面留一道缝；
	# 现在它整个在框里，靠 `INNER_PAD` 那点余量兜住 —— 这条守的就是那个余量。
	slot.show_speaker("邻居", "res://art/portrait/protagonist/quiet.png", false)
	slot.place(100.0, 60.0)
	slot.apply_breath(-DialoguePortrait.BREATH_AMOUNT)
	h.check("浮到最高也不出底", slot.bottom() <= 160.0, true)
	h.check("浮到最高也不露头", slot.rest_y - DialoguePortrait.BREATH_AMOUNT > 100.0, true)
	slot.apply_breath(DialoguePortrait.BREATH_AMOUNT)
	h.check("沉到最低也不出底", slot.bottom() <= 160.0, true)
	# 上面三条的地基：内边距不够的话，浮起来就顶出去了
	h.check("内边距大于呼吸幅度",
		DialoguePortrait.INNER_PAD > DialoguePortrait.BREATH_AMOUNT, true)
	slot.apply_breath(0.0)

	slot.hide()
	h.check("收起来之后没有说话人", slot.speaker, "")
	h.check("收起来之后不显示", slot.sprite.visible, false)

	# 面板变矮时立绘跟着变矮，底边仍然贴着内沿（头顶不被裁）
	slot.show_speaker("邻居", "res://art/portrait/protagonist/quiet.png", false)
	slot.place(120.0, 40.0)
	h.check("矮框也摆得下", slot.bottom(), 157.0)
	h.check("矮框里也不出上沿", slot.rest_y > 120.0, true)

	owner.queue_free()


## 绕过 GameSettings 直接写一份原始内容，用来造「坏掉的设置文件」。
static func _write_raw(text: String) -> void:
	var file := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


## 屏幕破碎特效：素材在位、能摆出「炸开完成」的样子、能收干净。
##
## **动画本身验不了** —— 无头测试没有帧循环，tween 推不动。所以验的是状态：
## 材质建起来了没有、遮罩参数真的写进 shader 了没有、收不收得掉。
## 「裂纹从中心往外炸」这件事靠截图和真窗口看（开发纪要 37）。
static func test_screen_shatter(h: TestHarness) -> void:
	var fx := ScreenShatter.new()
	h.root.add_child(fx)
	fx.setup()

	h.check("素材和 shader 都在", fx.ready_to_play(), true)
	h.check("默认是收着的", fx.visible, false)
	h.check("默认不在场上", fx.is_playing(), false)
	# 铺满整个视口 —— 它是整屏特效，不是一块贴图
	h.check("铺满屏幕", fx.size, Vector2(320.0, 180.0))
	h.check("开着 mipmap（细裂纹缩下去会闪）",
		fx.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)

	fx.show_burst()
	h.check("摆出炸开的样子", fx.visible, true)
	h.check("裂纹铺到底", fx.spread() > 1.0, true)
	h.check("在场上", fx.is_playing(), true)

	fx.set_spread(0.4)
	h.check("能摆到炸到一半", absf(fx.spread() - 0.4) < 0.001, true)

	fx.stop()
	h.check("收干净了", fx.visible, false)
	h.check("不在场上了", fx.is_playing(), false)

	fx.queue_free()
