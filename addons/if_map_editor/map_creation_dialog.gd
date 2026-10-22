## 新地图对话框：先选择可解码的 PNG 场景大图，再配置唯一 ID 与显示名。
##
## 只调用独立文件服务，原图宽高直接作为地图像素尺寸，不接触当前地图草稿。
##
## dock 负责 stash 旧草稿、load_map、刷新列表，以及取消或成功后的 queue_free。
@tool
extends ConfirmationDialog

const Creation := preload("res://addons/if_map_editor/map_creation.gd")

signal map_created(result: Dictionary)

var _map_dir := "res://data/maps"
var _art_dir := "res://art/map"
var _source_path := ""
var _source: Dictionary = {}
var _creating := false
var _content: VBoxContainer
var _file_dialog: FileDialog
var _source_label: Label
var _dimensions: Label
var _preview: TextureRect
var _id_edit: LineEdit
var _name_edit: LineEdit
var _status: Label


func _ready() -> void:
	if _content == null:
		_build()


## 设置创建目标；默认写入正式地图目录，测试可以传入 user:// 目录。
func configure(map_dir := "res://data/maps", art_dir := "res://art/map") -> void:
	if _content == null:
		_build()
	_map_dir = map_dir
	_art_dir = art_dir
	_refresh_validation()


## 清空上次选择并弹出窗口；取消不会创建任何文件。
func open_creation(map_dir := "res://data/maps", art_dir := "res://art/map") -> void:
	configure(map_dir, art_dir)
	_source_path = ""
	_source = {}
	_source_label.text = "尚未选择场景图"
	_source_label.tooltip_text = ""
	_dimensions.text = "地图尺寸：等待原图"
	_preview.texture = null
	_id_edit.clear()
	_name_edit.clear()
	_refresh_validation()
	var target := Vector2i(600, 580)
	if is_inside_tree():
		var available := Vector2i(get_parent().get_viewport().get_visible_rect().size) - Vector2i(32, 32)
		target = Vector2i(maxi(360, mini(target.x, available.x)),
			maxi(480, mini(target.y, available.y)))
	_prepare_popup_layout(target)
	min_size = target
	max_size = target
	popup_centered(target)


func _prepare_popup_layout(target: Vector2i) -> void:
	var width := maxf(1.0, float(target.x) - 32.0)
	_content.custom_minimum_size.x = width
	for child: Node in _content.get_children():
		if child is Label:
			(child as Label).size = Vector2(width, 0)
			(child as Label).update_minimum_size()
	_content.size = Vector2(width, maxf(1.0, float(target.y) - 80.0))


func _build() -> void:
	title = "新建地图"
	ok_button_text = "创建地图文件"
	cancel_button_text = "取消"
	dialog_hide_on_ok = false
	min_size = Vector2i(360, 480)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	add_child(_content)
	var choose := Button.new()
	choose.text = "1. 选择 PNG 场景大图…"
	choose.pressed.connect(_open_picker)
	_content.add_child(choose)
	_source_label = _label("尚未选择场景图")
	_source_label.max_lines_visible = 2
	_source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_content.add_child(_source_label)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(0, 140)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_content.add_child(_preview)
	_dimensions = _label("地图尺寸：等待原图")
	_content.add_child(_dimensions)
	_content.add_child(_label("2. 输入唯一 map_id 与地图显示名"))
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "map_id：仅 a-z、0-9、_"
	_id_edit.text_changed.connect(func(_text: String) -> void: _refresh_validation())
	_content.add_child(_id_edit)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "显示名，例如：旧图书馆"
	_name_edit.text_changed.connect(func(_text: String) -> void: _refresh_validation())
	_content.add_child(_name_edit)
	_status = _label("")
	_status.max_lines_visible = 2
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_content.add_child(_status)
	_content.add_child(_label("仅创建地图 JSON 和背景素材文件。尚未建立传送或剧情入口。"))
	_file_dialog = FileDialog.new()
	_file_dialog.title = "选择完整的 PNG 场景大图"
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.png ; PNG 场景大图"])
	_file_dialog.file_selected.connect(_select_source)
	add_child(_file_dialog)
	confirmed.connect(_confirm_creation)
	_refresh_validation()


func _open_picker() -> void:
	_file_dialog.popup_centered_ratio(0.8)


func _select_source(path: String) -> void:
	_source_path = path
	_source = Creation.inspect_png(path)
	_source_label.text = path
	_source_label.tooltip_text = path
	_preview.texture = null
	_dimensions.text = "地图尺寸：等待有效 PNG"
	if _source["ok"]:
		var size: Vector2i = _source["size"]
		_preview.texture = ImageTexture.create_from_image(_source["image"])
		_dimensions.text = "原图：%d × %d 像素；地图：%d × %d（像素 1:1）" % [
			size.x, size.y, size.x, size.y]
	_refresh_validation()


func _refresh_validation() -> void:
	var valid_source := bool(_source.get("ok", false))
	_id_edit.editable = valid_source and not _creating
	_name_edit.editable = valid_source and not _creating
	var message := ""
	if not valid_source:
		message = str(_source.get("error", "请先选择有效的 PNG 场景大图，再配置地图信息。"))
	else:
		message = Creation.validate_identity(_id_edit.text, _name_edit.text, _map_dir)
	_status.text = message if not message.is_empty() else "可以创建；出生点默认位于场景中心。"
	_status.tooltip_text = message
	get_ok_button().disabled = _creating or not message.is_empty()


func _confirm_creation() -> void:
	if _creating:
		return
	_refresh_validation()
	if get_ok_button().disabled:
		return
	_creating = true
	_refresh_validation()
	var result := Creation.create(_id_edit.text, _name_edit.text, _source_path, _map_dir, _art_dir)
	_creating = false
	_refresh_validation()
	if not result["ok"]:
		_status.text = result["error"]
		_status.tooltip_text = result["error"]
		get_ok_button().disabled = true
		return
	hide()
	map_created.emit(result)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
