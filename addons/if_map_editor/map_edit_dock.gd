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
	var copy := Button.new()
	copy.text = "复制布局到…"
	copy.tooltip_text = "把这张图的碰撞箱/传送区/物件覆盖到另一张图上（白天版↔夜间版）"
	copy.pressed.connect(_open_copy_dialog)
	row.add_child(copy)
	return row


func _row_layers() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_text("显示："))
	for item in [["背景", "show_bg"], ["前景层", "show_overlay"], ["墙", "show_walls"],
			["传送区", "show_portals"], ["物件", "show_actors"], ["出生点", "show_spawns"],
			["可走格", "show_walk"]]:
		var cb := CheckBox.new()
		cb.text = str(item[0])
		cb.button_pressed = true
		cb.tooltip_text = "取消勾选：这一类既不显示，也点不中（底下压着的东西就能选中了）"
		cb.toggled.connect(_on_layer.bind(str(item[1])))
		row.add_child(cb)
	var refresh := Button.new()
	refresh.text = "重算可走格"
	refresh.tooltip_text = "改完墙之后点它，重新跑一遍游戏那份 WalkGrid"
	refresh.pressed.connect(func() -> void:
		_status.text = "正在算可走格……"
		canvas.recompute_walk())
	row.add_child(refresh)

	# 前景层不透明度：它恒在角色之上，会挡住底下正在编辑的东西
	row.add_child(_text("  前景层"))
	var alpha := HSlider.new()
	alpha.min_value = 0
	alpha.max_value = 100
	alpha.step = 5
	alpha.value = 100
	alpha.custom_minimum_size = Vector2(120, 0)
	alpha.tooltip_text = "调淡前景层，看清它底下盖着的碰撞箱/传送区。只影响显示，不改数据。"
	alpha.value_changed.connect(func(v: float) -> void:
		canvas.overlay_alpha = v / 100.0
		canvas.queue_redraw())
	row.add_child(alpha)
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

	var remove := Button.new()
	remove.text = "删除选中"
	remove.tooltip_text = "删掉当前选中的墙 / 传送区 / 出生点（Delete 键同样管用）"
	remove.pressed.connect(_on_delete)
	row.add_child(remove)

	var add_spawn := Button.new()
	add_spawn.text = "加出生点"
	add_spawn.tooltip_text = "加一个出生点（会问你名字，加在地图正中，之后拖到位置）。"
	add_spawn.tooltip_text += "\n注意：至少得留一个 start —— 新游戏和多数传送点都找它。"
	add_spawn.pressed.connect(_open_spawn_dialog)
	row.add_child(add_spawn)
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
	canvas.set_layer_visible(prop, on)
	if prop == "show_walk":
		if on:
			_status.text = "正在算可走格……（用的是游戏同一份 WalkGrid）"
	else:
		_status.text = "「%s」%s —— 显示开关同时管能不能点中" % [prop, "开着" if on else "关掉了"]


func _on_delete() -> void:
	if canvas.sel_kind < 0:
		return
	var names := ["墙", "传送区", "物件", "出生点"]
	var what: String = names[canvas.sel_kind]
	var was: String = model.label_of(canvas.sel_kind, canvas.sel_index)
	model.remove_at(canvas.sel_kind, canvas.sel_index)
	canvas.sel_kind = -1
	canvas.sel_index = -1
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_status.text = "删了一个%s%s（还没保存，点「重新载入」就能全部撤回来）" % [
		what, "（%s）" % was if was != "" else ""]


## 加一个出生点：问名字、加在地图正中，之后拖到位置。
func _open_spawn_dialog() -> void:
	if model.map_id == "":
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "加一个出生点"
	dialog.ok_button_text = "加"
	var box := VBoxContainer.new()
	var head := _text("名字（传送点就是这样引用它的，别和现有的重名）：")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	var field := LineEdit.new()
	field.custom_minimum_size = Vector2(200, 0)
	field.text = "from_"
	box.add_child(field)
	var tip := _text("加进来在地图正中，选中之后拖到位置上；x/y 也能敲数字。")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)
	dialog.add_child(box)
	dialog.confirmed.connect(func() -> void:
		var index := model.add_spawn(field.text.strip_edges())
		if index < 0:
			_status.text = "这个名字不能用：空的，或者已经有同名的出生点了"
		else:
			model.set_spawn_point(index, model.map_size() * 0.5)
			canvas.sel_kind = Kind.SPAWN
			canvas.sel_index = index
			_on_edited()
			_refresh_selection()
			canvas.queue_redraw()
			_status.text = "加好了出生点「%s」，现在把它拖到位置上" % field.text.strip_edges()
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 190))
	field.grab_focus()


func _open_copy_dialog() -> void:
	if model.map_id == "":
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "复制布局到另一张地图"
	dialog.ok_button_text = "覆盖过去"
	var box := VBoxContainer.new()
	var head := _text("把 %s 的碰撞箱、传送区、物件，覆盖到：" % model.map_id)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	var picker := OptionButton.new()
	for id in Model.list_maps():
		if id != model.map_id:
			picker.add_item(id)
	box.add_child(picker)
	var with_spawns := CheckBox.new()
	with_spawns.text = "连出生点一起复制"
	box.add_child(with_spawns)
	var warn := _text("目标图里这三项会被整个换掉；尺寸、背景、前景层、音乐不动。")
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(warn)
	dialog.add_child(box)
	dialog.confirmed.connect(func() -> void:
		var target := picker.get_item_text(picker.selected)
		var counts := "%d 墙 / %d 传送区 / %d 物件" % [
			model.count(Kind.WALL), model.count(Kind.PORTAL), model.count(Kind.ACTOR)]
		var err := model.copy_layout_to(target, with_spawns.button_pressed)
		_status.text = ("已把 %s 覆盖到 %s" % [counts, target]) if err == "" else err
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(430, 210))


func _on_spin_changed(_v: float) -> void:
	if _syncing or canvas.sel_kind < 0:
		return
	if canvas.sel_kind == Kind.SPAWN:
		# 出生点是坐标，不是矩形 —— 只认 x / y 两个框
		canvas.model.set_spawn_point(canvas.sel_index, Vector2(_spins[0].value, _spins[1].value))
		_on_edited()
		canvas.queue_redraw()
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
		var names := ["墙", "传送区", "物件", "出生点"]
		var r: Rect2 = model.rect_of(kind, index)
		_sel_label.text = "%s #%d %s" % [names[kind], index, model.label_of(kind, index)]
		_spins[0].value = r.position.x
		_spins[1].value = r.position.y
		_spins[2].value = r.size.x
		_spins[3].value = r.size.y
		var is_spawn: bool = kind == Kind.SPAWN
		# 出生点没有宽高可改（它就是个坐标），x/y 照旧能敲
		_spins[0].editable = true
		_spins[1].editable = true
		_spins[2].editable = not is_spawn
		_spins[3].editable = not is_spawn
		if is_spawn:
			# 出生点显示的是「点本身」，别把包装用的 6×6 露出来
			var p: Vector2 = model.spawn_point(index)
			_spins[0].value = p.x
			_spins[1].value = p.y
		var is_cover: bool = kind == Kind.ACTOR and model.is_cover_actor(index)
		_base_row.visible = is_cover
		if is_cover:
			_base_spin.value = model.actor_cover_y(index)
			_base_spin.tooltip_text = "黄线=自动（贴图底边）；橙线=手动覆盖"
	_syncing = false


func _on_edited() -> void:
	_refresh_dirty()
