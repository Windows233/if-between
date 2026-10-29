extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var h := TestHarness.new()
	h.setup(root)
	await preload("res://tests/test_diary_followups.gd").run(h)
	if DisplayServer.get_name() != "headless":
		var main := h.new_main()
		main.enter_map(&"library", &"from_school_gate")
		main.dialogue.play(Dialogue.from_array([{"speaker":"猫", "text":"你终于来了。", "side":"right", "portrait":"res://art/portrait/library_cat_dialogue.png"}]))
		for i in 30: await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/screenshots/cat_dialogue_revision.png")
		main.dialogue.play(Dialogue.from_array([{"text":"白凝冰追来了，快逃回教学楼！\n到门口按E或空格。"}]))
		main.dialogue.advance()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/screenshots/c_escape_caption_revision.png")
		main.queue_free()
	print("Diary followups: ",h.passed," / ",h.failed," ",h.failures)
	quit(0 if h.failed == 0 else 1)
