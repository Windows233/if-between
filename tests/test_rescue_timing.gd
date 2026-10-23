## 救援判定与独立面板的回归测试，也可用 --script 单独运行。
## 覆盖双向边界、练习、累计失误、输入门禁和取消重开，不依赖剧情集成。
## 主测试入口可直接调用 static run(h)，本文件不修改或注册公共 runner。
class_name TestRescueTiming
extends SceneTree


func _initialize() -> void:
	call_deferred("_run_standalone")


func _run_standalone() -> void:
	var harness: TestHarness = TestHarness.new()
	harness.setup(root)
	run(harness)
	quit(0 if harness.report() else 1)


static func run(h: TestHarness) -> void:
	h.section("救援判定与面板")
	var tree := h.root.get_tree()
	var was_paused: bool = tree.paused
	tree.paused = false
	_test_practice(h)
	_test_motion_and_windows(h)
	_test_mistakes_and_success(h)
	_test_panel_lifecycle(h)
	_test_panel_input(h)
	_test_panel_pause(h)
	_test_reentrant_close(h)
	tree.paused = was_paused


static func _running() -> RescueTiming:
	var model: RescueTiming = RescueTiming.new()
	model.reset()
	model.submit()
	model.submit()
	return model


static func _test_practice(h: TestHarness) -> void:
	for phase: float in [0.0, 0.25, 0.5]:
		var model: RescueTiming = RescueTiming.new()
		h.check("初始关闭", model.state, RescueTiming.State.CLOSED)
		model.reset()
		model.phase = phase
		var verdict: RescueTiming.Verdict = model.submit()
		h.check("练习产生实际反馈", verdict != RescueTiming.Verdict.NONE, true)
		h.check("练习只做一次", model.state, RescueTiming.State.PRACTICE_FEEDBACK)
		h.check("练习不算完成一根线", model.line_index, 0)
		h.check("练习不计失误", model.mistakes, 0)
		model.advance(1000.0)
		h.check("练习反馈等待确认", model.phase, phase)
		h.check("确认不是再次判定", model.submit(), RescueTiming.Verdict.NONE)
		h.check("确认后正式开始", model.state, RescueTiming.State.RUNNING)
		h.check("正式从起点开始", model.phase, 0.0)
		model.submit()
		h.check("第二次偏早开始计错", model.mistakes, 1)


static func _test_motion_and_windows(h: TestHarness) -> void:
	var expected_periods: Array[float] = [3.0, 2.6, 2.4]
	var expected_windows: Array[float] = [0.35, 0.30, 0.25]
	for line: int in RescueTiming.LINE_COUNT:
		var model: RescueTiming = _running()
		model.line_index = line
		h.check("往返周期 %d" % line, model.round_trip_seconds(), expected_periods[line])
		h.check("判定宽度 %d" % line, model.window_ratio(), expected_windows[line])
		model.advance(expected_periods[line] * 0.25)
		h.check("去程中点", model.marker_position(), 0.5)
		model.advance(expected_periods[line] * 0.25)
		h.check("右端折返", model.marker_position(), 1.0)
		model.advance(expected_periods[line] * 0.25)
		h.check("返程中点", model.marker_position(), 0.5)
		model.advance(expected_periods[line] * 0.25)
		h.check("完整往返回起点", model.marker_position(), 0.0)
		model.advance(expected_periods[line] * 1000.25)
		h.check("多圈大步长仍连续", is_equal_approx(model.marker_position(), 0.5), true)
		h.check("不按不会扣错", model.mistakes, 0)
		h.check("不按不会自动成功", model.line_index, line)
		var previous_phase: float = model.phase
		for invalid_delta: float in [-1.0, 0.0, INF, NAN]:
			model.advance(invalid_delta)
			h.check("忽略无效时间", model.phase, previous_phase)
		for boundary: float in [model.window_start(), model.window_end()]:
			for returning: bool in [false, true]:
				var edge: RescueTiming = _running()
				edge.line_index = line
				edge.phase = 1.0 - boundary * 0.5 if returning else boundary * 0.5
				h.check("双向窗口边界有效", edge.submit(), RescueTiming.Verdict.HIT)
		for returning: bool in [false, true]:
			for above: bool in [false, true]:
				var outside: RescueTiming = _running()
				outside.line_index = line
				var position: float = model.window_end() + 0.0001 if above else model.window_start() - 0.0001
				outside.phase = 1.0 - position * 0.5 if returning else position * 0.5
				var expected: RescueTiming.Verdict = RescueTiming.Verdict.EARLY if returning == above else RescueTiming.Verdict.LATE
				h.check("双向窗口外区分早晚", outside.submit(), expected)


static func _test_mistakes_and_success(h: TestHarness) -> void:
	var failure: RescueTiming = _running()
	for count: int in RescueTiming.ERROR_LIMIT:
		failure.phase = 0.0
		h.check("起点偏早", failure.submit(), RescueTiming.Verdict.EARLY)
		h.check("累计失误", failure.mistakes, count + 1)
		var frozen_phase: float = failure.phase
		failure.advance(10.0)
		h.check("错误或终局冻结", failure.phase, frozen_phase)
		if count < RescueTiming.ERROR_LIMIT - 1:
			h.check("等待错误确认", failure.state, RescueTiming.State.MISTAKE)
			h.check("确认不再扣错", failure.submit(), RescueTiming.Verdict.NONE)
			h.check("同根线重试", failure.line_index, 0)
		else:
			h.check("三错进入终局", failure.state, RescueTiming.State.FAILED)
	h.check("第三错后保持失败", failure.state, RescueTiming.State.FAILED)
	for repeat: int in 5:
		h.check("失败后忽略提交", failure.submit(), RescueTiming.Verdict.NONE)
	h.check("失败不再累计", failure.mistakes, RescueTiming.ERROR_LIMIT)
	var success: RescueTiming = _running()
	for line: int in RescueTiming.LINE_COUNT:
		if line < 2:
			success.submit()
			success.submit()
		success.phase = 0.25
		h.check("依次解线", success.submit(), RescueTiming.Verdict.HIT)
		h.check("只完成当前一根", success.line_index, line + 1)
		h.check("新线从起点开始", success.phase, 0.0)
	h.check("跨线累计两次失误仍可成功", success.mistakes, 2)
	h.check("三根线完成", success.state, RescueTiming.State.SUCCEEDED)
	success.advance(10.0)
	h.check("成功后忽略提交", success.submit(), RescueTiming.Verdict.NONE)
	success.close()
	h.check("关闭后的提交无效", success.submit(), RescueTiming.Verdict.NONE)
	success.reset()
	h.check("重开清空进度", success.line_index, 0)
	h.check("重开清空失误", success.mistakes, 0)


static func _new_panel(h: TestHarness) -> RescuePanel:
	var panel: RescuePanel = RescuePanel.new()
	panel.allow_background_process = true
	h.root.add_child(panel)
	panel.setup()
	panel.open()
	return panel


static func _test_panel_lifecycle(h: TestHarness) -> void:
	var panel: RescuePanel = _new_panel(h)
	var completed_values: Array[bool] = []
	var cancellations: Array[bool] = []
	var feedback_values: Array[StringName] = []
	panel.completed.connect(func(success: bool) -> void: completed_values.append(success))
	panel.cancelled.connect(func() -> void: cancellations.append(true))
	panel.feedback.connect(func(kind: StringName) -> void: feedback_values.append(kind))
	panel.setup()
	h.check("重复 setup 不重复造根节点", panel.get_child_count(), 1)
	h.check("层号低于暂停和选项", panel.layer, 12)
	panel.submit()
	panel.submit()
	for line: int in RescueTiming.LINE_COUNT:
		panel.model.phase = 0.25
		panel.submit()
	h.check("成功只完成一次", completed_values, [true])
	h.check("成功后自动关闭", panel.is_open(), false)
	h.check("成功结果可读", panel.success_result, true)
	h.check("完成有音效事件", feedback_values.back(), &"complete")
	panel.close()
	panel.submit()
	h.check("关闭保留成功结果", panel.success_result, true)
	h.check("成功后 close 不再取消", cancellations.size(), 0)
	panel.open()
	h.check("重开重置结果", panel.success_result, false)
	panel.close()
	panel.close()
	h.check("取消只发一次", cancellations.size(), 1)
	h.check("取消不伪造完成", completed_values, [true])
	panel.open()
	panel.submit()
	panel.submit()
	for count: int in RescueTiming.ERROR_LIMIT:
		panel.submit()
		if count < RescueTiming.ERROR_LIMIT - 1:
			panel.submit()
	panel.submit()
	h.check("三错只发一次失败", completed_values, [true, false])
	h.check("失败关闭且结果为 false", panel.is_open() or panel.success_result, false)
	panel.open()
	panel.free()
	h.check("退出树结束等待", cancellations.size(), 2)


static func _key(keycode: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	return event


static func _test_panel_input(h: TestHarness) -> void:
	var panel: RescuePanel = _new_panel(h)
	h.check("空格路由消费", panel.handle_input(_key(KEY_SPACE)), true)
	h.check("重复按下被挡住", panel.handle_input(_key(KEY_SPACE)), true)
	panel.handle_input(_key(KEY_SPACE, true, true))
	h.check("按住不会确认练习", panel.model.state, RescueTiming.State.PRACTICE_FEEDBACK)
	panel.handle_input(_key(KEY_SPACE, false))
	panel.handle_input(_key(KEY_SPACE))
	h.check("松开再按才开始", panel.model.state, RescueTiming.State.RUNNING)
	panel.handle_input(_key(KEY_SPACE, true, true))
	h.check("重复键不会误判新线", panel.model.mistakes, 0)
	panel.handle_input(_key(KEY_ENTER))
	h.check("确认键走同一判定", panel.model.mistakes, 1)
	panel.handle_input(_key(KEY_ENTER))
	h.check("按住不会解除错误反馈", panel.model.state, RescueTiming.State.MISTAKE)
	panel.handle_input(_key(KEY_ENTER, false))
	panel.handle_input(_key(KEY_ENTER))
	h.check("再确认恢复", panel.model.state, RescueTiming.State.RUNNING)
	var button: Button = panel.get_node("RescueRoot/Submit") as Button
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = button.get_global_rect().get_center()
	panel.model.phase = 0.25
	h.check("鼠标唯一按钮路由", panel.handle_input(click), true)
	h.check("鼠标命中解开一根", panel.model.line_index, 1)
	panel.handle_input(click)
	h.check("鼠标按住不会重判", panel.model.mistakes, 1)
	click.pressed = false
	panel.handle_input(click)
	click.pressed = true
	panel.model.phase = 0.25
	button.gui_input.emit(click)
	h.check("GUI 按钮共用 submit", panel.model.line_index, 2)
	h.check("ESC 留给暂停入口", panel.handle_input(_key(KEY_ESCAPE)), false)
	panel.close()
	h.check("关闭后不拦截剧情输入", panel.handle_input(_key(KEY_SPACE)), false)
	panel.free()


static func _test_panel_pause(h: TestHarness) -> void:
	var panel: RescuePanel = _new_panel(h)
	h.check("面板为 PAUSABLE", panel.process_mode, Node.PROCESS_MODE_PAUSABLE)
	panel.set_focus_paused(true)
	panel._process(2.0)
	panel.submit()
	h.check("失焦时间冻结", panel.model.phase, 0.0)
	h.check("失焦提交无效", panel.model.state, RescueTiming.State.PRACTICE)
	panel.set_focus_paused(false)
	panel._process(0.75)
	h.check("恢复后只走新增时间", panel.model.marker_position(), 0.5)
	panel.allow_background_process = false
	panel._on_focus_exited()
	panel._process(1.0)
	h.check("窗口失焦同样冻结", panel.model.marker_position(), 0.5)
	panel.allow_background_process = true
	panel._process(0.75)
	h.check("渲染 probe 可后台推进", panel.model.marker_position(), 1.0)
	var tree: SceneTree = h.root.get_tree()
	var was_paused: bool = tree.paused
	tree.paused = true
	panel._process(0.75)
	panel.submit()
	h.check("后台开关也不绕过暂停", panel.model.marker_position(), 1.0)
	h.check("暂停提交无效", panel.model.state, RescueTiming.State.PRACTICE)
	tree.paused = was_paused
	panel.free()


static func _test_reentrant_close(h: TestHarness) -> void:
	var panel: RescuePanel = _new_panel(h)
	var completed_values: Array[bool] = []
	panel.completed.connect(func(success: bool) -> void: completed_values.append(success))
	panel.submit()
	panel.submit()
	panel.model.line_index = RescueTiming.LINE_COUNT - 1
	panel.model.phase = 0.25
	panel.feedback.connect(func(kind: StringName) -> void:
		if kind == &"complete":
			panel.close()
			panel.open()
	)
	panel.submit()
	h.check("回调内重开保持新练习", panel.model.state, RescueTiming.State.PRACTICE)
	h.check("旧完成回调不侵入新一轮", completed_values.is_empty(), true)
	panel.free()
