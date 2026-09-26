## 探针：地图编辑器的**界面层能不能被构造出来**（无头跑）。
##
## 插件本体只能在编辑器里点，但面板与画布都是普通 `Control` ——
## 无头也能 new 出来、载入地图、跑模型操作。它抓的是「一打开就报错」
## 这一类问题（空引用、属性名写错、构造顺序不对）。
##
##   <godot> --headless --path <项目> --script res://tests/probe_map_editor.gd
##
## 不是自动测试的一部分（`run_tests.gd` 不调它）—— 画得对不对得用眼睛，
## 那个在编辑器和游戏里看。
extends SceneTree

const Dock := preload("res://addons/if_map_editor/map_edit_dock.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const Model := preload("res://addons/if_map_editor/map_edit_model.gd")


func _initialize() -> void:
	var dock: Control = Dock.new()
	dock.size = Vector2(1280, 640)
	get_root().add_child(dock)
	await process_frame
	await process_frame

	print("① 面板起来了。地图数：%d" % Model.list_maps().size())
	print("   当前载入：%s" % dock.model.map_id)

	# 载一张具体的图（门卫室）
	var ids := Model.list_maps()
	var pick := ids.find("gatehouse")
	dock._map_picker.select(pick if pick >= 0 else 0)
	dock._load_selected()
	dock.canvas.size = Vector2(1280, 420)
	dock.canvas.fit_to_view()
	await process_frame
	print("② 载入 %s：尺寸 %s" % [dock.model.map_id, dock.model.map_size()])
	print("   墙 %d / 传送区 %d / 物件 %d" % [
		dock.model.count(Model.Kind.WALL),
		dock.model.count(Model.Kind.PORTAL),
		dock.model.count(Model.Kind.ACTOR)])

	# 三个工具都切一遍
	for tool in [Canvas.Tool.SELECT, Canvas.Tool.WALL, Canvas.Tool.PORTAL, Canvas.Tool.BASELINE]:
		dock._on_tool(tool)
		await process_frame
	print("③ 四个工具切换正常")

	# 可走格（调的是游戏同一份 WalkGrid）
	dock.canvas.set_walk_visible(true)
	await process_frame
	print("④ 可走格纹理：%s" % ("有" if dock.canvas._walk_texture != null else "没有"))

	# 模型增删改一圈（不保存）
	var i: int = dock.model.add_rect(Model.Kind.WALL, Rect2(1, 2, 30, 40))
	dock.model.set_rect(Model.Kind.WALL, i, Rect2(3, 4, 31, 41))
	var back: Rect2 = dock.model.rect_of(Model.Kind.WALL, i)
	dock.model.remove_at(Model.Kind.WALL, i)
	print("⑤ 模型增删改：临时条目 %s，dirty=%s" % [back, dock.model.dirty])

	# 选中一件遮挡物，走一遍「拉基线」的数值路径
	for a in dock.model.count(Model.Kind.ACTOR):
		if dock.model.is_cover_actor(a):
			dock.canvas.sel_kind = Model.Kind.ACTOR
			dock.canvas.sel_index = a
			dock._refresh_selection()
			print("⑥ 选中遮挡物 #%d：基线 %.0f（可手动=%s）" % [
				a, dock.model.actor_cover_y(a), dock._base_row.visible])
			break

	# 前景层：卧室那种「下围墙挡住人但没有物件」的图 —— 验它算得出范围
	var bed := ids.find("bedroom")
	if bed >= 0:
		dock._map_picker.select(bed)
		dock._load_selected()
		dock.canvas.size = Vector2(1280, 420)
		dock.canvas.fit_to_view()
		await process_frame
		var covers: int = 0
		for a in dock.model.count(Model.Kind.ACTOR):
			if dock.model.is_cover_actor(a):
				covers += 1
		print("⑦ 卧室：遮挡物件 %d 个，前景层 %s" % [
			covers, "有" if dock.model.overlay_path() != "" else "无"])
		print("   前景层实际范围（贴图像素）：%s" % dock.canvas._overlay_used)

	# 出生点：列出来 + 选中一个（验画布那套拖动/数值框对它也管用）
	if dock.model.count(Model.Kind.SPAWN) > 0:
		dock.canvas.sel_kind = Model.Kind.SPAWN
		dock.canvas.sel_index = 0
		dock._refresh_selection()
		print("⑧ 出生点 %d 个：%s；选中「%s」在 %s（宽高框可编辑=%s）" % [
			dock.model.count(Model.Kind.SPAWN),
			", ".join(dock.model.spawn_names()),
			dock.model.label_of(Model.Kind.SPAWN, 0),
			dock.model.spawn_point(0),
			str(dock._spins[2].editable)])

	print("=== 地图编辑器探针通过 ===")
	quit(0)
