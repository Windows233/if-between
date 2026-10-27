## 按真实绘制带由前到后列出的图层入口，含不属于物件的整张前景与背景。
## 只发送选择/显示信号，不移动场景树编组，不修改地图数据或真实层级。
## 多部件跨层时同一物件可在多个绘制带出现；显示开关仅影响编辑器画布。
@tool
extends VBoxContainer

signal actor_selected(index: int)
signal overlay_selected
signal background_selected
signal visibility_requested(prop: String, on: bool)

const MapDef := preload("res://core/map_def.gd")
const BANDS := ["above_overlay", "front", "auto", "map_under_player", "back"]
const LABELS := {"above_overlay": "最顶层：盖住人物与前景", "front": "固定盖住人物／前景之下",
	"auto": "自动前后：按人物脚底Y", "map_under_player": "底图上方：角色后方", "back": "普通物件层"}

var model
var canvas
var tree: Tree
var _toggle_overlay: CheckBox
var _toggle_background: CheckBox
var _syncing := false
var _signature: Array = []


func configure(source, source_canvas) -> void:
	model = source
	canvas = source_canvas
	name = "DrawLayersPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var heading := Label.new()
	heading.text = "绘制图层（上面盖住下面）"
	add_child(heading)
	var toggles := HFlowContainer.new()
	_toggle_overlay = _toggle("显示整张前景", "ToggleOverlay", "show_overlay")
	_toggle_background = _toggle("显示背景", "ToggleBackground", "show_bg")
	toggles.add_child(_toggle_overlay)
	toggles.add_child(_toggle_background)
	add_child(toggles)
	tree = Tree.new()
	tree.name = "DrawLayersTree"
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_SINGLE
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 180
	tree.item_selected.connect(_on_selected)
	add_child(tree)
	var note := Label.new()
	note.text = "底图上方层始终在角色后面；自动前后按人物脚底Y切换；固定前层和最顶层会盖住人物。点“当前布局试走”可用真实角色验证。显隐只用于对照，不会保存。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	refresh()


func refresh() -> void:
	if tree == null or model == null:
		return
	var signature := _data_signature()
	if signature == _signature:
		return
	_signature = signature.duplicate(true)
	var selected_key := ""
	if tree.get_selected() != null:
		selected_key = str(tree.get_selected().get_metadata(0).get("key", ""))
	_syncing = true
	tree.clear()
	var root := tree.create_item()
	var definition = MapDef.from_dictionary(model.data)
	var ordered: Array = MapDef.ordered_actors(definition.actors)
	ordered.reverse()
	for band: String in BANDS:
		if band == "front":
			_add_fixed(root, "overlay", "整张前景", str(model.data.get("overlay", "")), selected_key)
		var section := tree.create_item(root)
		section.set_text(0, LABELS[band])
		section.set_selectable(0, false)
		for actor: MapDef.Actor in ordered:
			if not actor.visual_layers().has(band):
				continue
			var index: int = definition.actors.find(actor)
			var item := tree.create_item(section)
			var identity := str(model.actor_field(index, "id", ""))
			var label := str(model.actor_field(index, "label", identity))
			if label.is_empty():
				label = identity
			var order := int(model.actor_field(index, "draw_order", 0))
			var hidden: bool = canvas != null and canvas.actor_is_hidden(index)
			item.set_text(0, "%s [%s] · %d%s" % [label, identity, order, " · 隐藏" if hidden else ""])
			var key := "actor:%d:%s" % [index, band]
			item.set_metadata(0, {"kind": "actor", "index": index, "layer": band, "key": key})
			item.set_tooltip_text(0, "%s；同层顺序 %d。点击查看物件，数值越大越靠前。" % [LABELS[band], order])
			if key == selected_key:
				item.select(0)
	_add_fixed(root, "background", "背景", str(model.data.get("background", "")), selected_key)
	_toggle_overlay.set_pressed_no_signal(canvas == null or canvas.show_overlay)
	_toggle_background.set_pressed_no_signal(canvas == null or canvas.show_bg)
	_toggle_overlay.disabled = str(model.data.get("overlay", "")).is_empty()
	_toggle_background.disabled = str(model.data.get("background", "")).is_empty()
	_syncing = false


func _data_signature() -> Array:
	var actors: Array = []
	for index: int in model.count(model.Kind.ACTOR):
		var source: Dictionary = model.actor_dict(index)
		var parts: Array = []
		for part: Variant in source.get("visual_parts", []):
			if part is Dictionary:
				parts.append(str(part.get("layer", "auto")))
		actors.append([source.get("id", ""), source.get("label", ""), source.get("draw_layer", ""),
			source.get("draw_order", 0), source.get("over", false), source.get("cover", false),
			parts, canvas != null and canvas.actor_is_hidden(index)])
	return [model.map_id, model.data.get("overlay", ""), model.data.get("background", ""),
		canvas == null or canvas.show_overlay, canvas == null or canvas.show_bg, actors]


func _add_fixed(root: TreeItem, kind: String, caption: String, path: String, selected_key: String) -> void:
	var item := tree.create_item(root)
	item.set_text(0, "%s：%s" % [caption, path.get_file() if not path.is_empty() else "无"])
	item.set_metadata(0, {"kind": kind, "key": kind})
	item.set_tooltip_text(0, path if not path.is_empty() else caption + "尚未设置")
	item.set_selectable(0, not path.is_empty())
	if kind == selected_key and not path.is_empty():
		item.select(0)


func _toggle(caption: String, node_name: String, prop: String) -> CheckBox:
	var button := CheckBox.new()
	button.name = node_name
	button.text = caption
	button.tooltip_text = "只影响编辑器显示，不保存到地图。"
	button.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			visibility_requested.emit(prop, on))
	return button


func _on_selected() -> void:
	if _syncing or tree.get_selected() == null:
		return
	var info: Dictionary = tree.get_selected().get_metadata(0)
	match str(info.get("kind", "")):
		"actor":
			actor_selected.emit(int(info["index"]))
		"overlay":
			overlay_selected.emit()
		"background":
			background_selected.emit()
