## 把一个 MapDef 变成看得见、撞得到的节点树。
##
## 占位阶段的做法：地面、墙、传送点全用纯色多边形拼出来。
## 等美术资源到位，把这个文件换成 TileMapLayer 实现就行，
## MapDef 的数据格式和 Player 的移动逻辑都不受影响。
##
## 这一层是**唯一**允许把地图数据翻译成画面的地方。别的地方不该知道
## 「墙长什么样」，只该知道「这里有面墙」。
class_name MapView
extends Node2D

const TextureSource := preload("res://scenes/map_texture_source.gd")

const FLOOR_COLOR := Color("#1b1d23")
const WALL_COLOR := Color("#3a3f4b")
const PORTAL_COLOR := Color("#4e7a52")
## 大地图底色，比室内亮一点，一眼能看出「这是外面」
const OVERWORLD_COLOR := Color("#232a24")
## 大地图上的地点按钮，以及鼠标悬停时的样子
const PLACE_COLOR := Color("#4e7a52")
const PLACE_HOVER_COLOR := Color("#7fae82")
## 地点贴图悬停时的提亮色（乘算，比 1 大就是变亮）
const PLACE_HOVER_TINT := Color(1.25, 1.25, 1.2)
## 大地图上地点名那块底
const PLACE_LABEL_BG := Color(0.06, 0.08, 0.12, 0.72)
const PLACE_LABEL_COLOR := Color("#f2ead6")

## 地点方块：**自己画的，不用位图素材**。
##
## 地点那个框：**画的，不贴图**。
##
## 素材包那张「悬浮框」是 1048x568 的，而地图标记只有一百来个游戏单位 ——
## 缩十倍之后四角那 96 像素的切角只剩九个像素，框就散了。
## 这不是参数没调好，是**方法**不对：位图缩到那个比例，怎么调都是糊的。
## 所以照它的样式画。颜色照素材包 README 抄。
const FRAME_FILL := Color(8.0 / 255.0, 22.0 / 255.0, 55.0 / 255.0, 0.88)
const EDGE_IDLE := Color(196.0 / 255.0, 208.0 / 255.0, 232.0 / 255.0)
const EDGE_HOVER := Color(1.0, 0.99, 0.94)
## 未开放的框压暗、压透，一眼看得出「这个还去不了」
const EDGE_LOCKED := Color(108.0 / 255.0, 118.0 / 255.0, 138.0 / 255.0, 0.72)
const ACCENT_EDGE := Color(1.0, 185.0 / 255.0, 232.0 / 255.0)
## 切角占框宽的比例。素材是 52/960 ≈ 5.4%，这里放宽一点 ——
## 框小，照原比例切角就看不出是切角了。
const CUT_RATIO := 0.17
## 名字字号，和框内上下左右的留白。
const NAME_FONT := 9.0
const BOX_PAD := Vector2(7.0, 5.0)
## 详情展开框：在名字框**下面**往下长。横向宽度固定，好让文字换行。
const DETAIL_W := 118.0
const DETAIL_FONT := 8.0
const DETAIL_LINE_H := 10.5
const DETAIL_PAD := Vector2(6.0, 5.0)
## 展开的框比名字框实一些 —— 上面压着字，得读得清。
const FRAME_FILL_DEEP := Color(8.0 / 255.0, 22.0 / 255.0, 55.0 / 255.0, 0.97)
const DETAIL_COLOR := Color(205.0 / 255.0, 212.0 / 255.0, 230.0 / 255.0)
## 名字的三种颜色：常态、悬停、未开放（压暗一档）。
const NAME_COLOR := Color("#eef4ff")
const HOVER_NAME_COLOR := Color("#fff8e6")
const LOCKED_NAME_COLOR := Color(0.72, 0.76, 0.84, 0.9)
## 地点框和名字的层：压在地图插画上面（背景图是 -20），但在文字层下面。
const PLACE_Z := 5
## 特殊地点的强调色。素材包 README 里「异界裂缝」的标题是粉的。
const ACCENT_COLOR := Color("#ffb9e8")

## 大地图左上角的标题、副题，和底部那行操作提示。
##
## 照策划那份互动示意的版式抄的。**字号比示意放大了几档** ——
## 那个示意是 1920 宽的，按比例换到 320 宽的视口只剩六七像素，
## 中文那个大小认不出来。
const TITLE_TEXT := "迷雾城 · 旧港区"
const SUBTITLE := "在这个看似平凡的小镇里，\n藏着不为人知的「如果」"
const HINT_TEXT := "点击名称前往　未开放的地点还在修建中"
## 地图内的文字层：压在地点框上面，但在任何菜单下面。
const TEXT_Z := 20
## NPC 与可调查物件
const ACTOR_COLOR := Color("#c96a5a")
## 占位方块的外框，让色块的边界看得出来
const BLOCK_EDGE := Color(0.06, 0.07, 0.10, 0.85)
## 占位方块上的名字
const LABEL_COLOR := Color("#e8e8e8")
## 场景还没有背景图时，铺在底色中央的那行字
const TITLE_COLOR := Color(0.78, 0.80, 0.86, 0.55)

## 兜底边界墙的厚度。数据里没画满边界时，靠它拦住角色。
const BORDER_THICKNESS := 32.0

## 场景里的物件画在第几层。角色是 10（见 `Player.create()`）。
const PROP_Z := 5
## 会挡人的家具（`MapDef.Actor.cover`）在「人在它后面」时升到这一层，
## 盖住角色的下半身。**必须大于角色的 10。**
const COVER_Z := 11
## **永远盖住角色**的物件（`MapDef.Actor.over`）用的层级。
##
## 和 `COVER_Z` 分开是为了以后能调 —— 「按站位挡」和「一直挡」是两件事，
## 现在都压着角色，但谁高谁低将来可能有别的意图。
const OVER_Z := 12

## 前景遮挡层（`MapDef.overlay`）的层级。**比 `OVER_Z` 还高** ——
## 它是整张盖住画面的那种，不是一件家具。角色是 10，所以这一层之下
## 所有东西都被它按图上的形状切掉。
const OVERLAY_Z := 13

var map_def: MapDef = null
## 当前的世界状态。用来判断哪些角色和连接「现在存在」。
## 为 null 表示全部显示（预览场景时用）。
var _flags: WorldState = null
var _built: Node2D = null
## 大地图上 地点 id -> 色块节点。鼠标悬停时靠它改颜色。
var _place_nodes: Dictionary = {}
## 大地图上的地点。方块是 `_draw()` 画的（不能存节点），所以除了名字标签，
## 还得把中心点和状态记下来。
var _places: Array[Dictionary] = []
var _hovered: StringName = &""
## 现在展开着详情的地点。空 = 没展开。
var _detail_for: StringName = &""
## 详情那块文字。只用一个，换地点时改内容。
var _detail: Label = null
## 会挡人的家具：`[{"node": Sprite2D, "cover_y": float}]`。
## 它们的层级随角色站的位置变，见 `set_player_y()`。
var _covers: Array[Dictionary] = []
## 这张地图有没有插画。有的话，家具、墙、门都不再画色块。
var _has_picture := false


## 地图插画、前景和物件共用像素采样；构造时设置也覆盖编辑器试走子类。
func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## 重建整个场景。切换场景、或者世界状态变了之后调用。
## 会先清掉上一次的内容。
func build(p_map_def: MapDef, flags: WorldState = null) -> void:
	map_def = p_map_def
	_flags = flags
	clear()

	_built = Node2D.new()
	_built.name = "Built"
	add_child(_built)

	# 大地图不建墙，也没有可操控的角色，只有可点击的地点
	if map_def.kind == MapDef.Kind.OVERWORLD:
		_build_overworld()
		return

	_build_room()


## 室内：背景图 + 连接标记 + 角色，并且建碰撞。
##
## 贴了插画之后，**墙、地面、家具都不再画** —— 插画上本来就画着它们。
## 碰撞照旧建，玩家撞在看不见的边界上；看得见的那道墙是画出来的。
##
## 家具也只在**背景上没画它**的时候才贴图（书桌、那盏提灯）。
## 从插画上切一份再贴回去是重复画两遍，而且贴图会盖住角色 ——
## 站在家具旁边的人被切成一条，就是这么来的（开发纪要 36）。
func _build_room() -> void:
	_has_picture = _add_background()
	if not _has_picture:
		_add_rect(Rect2(Vector2.ZERO, Vector2(map_def.size)), FLOOR_COLOR, -10)
		_add_scene_title()

	for portal: MapDef.Portal in map_def.active_portals(_flags):
		if _add_prop(portal.sprite, portal.rect, -5) != null:
			continue
		# 没贴图又没插画时才画绿块；有插画就看画，别在门上糊一块绿
		if not _has_picture:
			_add_rect(portal.rect, PORTAL_COLOR, -5)

	for wall: Rect2 in map_def.walls:
		if not _has_picture:
			_add_rect(wall, WALL_COLOR, 0)
	for actor: MapDef.Actor in map_def.active_actors(_flags):
		# 画在墙之上，不然站在墙前面会被挡住
		_add_actor(actor)

	_build_wall_collision()
	_build_actor_collision()
	_add_overlay()


## 还没有背景图时，把场景名字淡淡地铺在中间。
##
## 玩家认得出自己在哪，也不会把「没画完」当成「渲染坏了」。
func _add_scene_title() -> void:
	if map_def.name == "":
		return
	var label := Label.new()
	label.text = map_def.name
	label.size = Vector2(map_def.size.x, 14.0)
	label.position = Vector2(0.0, map_def.size.y * 0.5 - 7.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", TITLE_COLOR)
	label.z_index = -9
	_built.add_child(label)


## 场景里的一个人或一件东西。
##
## **只有插画上没画的东西才需要贴图**：不在背景图里的独立素材（书桌），
## 或者要从背景里单个拎出来的（卧室门口那盏提灯）。
## 其余家具插画上都有，`sprite` 留空 —— 这里就什么都不画。
func _add_actor(actor: MapDef.Actor) -> void:
	var rectangles := actor.world_visual_rects()
	var sprites := actor.visual_sprites()
	var layers := actor.visual_layers()
	var baselines := actor.visual_cover_ys()
	var drawn := false
	for index: int in rectangles.size():
		var node := _add_prop(sprites[index], rectangles[index], PROP_Z)
		if node == null:
			continue
		drawn = true
		node.transform = actor.visual_texture_transform(index, node.texture.get_size())
		if layers[index] == "front":
			node.z_index = OVER_Z
		elif layers[index] == "auto":
			_covers.append({"node": node, "cover_y": baselines[index]})
	if drawn or not actor.visual_parts.is_empty():
		return

	# 没有贴图。插画上画着它，所以**什么都不画** ——
	# 再补一块色块和名字，等于在画好的家具上糊一层。
	if _has_picture:
		return

	# 兜底那条路：这张地图还没有插画，那就画色块 + 名字，
	# 至少让人看得出「这里能交互」。
	var poly := _add_rect(actor.rect, ACTOR_COLOR, PROP_Z)
	if poly != null:
		_add_outline(actor.rect)
	_add_actor_label(actor.rect, actor.label)


## 角色站到哪儿了。会挡人的家具靠它决定画在角色上面还是下面。
##
## **为什么不交给引擎的 y 排序**：角色不在 `_built` 底下（它是 main 的
## 子节点，换场景时要留着），而 y-sort 只在同一个父节点的孩子之间起作用。
## 所以这里自己比。房间里这类家具通常只有一件，每帧读一个 y 的开销可以忽略。
func set_player_y(y: float) -> void:
	if _covers.is_empty():
		return
	for item: Dictionary in _covers:
		var node: Node2D = item["node"]
		if not is_instance_valid(node):
			continue
		# 人在家具后面（脚更靠北）→ 家具盖住人；人在前面 → 人盖住家具
		node.z_index = COVER_Z if y < float(item["cover_y"]) else PROP_Z


## 场上会挡人的家具数量。测试用。
## 当前这一层前景遮挡图的节点。没挂就是 null。测试与调试用。
##
## **只能从 `_built` 底下找。** `clear()` 用的是 `queue_free()`（帧末才真删），
## 而测试里没有帧循环 —— 直接 `find_child` 会摸到上一个场景留下的那一层，
## 量出来的尺寸是上一张地图的。
func overlay_node() -> Sprite2D:
	if _built == null or not is_instance_valid(_built):
		return null
	return _built.get_node_or_null("Overlay") as Sprite2D


func cover_count() -> int:
	return _covers.size()


## 第 `index` 件遮挡家具**当前**的层级。
##
## 层级随角色站的位置变，看一眼场景是查不出来的 —— 测试靠这条守
## 「人在桌后被挡住、人在桌前挡住桌子」。
func cover_z(index: int) -> int:
	if index < 0 or index >= _covers.size():
		return 0
	var node: Node2D = _covers[index]["node"]
	return node.z_index if is_instance_valid(node) else 0


## 贴一块物件贴图，按 `rect` 的大小缩放着放上去。
##
## 贴图是从地图插画里切下来的，所以「画上的桌子」和「能交互的桌子」
## 是同一块像素 —— 玩家看到什么，就能点什么。
## 路径为空或者图不在了返回 null，让调用方回退到占位画法。
func _add_prop(path: String, rect: Rect2, z: int) -> Sprite2D:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		push_warning("[地图] 找不到物件贴图：%s" % path)
		return null
	var texture: Resource = load(path)
	if not (texture is Texture2D):
		push_warning("[地图] 物件贴图不是图片：%s" % path)
		return null

	var image: Texture2D = TextureSource.resolve(path, texture)
	var sprite := Sprite2D.new()
	sprite.texture = image
	sprite.centered = false
	sprite.position = rect.position
	sprite.z_index = z

	var picture := image.get_size()
	if picture.x > 0.0 and picture.y > 0.0 \
			and rect.size.x > 0.0 and rect.size.y > 0.0:
		sprite.scale = Vector2(rect.size.x / picture.x, rect.size.y / picture.y)

	_built.add_child(sprite)
	return sprite


## 一圈描边。靠外再画一圈稍大的深色多边形压在下面。
func _add_outline(rect: Rect2) -> void:
	var grow := 1.0
	var outer := Rect2(rect.position - Vector2(grow, grow),
		rect.size + Vector2(grow, grow) * 2.0)
	_add_rect(outer, BLOCK_EDGE, 4)


## 物件头顶的名字。字比物件宽的时候就让它溢出，**不许砍字** ——
## 玩家得看得清这是什么；挤在一起是布局的问题，那是摆位置的活。
func _add_actor_label(rect: Rect2, text: String) -> void:
	if text == "":
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", LABEL_COLOR)

	var width := maxf(rect.size.x, 40.0)
	label.size = Vector2(width, 11.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 贴着上沿摆放；太靠顶（会被地图边界切掉）就翻到底下
	var y := rect.position.y - 11.0
	if rect.position.y < 14.0:
		y = rect.position.y + rect.size.y + 1.0
	label.position = Vector2(rect.position.x + rect.size.x * 0.5 - width * 0.5, y)
	label.z_index = 6
	_built.add_child(label)


## 大地图：一整张背景图（没有就铺底色）+ 若干可点选的地点
func _build_overworld() -> void:
	# **这个赋值不能漏。** 它原来只在 `_build_room` 里设，
	# 而大地图走的是另一条路（`build` 里 OVERWORLD 直接 return）——
	# 于是大地图上 `_has_picture` 永远是 false，地点全被铺成绿块
	# （2026-09-24 换新图时看到的：四块绿方块糊在教堂、集市、委托店、白塔上）。
	_has_picture = _add_background()
	if not _has_picture:
		_add_rect(Rect2(Vector2.ZERO, Vector2(map_def.size)), OVERWORLD_COLOR, -10)

	for portal: MapDef.Portal in map_def.active_portals(_flags):
		_add_place(portal)

	_add_overworld_text()


## 大地图左上角的标题、和底部的操作提示。
##
## 版式照策划那份互动示意：标题 + 一句副题。
## 字号比示意里**放大了几档** —— 那个示意是 1920 宽的，按比例换算到
## 320 宽的视口只有六七像素，中文那个大小根本认不出来。
##
## 不铺底色，只给字加深色描边：插画本身够花，铺块底会把画面切碎；
## 描边够把字从背景里拎出来了。
func _add_overworld_text() -> void:
	var title := Label.new()
	title.text = TITLE_TEXT
	title.position = Vector2(14.0, 9.0)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color("#ffffff"))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 4)
	title.z_index = TEXT_Z
	_built.add_child(title)

	var subtitle := Label.new()
	subtitle.text = SUBTITLE
	subtitle.position = Vector2(14.0, 25.0)
	subtitle.add_theme_font_size_override("font_size", 7)
	subtitle.add_theme_color_override("font_color", Color(0.88, 0.92, 0.98, 0.92))
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	subtitle.add_theme_constant_override("outline_size", 3)
	subtitle.z_index = TEXT_Z
	_built.add_child(subtitle)

	var hint := Label.new()
	hint.text = HINT_TEXT
	hint.size = Vector2(map_def.size.x, 12.0)
	hint.position = Vector2(0.0, map_def.size.y - 16.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 7)
	hint.add_theme_color_override("font_color", Color(0.85, 0.89, 0.95, 0.55))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 3)
	hint.z_index = TEXT_Z
	_built.add_child(hint)


## 贴背景图。没有图或者加载失败就返回 false，让调用方铺底色。
func _add_background() -> bool:
	if map_def.background == "":
		return false
	if not ResourceLoader.exists(map_def.background):
		push_warning("[地图] 找不到背景图：%s" % map_def.background)
		return false

	var texture: Resource = load(map_def.background)
	if not (texture is Texture2D):
		push_warning("[地图] 背景不是图片：%s" % map_def.background)
		return false

	var image: Texture2D = texture
	var sprite := Sprite2D.new()
	sprite.name = "Background"
	sprite.texture = image
	sprite.centered = false
	sprite.z_index = -20

	# 按场景大小铺满。**地图 size 必须和这张图成比例**，
	# 不然会被拉变形 —— 数据里的 size 就是「图 × 缩放系数」。
	var area := Vector2(map_def.size)
	var picture := image.get_size()
	if picture.x > 0.0 and picture.y > 0.0:
		sprite.scale = Vector2(area.x / picture.x, area.y / picture.y)
	sprite.position = Vector2.ZERO

	_built.add_child(sprite)
	return true


## 前景遮挡层。一张和背景同尺寸的**扣图**，中间是空的，只留该盖住角色的部分。
##
## **它就是「简单叠加」**：层级压在所有东西（含角色）之上，角色走到那一带自然
## 被图上的围墙／建筑盖住 —— 不用碰碰撞箱，也不用按站位算什么前后。
## **想让人物能站得更靠下，是去把那一带的墙往下挪，不是改这里。**
##
## 图和背景的像素尺寸不一定一样（有的扣图是 1/4 缩略），
## 所以按地图 size 拉齐 —— 和 `_add_background` 同一个算法。
func _add_overlay() -> void:
	if map_def.overlay == "":
		return
	if not ResourceLoader.exists(map_def.overlay):
		push_warning("[地图] 找不到前景层图：%s" % map_def.overlay)
		return
	var texture: Resource = load(map_def.overlay)
	if not (texture is Texture2D):
		push_warning("[地图] 前景层不是图片：%s" % map_def.overlay)
		return

	var image: Texture2D = TextureSource.resolve(map_def.overlay, texture)
	var sprite := Sprite2D.new()
	sprite.name = "Overlay"
	sprite.texture = image
	sprite.centered = false
	sprite.z_index = OVERLAY_Z
	var area := Vector2(map_def.size)
	var picture := image.get_size()
	if picture.x > 0.0 and picture.y > 0.0:
		sprite.scale = Vector2(area.x / picture.x, area.y / picture.y)
	sprite.position = Vector2.ZERO
	_built.add_child(sprite)


## 大地图上的一个地点：**一个框，里面套着地点名**。
##
## 框是 `_draw()` 画的（理由见文件头那几条常量）。名字写在框里、居中。
##
## 框本身可点：悬停换亮描边，点击进去。
func _add_place(portal: MapDef.Portal) -> void:
	var center := portal.rect.get_center()
	var label := Label.new()
	label.text = portal.label
	label.add_theme_font_size_override("font_size", int(NAME_FONT))
	# **框的宽度要问 `Label` 要，不能手算。**
	#
	# 中文一个字的宽度不等于字号 —— 原来拿「字数 x 字号」当宽度，
	# 框比实际文字窄，文字就从左上角往外溢，看着像「越长的越往右下飘」
	# （2026-09-24 策划报的就是这个）。`get_minimum_size()` 在设了 text
	# 和字号之后就能问，那才是真正的排版宽度。
	var need := label.get_minimum_size()
	var box := Rect2(center - (need + BOX_PAD * 2.0) * 0.5, need + BOX_PAD * 2.0)

	label.size = need
	label.position = box.position + BOX_PAD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var base := ACCENT_COLOR if portal.accent \
		else (LOCKED_NAME_COLOR if portal.is_locked() else NAME_COLOR)
	label.add_theme_color_override("font_color", base)
	label.z_index = PLACE_Z + 1
	_built.add_child(label)

	_places.append({
		"id": portal.id, "rect": box, "label": label, "base": base,
		"detail": portal.detail,
		"locked": portal.is_locked(), "accent": portal.accent,
	})


## 在某个地点的**名字框下面**展开详情。传空就收起来。
##
## **不是跟鼠标的浮框。** 策划要的是「详细信息在原本的名称框下面展开」：
## 横向和那个名字框同一列，纵向接在它下沿，往下长。
func show_detail(portal_id: StringName) -> void:
	if _detail_for == portal_id:
		return
	_detail_for = portal_id
	_sync_detail()
	queue_redraw()


## 现在展开的是哪个地点。给测试用。
func detail_for() -> StringName:
	return _detail_for


## 把详情那块文字的内容和位置更新一遍。
func _sync_detail() -> void:
	var place := _find_place(_detail_for)
	if place.is_empty():
		if _detail != null:
			_detail.visible = false
		return
	var box := _detail_box(place)
	if _detail == null:
		_detail = Label.new()
		_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_detail.add_theme_font_size_override("font_size", int(DETAIL_FONT))
		_detail.add_theme_color_override("font_color", DETAIL_COLOR)
		_detail.z_index = PLACE_Z + 2
		_built.add_child(_detail)
	_detail.text = place["detail"]
	_detail.position = box.position + DETAIL_PAD
	_detail.size = box.size - DETAIL_PAD * 2.0
	_detail.visible = true


## 详情框的位置和大小：横向以名字框为中心，纵向接在它下沿。
##
## 高度按**行数估**（中文等宽，拿「每行几个字」除一下就行）——
## `Label` 的 `get_line_count()` 要等一帧排版才准，这里给框画边等不起。
func _detail_box(place: Dictionary) -> Rect2:
	var name_box: Rect2 = place["rect"]
	var text_w := DETAIL_W - DETAIL_PAD.x * 2.0
	var per_line := maxi(1, int(text_w / DETAIL_FONT))
	var text := String(place.get("detail", ""))
	var lines := maxi(1, ceili(float(text.length()) / float(per_line)))
	var h := float(lines) * DETAIL_LINE_H + DETAIL_PAD.y * 2.0
	return Rect2(name_box.get_center().x - DETAIL_W * 0.5, name_box.end.y + 2.0,
		DETAIL_W, h)


## 按 id 找一个地点。找不到返回空字典。
func _find_place(portal_id: StringName) -> Dictionary:
	if portal_id == &"":
		return {}
	for place: Dictionary in _places:
		if StringName(place["id"]) == portal_id:
			return place
	return {}


## 画所有地点框。
func _draw() -> void:
	if map_def == null or map_def.kind != MapDef.Kind.OVERWORLD:
		return
	for place: Dictionary in _places:
		var on: bool = StringName(place["id"]) == _hovered
		var edge := EDGE_LOCKED if place["locked"] else (EDGE_HOVER if on else EDGE_IDLE)
		if place["accent"] and not on:
			edge = ACCENT_EDGE
		_draw_frame(place["rect"], edge, 2.4 if on else 1.5, FRAME_FILL)
	# 展开着的详情**最后画**，压在所有名字框上面
	var opened := _find_place(_detail_for)
	if not opened.is_empty():
		_draw_frame(_detail_box(opened), EDGE_HOVER, 1.8, FRAME_FILL_DEEP)


## 一个切角框：八条边（四角各切一刀）+ 四个小菱形。
##
## 切角按**框宽的比例**算，所以框大框小都是同一个样子 —— 这正是位图做不到的。
func _draw_frame(rect: Rect2, edge: Color, width: float, fill: Color) -> void:
	var p := rect.position
	var e := rect.end
	var cut := minf(rect.size.x * CUT_RATIO, rect.size.y * 0.30)
	var pts := PackedVector2Array([
		p + Vector2(cut, 0.0), Vector2(e.x - cut, p.y),
		Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y),
		Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut),
	])
	draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, edge, width)
	# 四角的小菱形，摆在框角上
	var d := minf(rect.size.y * 0.14, rect.size.x * 0.05)
	for corner: Vector2 in [p, Vector2(e.x, p.y), Vector2(p.x, e.y), e]:
		draw_colored_polygon(PackedVector2Array([
			corner + Vector2(0.0, -d), corner + Vector2(d, 0.0),
			corner + Vector2(0.0, d), corner + Vector2(-d, 0.0)]), edge)


## 高亮某个地点。传空表示取消全部高亮。
##
## 鼠标悬停时框换成亮描边（`_draw()` 里看 `_hovered`）、名字换成暖白，
## 玩家才知道这儿点得动。
func set_hovered(portal_id: StringName) -> void:
	if _hovered == portal_id:
		return
	_hovered = portal_id
	for place: Dictionary in _places:
		var label: Label = place.get("label")
		if not is_instance_valid(label):
			continue
		var on: bool = StringName(place["id"]) == portal_id
		label.add_theme_color_override("font_color",
			HOVER_NAME_COLOR if on else Color(place.get("base", NAME_COLOR)))
	queue_redraw()



func clear() -> void:
	_place_nodes.clear()
	_places.clear()
	_detail_for = &""
	_detail = null
	_covers.clear()
	_hovered = &""
	# **旧的 `Built` 要真的扔掉。**
	#
	# `build()` 每次都 new 一个挂上来，不扔的话切一次场景就堆一层 ——
	# 表现是**上一张图的东西还画在画面上**：2026-09-24 在大地图上截图，
	# 左边赫然摆着委托屋的书桌，就是这么来的。
	# 越玩越重是顺带的代价。
	if _built != null and is_instance_valid(_built):
		_built.queue_free()
	_built = null
	queue_redraw()



func _build_wall_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	_built.add_child(body)

	for wall: Rect2 in map_def.walls:
		_add_box_collision(body, wall, "wall")

	# 兜底：场景四边各加一道，防止数据里边界没画严导致角色走出去
	var outer: Rect2 = Rect2(Vector2.ZERO, Vector2(map_def.size))
	var t: float = BORDER_THICKNESS
	_add_box_collision(body, Rect2(outer.position - Vector2(t, t),
		Vector2(outer.size.x + t * 2.0, t)), "border_top")
	_add_box_collision(body, Rect2(outer.position + Vector2(-t, outer.size.y),
		Vector2(outer.size.x + t * 2.0, t)), "border_bottom")
	_add_box_collision(body, Rect2(outer.position - Vector2(t, 0),
		Vector2(t, outer.size.y)), "border_left")
	_add_box_collision(body, Rect2(outer.position + Vector2(outer.size.x, 0),
		Vector2(t, outer.size.y)), "border_right")


## 角色的碰撞。
##
## 三条路：
##   - `solid` 的：整块挡（示意图上没涂、但要单独挡的那种）
##   - 有贴图的家具：**自己不建碰撞**，挡不挡全看地图的 `walls`
##     —— 那是策划涂绿的地方，比按物件框推准
##   - 没有贴图的人：挡脚下一条。俯视角里人的「实体」是脚下那一点，
##     整块挡住会让玩家觉得撞在一堵看不见的墙上，也没法贴着人绕过去。
func _build_actor_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "Actors"
	_built.add_child(body)

	var any := false
	for actor: MapDef.Actor in map_def.active_actors(_flags):
		if actor.has_local_collision:
			for local_shape: Rect2 in actor.collision_rects():
				_add_box_collision(body, local_shape, "actor_%s" % actor.id)
				any = true
			continue
		if actor.solid:
			_add_box_collision(body, actor.rect, "actor_%s" % actor.id)
			any = true
			continue
		if not actor.person:
			continue
		# 人（NPC）：挡脚下一小条，不然玩家会从他身体里穿过去。
		var foot := Rect2(
			actor.rect.position + Vector2(2.0, actor.rect.size.y - 8.0),
			Vector2(maxf(actor.rect.size.x - 4.0, 1.0), 8.0)
		)
		_add_box_collision(body, foot, "actor_%s" % actor.id)
		any = true

	if not any:
		body.queue_free()


func _add_box_collision(parent: StaticBody2D, rect: Rect2, label: String) -> void:
	var shape := CollisionShape2D.new()
	shape.name = label
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.position + rect.size * 0.5
	parent.add_child(shape)


## 画一块矩形。返回画出来的节点；尺寸为 0 时画不了，返回 null。
func _add_rect(rect: Rect2, color: Color, z: int) -> Polygon2D:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return null
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	])
	poly.color = color
	poly.z_index = z
	_built.add_child(poly)
	return poly
