## 真实绘制层的属性卡和列表：内存地图、信号、旧数据兼容和撤销。
## 可独立无头执行，也可由插件全量入口调用run(h)。
extends SceneTree

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const Inspector := preload("res://addons/if_map_editor/map_draw_layer_inspector.gd")
const LayersPanel := preload("res://addons/if_map_editor/map_draw_layers_panel.gd")
const MapDef := preload("res://core/map_def.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var h := TestHarness.new()
	h.setup(root)
	run(h)
	quit(0 if h.report() else 1)


static func fixture() -> Dictionary:
	return {"id": "layers_ui", "size": [640, 480], "walls": [], "spawns": {"start": [20, 20]},
		"background": "res://art/map/library_no_cat.png", "overlay": "res://art/map/library_wall.png",
		"actors": [
			{"id": "blood", "label": "入口血迹", "sprite": "res://art/fx/library/blood_entrance.png",
				"rect": [100, 100, 80, 100], "reach_local": [5, 10, 40, 50], "collision": [[2, 50, 30, 10]]},
			{"id": "front", "label": "前层物件", "rect": [20, 20, 30, 40], "over": true, "draw_order": 7},
			{"id": "back", "label": "后层物件", "rect": [20, 20, 30, 40], "draw_order": -5},
			{"id": "cover", "label": "自动遮挡", "rect": [20, 20, 30, 40], "cover": true}]}


static func run(h: TestHarness) -> void:
	h.section("真实绘制层属性卡与图层列表")
	_test_inspector(h)
	_test_panel(h)


static func _test_inspector(h: TestHarness) -> void:
	var model := Model.new()
	model.data = fixture()
	model.reset_history()
	var inspector := Inspector.new()
	h.root.add_child(inspector)
	inspector.configure(model, 0)
	var changes: Array[int] = [0]
	var overlay_requests: Array[int] = [0]
	inspector.edited.connect(func() -> void:
		changes[0] += 1
		model.record_history())
	inspector.overlay_selected.connect(func() -> void: overlay_requests[0] += 1)
	var original: Dictionary = model.actor_dict(0).duplicate(true)
	var peers: Array = model.data["actors"].slice(1).duplicate(true)
	var picker := inspector.get_node("DrawLayerPicker") as OptionButton
	var order := inspector.find_child("DrawOrder", true, false) as SpinBox
	h.check("旧物件默认沿用原层级", picker.selected, 0)
	h.check("旧物件默认同层顺序为零", order.value, 0.0)
	h.check("前景路径能定位整张素材", inspector.get_node("OverlayPath").tooltip_text, model.data["overlay"])
	h.check("构建图层卡不改地图", model.actor_dict(0), original)
	(inspector.get_node("AboveOverlay") as Button).pressed.emit()
	h.check("快速按钮把物件置于整张前景上", model.actor_field(0, "draw_layer"), "above_overlay")
	h.check("快速切层同步下拉框", picker.selected, 4)
	h.check("快速切层只记录一笔修改", changes[0], 1)
	var expected: Dictionary = original.duplicate(true)
	expected["draw_layer"] = "above_overlay"
	h.check("切层不改变物件几何或互动内容", model.actor_dict(0), expected)
	(inspector.find_child("LayerToFront", true, false) as Button).pressed.emit()
	h.check("同层置顶越过现有最大顺序", model.actor_field(0, "draw_order"), 8)
	h.check("同层置顶不改其它物件", model.data["actors"].slice(1), peers)
	(inspector.find_child("LayerToBack", true, false) as Button).pressed.emit()
	h.check("同层置底小于现有最小顺序", model.actor_field(0, "draw_order"), -6)
	(inspector.find_child("LayerBringForward", true, false) as Button).pressed.emit()
	h.check("顺序加一只增一", model.actor_field(0, "draw_order"), -5)
	model.undo()
	inspector.sync_fields()
	h.check("撤销后顺序读数同步", order.value, -6.0)
	model.redo()
	inspector.sync_fields()
	h.check("重做后顺序读数同步", order.value, -5.0)
	picker.item_selected.emit(0)
	h.check("切回沿用设置清除覆盖字段", model.actor_dict(0).has("draw_layer"), false)
	(inspector.get_node("SelectOverlay") as Button).pressed.emit()
	h.check("查看整张前景发出选择信号", overlay_requests[0], 1)
	order.editable = false
	picker.disabled = true
	inspector.sync_fields()
	h.check("字段同步不解开外层只读保护", [order.editable, picker.disabled], [false, true])
	var multi := Inspector.new()
	h.root.add_child(multi)
	var selected: Array[int] = [0, 1]
	multi.configure(model, 0, selected)
	var before_multi: Dictionary = model.data.duplicate(true)
	h.check("多选禁止图层覆盖", (multi.get_node("DrawLayerPicker") as OptionButton).disabled, true)
	(multi.get_node("AboveOverlay") as Button).pressed.emit()
	h.check("多选按钮回调也不能偷改首个物件", model.data, before_multi)
	model.data.erase("overlay")
	inspector.sync_fields()
	h.check("没有整张前景时查看按钮禁用", (inspector.get_node("SelectOverlay") as Button).disabled, true)
	model.set_actor_field(0, "draw_layer", "auto")
	inspector.sync_fields()
	h.check("自动遮挡提示角色脚底判定", str(inspector.get_node("LayerHint").text).contains("按人物脚底Y"), true)
	var baseline_text := "%.1f" % MapDef._actor_from(model.actor_dict(0)).effective_cover_y()
	h.check("自动遮挡提示展示有效阈值", str(inspector.get_node("LayerHint").text).contains(baseline_text), true)
	(inspector.get_node("AboveOverlay") as Button).pressed.emit()
	h.check("没有整张前景时仍提示最顶层会盖住角色",
		str(inspector.get_node("LayerHint").text).contains("始终盖住角色"), true)
	multi.free()
	inspector.free()


static func _test_panel(h: TestHarness) -> void:
	var model := Model.new()
	model.data = fixture()
	model.set_actor_field(0, "draw_layer", "above_overlay")
	model.set_actor_field(0, "draw_order", 10)
	var canvas := Canvas.new()
	canvas.model = model
	var panel := LayersPanel.new()
	h.root.add_child(panel)
	var selected: Array[int] = []
	var overlays: Array[int] = [0]
	var backgrounds: Array[int] = [0]
	var visibility: Array = []
	panel.actor_selected.connect(func(index: int) -> void: selected.append(index))
	panel.overlay_selected.connect(func() -> void: overlays[0] += 1)
	panel.background_selected.connect(func() -> void: backgrounds[0] += 1)
	panel.visibility_requested.connect(func(prop: String, on: bool) -> void: visibility.append([prop, on]))
	var before: Dictionary = model.data.duplicate(true)
	panel.configure(model, canvas)
	h.check("图层列表无拖放排序入口", panel.tree.get_script(), null)
	var items := _items(panel.tree.get_root())
	var above := _find(items, "actor", 0)
	var front := _find(items, "actor", 1)
	var overlay := _find(items, "overlay")
	var background := _find(items, "background")
	var before_root := panel.tree.get_root()
	panel.refresh()
	h.check("签名未变时保留图层树节点", panel.tree.get_root(), before_root)
	model.set_actor_field(0, "rect", [100, 100, 90, 110])
	panel.refresh()
	h.check("仅几何变化不重建图层树", panel.tree.get_root(), before_root)
	model.set_actor_field(0, "rect", before["actors"][0]["rect"])
	h.check("血迹列在真实前景之上带", above.get_metadata(0).get("layer"), "above_overlay")
	h.check("沿用over的物件列在人前带", front.get_metadata(0).get("layer"), "front")
	h.check("整张前景清楚显示素材文件名", overlay.get_text(0).contains("library_wall.png"), true)
	h.check("背景清楚显示素材文件名", background.get_text(0).contains("library_no_cat.png"), true)
	h.check("从前到后列表包含前景分界", items.find(above) < items.find(overlay) and items.find(overlay) < items.find(front), true)
	above.select(0)
	panel._on_selected()
	h.check("图层列表可选择所指物件", selected.has(0), true)
	overlay.select(0)
	panel._on_selected()
	h.check("整张前景行可选择", overlays[0] > 0, true)
	background.select(0)
	panel._on_selected()
	h.check("背景行可选择", backgrounds[0] > 0, true)
	(panel.find_child("ToggleOverlay", true, false) as CheckBox).button_pressed = false
	h.check("前景显隐发出正确属性", visibility.has(["show_overlay", false]), true)
	canvas.show_overlay = false
	panel.refresh()
	h.check("显隐状态刷新不反向回写或触发选择", (panel.find_child("ToggleOverlay", true, false) as CheckBox).button_pressed, false)
	h.check("图层列表选择与显隐不修改地图数据", model.data, before)
	panel.free()
	canvas.free()


static func _items(root: TreeItem) -> Array[TreeItem]:
	var result: Array[TreeItem] = []
	var current := root.get_first_child()
	while current != null:
		result.append(current)
		result.append_array(_items(current))
		current = current.get_next()
	return result


static func _find(items: Array[TreeItem], kind: String, index := -1) -> TreeItem:
	for item: TreeItem in items:
		var metadata: Variant = item.get_metadata(0)
		if metadata is Dictionary and metadata.get("kind", "") == kind \
				and (index < 0 or metadata.get("index", -1) == index):
			return item
	return null
