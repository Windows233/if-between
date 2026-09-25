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
	print("=== IF：如果之间 测试 ===")

	var h := TestHarness.new()
	h.setup(root)

	h.section("规则引擎")
	TestRules.run(h)
	h.section("地图与场景")
	TestMap.run(h)
	TestWalkable.run(h)
	h.section("对话与选项")
	TestDialogue.run(h)
	h.section("剧情事件")
	TestStory.run(h)
	h.section("演出指令与过场")
	TestCutscene.run(h)
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

	if h.report():
		quit(0)
		return
	quit(1)
