## 音频：把声音分成音乐 / 音效两条线，音量滑条怎么换算，地图配什么曲。
##
## 这一组里最要紧的一条是**「50% = 原音量」**：那是策划定的基准，
## 它错了整套音量手感就全偏了，而且在游戏里听不出来（只觉得「有点小」）。
class_name TestAudio
extends RefCounted


static func run(h: TestHarness) -> void:
	test_slider_math(h)
	test_buses(h)
	test_settings_fields(h)
	test_map_music(h)
	test_playback(h)
	test_music_step(h)
	test_meet_b_stops_music(h)
	test_footsteps_and_doors(h)


## 滑条位置换算成增益倍数。
static func test_slider_math(h: TestHarness) -> void:
	# 基准：**75% 才是原音量**（2026-09-24 从 50% 挪上来的，上半段留作余量）
	h.check("75% 就是原音量", AudioBuses.slider_to_gain(0.75), 1.0)
	h.check("50% 是原音量的三分之二",
		snappedf(AudioBuses.slider_to_gain(0.5), 0.001), 0.667)
	h.check("100% 是原音量的 4/3",
		snappedf(AudioBuses.slider_to_gain(1.0), 0.001), 1.333)
	h.check("0% 是静音", AudioBuses.slider_to_gain(0.0), 0.0)
	# 往左拉过头也不该出负数
	h.check("负数当静音处理", AudioBuses.slider_to_gain(-0.3), 0.0)

	# 默认位置**故意**压得比基准低：原音量那根刻度在上面（75%），
	# 默认停在 25%，起步不吵人。
	#
	# **这两个常量是两件事，别再拿「它们相等」当守卫** ——
	# 一开始相等（都是 0.5），2026-09-24 基准挪到 0.75，默认先是留在 0.5、
	# 后来又降到 0.25。三次都不是同一个数了。
	h.check("默认停在 25%", GameSettings.DEFAULT_VOLUME, 0.25)
	h.check("比基准低 50 个百分点",
		snappedf(AudioBuses.BASE_SLIDER - GameSettings.DEFAULT_VOLUME, 0.001), 0.5)


## 两条总线：都在、都接 Master、**各管各的**。
static func test_buses(h: TestHarness) -> void:
	AudioBuses.setup()
	var music := AudioServer.get_bus_index(AudioBuses.MUSIC)
	var sfx := AudioServer.get_bus_index(AudioBuses.SFX)
	h.check("音乐总线在", music >= 0, true)
	h.check("音效总线在", sfx >= 0, true)
	h.check("是两条不是一条", music == sfx, false)
	h.check("音乐接到 Master",
		AudioServer.get_bus_send(music), String(AudioBuses.MASTER))
	h.check("音效接到 Master",
		AudioServer.get_bus_send(sfx), String(AudioBuses.MASTER))

	# 重复 setup 不该多建
	var before := AudioServer.bus_count
	AudioBuses.setup()
	h.check("重复 setup 不会多建", AudioServer.bus_count, before)

	AudioBuses.set_music_slider(0.5)
	h.check("设 50% 读回来还是 50%",
		snappedf(AudioBuses.music_slider(), 0.001), 0.5)

	# **各管各的**：拉音乐不能动到音效
	AudioBuses.set_sfx_slider(0.2)
	AudioBuses.set_music_slider(0.8)
	h.check("拉音乐没动到音效",
		snappedf(AudioBuses.sfx_slider(), 0.001), 0.2)
	h.check("音乐自己变了",
		snappedf(AudioBuses.music_slider(), 0.001), 0.8)

	# 归零走 mute，不是写一个 -inf dB 进去
	AudioBuses.set_music_slider(0.0)
	h.check("拉到 0 会静音", AudioServer.is_bus_mute(music), true)
	h.check("静音时读回来是 0", AudioBuses.music_slider(), 0.0)
	AudioBuses.set_music_slider(0.5)
	h.check("拉回来就解除静音", AudioServer.is_bus_mute(music), false)

	# 收尾：摆回默认，别把后面的用例带跑
	AudioBuses.apply(GameSettings.DEFAULT_VOLUME, GameSettings.DEFAULT_VOLUME)


## 设置里那两项：默认值、按一格走一步、到两头停住、存得进读得出。
static func test_settings_fields(h: TestHarness) -> void:
	var s := GameSettings.new()
	# 默认位置**从常量算**，不写字面量 —— 它改过一次（50% → 25%），
	# 写死的话每改一次都要回来改这里，而这几条本来只想验「两边同一个默认」。
	var start := "%d%%" % roundi(GameSettings.DEFAULT_VOLUME * 100.0)
	h.check("默认音乐就是那个默认值", s.music_label(), start)
	h.check("默认音效也是", s.sfx_label(), start)

	# 下面测的是**按一格走多远**，跟默认值无关 —— 显式摆到 50% 起算
	s.music_volume = 0.5
	s.adjust_music(1)
	h.check("往右一格是 55%", s.music_label(), "55%")
	s.adjust_music(-1)
	s.adjust_music(-1)
	h.check("从 55% 往左两格是 45%", s.music_label(), "45%")

	# 两头要**停住**，不能绕回去 —— 滑条绕圈是反直觉的
	s.music_volume = 1.0
	s.adjust_music(1)
	h.check("到顶就停", s.music_label(), "100%")
	s.music_volume = 0.0
	s.adjust_music(-1)
	h.check("到底也停", s.music_label(), "0%")

	s.sfx_volume = 0.5
	s.adjust_sfx(1)
	h.check("音效那条自己走", s.sfx_label(), "55%")
	h.check("没顺手把音乐带上", s.music_label(), "0%")

	# 存读往返
	s.music_volume = 0.35
	s.sfx_volume = 0.75
	h.check("存得进", s.save_settings(), true)
	var back := GameSettings.new()
	back.load_settings()
	h.check("音乐读得回", back.music_label(), "35%")
	h.check("音效读得回", back.sfx_label(), "75%")

	# 收尾：把文件恢复成默认。下面还有用例会读设置，
	# 留一个 35% 在那儿会影响它们。
	back.music_volume = GameSettings.DEFAULT_VOLUME
	back.sfx_volume = GameSettings.DEFAULT_VOLUME
	back.save_settings()


## 脚步和开门：在什么地上走、走的是不是门。
##
## 这一组盯的是**判断**本身（该响的响、不该响的不响），不是音量波形 ——
## 无头里播放器没进树，`play_sound` 会静默跳过，验不到「真出声了没有」。
## 所以脚步看「锚点有没有被推走」（推走就是触发过了），
## 开门看 `_play_door_sound` 的返回值。
static func test_footsteps_and_doors(h: TestHarness) -> void:
	# 木地板的三个场景填了 `footstep`，户外的没填
	h.check("委托屋是木地板", DataLoader.load_map(&"desk_shop").footstep != "", true)
	h.check("卧室是木地板", DataLoader.load_map(&"bedroom").footstep != "", true)
	h.check("夜里卧室也是", DataLoader.load_map(&"bedroom_night").footstep != "", true)
	h.check("集市不是（户外石板）", DataLoader.load_map(&"market").footstep, "")
	h.check("大地图不是", DataLoader.load_map(&"overworld").footstep, "")

	var main := h.new_main()
	main.enter_map(&"desk_shop", &"start")

	# 站着不动不响
	main._footstep_at = main.player.global_position
	main._update_footsteps()
	h.check("站着不动不响", main._footstep_at, main.player.global_position)

	# 走够一步就响：锚点被推到新位置，那就是「响过了」的证据
	main.player.global_position += Vector2(main.FOOTSTEP_DISTANCE + 1.0, 0.0)
	var arrived: Vector2 = main.player.global_position
	main._update_footsteps()
	h.check("走够一步就响", main._footstep_at, arrived)

	# 差一点点不响，而且锚点不该动
	main._footstep_at = main.player.global_position
	main.player.global_position += Vector2(main.FOOTSTEP_DISTANCE - 1.0, 0.0)
	main._update_footsteps()
	h.check("没走够不响", main._footstep_at, arrived)

	# 户外：同一条路走三倍远也不响
	main.enter_map(&"overworld", &"default")
	main._footstep_at = main.player.global_position
	var stood: Vector2 = main.player.global_position
	main.player.global_position += Vector2(main.FOOTSTEP_DISTANCE * 3.0, 0.0)
	main._update_footsteps()
	h.check("户外的地上不响", main._footstep_at, stood)

	# 进门音效：**目的地是一间屋子就响**，露天不响。判据只看目的地 ——
	# 「推门走进去」是单向动作，出门不算。
	#
	# **两条路都得走一遍。** 声音挂在 `travel_to()` 上，而玩家走门有两条：
	# 屋里按交互键（`interact()` → `_take_portal()`）和大地图上点地点
	# （`_travel_through_portal()`）。只在其中一条上验，就会漏掉
	# 「声音挂在玩家走不到的那个入口上」—— 2026-09-24 报的
	# 「进出卧室没音效」就是这么来的，当时声音只挂在后一条上。
	#
	# 验的是 `last_sound`（`play_sound` 一进来就记），
	# 因为无头下播放器没进树、真播不了。
	main.enter_map(&"desk_shop", &"start")
	h.check("委托屋是室内", main.current_map.indoor, true)

	# 路一：站在卧室门口按交互键。**这是玩家进卧室的方式。**
	var door: Rect2 = main.current_map.portals[0].rect
	main.player.global_position = door.get_center()
	main.last_sound = ""
	main.interact()
	h.check("站在卧室门口按交互，响的是开门声",
		main.last_sound, main.DOOR_SOUND)

	# 路二：大地图上点地点
	main.enter_map(&"overworld", &"default")
	main.last_sound = ""
	main.travel_to(&"desk_shop", &"from_overworld")
	h.check("大地图 → 委托屋（进屋，响）", main.last_sound, main.DOOR_SOUND)

	# 露天的两头都不响
	main.last_sound = ""
	main.travel_to(&"market", &"from_overworld")
	h.check("大地图 → 集市（露天，不响）", main.last_sound, "")
	main.enter_map(&"desk_shop", &"start")
	main.last_sound = ""
	main.travel_to(&"overworld", &"default")
	h.check("委托屋 → 大地图（出到露天，不响）", main.last_sound, "")

	# 集市标了 `indoor: false`（露天市集）。它也是 `ROOM`，只是没有门可开。
	h.check("集市不是室内", DataLoader.load_map(&"market").indoor, false)
	h.check("卧室是室内", DataLoader.load_map(&"bedroom").indoor, true)

	main.queue_free()


## 地图配曲。三张有，卧室白天黑夜都没有 —— 那是定的，不是漏了。
static func test_map_music(h: TestHarness) -> void:
	var expected := {
		&"desk_shop": "res://audio/bgm/主角店内.mp3",
		&"overworld": "res://audio/bgm/大地图背景音乐.mp3",
		&"market": "res://audio/bgm/集市音乐.wav",
	}
	for mid: StringName in expected:
		var def := DataLoader.load_map(mid)
		h.check("%s 配了曲" % mid, def.music, expected[mid])
		# 配了就得真在。文件不在的话游戏里是「安静」，看画面看不出来。
		h.check("%s 的曲子文件找得到" % mid,
			ResourceLoader.exists(def.music), true)

	h.check("白天卧室没有音乐", DataLoader.load_map(&"bedroom").music, "")
	h.check("夜里卧室也没有音乐", DataLoader.load_map(&"bedroom_night").music, "")


## 切场景时的换曲。走的是 `main._play_map_music`。
static func test_playback(h: TestHarness) -> void:
	var main := h.new_main()

	# 播放器各挂各的总线 —— 「区分音频类型」这件事的落地
	h.check("音乐播放器挂在音乐总线",
		String(main.bgm.bus), String(AudioBuses.MUSIC))
	h.check("音效播放器挂在音效总线",
		String(main.sfx.bus), String(AudioBuses.SFX))

	main.enter_map(&"desk_shop", &"start")
	h.check("进屋就配上曲子", main.current_music(), "res://audio/bgm/主角店内.mp3")

	# 同一首来回走，stream 不该被换掉（换了就是从头发声）
	var first: AudioStream = main.bgm.stream
	main.enter_map(&"desk_shop", &"start")
	h.check("同一首不换 stream", main.bgm.stream == first, true)

	# 卧室没有音乐：进去要停
	main.enter_map(&"bedroom", &"from_desk")
	h.check("进卧室把曲子停了", main.current_music(), "")
	h.check("stream 也卸了", main.bgm.stream, null)

	# 出来又配上
	main.enter_map(&"desk_shop", &"start")
	h.check("回屋又配上", main.current_music(), "res://audio/bgm/主角店内.mp3")

	# 夜里那张同样没有音乐
	main.enter_map(&"bedroom_night", &"from_desk")
	h.check("夜版卧室也没有音乐", main.current_music(), "")

	# **标题放它自己的曲子**，不是上一个场景的。
	# `boot()` 那会儿起始场景其实已经加载好了，不换一手的话，
	# 玩家还没进屋就听着屋里的曲子。
	main.enter_map(&"desk_shop", &"start")
	h.check("先确认屋里有曲子", main.current_music(), "res://audio/bgm/主角店内.mp3")
	main.show_title()
	h.check("标题换成标题曲", main.current_music(), main.TITLE_MUSIC)
	h.check("标题曲真挂上了", main.bgm.stream != null, true)

	# 反复回标题（暂停菜单那儿的「返回主菜单」走这条）不该把曲子从头掐一遍
	var title_track: AudioStream = main.bgm.stream
	main.show_title()
	h.check("标题曲不因为再回一次就重放", main.bgm.stream == title_track, true)

	# 从标题点新游戏：换上委托屋那首，标题曲被顶掉
	main.enter_map(&"desk_shop", &"start")
	h.check("从标题进屋换成屋里的曲子",
		main.current_music(), "res://audio/bgm/主角店内.mp3")

	# 标题曲那个文件必须真在 —— 不在的话 `play_music` 会当成「没有音乐」
	# 静默跳过，而**听不出区别**（本来就没声），所以只能靠这条守。
	#
	# 以前它是个静音占位 wav，这里还顺带验了后缀。2026-09-24 换成正式的
	# mp3 之后，**后缀那条断言就没意义了，删掉** —— 要守的是「文件在不在」，
	# 不是「它是什么格式」。按格式写断言的话，下次换个格式又要来改一遍。
	h.check("标题曲找得到", ResourceLoader.exists(main.TITLE_MUSIC), true)

	main.queue_free()


## 剧本里的 `music` 指令：什么时候起、什么时候停由剧本说了算。
##
## 开场就用它压着：黑屏念旁白那段要安静，等画面亮起来才起前奏
## （见 `ch1_opening` 的 `title` / `wake` 两个节点）。
static func test_music_step(h: TestHarness) -> void:
	var main := h.new_main()
	main.cutscene.instant = true

	main.enter_map(&"desk_shop", &"start")
	h.check("进场景先有曲子在放",
		main.current_music(), "res://audio/bgm/主角店内.mp3")

	# 停：`path` 留空就是停
	var stop: Array[StageStep] = [StageStep.from_dictionary(
		{"do": "music", "path": ""})]
	main.cutscene.run(stop)
	h.check("指令能把音乐停掉", main.current_music(), "")

	# 起
	var start: Array[StageStep] = [StageStep.from_dictionary(
		{"do": "music", "path": "res://audio/bgm/主角店内.mp3"})]
	main.cutscene.run(start)
	h.check("指令能把音乐起回来",
		main.current_music(), "res://audio/bgm/主角店内.mp3")

	# 换个场景之后照样能压住（剧本是自己控制时机的，不看地图字段）
	main.enter_map(&"market", &"from_overworld")
	h.check("集市有它自己的曲子",
		main.current_music(), "res://audio/bgm/集市音乐.wav")
	main.cutscene.run(stop)
	h.check("在集市也能压住", main.current_music(), "")

	main.queue_free()


## 过渡到第二章：**黑衣人消失那一段要把曲子停掉**。
##
## 那一段是纯黑闪烁（`bg_blink` 走六下），配着集市曲子出戏。
## 停掉之后不用在剧本末尾补一条恢复 —— `goto` 换场景时按新场景的 `music`
## 字段自己就起了。
static func test_meet_b_stops_music(h: TestHarness) -> void:
	# 剧本上：`pendant` 那一步在收掉黑衣人**之前**停一次音乐
	var event := DataLoader.load_event(&"meet_b")
	h.check("事件在", event != null, true)
	if event == null:
		return
	var node := event.node(&"pendant")
	h.check("那一步在", node != null, true)
	if node == null:
		return

	var stop_at := -1
	var remove_at := -1
	for i: int in node.stage.size():
		var step: StageStep = node.stage[i]
		# **空路径才是「停」**，写别的路径是换曲
		if step.kind == &"music" and step.text("path") == "":
			stop_at = i
		elif step.kind == &"npc_remove":
			remove_at = i
	h.check("有一条停音乐的指令", stop_at >= 0, true)
	h.check("它排在黑衣人消失之前",
		stop_at >= 0 and remove_at >= 0 and stop_at < remove_at, true)

	# 跑起来：停之后换场景，委托屋的曲子自己起回来
	var main := h.new_main()
	main.cutscene.instant = true
	main.enter_map(&"market_night", &"from_overworld")
	h.check("集市原本有曲子",
		main.current_music(), "res://audio/bgm/集市音乐.wav")

	main.start_story(&"meet_b")
	h.pick(main, &"go")
	# pendant 那步改道了：黑屏后进死巷（第二章开场），配大地图的曲子
	h.check("落到死巷配上了它的曲子",
		main.current_music(), "res://audio/bgm/reclamation.mp3")

	# 流水上的痕迹：那一次「停」确实排在「收人」前面
	var seen: Array = main.cutscene.history()
	h.check("停音乐排在收人之前",
		seen.find("music") >= 0 and seen.find("music") < seen.find("npc_remove"),
		true)

	main.queue_free()
