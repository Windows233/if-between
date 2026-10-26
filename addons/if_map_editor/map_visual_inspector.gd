## 贴图位置与大小的独立入口；使用现有几何变换保留世界交互区和碰撞。
## 数值提交后就地刷新，只有视觉部件结构变化才请求重建属性卡。
## 面板字段名供GUI回归使用；等比锁只影响当前面板，不写入地图。
@tool
extends VBoxContainer

signal edited
signal rebuild_requested
signal tool_requested(which: int)

const Transform := preload("res://addons/if_map_editor/map_object_transform.gd")
const MapDef := preload("res://core/map_def.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const LAYERS := ["back", "auto", "front"]
var model
var actor_index := -1
var selection: Array[int] = []
var _variant_id_input: LineEdit
var _variant_path_input: LineEdit
var _texture_width: SpinBox
var _texture_height: SpinBox
var _texture_x: SpinBox
var _texture_y: SpinBox
var _texture_aspect_lock: CheckBox
var _texture_scale: SpinBox
var _texture_tool_button: Button
var _part_geometry_fields: Dictionary = {}
var _part_offset_fields: Dictionary = {}


func configure(source, index: int, selected: Array[int] = []) -> void:
	model = source
	actor_index = index
	selection.assign(selected if not selected.is_empty() else [index])
	var title := Label.new()
	title.text = "贴图大小与外观"
	add_child(title)
	_build_texture_size()
	_texture_tool_button = Button.new()
	_texture_tool_button.name = "EditTextureOnCanvas"
	_texture_tool_button.text = "在画布调整贴图"
	_texture_tool_button.toggle_mode = true
	_texture_tool_button.disabled = selection.size() != 1
	_texture_tool_button.tooltip_text = "拖动青色贴图框或手柄，只调整贴图；绿色交互框和红色碰撞保持原位。"
	_texture_tool_button.pressed.connect(func() -> void: tool_requested.emit(Canvas.Tool.TEXTURE))
	add_child(_texture_tool_button)
	var tools := HFlowContainer.new()
	for action: Array in [["水平翻转", "flip_h"], ["垂直翻转", "flip_v"], ["顺时针 90°", "rotate_cw"], ["逆时针 90°", "rotate_ccw"]]:
		var button := Button.new()
		button.text = action[0]
		button.pressed.connect(_transform.bind(str(action[1])))
		tools.add_child(button)
	var scale := SpinBox.new()
	scale.min_value = 0.01
	scale.max_value = 100
	scale.step = 0.01
	scale.value = 1
	scale.custom_minimum_size.x = 100
	scale.name = "TextureScale"
	_texture_scale = scale
	tools.add_child(scale)
	var apply := Button.new()
	apply.text = "等比缩放"
	apply.name = "ApplyTextureScale"
	apply.pressed.connect(func() -> void: _transform("scale", scale.value))
	tools.add_child(apply)
	add_child(tools)
	var note := Label.new()
	note.text = "本栏只改贴图。交互区域在下方单独调节，红色碰撞区域也保持原大小。部件矩形相对贴图左上角。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var advanced_start := get_child_count()
	_build_sprite_variants()
	var parts: Array = model.actor_field(index, "visual_parts", [])
	for part_index: int in parts.size():
		if parts[part_index] is Dictionary:
			_build_part(part_index, parts[part_index])
	var add := Button.new()
	add.text = "添加视觉部件"
	add.pressed.connect(add_part)
	add_child(add)
	var advanced_children := get_children().slice(advanced_start)
	var advanced := VBoxContainer.new()
	advanced.name = "AdvancedAppearance"
	advanced.visible = false
	for child: Node in advanced_children:
		remove_child(child)
		advanced.add_child(child)
	var toggle := Button.new()
	toggle.name = "AdvancedAppearanceToggle"
	toggle.text = "更多外观（贴图状态与部件）"
	toggle.toggle_mode = true
	toggle.toggled.connect(func(expanded: bool) -> void: advanced.visible = expanded)
	add_child(toggle)
	add_child(advanced)


func _build_texture_size() -> void:
	var section := VBoxContainer.new()
	section.name = "TextureSize"
	section.add_child(_text("贴图位置与大小（地图单位）"))
	var position_row := HFlowContainer.new()
	_texture_x = _geometry_field(position_row, "X", 0)
	_texture_x.name = "TextureX"
	_texture_y = _geometry_field(position_row, "Y", 1)
	_texture_y.name = "TextureY"
	section.add_child(position_row)
	var row := HFlowContainer.new()
	_texture_width = _geometry_field(row, "宽", 2)
	_texture_width.name = "TextureWidth"
	_texture_height = _geometry_field(row, "高", 3)
	_texture_height.name = "TextureHeight"
	_sync_texture_fields()
	section.add_child(row)
	_texture_aspect_lock = CheckBox.new()
	_texture_aspect_lock.name = "TextureAspectLock"
	_texture_aspect_lock.text = "锁定贴图宽高比例"
	_texture_aspect_lock.button_pressed = true
	_texture_aspect_lock.tooltip_text = "开启时修改宽或高会等比调整另一边；关闭后可分别拉伸。交互区和碰撞不变。"
	section.add_child(_texture_aspect_lock)
	var restore := Button.new()
	restore.text = "恢复背景 1:1"
	restore.name = "RestoreTextureSize"
	restore.tooltip_text = "按主贴图像素与地图背景图比例恢复大小；交互区和碰撞保持不变。"
	restore.disabled = _source_texture_size().is_zero_approx() or selection.size() != 1
	restore.pressed.connect(_restore_texture_size)
	section.add_child(restore)
	add_child(section)
	if selection.size() != 1:
		for field: SpinBox in [_texture_x, _texture_y, _texture_width, _texture_height]:
			field.editable = false
			field.tooltip_text = "精确位置和尺寸需单选一件物件。"
		_texture_aspect_lock.disabled = true


func _geometry_field(parent: Control, caption: String, component: int) -> SpinBox:
	parent.add_child(_text(caption))
	var field := SpinBox.new()
	field.min_value = 0.01 if component >= 2 else -100000
	field.max_value = 100000
	field.step = 0.01
	field.update_on_text_changed = false
	field.custom_minimum_size.x = 100
	field.value_changed.connect(_on_texture_geometry_changed.bind(component))
	parent.add_child(field)
	return field


func _on_texture_geometry_changed(_value: float, component: int) -> void:
	if selection.size() != 1 or _texture_width == null or _texture_height == null:
		return
	var previous := Transform.rect_from(model.actor_field(actor_index, "rect", []))
	var size := Vector2(_texture_width.value, _texture_height.value)
	if _texture_aspect_lock != null and _texture_aspect_lock.button_pressed and previous.has_area():
		if component == 2:
			size.y = size.x * previous.size.y / previous.size.x
		elif component == 3:
			size.x = size.y * previous.size.x / previous.size.y
	var target := Rect2(Vector2(_texture_x.value, _texture_y.value), size)
	_apply_texture_rect(target)


func _sync_texture_fields() -> void:
	var rect := Transform.rect_from(model.actor_field(actor_index, "rect", []))
	_texture_x.set_value_no_signal(rect.position.x)
	_texture_y.set_value_no_signal(rect.position.y)
	_texture_width.set_value_no_signal(rect.size.x)
	_texture_height.set_value_no_signal(rect.size.y)
	var parts: Array = model.actor_field(actor_index, "visual_parts", [])
	for part_index: Variant in _part_geometry_fields:
		if int(part_index) >= parts.size() or not parts[part_index] is Dictionary:
			continue
		var part: Dictionary = parts[part_index]
		var values: Array = part.get("rect", [0, 0, 1, 1])
		var fields: Array = _part_geometry_fields[part_index]
		for component: int in fields.size():
			(fields[component] as SpinBox).set_value_no_signal(float(values[component]))
		if _part_offset_fields.has(part_index):
			(_part_offset_fields[part_index] as SpinBox).set_value_no_signal(float(part.get("sort_offset", 0)))


func sync_tool(which: int) -> void:
	if _texture_tool_button != null:
		_texture_tool_button.set_pressed_no_signal(which == Canvas.Tool.TEXTURE)


func _restore_texture_size() -> void:
	var size := _source_texture_size()
	if size.is_zero_approx():
		return
	if int(model.actor_field(actor_index, "quarter_turns", 0)) % 2 != 0:
		size = Vector2(size.y, size.x)
	_apply_texture_size(size)


func _source_texture_size() -> Vector2:
	var actor := MapDef._actor_from(model.actor_dict(actor_index))
	for path: String in actor.visual_sprites():
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		if path.begins_with("res://"):
			var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
			if texture != null:
				return model.world_size_for_image(texture.get_size())
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			continue
		return model.world_size_for_image(Vector2(image.get_size()))
	return Vector2.ZERO


func _apply_texture_size(size: Vector2) -> bool:
	if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0:
		return false
	var rect := Transform.rect_from(model.actor_field(actor_index, "rect", []))
	return _apply_texture_rect(Rect2(rect.position, size))


func _apply_texture_rect(target: Rect2) -> bool:
	var updated := Transform.resized_actor(model.actor_dict(actor_index), target)
	if not Transform.write_actor(model, actor_index, updated):
		_sync_texture_fields()
		return false
	_sync_texture_fields()
	edited.emit()
	return true


func _build_sprite_variants() -> void:
	var section := VBoxContainer.new()
	section.add_child(_text("同一物件的贴图状态"))
	var variants: Variant = model.actor_field(actor_index, "sprite_variants", {})
	if not variants is Dictionary:
		variants = {}
	var keys: Array = variants.keys()
	keys.sort()
	var default_row := HFlowContainer.new()
	default_row.add_child(_text("默认贴图"))
	var default_picker := OptionButton.new()
	default_picker.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	default_picker.add_item("基础贴图")
	for variant_id: Variant in keys:
		default_picker.add_item(str(variant_id))
	var active := str(model.actor_field(actor_index, "sprite_variant", ""))
	default_picker.select(0 if active.is_empty() else maxi(keys.find(active) + 1, 0))
	default_picker.item_selected.connect(func(option: int) -> void:
		set_default_sprite_variant("" if option == 0 else str(keys[option - 1])))
	default_row.add_child(default_picker)
	section.add_child(default_row)
	for variant_id: Variant in keys:
		_add_sprite_variant_row(section, str(variant_id), str(variants[variant_id]))
	var add_row := HFlowContainer.new()
	_variant_id_input = LineEdit.new()
	_variant_id_input.placeholder_text = "变体 ID"
	_variant_id_input.custom_minimum_size.x = 90
	add_row.add_child(_variant_id_input)
	_variant_path_input = LineEdit.new()
	_variant_path_input.placeholder_text = "res:// 贴图路径"
	_variant_path_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_variant_path_input)
	var add := Button.new()
	add.text = "添加变体"
	add.pressed.connect(func() -> void:
		if add_sprite_variant(_variant_id_input.text, _variant_path_input.text):
			rebuild_requested.emit())
	add_row.add_child(add)
	section.add_child(add_row)
	add_child(section)


func _text(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label


func _add_sprite_variant_row(parent: Control, variant_id: String, sprite_path: String) -> void:
	var row := HFlowContainer.new()
	var identity := LineEdit.new()
	identity.text = variant_id
	identity.custom_minimum_size.x = 90
	row.add_child(identity)
	var texture := LineEdit.new()
	texture.text = sprite_path
	texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texture)
	var apply := Button.new()
	apply.text = "应用"
	apply.pressed.connect(func() -> void:
		if update_sprite_variant(variant_id, identity.text, texture.text):
			rebuild_requested.emit())
	row.add_child(apply)
	var remove := Button.new()
	remove.text = "删除"
	remove.pressed.connect(func() -> void:
		if remove_sprite_variant(variant_id):
			rebuild_requested.emit())
	row.add_child(remove)
	parent.add_child(row)


func add_sprite_variant(variant_id: String, sprite_path: String) -> bool:
	var variants: Dictionary = model.actor_field(actor_index, "sprite_variants", {}).duplicate(true)
	var key := variant_id.strip_edges()
	var path := sprite_path.strip_edges()
	if key.is_empty() or variants.has(key) or not _valid_sprite_path(path):
		return false
	variants[key] = path
	model.set_actor_field(actor_index, "sprite_variants", variants)
	if str(model.actor_field(actor_index, "sprite_variant", "")).is_empty():
		model.set_actor_field(actor_index, "sprite_variant", key)
	edited.emit()
	return true


func update_sprite_variant(old_id: String, new_id: String, sprite_path: String) -> bool:
	var variants: Dictionary = model.actor_field(actor_index, "sprite_variants", {}).duplicate(true)
	var old_key := old_id.strip_edges()
	var new_key := new_id.strip_edges()
	var path := sprite_path.strip_edges()
	if not variants.has(old_key) or new_key.is_empty() \
			or (new_key != old_key and variants.has(new_key)) or not _valid_sprite_path(path):
		return false
	variants.erase(old_key)
	variants[new_key] = path
	model.set_actor_field(actor_index, "sprite_variants", variants)
	if str(model.actor_field(actor_index, "sprite_variant", "")) == old_key:
		model.set_actor_field(actor_index, "sprite_variant", new_key)
	edited.emit()
	return true


func remove_sprite_variant(variant_id: String) -> bool:
	var variants: Dictionary = model.actor_field(actor_index, "sprite_variants", {}).duplicate(true)
	var key := variant_id.strip_edges()
	if not variants.has(key):
		return false
	variants.erase(key)
	model.set_actor_field(actor_index, "sprite_variants", variants)
	if str(model.actor_field(actor_index, "sprite_variant", "")) == key:
		model.set_actor_field(actor_index, "sprite_variant", "")
	edited.emit()
	return true


func set_default_sprite_variant(variant_id: String) -> bool:
	var variants: Dictionary = model.actor_field(actor_index, "sprite_variants", {})
	if not variant_id.is_empty() and not variants.has(variant_id):
		return false
	model.set_actor_field(actor_index, "sprite_variant", variant_id)
	edited.emit()
	return true


func _valid_sprite_path(path: String) -> bool:
	return path.begins_with("res://") and FileAccess.file_exists(path)


func _build_part(index: int, part: Dictionary) -> void:
	var box := VBoxContainer.new()
	var row := HFlowContainer.new()
	var identity := LineEdit.new()
	identity.text = str(part.get("id", ""))
	identity.placeholder_text = "部件 ID"
	identity.custom_minimum_size.x = 90
	identity.text_submitted.connect(func(text: String) -> void: set_part(index, "id", text))
	row.add_child(identity)
	var layer := OptionButton.new()
	layer.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for text: String in ["固定后层", "按基线遮挡", "固定前层"]:
		layer.add_item(text)
	layer.select(maxi(LAYERS.find(str(part.get("layer", "auto"))), 0))
	layer.item_selected.connect(func(value: int) -> void: set_part(index, "layer", LAYERS[value]))
	row.add_child(layer)
	var remove := Button.new()
	remove.text = "删除部件"
	remove.pressed.connect(remove_part.bind(index))
	row.add_child(remove)
	box.add_child(row)
	var texture := LineEdit.new()
	texture.text = str(part.get("sprite", ""))
	texture.placeholder_text = "res:// 贴图路径（Enter 应用）"
	texture.text_submitted.connect(func(text: String) -> void: set_part(index, "sprite", text))
	box.add_child(texture)
	var geometry := HFlowContainer.new()
	var rect: Array = part.get("rect", [0, 0, 1, 1])
	var fields: Array[SpinBox] = []
	for component: int in 4:
		var label := Label.new()
		label.text = ["x", "y", "宽", "高"][component]
		geometry.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = -100000
		spin.max_value = 100000
		spin.step = 0.1
		spin.value = float(rect[component])
		spin.custom_minimum_size.x = 80
		spin.value_changed.connect(func(value: float) -> void:
			var updated: Array = model.actor_field(actor_index, "visual_parts", [])[index].get("rect").duplicate()
			updated[component] = value
			set_part(index, "rect", updated))
		geometry.add_child(spin)
		fields.append(spin)
	_part_geometry_fields[index] = fields
	box.add_child(geometry)
	var baseline := HBoxContainer.new()
	var baseline_label := Label.new()
	baseline_label.text = "遮挡基线偏移"
	baseline.add_child(baseline_label)
	var offset := SpinBox.new()
	offset.min_value = -100000
	offset.max_value = 100000
	offset.step = 0.1
	offset.value = float(part.get("sort_offset", 0))
	offset.value_changed.connect(func(value: float) -> void: set_part(index, "sort_offset", value))
	baseline.add_child(offset)
	_part_offset_fields[index] = offset
	box.add_child(baseline)
	add_child(box)


func set_part(index: int, field: String, value: Variant) -> bool:
	var parts: Array = model.actor_field(actor_index, "visual_parts", []).duplicate(true)
	if index < 0 or index >= parts.size():
		return false
	if field == "rect" and (not value is Array or value.size() != 4 or float(value[2]) <= 0 or float(value[3]) <= 0):
		return false
	parts[index][field] = value
	model.set_actor_field(actor_index, "visual_parts", parts)
	edited.emit()
	return true


func add_part() -> void:
	var parts: Array = model.actor_field(actor_index, "visual_parts", []).duplicate(true)
	var rect: Array = model.actor_field(actor_index, "rect", [0, 0, 1, 1])
	var number := parts.size() + 1
	while parts.any(func(part: Variant) -> bool: return part is Dictionary and str(part.get("id", "")) == "part_%d" % number):
		number += 1
	parts.append({"id": "part_%d" % number, "sprite": model.actor_field(actor_index, "sprite", ""),
		"rect": [0, 0, rect[2], rect[3]], "layer": "auto"})
	model.set_actor_field(actor_index, "visual_parts", parts)
	edited.emit()
	rebuild_requested.emit()


func remove_part(index: int) -> void:
	var parts: Array = model.actor_field(actor_index, "visual_parts", []).duplicate(true)
	if index < 0 or index >= parts.size():
		return
	parts.remove_at(index)
	if parts.is_empty():
		model.erase_actor_field(actor_index, "visual_parts")
	else:
		model.set_actor_field(actor_index, "visual_parts", parts)
	edited.emit()
	rebuild_requested.emit()


func _transform(operation: String, value: Variant = null) -> void:
	if Transform.apply(model, selection, operation, value, false):
		_sync_texture_fields()
		edited.emit()
