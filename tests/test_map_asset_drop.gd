extends RefCounted

const Model := preload("res://addons/if_map_editor/map_edit_model.gd")
const Canvas := preload("res://addons/if_map_editor/map_edit_canvas.gd")
const AssetList := preload("res://addons/if_map_editor/map_asset_list.gd")


static func run(harness: TestHarness) -> void:
	var model := Model.new()
	model.data = {"size": [467, 374], "background": "res://art/map/library.png",
		"walls": [], "portals": [], "actors": [], "spawns": {}}
	var canvas := Canvas.new()
	canvas.model = model
	canvas.map_size = model.map_size()
	var path := "res://art/props/library_shelf_a_cover.png"
	var background := Image.load_from_file(str(model.data["background"]))
	var source := Image.load_from_file(path)
	var expected := Vector2(source.get_size()) * model.map_size() / Vector2(background.get_size())
	var payload := {"type": "if_map_asset", "path": path}
	var assets := AssetList.new()
	assets.canvas = canvas
	var texture := load(path) as Texture2D
	for scale_factor: float in [0.5, 2.0, 4.0]:
		canvas.zoom = scale_factor
		canvas.pan = Vector2(35, 22)
		var point := canvas.to_screen(Vector2(210, 160))
		var preview := assets.make_drag_preview(path, texture)
		var sprite := preview.get_child(0) as TextureRect
		harness.check("缩放 %.1f 拖动预览与落地尺寸一致" % scale_factor,
			sprite.size.is_equal_approx(expected * scale_factor), true)
		harness.check("拖动预览与落地采用相同居中点", sprite.position, -sprite.size * 0.5)
		harness.check("预览保持矩形比例并忽略源图最小尺寸", sprite.expand_mode, TextureRect.EXPAND_IGNORE_SIZE)
		preview.free()
		harness.check("缩放 %.1f 允许拖入有效素材" % scale_factor, canvas._can_drop_data(point, payload), true)
		canvas._drop_data(point, payload)
		var rect: Rect2 = model.rect_of(Model.Kind.ACTOR, canvas.sel_index)
		harness.check("缩放 %.1f 后尺寸仍对应背景原图像素" % scale_factor,
			rect.size.is_equal_approx(expected), true)
		harness.check("缩放 %.1f 拖入后围绕落点居中" % scale_factor,
			(rect.get_center() - Vector2(210, 160)).length() <= 1.0, true)
		harness.check("画布选中新创建的物件", canvas.selected_actors(), [canvas.sel_index])
	harness.check("三个缩放级别各创建一件", model.count(Model.Kind.ACTOR), 3)
	harness.check("落在地图外不接收素材", canvas._can_drop_data(canvas.to_screen(Vector2(-10, -10)), payload), false)
	canvas.tool = Canvas.Tool.COLLISION
	harness.check("画物件碰撞时不会误放素材", canvas._can_drop_data(canvas.to_screen(Vector2(100, 100)), payload), false)
	canvas.free()
	assets.free()
