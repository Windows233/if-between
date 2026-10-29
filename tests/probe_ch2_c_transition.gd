## C同行转场、跨重试第三次失败救场和直接入馆的真实流程专项入口。
extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var h := TestHarness.new()
	h.setup(root)
	await preload("res://tests/test_chase_motion.gd").run(h)
	print("C transition checks: ",h.passed," passed / ",h.failed," failed ",h.failures)
	quit(0 if h.failed == 0 else 1)
