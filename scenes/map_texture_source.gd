## 将同源缩略切片映射回高清图集，并解析单独登记的像素重绘背景。
##
## 清单使用原纹理的精确裁切位置，不从物件当前位置反推；挪动、翻转、旋转和遮挡
## 继续由 MapView 决定。本层只解析纹理，不改地图、节点、材质或 PNG。
##
## 加条目先确认同源和原始尺寸。源图缺失、尺寸变化或区域越界时保留原纹理，
## 只缓存成功的 AtlasTexture；不能让一次失败污染后续加载。
extends RefCounted

const MARKET_DAY := "res://art/map/market_overlay.png"
const MARKET_NIGHT := "res://art/map/market_night_overlay.png"
const MARKET_SIZE := Vector2i(6688, 3764)
## 像素重绘保留旧图作回退；世界尺寸仍由地图决定，绝不改动交互或碰撞坐标。
const PIXEL_REPAINTS := {
	"res://art/background/chapter2_dead_alley.png": {
		"source_path": "res://art/background/chapter2_dead_alley_pixel_20261024.png",
		"old_size": Vector2i(4608, 3072), "source_size": Vector2i(1536, 1024),
		"region": Rect2i(0, 0, 1536, 1024)},
}
## region 均为高清原图像素；旧切片来自 1672×941 透明图的精确裁切，坐标乘 4。
const MANIFEST := {
	"res://art/props/market_day_building_left.png": {"source_path": MARKET_DAY,
		"old_size": Vector2i(786, 426), "source_size": MARKET_SIZE, "region": Rect2i(0, 1096, 3144, 1704)},
	"res://art/props/market_day_building_right.png": {"source_path": MARKET_DAY,
		"old_size": Vector2i(774, 382), "source_size": MARKET_SIZE, "region": Rect2i(3592, 1272, 3096, 1528)},
	"res://art/props/market_day_bottom_wall.png": {"source_path": MARKET_DAY,
		"old_size": Vector2i(1672, 241), "source_size": MARKET_SIZE, "region": Rect2i(0, 2800, 6688, 964)},
	"res://art/props/market_day_stall_white.png": {"source_path": MARKET_DAY,
		"old_size": Vector2i(310, 231), "source_size": MARKET_SIZE, "region": Rect2i(776, 784, 1240, 924)},
	"res://art/props/market_day_stall_red.png": {"source_path": MARKET_DAY,
		"old_size": Vector2i(260, 215), "source_size": MARKET_SIZE, "region": Rect2i(3864, 848, 1040, 860)},
	"res://art/props/market_day_stall_purple.png": {"source_path": MARKET_DAY,
		"old_size": Vector2i(289, 234), "source_size": MARKET_SIZE, "region": Rect2i(5016, 824, 1156, 936)},
	"res://art/props/market_day_fountain.png": {"source_path": MARKET_DAY,
		"old_size": Vector2i(254, 222), "source_size": MARKET_SIZE, "region": Rect2i(2832, 1812, 1016, 888)},
	"res://art/props/market_night_building_left.png": {"source_path": MARKET_NIGHT,
		"old_size": Vector2i(786, 426), "source_size": MARKET_SIZE, "region": Rect2i(0, 1096, 3144, 1704)},
	"res://art/props/market_night_building_right.png": {"source_path": MARKET_NIGHT,
		"old_size": Vector2i(774, 382), "source_size": MARKET_SIZE, "region": Rect2i(3592, 1272, 3096, 1528)},
	"res://art/props/market_night_bottom_wall.png": {"source_path": MARKET_NIGHT,
		"old_size": Vector2i(1672, 241), "source_size": MARKET_SIZE, "region": Rect2i(0, 2800, 6688, 964)},
	"res://art/props/market_night_stall_white.png": {"source_path": MARKET_NIGHT,
		"old_size": Vector2i(310, 231), "source_size": MARKET_SIZE, "region": Rect2i(776, 784, 1240, 924)},
	"res://art/props/market_night_stall_red.png": {"source_path": MARKET_NIGHT,
		"old_size": Vector2i(260, 215), "source_size": MARKET_SIZE, "region": Rect2i(3864, 848, 1040, 860)},
	"res://art/props/market_night_stall_purple.png": {"source_path": MARKET_NIGHT,
		"old_size": Vector2i(289, 234), "source_size": MARKET_SIZE, "region": Rect2i(5016, 824, 1156, 936)},
	"res://art/props/market_night_fountain.png": {"source_path": MARKET_NIGHT,
		"old_size": Vector2i(254, 222), "source_size": MARKET_SIZE, "region": Rect2i(2832, 1812, 1016, 888)},
}

static var _cache: Dictionary = {}


static func resolve(path: String, original: Texture2D) -> Texture2D:
	if original != null and PIXEL_REPAINTS.has(path):
		var repaint: Dictionary = PIXEL_REPAINTS[path]
		if original.get_size() == Vector2(repaint.old_size):
			var source := _load_source(repaint)
			if source != null:
				return source
	if original == null or not MANIFEST.has(path):
		return original
	var entry: Dictionary = MANIFEST[path]
	if original.get_size() != Vector2(entry.old_size):
		return original
	var source := _load_source(entry)
	if source == null:
		return original
	if _cache.has(path):
		var cached := _cache[path] as AtlasTexture
		if cached.atlas == source and cached.region == Rect2(entry.region):
			return cached
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(entry.region)
	atlas.filter_clip = true
	_cache[path] = atlas
	return atlas


static func _load_source(entry: Dictionary) -> Texture2D:
	var path := str(entry.get("source_path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource: Resource = ResourceLoader.load(path)
	if not (resource is Texture2D):
		return null
	var source := resource as Texture2D
	var expected := Vector2(entry.get("source_size", Vector2i.ZERO))
	var region := Rect2(entry.get("region", Rect2i()))
	if source.get_size() != expected or not region.has_area() \
			or not Rect2(Vector2.ZERO, expected).encloses(region):
		return null
	return source
