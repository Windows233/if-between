## 测试入口。无头运行：
##
##   godot --headless --path <项目> --script res://tests/run_tests.gd
##
## 退出码 0 = 全通过，1 = 有失败。刻意不依赖 gdUnit4，
## 少一个依赖，任何人 clone 下来都能直接跑。
##
## 用例按主题分在 `test_*.gd` 里，这里只负责串起来。
## 断言、建主场景、把对话推到底这些公共工具在 `TestHarness`。
##
## **加新用例时，记得把函数加进对应组的 `run()`**，否则写了也不会跑 ——
## 这一点没有别的机制兜着。
extends SceneTree


func _initialize() -> void:
	# 首帧后根节点才入树；提前运行会令异步用例 get_tree() 为空而被跳过。
	_run_all.call_deferred()


func _run_all() -> void:
	print("=== IF：如果之间 测试 ===")

	var h := TestHarness.new()
	h.setup(root)

	h.section("规则引擎")
	TestRules.run(h)
	h.section("地图与场景")
	TestMap.run(h)
	TestWalkable.run(h)
	preload("res://tests/test_map_geometry_runtime.gd").run(h)
	preload("res://tests/test_map_visual_parts.gd").run(h)
	preload("res://tests/test_map_draw_layers.gd").run(h)
	h.section("对话与选项")
	TestDialogue.run(h)
	h.section("剧情事件")
	TestStory.run(h)
	h.section("演出指令与过场")
	TestCutscene.run(h)
	await preload("res://tests/test_ch2_integration.gd").run(h)
	preload("res://tests/test_personal_anchor.gd").run(h)
	preload("res://tests/test_rescue_timing.gd").run(h)
	await preload("res://tests/test_rescue_integration.gd").run(h)
	preload("res://tests/test_library_access.gd").run(h)
	await preload("res://tests/test_library_after.gd").run(h)
	await preload("res://tests/test_ch2_escape.gd").run(h)
	preload("res://tests/test_c_sprites.gd").run(h)
	h.section("背包")
	TestInventory.run(h)
	h.section("结局与存档")
	TestEndingSave.run(h)
	h.section("结局图鉴")
	TestGallery.run(h)
	h.section("标题与菜单")
	TestMenus.run(h)
	h.section("表现层")
	TestPresentation.run(h)
	h.section("音频")
	TestAudio.run(h)
	call_deferred("_finish_with_triggers", h)


func _finish_with_triggers(h: TestHarness) -> void:
	# 救援用例需要已入树的根节点；只在延迟入口执行一次。
	await preload("res://tests/test_character_scale.gd").run(h)
	preload("res://tests/test_map_render_quality.gd").run(h)
	preload("res://tests/test_world_look.gd").run(h)
	preload("res://tests/test_rescue_timing.gd").run(h)
	await preload("res://tests/test_rescue_integration.gd").run(h)
	await preload("res://tests/test_map_triggers.gd").run(h)

	if h.report():
		quit(0)
		return
	quit(1)
