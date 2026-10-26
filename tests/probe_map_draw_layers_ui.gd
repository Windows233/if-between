## 真实图书馆前景/血迹的GPU对照与新图层入口验收；只操作内存副本。
## godot --path . --script res://tests/probe_map_draw_layers_ui.gd（不能headless）
extends SceneTree

const TextureTests = preload("res://tests/test_map_texture_ui.gd")
const Canvas = preload("res://addons/if_map_editor/map_edit_canvas.gd")
var output := "user://map_draw_layers_probe"
var checks := 0
var failures := 0
var raw: Dictionary
var blood_index := -1
var editor_view: SubViewport
var game_view: SubViewport
var editor_canvas: Control
var runtime: MapView
var dock: Control


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600, 1100)
	root.content_scale_size = root.size
	root.title = "IF 图层上下关系 · 独立内存地图验收"
	raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/library.json"))
	for index: int in raw["actors"].size():
		if raw["actors"][index].get("id", "") == "library_blood_visual":
			blood_index = index
	_check("真实图书馆入口血迹存在", blood_index >= 0)
	if blood_index < 0:
		quit(1)
		return
	var dimensions := Vector2i(raw["size"][0], raw["size"][1])
	editor_view = _viewport(dimensions)
	game_view = _viewport(dimensions)
	editor_canvas = Canvas.new()
	editor_view.add_child(editor_canvas)
	editor_canvas.size = Vector2(dimensions)
	editor_canvas.model = preload("res://addons/if_map_editor/map_edit_model.gd").new()
	editor_canvas.model.data = raw.duplicate(true)
	editor_canvas.load_map(editor_canvas.model, raw["background"], raw["overlay"], Vector2(dimensions))
	editor_canvas.zoom = 1.0
	editor_canvas.pan = Vector2.ZERO
	editor_canvas.show_walls = false
	editor_canvas.show_portals = false
	editor_canvas.show_spawns = false
	runtime = MapView.new()
	runtime.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	game_view.add_child(runtime)
	var original_geometry := MapDef._actor_from(raw["actors"][blood_index])
	var baseline := await _render("")
	var front := await _render("front")
	_check("人物之上仍在台阶前景之下，编辑器与游戏一致", front.is_equal_approx(baseline))
	var above := await _render("above_overlay")
	_check("放到整张前景之上后血迹实际露出", not above.is_equal_approx(baseline))
	var current := MapDef._actor_from(raw["actors"][blood_index])
	_check("调图层不改变血迹几何与交互", current.rect == original_geometry.rect and current.reach == original_geometry.reach)
	dock = TextureTests.FixtureDock.new()
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.model.data = raw.duplicate(true)
	dock.model.map_id = "library_layers_memory_probe"
	dock.model.draft_dir = output.path_join("unused_drafts")
	dock.model.reset_history()
	dock.canvas.load_map(dock.model, raw["background"], raw["overlay"], Vector2(dimensions))
	await _frames()
	dock._set_initial_panel_layout()
	dock._select_draw_actor(blood_index)
	dock._asset_tabs.current_tab = dock._draw_layers_panel.get_index()
	dock.canvas.zoom = 4.0
	dock.canvas.pan = dock.canvas.size * 0.5 - Vector2(235, 315) * 4.0
	dock.canvas.queue_redraw()
	await _frames()
	_check("图层页中文可见", dock._asset_tabs.get_tab_title(dock._draw_layers_panel.get_index()) == "图层")
	var select_overlay := dock._actor_panel.find_child("SelectOverlay", true, false) as Button
	_check("所选物件能找到整张前景入口", select_overlay != null)
	var before: Dictionary = dock.model.data.duplicate(true)
	dock._on_layer(false, "show_overlay")
	_check("临时隐藏前景不写地图", before == dock.model.data)
	_check("图层页与原显示设置的前景开关同步", not dock._layer_checkboxes["show_overlay"].button_pressed)
	dock._on_layer(true, "show_overlay")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("library_layers_editor.png"))
	if select_overlay != null:
		select_overlay.pressed.emit()
	_check("查看前景进入正确属性卡", dock.canvas.sel_kind == dock.Kind.OVERLAY)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(before))
	_check("保存回读保留新绘制层", MapDef.from_dictionary(snapshot).actors[blood_index].draw_layer == "above_overlay")
	print("图书馆图层真窗口：%d/%d；截图 %s" % [checks - failures, checks, ProjectSettings.globalize_path(output)])
	quit(0 if failures == 0 else 1)


func _viewport(dimensions: Vector2i) -> SubViewport:
	var view := SubViewport.new()
	view.size = dimensions
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	return view


func _render(layer: String) -> Color:
	if layer.is_empty():
		raw["actors"][blood_index].erase("draw_layer")
	else:
		raw["actors"][blood_index]["draw_layer"] = layer
	editor_canvas.model.data = raw.duplicate(true)
	editor_canvas.queue_redraw()
	runtime.build(MapDef.from_dictionary(raw), WorldState.new())
	await _frames()
	await RenderingServer.frame_post_draw
	var editor_image := editor_view.get_texture().get_image()
	var game_image := game_view.get_texture().get_image()
	# 真实本图台阶与血迹的不透明重叠点；通用几何规则由内存夹具测试。
	var editor_pixel := editor_image.get_pixel(235, 337)
	var game_pixel := game_image.get_pixel(235, 337)
	# 实际游戏带世界像素材质，编辑器画布直接采原图，石阶有少量采样色差。
	# 容差仍远小于灰色台阶和深红血迹的差别，能捕获前后层反转。
	var difference := Vector3(editor_pixel.r - game_pixel.r,
		editor_pixel.g - game_pixel.g, editor_pixel.b - game_pixel.b).length()
	_check("图层 %s 编辑器与游戏重叠处显示同一层" % layer, difference < 0.06)
	var suffix := "original" if layer.is_empty() else layer
	editor_image.save_png(output.path_join("editor_" + suffix + ".png"))
	game_image.save_png(output.path_join("game_" + suffix + ".png"))
	return game_pixel


func _frames() -> void:
	await process_frame
	await process_frame


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("  ✓ " if passed else "  × ") + label)
