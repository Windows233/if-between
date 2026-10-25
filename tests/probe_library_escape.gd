## 真窗口自动试走：第二次闪避成功 → 两段追逐 → 窗边 → B → End7。
## 只在隔离 APPDATA 中运行；使用真实物理移动和实时演出，不替代人工手感验收。
extends SceneTree

var main: Variant
var elapsed := 0.0
var phase_seen := ""
var walked: Dictionary = {}
var failures: Array[String] = []
var shots: Dictionary = {}
var output := "user://library_escape_probe"
var _finishing := false
var _pulse := 0.0


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	_start.call_deferred()


func _start() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.start_at_title = false
	main.debug_start_map = ""
	root.add_child(main)
	main.boot()
	main.flags.set_value(&"ch2/personal/library_cat_hidden", true)
	main.flags.set_value(&"ch2/library/box_opened", true)
	for item: String in ["charm", "key", "crowbar", "night_tear", "cat_doll", "pendant"]:
		main.flags.set_value(StringName("item/" + item), 1)
	main.enter_map(&"library", &"from_school_gate", true)
	main.player.global_position = Vector2(233, 258)
	main.start_story(&"ch2_library_cat", &"dodge_success")


func _process(delta: float) -> bool:
	if main == null or _finishing:
		return false
	elapsed += delta
	_pulse += delta
	if _pulse > 5:
		_pulse = 0
		print("[实走进度] ", main.current_map.id, "/", main.story.current_node_id(), " at ", main.player.global_position,
			" move=", main.player.is_physics_processing(), " focus=", main.escape_session._focused)
	if elapsed > 100:
		failures.append("试走超时：%s/%s，脚点%s" % [main.current_map.id, main.story.current_node_id(), main.player.global_position])
		_finish()
		return false
	if main.dialogue.is_open():
		main.dialogue.advance()
		main.dialogue.advance()
	main.cutscene.consume_click()
	if main.choice_menu.is_open():
		failures.append("预期成功路线出现未处理选项：%s" % main.story.current_node_id())
		_finish()
		return false
	if main.escape_session.active:
		# 自动试走窗口位于屏幕外，显式模拟保持焦点；正式游戏仍遵守失焦冻结。
		main.escape_session._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		var phase: String = main.escape_session.phase
		if phase_seen != phase:
			phase_seen = phase
			if phase == "library" and WalkGrid.is_free(main.current_map, Vector2(233, 238)):
				failures.append("倒塌书架未产生实际碰撞")
			shots[phase] = true
			_snapshot(phase)
			var key := InputEventKey.new()
			key.physical_keycode = KEY_F
			key.pressed = true
			main._unhandled_input(key)
			var goal: Vector2 = main.current_map.spawn_point(&"from_school_gate" if phase == "library" else &"near_classroom")
			main.player.walk_path.assign(WalkGrid.path_to(main.current_map, main.player.global_position, goal))
			walked[phase] = {"from":main.player.global_position, "to":goal}
		main.escape_session.try_exit()
		return false
	if not main.story.is_active() and not main.fade.is_busy():
		if main.current_map.id == &"classroom":
			_walk_interact("window", &"classroom_window")
		elif main.current_map.id == &"market_night":
			_walk_interact("B", &"b_end_anchor")
	if main.flags.get_value(&"ch2/night_tear_absorbed") == true and not shots.has("end7"):
		shots["end7"] = true
		_snapshot("end7")
	if main.gallery != null and main.gallery.has(&"end7_rewritten"):
		_finish()
	return false


func _walk_interact(key: String, actor_id: StringName) -> void:
	var actor: MapDef.Actor
	for item: MapDef.Actor in main.current_map.actors:
		if item.id == actor_id:
			actor = item
	if actor == null:
		failures.append("缺少交互点：" + str(actor_id))
		_finish()
		return
	if not walked.has(key):
		var path := WalkGrid.path_to(main.current_map, main.player.global_position, actor.reach.get_center())
		if key == "window":
			# 从教室中间过道向上，再沿课桌上方通路到窗下；避免贴桌角走。
			path.assign([Vector2(main.current_map.spawn_point(&"from_gate").x, actor.reach.get_center().y), actor.reach.get_center()])
		main.player.walk_path.assign(path)
		walked[key] = true
	if main.player.walk_path.is_empty():
		main.player.facing = (actor.reach.get_center() - main.player.global_position).normalized()
		main.interact()
		if main.story.is_active():
			_snapshot(key)


func _snapshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	for key: String in ["library", "gate", "window", "B"]:
		if not walked.has(key):
			failures.append("未完成试走：" + key)
	var report := {"seconds":elapsed,"route":walked,"failures":failures,
		"coin_removed":main.flags.get_value(&"item/charm"),
		"tear_removed":main.flags.get_value(&"item/night_tear"),
		"doll_delivered":main.flags.get_value(&"item/cat_doll"),
		"final_state":main.flags.get_value(&"ch2/night_tear_absorbed")}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("[后段实走] ", JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
