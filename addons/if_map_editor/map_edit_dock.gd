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
## 「物件属性」面板：只在选中物件时出现。**每次换选中项才重建** ——
## 每敲一个字都重建会把光标弄丢。
var _actor_panel: VBoxContainer
var _panel_scroll: ScrollContainer
var _panel_kind := -1
var _panel_index := -1


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

	# 属性面板放进**定高滚动区**：对话一行一句，行数一多面板会很长，
	# 不挡住下面的画布（也不把下面的东西挤出屏幕）。
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.custom_minimum_size = Vector2(0, 168)
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_scroll.visible = false
	add_child(_panel_scroll)
	_actor_panel = VBoxContainer.new()
	_actor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_scroll.add_child(_actor_panel)

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

	var import_image := Button.new()
	import_image.text = "导入图像…"
	import_image.tooltip_text = "挑一张 PNG → 拷进 art/props/ → 新建一件遮挡物件（位置和基线之后在画布上调）"
	import_image.pressed.connect(_open_import_dialog)
	row.add_child(import_image)

	var add_actor := Button.new()
	add_actor.text = "加物件"
	add_actor.tooltip_text = "加一件家具/NPC，落在地图正中；下面的「物件属性」里填名字、贴图和互动内容。"
	add_actor.pressed.connect(_on_add_actor)
	row.add_child(add_actor)
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


## 删东西。**有跨文件关联的先问一句** —— 删掉就断了那条入口，
## 而且数据本身还是合法的，`check_data` 也不会报（它只查「引用存在不存在」，
## 查不出「本来该有个人来触发」）。
func _on_delete() -> void:
	if canvas.sel_kind < 0:
		return
	var names := ["墙", "传送区", "物件", "出生点", "前景层"]
	var what: String = names[canvas.sel_kind]
	var was: String = model.label_of(canvas.sel_kind, canvas.sel_index)
	var refs: Array[String] = []
	if canvas.sel_kind == Kind.ACTOR:
		refs = model.actor_references(canvas.sel_index)
	elif canvas.sel_kind == Kind.PORTAL:
		refs = model.portal_references(canvas.sel_index)
	if refs.is_empty():
		_do_delete(what, was)
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "删这件「%s」？它身上挂着东西" % was
	dialog.ok_button_text = "照样删掉"
	var box := VBoxContainer.new()
	var head := _text("删掉之后，下面这些就再也触发不到了（文件还在，只是没了入口）：")
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	for line in refs:
		var item := _text("· " + line)
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(item)
	dialog.add_child(_scrolled(box, Vector2(420, 180)))
	dialog.confirmed.connect(func() -> void:
		_do_delete(what, was)
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(470, 220))


func _do_delete(what: String, was: String) -> void:
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
	dialog.add_child(_scrolled(box, Vector2(380, 150)))
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
	picker.fit_to_longest_item = false
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
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	dialog.add_child(scroll)
	dialog.confirmed.connect(func() -> void:
		var target := picker.get_item_text(picker.selected)
		var counts := "%d 墙 / %d 传送区 / %d 物件" % [
			model.count(Kind.WALL), model.count(Kind.PORTAL), model.count(Kind.ACTOR)]
		var err := model.copy_layout_to(target, with_spawns.button_pressed)
		_status.text = ("已把 %s 覆盖到 %s" % [counts, target]) if err == "" else err
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


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
		var names := ["墙", "传送区", "物件", "出生点", "前景层"]
		var r: Rect2 = model.rect_of(kind, index)
		_sel_label.text = "%s #%d %s" % [names[kind], index, model.label_of(kind, index)]
		_spins[0].value = r.position.x
		_spins[1].value = r.position.y
		_spins[2].value = r.size.x
		_spins[3].value = r.size.y
		var is_spawn: bool = kind == Kind.SPAWN
		var is_overlay: bool = kind == Kind.OVERLAY
		# 出生点没有宽高可改（它就是个坐标）；前景层整张拉伸，四个都不给改
		_spins[0].editable = not is_overlay
		_spins[1].editable = not is_overlay
		_spins[2].editable = not is_spawn and not is_overlay
		_spins[3].editable = not is_spawn and not is_overlay
		if is_overlay:
			_spins[0].value = 0
			_spins[1].value = 0
			_spins[2].value = 0
			_spins[3].value = 0
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
	_sync_actor_panel()


func _on_edited() -> void:
	_refresh_dirty()


# ---------------------------------------------------------------- 物件属性面板
#
# 这块只在**选中物件**时出现。能改：id / 名字 / 贴图 / 三个常用开关（装饰、
# 遮挡、恒在上层）、以及互动内容（单句旁白 / 多句对话）。
#
# **不编剧情。** 挂了 `event`（剧情文件）或 `actions`（多动作菜单）的物件，
# 这里只显示「在哪个文件里」，不动它 —— 剧情正文归 `data/events/`。
#
# **认不得的字段一律原样留着**：所有写入都是「就地改那个字典里的某一个键」
# （`set_actor_field` / `_set_talk`），不重建字典。对话行支持的
# `size_delta` / `shake` 编辑器不显示，但也不会被抹掉。

func _on_add_actor() -> void:
	var index := model.add_actor()
	canvas.sel_kind = Kind.ACTOR
	canvas.sel_index = index
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_status.text = "加了一件物件（先落在地图正中）。拖到位置上，再填下面的名字、贴图、互动内容。"


## 只在「换了选中项」时重建面板 —— 每敲一个字都重建会把光标弄丢。
func _sync_actor_panel() -> void:
	var kind: int = canvas.sel_kind
	if kind != Kind.ACTOR and kind != Kind.OVERLAY:
		_panel_scroll.visible = false
		_panel_kind = -1
		_panel_index = -1
		return
	if _panel_kind == kind and _panel_index == canvas.sel_index:
		_panel_scroll.visible = true
		return
	if kind == Kind.OVERLAY:
		_build_overlay_panel()
	else:
		_build_actor_panel()


## 前景层只有一条数据（路径），能做的就三件：看它是谁、换一张、清掉。
## **它整张拉伸到地图大小**，所以没有位置/尺寸可调。
func _build_overlay_panel() -> void:
	_panel_kind = Kind.OVERLAY
	_panel_index = 0
	for child in _actor_panel.get_children():
		child.queue_free()
	_panel_scroll.visible = true

	_actor_panel.add_child(_text("前景层（恒在角色之上，整张拉伸到地图大小）"))
	var row := HBoxContainer.new()
	row.add_child(_text("图片"))
	var path_line := LineEdit.new()
	path_line.text = model.overlay_path()
	path_line.custom_minimum_size = Vector2(380, 0)
	path_line.text_changed.connect(func(t: String) -> void:
		model.set_overlay_path(t)
		canvas.set_overlay_texture(t)
		_on_edited())
	row.add_child(path_line)
	var swap := Button.new()
	swap.text = "导入图像…"
	swap.tooltip_text = "挑一张 PNG 当作这张图的前景层：拷进 art/map/，命名成 <地图名>_wall"
	swap.pressed.connect(_open_overlay_import_dialog)
	row.add_child(swap)
	var clear := Button.new()
	clear.text = "清除"
	clear.tooltip_text = "把前景层去掉（这条数据清空，图还在 art/map 里）"
	clear.pressed.connect(func() -> void:
		model.clear_overlay()
		canvas.set_overlay_texture("")
		_on_edited()
		canvas.sel_kind = -1
		_refresh_selection()
		_status.text = "前景层清掉了（那条数据没了，图还在 art/map 里）")
	row.add_child(clear)
	_actor_panel.add_child(row)
	_actor_panel.add_child(_text("提示：想看它盖住了什么，把「前景层」不透明度滑条拉淡。"))

	if model.overlay_path() == "":
		_actor_panel.add_child(_text("这张图现在没有前景层。点「导入图像…」加一张。"))


func _build_actor_panel() -> void:
	_panel_kind = Kind.ACTOR
	_panel_index = canvas.sel_index
	for child in _actor_panel.get_children():
		child.queue_free()
	_panel_scroll.visible = true

	_actor_panel.add_child(_text("物件属性（id 与名字改完，记得点上面的「保存到 JSON」）"))

	var row1 := HBoxContainer.new()
	row1.add_child(_text("id"))
	row1.add_child(_field("id", 110.0))
	row1.add_child(_text("  名字"))
	row1.add_child(_field("label", 130.0))
	_actor_panel.add_child(row1)

	var row2 := HBoxContainer.new()
	row2.add_child(_text("贴图"))
	var sprite_line := _field("sprite", 320.0)
	row2.add_child(sprite_line)
	var picker := OptionButton.new()
	picker.add_item("（从 art/props 选）")
	var props := model.prop_files()
	for path in props:
		picker.add_item(path.get_file())
	picker.item_selected.connect(func(i: int) -> void:
		if i <= 0:
			return
		var path: String = props[i - 1]
		model.set_actor_field(_panel_index, "sprite", path)
		sprite_line.text = path
		_on_edited()
		canvas.queue_redraw())
	row2.add_child(picker)
	_actor_panel.add_child(row2)

	var row3 := HBoxContainer.new()
	row3.add_child(_text("属性："))
	row3.add_child(_bool_field("decor", "只装饰（不参与交互）"))
	row3.add_child(_bool_field("cover", "会挡人（按站位分前后）"))
	row3.add_child(_bool_field("over", "永远画在角色之上"))
	_actor_panel.add_child(row3)

	_build_interaction_section()
	_actor_panel.add_child(_switch_row())


func _build_interaction_section() -> void:
	var form: String = model.actor_form(_panel_index)
	var names := {
		"line": "单句旁白", "talk": "多句对话", "event": "挂了剧情事件",
		"actions": "多动作菜单", "decor": "纯装饰（不交互）", "none": "还没写",
	}
	var head := HBoxContainer.new()
	head.add_child(_text("互动内容："))
	head.add_child(_text(str(names.get(form, form))))
	_actor_panel.add_child(head)

	match form:
		"line":
			_actor_panel.add_child(_text_area("line", 520.0, 44.0))
		"talk":
			_build_talk_list()
		"event":
			_actor_panel.add_child(_text("  → data/events/%s.json（正文在那个文件里，编辑器不编剧情）"
				% str(model.actor_field(_panel_index, "event", ""))))
		"actions":
			_actor_panel.add_child(_text("  → 写在 data/maps 里的多动作菜单，编辑器暂不编辑"))
		_:
			_actor_panel.add_child(_text("  想让它能说话，就点右边的按钮换成旁白或对话。"))


func _switch_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var to_line := Button.new()
	to_line.text = "换成单句旁白"
	to_line.pressed.connect(func() -> void: _switch_form("line"))
	row.add_child(to_line)
	var to_talk := Button.new()
	to_talk.text = "换成多句对话"
	to_talk.pressed.connect(func() -> void: _switch_form("talk"))
	row.add_child(to_talk)
	row.add_child(_text("（原来的内容会搬过去；挂了剧情事件的件不动）"))
	return row


func _switch_form(form: String) -> void:
	var d := model.actor_dict(_panel_index)
	if d.has("event") or d.has("actions"):
		_status.text = "这件挂了剧情事件或动作菜单，编辑器不动它 —— 想改成对话，先去那个文件里把它摘掉"
		return
	if form == "line":
		model.erase_actor_field(_panel_index, "talk")
		model.set_actor_field(_panel_index, "line", str(d.get("line", "")))
	else:
		var old := str(d.get("line", ""))
		model.erase_actor_field(_panel_index, "line")
		model.set_actor_field(_panel_index, "talk",
			[{"text": old}] if old != "" else [{"text": ""}])
	_on_edited()
	_build_actor_panel()
	canvas.queue_redraw()
	_status.text = "换成「%s」了（原本那种写法的内容已清掉）" % ("单句旁白" if form == "line" else "多句对话")


func _build_talk_list() -> void:
	var talk := model.actor_talk(_panel_index)
	var portraits := model.portrait_names()
	for i in talk.size():
		var line: Dictionary = talk[i] if talk[i] is Dictionary else {}
		var row := HBoxContainer.new()

		var who := LineEdit.new()
		who.text = str(line.get("speaker", ""))
		who.placeholder_text = "说话人（空=旁白）"
		who.custom_minimum_size = Vector2(96, 0)
		who.text_changed.connect(func(t: String) -> void: _set_talk(i, "speaker", t))
		row.add_child(who)

		var side := OptionButton.new()
		side.add_item("左")
		side.add_item("右")
		side.selected = 1 if str(line.get("side", "left")) == "right" else 0
		side.item_selected.connect(func(k: int) -> void:
			_set_talk(i, "side", "right" if k == 1 else "left"))
		row.add_child(side)

		var port := OptionButton.new()
		port.add_item("（无立绘）")
		for name in portraits:
			port.add_item(name)
		var cur := str(line.get("portrait", ""))
		for k in portraits.size():
			if portraits[k] == cur:
				port.selected = k + 1
		port.item_selected.connect(func(k: int) -> void:
			_set_talk(i, "portrait", "" if k == 0 else portraits[k - 1]))
		row.add_child(port)

		var body := TextEdit.new()
		body.text = str(line.get("text", ""))
		body.custom_minimum_size = Vector2(300, 38)
		body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		body.text_changed.connect(func() -> void: _set_talk(i, "text", body.text))
		row.add_child(body)

		row.add_child(_line_button("↑", func() -> void: _move_talk(i, i - 1)))
		row.add_child(_line_button("↓", func() -> void: _move_talk(i, i + 1)))
		row.add_child(_line_button("✕", func() -> void: _remove_talk(i)))
		_actor_panel.add_child(row)

	var add := Button.new()
	add.text = "加一句"
	add.pressed.connect(func() -> void:
		model.actor_talk(_panel_index).append({"text": ""})
		model.mark_dirty()
		_on_edited()
		_build_actor_panel()
		canvas.queue_redraw())
	_actor_panel.add_child(add)


## 把内容塞进一个定高的滚动区 —— 弹窗内容再长也不会把按钮顶出屏幕。
func _scrolled(content: Control, view: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = view
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _line_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(30, 0)
	b.pressed.connect(action)
	return b


func _set_talk(index: int, key: String, value: Variant) -> void:
	var talk := model.actor_talk(_panel_index)
	if index < 0 or index >= talk.size():
		return
	if not (talk[index] is Dictionary):
		talk[index] = {}
	(talk[index] as Dictionary)[key] = value
	model.mark_dirty()
	_on_edited()
	canvas.queue_redraw()


func _remove_talk(index: int) -> void:
	var talk := model.actor_talk(_panel_index)
	if index < 0 or index >= talk.size():
		return
	talk.remove_at(index)
	model.mark_dirty()
	_on_edited()
	_build_actor_panel()
	canvas.queue_redraw()


func _move_talk(from_index: int, to_index: int) -> void:
	var talk := model.actor_talk(_panel_index)
	if from_index < 0 or from_index >= talk.size():
		return
	if to_index < 0 or to_index >= talk.size():
		return
	var item: Variant = talk[from_index]
	talk.remove_at(from_index)
	talk.insert(to_index, item)
	model.mark_dirty()
	_on_edited()
	_build_actor_panel()
	canvas.queue_redraw()


func _field(key: String, width: float) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = str(model.actor_field(_panel_index, key, ""))
	edit.custom_minimum_size = Vector2(width, 0)
	edit.text_changed.connect(func(t: String) -> void:
		model.set_actor_field(_panel_index, key, t)
		_on_edited())
	return edit


func _bool_field(key: String, label: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = label
	box.button_pressed = bool(model.actor_field(_panel_index, key, false))
	box.toggled.connect(func(on: bool) -> void:
		# 勾「只装饰」= 不参与交互 → 挂着的剧情就再也触发不到。
		# 这条**数据合法、check_data 查不出来**，所以在这儿拦一下。
		if key == "decor" and on and model.actor_has_story(_panel_index):
			box.set_pressed_no_signal(false)
			_confirm_decor(_panel_index, box)
			return
		model.set_actor_field(_panel_index, key, on)
		_on_edited()
		canvas.queue_redraw())
	return box


## 勾「只装饰」会把剧情入口堵死 —— 先把挂着的东西列出来问一句。
func _confirm_decor(index: int, box: CheckBox) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "勾「只装饰」？它就不参与交互了"
	dialog.ok_button_text = "知道，勾上"
	var text := "勾上之后玩家没法再跟它互动，下面这些也就触发不到了：\n\n"
	for line in model.actor_references(index):
		text += "· " + line + "\n"
	var label := _text(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(_scrolled(label, Vector2(420, 180)))
	dialog.confirmed.connect(func() -> void:
		model.set_actor_field(index, "decor", true)
		if is_instance_valid(box):
			box.set_pressed_no_signal(true)
		_on_edited()
		canvas.queue_redraw()
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(470, 240))


## 长文本用多行框 —— 对话一句话可能挺长，单行框看半句很难受。
func _text_area(key: String, width: float, height: float) -> TextEdit:
	var area := TextEdit.new()
	area.text = str(model.actor_field(_panel_index, key, ""))
	area.custom_minimum_size = Vector2(width, height)
	area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	area.text_changed.connect(func() -> void:
		model.set_actor_field(_panel_index, key, area.text)
		_on_edited())
	return area


# ---------------------------------------------------------------- 导入图片做遮挡片

## 从文件系统挑一张图 → 拷进 `art/props/` → 新建一件**遮挡物件**。
##
## 为什么默认勾 `cover`：这个入口就是给「从美术给的图里挑一块做遮挡片」用的
## （集市、学校那批白框遮挡片就是这么做的）。位置和基线随后在画布上调。
func _open_import_dialog() -> void:
	if model.map_id == "":
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.add_filter("*.png", "PNG 图片")
	fd.title = "挑一张图（会拷进 art/props/，并新建一件遮挡物件）"
	fd.file_selected.connect(func(path: String) -> void:
		_import_and_create(path)
		fd.queue_free())
	fd.canceled.connect(func() -> void: fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(760, 500))


## 前景层导入：拷进 `art/map/`，按项目习惯命名 `<地图名>_wall`。
##
## 不用管图的尺寸 —— 游戏里它会被**拉伸到整张地图**（`map_view._add_overlay`）。
func _open_overlay_import_dialog() -> void:
	if model.map_id == "":
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.add_filter("*.png", "PNG 图片")
	fd.title = "挑一张图当前景层（会拷进 art/map/）"
	fd.file_selected.connect(func(path: String) -> void:
		_import_overlay(path)
		fd.queue_free())
	fd.canceled.connect(func() -> void: fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(760, 500))


func _import_overlay(source_path: String) -> void:
	var res_path := model.import_image(source_path, "res://art/map", model.map_id + "_wall")
	if res_path == "":
		_status.text = "导入失败：得是能读的 .png。"
		return
	model.set_overlay_path(res_path)
	canvas.set_overlay_texture(res_path)
	canvas.clear_texture_cache()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	canvas.sel_kind = Kind.OVERLAY
	canvas.sel_index = 0
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_status.text = "前景层换成 %s（整张拉伸到地图大小，图的尺寸不用管）" % res_path
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		canvas.clear_texture_cache()
		canvas.set_overlay_texture(res_path))


func _import_and_create(source_path: String) -> void:
	var res_path := model.import_image(source_path, "res://art/props")
	if res_path == "":
		_status.text = "导入失败：得是能读的 .png。别的格式先在画图工具里另存成 png。"
		return
	var index := model.add_actor_with_sprite(res_path, true)
	canvas.sel_kind = Kind.ACTOR
	canvas.sel_index = index
	canvas.clear_texture_cache()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	_on_edited()
	_refresh_selection()
	canvas.queue_redraw()
	_status.text = "导入成 %s，并建了一件遮挡物件。拖到位置上、拉它的黄线；名字在下面改。" % res_path
	# 新文件被 Godot 导成纹理要一两秒，等一下再清缓存重画一次，图才出得来
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		canvas.clear_texture_cache()
		canvas.queue_redraw())
