extends SceneTree

## 挂在导出包上跑，验证「包里的资源真的认得出来」。
##
## **为什么要有这个。** 2026-09-24：临时角色在编辑器里好好的，打包之后
## 一个都不出来。包里 `DirAccess.get_files_at()` 给出的是 `down1.png.import`，
## 不是 `down1.png` —— 资源其实全在（`load()` 全成功），是「靠目录列表发现资源」
## 的代码在包里认不出名字。查这个问题花了一整轮，所以留一道自检：
## 导出完当场跑，不用等策划玩到那一段。
##
## **手跑：**
##   godot --headless --main-pack <导出的 exe> --script tools/check_pack.gd
## （`tools/export_demo.py` 导出完会自动跑，不用记这条命令。）
##
## 退出码 0 全过，1 有不对的。脚本从**绝对路径**加载，所以 tools/ 不进包也没关系。

const NPC_DIR := "res://art/npc"

## 立绘目录。子目录（`protagonist/`）也一起查。
const PORTRAIT_DIR := "res://art/portrait"

## 地图数据目录。查每张图的 `background` / `overlay` 在不在、加载得出来吗。
const MAP_DIR := "res://data/maps"

## 临时角色按这个高度造（和剧本里写的差不多，只验「能不能造出来」）。
const PROBE_HEIGHT := 45.0
const PROBE_Z := 12

var _bad := 0


func _initialize() -> void:
	print("=== 包内自检 ===")
	_check_actors()
	_check_portraits()
	_check_map_pictures()
	print("=== %s ===" % ("通过" if _bad == 0 else "有 %d 项不对" % _bad))
	quit(1 if _bad > 0 else 0)


## 每一张立绘都要能 `load()` 出来。
##
## 立绘是按名字拼路径加载的（`DialogueLine.portrait_path()` → `art/portrait/<名字>.png`），
## 所以「文件在不在、加载得出来吗」就是全部要查的。**换了素材忘了删旧 `.import`
## 的时候，这里会红** —— 那种错在编辑器里看不出来（图还是老的），只有包里才现形。
func _check_portraits() -> void:
	var checked := 0
	var folders: Array[String] = [PORTRAIT_DIR]
	for sub: String in DirAccess.get_directories_at(PORTRAIT_DIR):
		folders.append("%s/%s" % [PORTRAIT_DIR, sub])
	for folder: String in folders:
		for raw: String in DirAccess.get_files_at(folder):
			var base := raw
			if base.ends_with(".import"):
				base = base.substr(0, base.length() - ".import".length())
			if not base.ends_with(".png"):
				continue
			checked += 1
			if load("%s/%s" % [folder, base]) == null:
				_fail("立绘加载不出来：%s/%s" % [folder, base])
	print("  ✓ 立绘 %d 张都能加载" % checked)


## 每一个临时角色都要能真的造出节点来。
##
## **只 `load()` 一张图不算数。** 角色是按目录造动画的，包的目录列表里
## 名字带不带 `.import` 决定成败 —— 走一遍 `_make_actor` 才是端到端。
func _check_actors() -> void:
	var dirs := DirAccess.get_directories_at(NPC_DIR)
	if dirs.is_empty():
		_fail("%s 下列不出任何角色目录" % NPC_DIR)
		return

	var script: GDScript = load("res://scenes/cutscene.gd")
	var cut: RefCounted = script.new()
	for who: String in dirs:
		var folder := "%s/%s" % [NPC_DIR, who]
		var node: Variant = cut.call("_make_actor", folder, PROBE_HEIGHT, PROBE_Z)
		if node == null:
			_fail("%s：造不出来（帧扫不到）" % folder)
		elif not (node is AnimatedSprite2D):
			_fail("%s：造出来的不是动画角色，是 %s" % [folder, node.get_class()])
		else:
			var sprite: AnimatedSprite2D = node
			print("  ✓ %-26s 动画 %s" % [folder, sprite.sprite_frames.get_animation_names()])
			sprite.free()


## 每张地图的背景图和**前景层图**都要能 `load()`。
##
## 加了前景遮挡层之后这条更值：扣图是单独一份文件，忘了放、或者换了图没删旧
## `.import`，**编辑器里看着都正常**（背景还在，只是没人挡在前面），
## 要到玩到那一幕才发现 —— 或者只在日志里留一行 `push_warning`。
func _check_map_pictures() -> void:
	var checked := 0
	var bad := 0
	for name: String in DirAccess.get_files_at(MAP_DIR):
		var base := name
		if base.ends_with(".import"):
			base = base.substr(0, base.length() - ".import".length())
		if not base.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(
				FileAccess.get_file_as_string("%s/%s" % [MAP_DIR, base]))
		if not (data is Dictionary):
			continue
		for key: String in ["background", "overlay"]:
			var path := str((data as Dictionary).get(key, ""))
			if path == "":
				continue
			checked += 1
			if load(path) == null:
				_fail("%s 的 %s 加载不出来：%s" % [base, key, path])
				bad += 1
	print("  ✓ 地图图 %d 张都能加载（不对的 %d 张）" % [checked, bad])


func _fail(what: String) -> void:
	_bad += 1
	print("  ✗ " + what)
