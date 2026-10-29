## 一次性探针：真窗口截起名面板、带昵称的台词、IF 面板和追逐提示，检查排版。
##
## 用法："<godot>" --path "<项目>" --script res://tests/probe_name_entry.gd
## 输出：user://name_*.png
extends SceneTree

var _main: Node2D
var _frame := 0
var _step := 0


func _initialize() -> void:
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.start_at_title = false
	main.debug_start_map = ""
	main.free_roam_after_ending = false
	root.add_child(main)
	_main = main
	main.boot()
	main.show_title()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 20 != 0:
		return false
	match _step:
		0:
			_main.title_screen.select_index(0)
			_main.title_screen.handle_key(KEY_ENTER)
		1:
			_shot("name_panel_empty")
			_main.name_entry.set_text("林小满一二三四五")
		2:
			_shot("name_panel_full")
			_main.name_entry.set_text("abc1")
			_main.name_entry.submit()
		3:
			_shot("name_panel_error")
			_main.skip_opening = true
			_main.name_entry.set_text("林小满一二三四五")
			_main.name_entry.submit()
		4:
			var line := DialogueLine.new()
			line.speaker = "白凝冰"
			line.side = DialogueLine.Side.RIGHT
			line.portrait = "c/neutral"
			line.text = PlayerName.apply("算了算了，遇见就是缘分。{name}，和我组队吧")
			var dialogue := Dialogue.new()
			dialogue.lines.append(line)
			_main.dialogue.play(dialogue, true)
		5, 6, 7:
			pass
		8:
			_shot("name_dialogue")
			_main.dialogue.close()
			_main.if_panel.open("", PlayerName.apply("来找{name}帮忙"), "猫不见了")
		9:
			_shot("name_if_panel")
			_main.if_panel.close()
			_main.chase_overlay.start_qte(&"q", true)
		10:
			_shot("chase_caption")
			quit()
	_step += 1
	return false


func _shot(name: String) -> void:
	var image := root.get_texture().get_image()
	var path := "user://%s.png" % name
	image.save_png(path)
	print("[shot] ", ProjectSettings.globalize_path(path))
