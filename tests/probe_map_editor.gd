## 探针：地图编辑器主界面、物件检查器与画布工具能否构造（无头跑）。
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
const MapObjectTests := preload("res://tests/test_map_objects.gd")
const TestHarness := preload("res://tests/test_harness.gd")


func _initialize() -> void:
	var dock: Control = Dock.new()
	dock.size = Vector2(1280, 640)
	get_root().add_child(dock)
	await process_frame
	await process_frame

	print("① 面板起来了。地图数：%d" % Model.list_maps().size())
	print("   当前载入：%s" % dock.model.map_id)
	print("   三栏宽度：物件 %.0f / 画布 %.0f / 检查器 %.0f；画布高度 %.0f" % [
		dock._body_split.get_child(0).size.x,
		dock.canvas.size.x,
		dock._panel_scroll.size.x,
		dock.canvas.size.y])
	assert(dock.canvas.size.x > dock.canvas.custom_minimum_size.x)
	assert(dock.canvas.size.y > dock.canvas.custom_minimum_size.y)

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

	# 五种工具都切一遍
	for tool in [Canvas.Tool.SELECT, Canvas.Tool.WALL, Canvas.Tool.PORTAL,
			Canvas.Tool.BASELINE, Canvas.Tool.COLLISION]:
		dock._on_tool(tool)
		await process_frame
	assert(dock._object_list != null)
	assert(dock._actor_panel != null)
	assert(dock._asset_list != null and dock._asset_list.item_count > 0)
	dock._asset_filter.text = "gatehouse_desk"
	dock._refresh_assets()
	assert(dock._asset_list.item_count == 1)
	assert(str(dock._asset_list.get_item_metadata(0)) == "res://art/props/gatehouse_desk.png")
	dock._asset_filter.text = ""
	dock._refresh_assets()
	print("③ 五种工具切换正常；物件列表与检查器已构造")

	dock._on_tool(Canvas.Tool.SELECT)
	var before_drop: int = dock.model.count(Model.Kind.ACTOR)
	var asset_path := "res://art/props/gatehouse_desk.png"
	var drop_data := {"type": "if_map_asset", "path": asset_path}
	var drop_game_position := Vector2(120, 80)
	var drop_screen_position: Vector2 = dock.canvas.to_screen(drop_game_position)
	assert(dock.canvas._can_drop_data(drop_screen_position, drop_data))
	var outside_map_position: Vector2 = dock.canvas.to_screen(Vector2(-1, drop_game_position.y))
	assert(not dock.canvas._can_drop_data(outside_map_position, drop_data))
	dock._on_tool(Canvas.Tool.COLLISION)
	assert(not dock.canvas._can_drop_data(drop_screen_position, drop_data))
	dock._on_tool(Canvas.Tool.SELECT)
	dock.canvas._drop_data(drop_screen_position, drop_data)
	assert(dock.model.count(Model.Kind.ACTOR) == before_drop + 1)
	assert(str(dock.model.actor_field(before_drop, "sprite")) == asset_path)
	assert(dock.canvas.selected_actors().has(before_drop))
	var matching_size := Vector2.ZERO
	for actor_index in before_drop:
		if str(dock.model.actor_field(actor_index, "sprite", "")) == asset_path:
			matching_size = dock.model.rect_of(Model.Kind.ACTOR, actor_index).size
			break
	assert(matching_size.x > 0.0 and matching_size.y > 0.0)
	var dropped_rect: Rect2 = dock.model.rect_of(Model.Kind.ACTOR, before_drop)
	assert(dropped_rect.size == matching_size)
	assert(absf(dropped_rect.get_center().x - drop_game_position.x) <= 1.0)
	assert(absf(dropped_rect.get_center().y - drop_game_position.y) <= 1.0)
	assert(dock.model.undo())
	var no_selection: Array[int] = []
	dock.canvas.select_actors(no_selection)
	dock._refresh_selection()
	var fallback_asset_path := "res://art/props/desk.png"
	var fallback_drop_data := {"type": "if_map_asset", "path": fallback_asset_path}
	assert(dock.canvas._can_drop_data(drop_screen_position, fallback_drop_data))
	dock.canvas._drop_data(drop_screen_position, fallback_drop_data)
	assert(dock.model.count(Model.Kind.ACTOR) == before_drop + 1)
	assert(str(dock.model.actor_field(before_drop, "sprite")) == fallback_asset_path)
	var fallback_rect: Rect2 = dock.model.rect_of(Model.Kind.ACTOR, before_drop)
	var fallback_size: Vector2 = (load(fallback_asset_path) as Texture2D).get_size() / 12.0
	assert(absf(fallback_rect.size.x - fallback_size.x) <= 1.0)
	assert(absf(fallback_rect.size.y - fallback_size.y) <= 1.0)
	assert(dock.model.undo())
	dock.canvas.select_actors(no_selection)
	dock._refresh_selection()
	print("③ 素材筛选、画布拖放、尺寸与撤销通过")

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

	# 物件属性面板：选一件物件，看面板建起来没有、它的互动是哪种写法
	if dock.model.count(Model.Kind.ACTOR) > 0:
		dock.canvas.sel_kind = Model.Kind.ACTOR
		dock.canvas.sel_index = 0
		dock.model.use_local_geometry(0)
		dock._refresh_selection()
		await process_frame
		assert(dock.model.actor_field(0, "collision", null) is Array)
		assert(dock.model.actor_field(0, "reach_local", null) is Array)
		print("⑨ 物件 #0「%s」：互动写法=%s，对话行 %d，属性面板子项 %d（可见 %s）" % [
			dock.model.label_of(Model.Kind.ACTOR, 0),
			dock.model.actor_form(0),
			dock.model.actor_talk(0).size(),
			dock._actor_panel.get_child_count(),
			str(dock._actor_panel.visible)])

	# 前景层：能不能选中、面板是不是前景层那块、实际范围算得出来吗
	if dock.model.count(Model.Kind.OVERLAY) > 0:
		dock.canvas.sel_kind = Model.Kind.OVERLAY
		dock.canvas.sel_index = 0
		dock._refresh_selection()
		await process_frame
		var band: Rect2 = dock.canvas.overlay_game_rect()
		print("⑩ 前景层：路径 %s" % dock.model.overlay_path())
		print("   实际范围（游戏单位）%s；面板可见 %s；焦点在滚动区里 %s" % [
			band, str(dock._panel_scroll.visible), str(dock._actor_panel.get_parent() is ScrollContainer)])

	# 测试工具：鼠标处的脚底框
	dock.canvas.show_foot = true
	dock.canvas._mouse_inside = true
	dock.canvas._mouse_game = dock.canvas.map_size * 0.5
	await process_frame
	print("⑪ 脚底框：落点 %s → 框 %s，判据「%s」" % [
		dock.canvas._mouse_game,
		dock.canvas.foot_rect_at(dock.canvas._mouse_game),
		"站得住" if dock.canvas.foot_is_free(dock.canvas._mouse_game) else "站不住"])

	dock.model.data = {"id": "layout_probe", "size": [400, 300], "walls": [], "actors": [
		{"id": "first", "rect": [20, 40, 20, 20], "decor": true},
		{"id": "middle", "rect": [110, 80, 40, 30], "decor": true},
		{"id": "last", "rect": [200, 160, 60, 40], "decor": true}]}
	dock.model.reset_history()
	var one_actor: Array[int] = [0]
	var two_actors: Array[int] = [0, 1]
	var three_actors: Array[int] = [0, 1, 2]
	dock.canvas.select_actors(one_actor)
	dock._refresh_layout_menu()
	assert(dock._layout_popup.is_item_disabled(dock._layout_popup.get_item_index(Dock.LayoutAction.ALIGN_LEFT)))
	dock.canvas.select_actors(two_actors)
	dock._refresh_layout_menu()
	assert(not dock._layout_popup.is_item_disabled(dock._layout_popup.get_item_index(Dock.LayoutAction.ALIGN_LEFT)))
	assert(dock._layout_popup.is_item_disabled(dock._layout_popup.get_item_index(Dock.LayoutAction.DISTRIBUTE_HORIZONTAL)))
	dock.canvas.select_actors(three_actors)
	dock._refresh_layout_menu()
	assert(not dock._layout_popup.is_item_disabled(dock._layout_popup.get_item_index(Dock.LayoutAction.DISTRIBUTE_HORIZONTAL)))
	dock._on_layout_action(Dock.LayoutAction.ALIGN_LEFT)
	assert(dock.model.rect_of(Model.Kind.ACTOR, 1).position.x == 20)
	assert(dock.model.rect_of(Model.Kind.ACTOR, 2).position.x == 20)
	dock._object_command("undo")
	assert(dock.model.rect_of(Model.Kind.ACTOR, 1).position.x == 110)
	assert(dock.model.rect_of(Model.Kind.ACTOR, 2).position.x == 200)
	dock._object_command("redo")
	assert(dock.model.rect_of(Model.Kind.ACTOR, 1).position.x == 20)
	dock._object_command("undo")
	dock.canvas.select_actors(three_actors)
	dock._on_layout_action(Dock.LayoutAction.DISTRIBUTE_HORIZONTAL)
	assert(dock.model.rect_of(Model.Kind.ACTOR, 1).position.x == 100)
	dock._object_command("undo")
	assert(dock.model.rect_of(Model.Kind.ACTOR, 1).position.x == 110)
	print("⑫ 对齐/分布菜单门槛、排布操作与整步撤销重做通过")
	assert(dock._group_button != null and dock._ungroup_button != null)
	dock.canvas.select_actors(two_actors)
	dock._refresh_selection()
	assert(not dock._group_button.disabled)
	dock._object_command("group")
	assert(dock.model.group_name_for_actor(0) == "组 1")
	assert(dock._group_button.disabled)
	dock.canvas.select_actors(one_actor)
	assert(dock.canvas.selected_actors() == two_actors)
	dock._refresh_selection()
	assert(not dock._ungroup_button.disabled)
	dock._object_command("copy")
	dock._object_command("paste")
	assert(dock.model.group_name_for_actor(3) == "组 1 副本")
	dock._object_command("undo")
	dock.canvas.select_actors(one_actor)
	dock._object_command("ungroup")
	assert(dock.model.group_name_for_actor(0).is_empty())
	dock._object_command("undo")
	assert(dock.model.group_name_for_actor(0) == "组 1")
	print("⑬ 编组按钮、整组选取/复制、解组及撤销重做通过")
	var backup_harness = TestHarness.new()
	backup_harness.setup(root)
	MapObjectTests.test_copy_and_history(backup_harness)
	MapObjectTests.test_canvas(backup_harness)
	MapObjectTests.test_groups(backup_harness)
	MapObjectTests.test_backups(backup_harness)
	assert(backup_harness.failed == 0, "\n".join(backup_harness.failures))
	print("⑭ 编组模型与自动快照、备份恢复、撤销重做通过（%d 项断言）" % backup_harness.passed)

	print("=== 地图编辑器探针通过 ===")
	quit(0)
