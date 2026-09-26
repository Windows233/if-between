## 地图编辑器的面板：地图选择、图层开关、工具、选中项的数值、保存。
## 画布（`map_edit_canvas.gd`）挂在它下面，占满剩余空间。
##
## 数值框和画布是**双向同步**的：拖了矩形，数值跟着变；敲了数字，画面跟着动。
## 同步时用一个 `_syncing` 旗子挡住回写，免得程序设值又被当成玩家改动（会把
## 「未保存」的星号无缘无故点亮）。
@tool
extends VBoxContainer

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const Kind := Model.Kind

var model = Model.new()
var canvas: Control = null

var _map_picker: OptionButton
var _save_button: Button
var _tool_buttons: Array[Button] = []
var _sel_label: Label
var _spins: Array[SpinBox] = []
var _base_row: HBoxContainer
var _base_spin: SpinBox
var _status: Label
var _syncing := false


func _ready() -> void:
	_build()
	refresh_map_list()


# ---------------------------------------------------------------- 界面

func _build() -> void:
	add_child(_row_title())

	var tools := HBoxContainer.new()
	tools.add_child(_text("工具："))
	for item in [["选择 / 拖动 / 改尺寸", Canvas.Tool.SELECT],
			["画墙", Canvas.Tool.WALL],
			["画传送区", Canvas.Tool.PORTAL],
			["拉遮挡基线", Canvas.Tool.BASELINE]]:
		var b := Button.new()
		b.text = str(item[0])
		b.toggle_mode = true
		b.pressed.connect(_on_tool.bind(int(item[1])))
		tools.add_child(b)
		_tool_buttons.append(b)
	_tool_buttons[0].button_pressed = true
	add_child(tools)

	add_child(_row_layers())

	add_child(_row_selection())

	_status = _text("选一张地图开始。滚轮缩放，中键/右键拖动平移。")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	canvas = Canvas.new()
	canvas.custom_minimum_size = Vector2(360, 320)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.selection_changed.connect(_on_selection_changed)
	canvas.edited.connect(_on_edited)
	canvas.status.connect(func(t: String) -> void: _status.text = t)
	add_child(canvas)


func _row_title() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_text("地图："))
	_map_picker = OptionButton.new()
	_map_picker.custom_minimum_size = Vector2(200, 0)
	_map_picker.item_selected.connect(func(_i: int) -> void: _load_selected())
	row.add_child(_map_picker)
	var reload := Button.new()
	reload.text = "重新载入（丢弃改动）"
	reload.pressed.connect(func() -> void: _load_selected())
	row.add_child(reload)
	_save_button = Button.new()
	_save_button.text = "保存到 JSON"
	_save_button.pressed.connect(_on_save)
	row.add_child(_save_button)
	return row


func _row_layers() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_text("显示："))
	for item in [["背景", "show_bg"], ["前景层", "show_overlay"], ["墙", "show_walls"],
			["传送区", "show_portals"], ["物件", "show_actors"], ["可走格", "show_walk"]]:
		var cb := CheckBox.new()
		cb.text = str(item[0])
		cb.button_pressed = true
		cb.toggled.connect(_on_layer.bind(str(item[1])))
		row.add_child(cb)
	var refresh := Button.new()
	refresh.text = "重算可走格"
	refresh.tooltip_text = "改完墙之后点它，重新跑一遍游戏那份 WalkGrid"
	refresh.pressed.connect(func() -> void:
		_status.text = "正在算可走格……"
		canvas.recompute_walk())
	row.add_child(refresh)
	return row


func _row_selection() -> HBoxContainer:
	var row := HBoxContainer.new()
	_sel_label = _text("未选中")
	_sel_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(_sel_label)
	for name in ["x", "y", "宽", "高"]:
		row.add_child(_text(name))
		var spin := SpinBox.new()
		spin.min_value = -4096
		spin.max_value = 4096
		spin.step = 1
		spin.custom_minimum_size = Vector2(78, 0)
		spin.value_changed.connect(_on_spin_changed)
		row.add_child(spin)
		_spins.append(spin)

	_base_row = HBoxContainer.new()
	_base_row.add_child(_text("遮挡基线 Y"))
	_base_spin = SpinBox.new()
	_base_spin.min_value = -4096
	_base_spin.max_value = 4096
	_base_spin.step = 1
	_base_spin.custom_minimum_size = Vector2(78, 0)
	_base_spin.value_changed.connect(_on_base_spin)
	_base_row.add_child(_base_spin)
	var auto_button := Button.new()
	auto_button.text = "恢复自动（贴图底边）"
	auto_button.pressed.connect(_on_base_auto)
	_base_row.add_child(auto_button)
	_base_row.visible = false
	row.add_child(_base_row)
	return row


func _text(t: String) -> Label:
	var label := Label.new()
	label.text = t
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


# ---------------------------------------------------------------- 载入与保存

func refresh_map_list() -> void:
	var ids := Model.list_maps()
	_map_picker.clear()
	for id in ids:
		_map_picker.add_item(id)
	if ids.size() > 0:
		_load_selected()


func _load_selected() -> void:
	var id := _map_picker.get_item_text(_map_picker.selected)
	if id == "":
		return
	if not model.load_map(id):
		_status.text = "载入失败：%s" % id
		return
	canvas.load_map(model, model.background_path(), model.overlay_path(), model.map_size())
	_refresh_dirty()
	_status.text = "已载入 %s（%d×%d 游戏单位）。滚轮缩放，中键/右键拖动平移。" % [
		id, int(model.map_size().x), int(model.map_size().y)]


func _on_save() -> void:
	var err := model.save_to()
	if err == OK:
		_refresh_dirty()
		_status.text = "已保存 %s（git 里能看 diff）" % model.path
	else:
		_status.text = "保存失败，错误码 %d" % err


func _refresh_dirty() -> void:
	_save_button.text = "保存到 JSON *" if model.dirty else "保存到 JSON"


# ---------------------------------------------------------------- 交互

func _on_tool(which: int) -> void:
	canvas.tool = which
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = i == which
	match which:
		Canvas.Tool.SELECT:
			_status.text = "选择：点中矩形拖走；八个白点改尺寸；Delete 删掉；数值框可精确改。"
		Canvas.Tool.WALL:
			_status.text = "画墙：在图上按住左键拖出一个框，松手就加进 walls。"
		Canvas.Tool.PORTAL:
			_status.text = "画传送区：同上，落进 portals（默认 locked，不通往任何地方）。"
		Canvas.Tool.BASELINE:
			_status.text = "拉基线：点一件遮挡物（身上有黄线），上下拖，松手写进它的 cover_y。"


func _on_layer(on: bool, prop: String) -> void:
	canvas.set(prop, on)
	if prop == "show_walk":
		if on:
			_status.text = "正在算可走格……（用的是游戏同一份 WalkGrid）"
		canvas.set_walk_visible(on)
	else:
		canvas.queue_redraw()


func _on_spin_changed(_v: float) -> void:
	if _syncing or canvas.sel_kind < 0:
		return
	var r: Rect2 = canvas.model.rect_of(canvas.sel_kind, canvas.sel_index)
	var next := Rect2(
		Vector2(_spins[0].value, _spins[1].value),
		Vector2(maxf(1.0, _spins[2].value), maxf(1.0, _spins[3].value)))
	if next != r:
		canvas.model.set_rect(canvas.sel_kind, canvas.sel_index, next)
		_on_edited()
		canvas.queue_redraw()


func _on_base_spin(v: float) -> void:
	if _syncing or canvas.sel_kind != Kind.ACTOR or not canvas.model.is_cover_actor(canvas.sel_index):
		return
	canvas.model.set_actor_cover_y(canvas.sel_index, v)
	_on_edited()
	canvas.queue_redraw()


func _on_base_auto() -> void:
	if canvas.sel_kind != Kind.ACTOR:
		return
	canvas.model.clear_actor_cover_y(canvas.sel_index)
	_on_edited()
	_refresh_selection()


func _on_selection_changed() -> void:
	_refresh_selection()


func _refresh_selection() -> void:
	var kind: int = canvas.sel_kind
	var index: int = canvas.sel_index
	_syncing = true
	if kind < 0:
		_sel_label.text = "未选中"
		for spin in _spins:
			spin.editable = false
		_base_row.visible = false
	else:
		var names := ["墙", "传送区", "物件"]
		var r: Rect2 = model.rect_of(kind, index)
		_sel_label.text = "%s #%d %s" % [names[kind], index, model.label_of(kind, index)]
		_spins[0].value = r.position.x
		_spins[1].value = r.position.y
		_spins[2].value = r.size.x
		_spins[3].value = r.size.y
		for spin in _spins:
			spin.editable = true
		var is_cover: bool = kind == Kind.ACTOR and model.is_cover_actor(index)
		_base_row.visible = is_cover
		if is_cover:
			_base_spin.value = model.actor_cover_y(index)
			_base_spin.tooltip_text = "黄线=自动（贴图底边）；橙线=手动覆盖"
	_syncing = false


func _on_edited() -> void:
	_refresh_dirty()
