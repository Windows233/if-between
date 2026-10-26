## 过场覆盖层：章标题、屏幕中央的大图、画面碎掉。
##
## 这一层（14）是**演出层**：盖住对话框（10）、悬停提示（12）、选项框（13），
## 只让所有菜单压在它上面。理由：章标题、结局文字、碎玻璃出现的时候，
## 台词要么已经收起来了，要么本来就该被它们盖住。
##
## **大图不在这一层。** 它是**背景**，玩家要在 CG 上看见人物说话 ——
## 所以它单独挂在 `PICTURE_LAYER`（9），在对话框**下面**。见那个常量的说明。
##
## 黑底也不归它管 —— 那是 `StageCurtain` 的事，那一层在对话框下面。
## 分工是：黑幕管「底」，这里管「底上面动的东西」。
class_name StageOverlay
extends CanvasLayer

## 换了张图 / 把图收起来了。**别的东西靠它决定要不要让开** ——
## 右下角那个背包图标就是靠它：CG 摆着的时候不该杵在画面上。
signal picture_changed(showing: bool)

## 章标题的字号。320x180 的界面里 22 已经很大了，再大就得出屏。
const BANNER_FONT_SIZE := 22
const BANNER_COLOR := Color("#f0e6d2")

## 大图自己一层，**在对话框（10）之下**：地图(0) ＜ 大图(9) ＜ 对话框(10)
## ＜ 悬停 12 ＜ 选项框 13 ＜ 演出层(14) ＜ 所有菜单。
##
## 为什么不跟 `caption` / `banner` 一起挤在 14：那一层的职责是
## 「**盖住**对话框」（章标题、结局文字、碎玻璃要压在所有东西上面），
## 而 CG 是**背景** —— 人物要在 CG 上说话。两个职责正好相反。
## 14 上面紧挨着就是暂停菜单 15，中间没有位置留给对话框，
## 所以只能把大图挪下来。
##
## 2026-09-24：策划要「梦里那两句旁白出现在**对话框**里」，而大图原先在 14、
## 铺满整屏时把对话框整个盖住 —— 那两句一个字都看不见，按空格像没反应
##（症状是「CG 播放时间太长、按空格不灵」）。
const PICTURE_LAYER := 9

## 屏幕正中那几行字的默认字号。比章标题小，比正文大 —— 它念的是心里话。
const CAPTION_FONT_SIZE := 13
const CAPTION_COLOR := Color("#efe6d4")
const CAPTION_OUTLINE := Color(0, 0, 0, 0.85)
## 两行之间隔多少，以及一行浮完之后停多久再浮下一行。
##
## 开场那三句心声和 end1 的两行都靠它排 —— 行距够大才看得出是「一句一句
## 浮出来的」，而不是一次糊上去一段话。
const CAPTION_SEPARATION := 10
const CAPTION_GAP := 0.35

## 大图在屏幕上最多占多大。留边是为了看得出它是「一张图」，不是换了个场景。
const IMAGE_MAX_WIDTH_RATIO := 0.9
const IMAGE_MARGIN := 6.0

## 破碎切成多少块。16x9 = 144 片，够碎，又不至于卡。
const SHATTER_COLS := 16
const SHATTER_ROWS := 9

var _root: Control
var _banner: Label
## 大图挂在自己那层（`_picture_layer`）里，不在 `_root` 底下。
var _picture_layer: CanvasLayer
var _picture_root: Control
var _image: TextureRect
## 屏幕正中那几行字挂在这个竖排容器里。整块在屏幕里垂直居中，
## 所以两行字天然是「中线上下各一行」的样子（稿子说的「中心对称」）。
var _caption: VBoxContainer
var _tiles: Array[TextureRect] = []
## 屏幕破碎：一张黑底碎玻璃图从正中炸开（见 `ui/screen_shatter.gd`）。
var _shatter: ScreenShatter
## 睁眼：黑幕中间抠一个椭圆（见 `ui/screen_eye.gd`）。
##
## **它挂在 `_caption` 之后** —— 同层按加入顺序画，它得盖住这一层里别的东西
##（章标题、屏幕中央那几行字都可能在它底下）。它是「整屏转场」，
## 该在最上面。
var _eye: ScreenEye


func _ready() -> void:
	setup()


## 建界面。抽成显式方法，理由同 main.gd 的 boot()：
## `--script` 模式下 add_child 不会触发 `_ready`。重复调用安全。
func setup() -> void:
	if _root != null:
		return

	# 14：**演出层**。要盖住对话框（10）、悬停提示（12）、选项框（13），
	# 但**要低于所有菜单** —— 暂停菜单 15、存档 16、设置 17、标题 21。
	#
	# 原来是 26，压在菜单上面：演出到一半按 ESC，猫照片、碎玻璃、
	# 屏幕正中那两行字全盖在菜单上，菜单能按键但看不见（2026-09-24 改）。
	layer = 14

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.position = Vector2.ZERO
	_root.size = _view_size()

	_banner = Label.new()
	_banner.name = "Banner"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", BANNER_FONT_SIZE)
	_banner.add_theme_color_override("font_color", BANNER_COLOR)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_root.add_child(_banner)
	_banner.position = Vector2.ZERO
	_banner.size = _view_size()

	# 大图单独一层。**必须在 `_root` 之前建好** —— 那层在对话框下面，
	# 而这一层在对话框上面，跟先后无关；分开放是因为职责相反。
	# 见 `PICTURE_LAYER`。
	_picture_layer = CanvasLayer.new()
	_picture_layer.name = "PictureLayer"
	_picture_layer.layer = PICTURE_LAYER
	add_child(_picture_layer)

	_picture_root = Control.new()
	_picture_root.name = "Root"
	_picture_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture_root.position = Vector2.ZERO
	_picture_root.size = _view_size()
	_picture_layer.add_child(_picture_root)

	_image = TextureRect.new()
	_image.name = "Picture"
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.visible = false
	_picture_root.add_child(_image)

	# 碎玻璃。**建在 `_caption` 之前** —— 同层节点按加入顺序画，
	# 后加的盖在上面。碎屏发生在结局文字浮出来之前，裂纹不该压住那两行字。
	_shatter = ScreenShatter.new()
	_root.add_child(_shatter)
	_shatter.setup()

	# 眼罩。**建在 `_caption` 之后**，见 `_eye` 的说明。
	_eye = ScreenEye.new()
	_root.add_child(_eye)
	_eye.setup()

	_caption = VBoxContainer.new()
	_caption.name = "Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.alignment = BoxContainer.ALIGNMENT_CENTER
	_caption.add_theme_constant_override("separation", CAPTION_SEPARATION)
	_root.add_child(_caption)
	_caption.position = Vector2.ZERO
	_caption.size = _view_size()


# ---------------------------------------------------------------- 屏幕中央的字

## 屏幕正中浮现的几行字：一行一行淡入，**浮完不自己消失**。
##
## 跟章标题（`show_banner`）的区别：那个是一行大字、停一会儿自己走掉；
## 这个是「黑屏上慢慢浮出来的一段话」，浮完停在场上 —— 接下来要么
## 直接进下一幕，要么等玩家点一下（那一步由演出拿 `wait_click` 接着写）。
##
## 每行写成 `{"text": "...", "size": 16}`，`size` 不写就用 `CAPTION_FONT_SIZE`。
## end1 那两行的第二行要比第一行小两号，就是靠这个。
func show_caption(lines: Array, fade: float = 0.7) -> void:
	setup()
	clear_caption()

	var gaps: Array[float] = []
	for raw: Variant in lines:
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		var text := str(item.get("text", ""))
		if text == "":
			continue

		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",
			int(item.get("size", CAPTION_FONT_SIZE)))
		label.add_theme_color_override("font_color", CAPTION_COLOR)
		label.add_theme_color_override("font_outline_color", CAPTION_OUTLINE)
		label.add_theme_constant_override("outline_size", 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 一个字号一个高度，容器按内容排 —— 所以先把字设好再加进去
		label.size = Vector2(_view_size().x, float(label.get_theme_font_size("font_size")) + 6.0)
		label.modulate.a = 0.0
		_caption.add_child(label)
		# 这一行**浮出来之前**先等多久。不写就是 `CAPTION_GAP`。
		# 「再见面……」之后停一秒再浮出「却」，就是靠这个
		#（一行一行等同样的间隔，那一下顿不出来）。
		gaps.append(float(item.get("gap", CAPTION_GAP)))

	var index := 0
	for label: Label in _caption.get_children():
		# 第一行不先等 —— 那会让整块字出现得慢一拍
		if index > 0 and fade > 0.0:
			await _sleep(gaps[index] if index < gaps.size() else CAPTION_GAP)
		if fade > 0.0:
			var rise := create_tween()
			rise.tween_property(label, "modulate:a", 1.0, fade)
			await rise.finished
		else:
			label.modulate.a = 1.0
		index += 1
	# 最后一行浮完再等一拍，整段才算落定（不写这一下的话，写完立刻就被
	# 后面那一步收走，看着像最后一行没站稳）
	if fade > 0.0 and index > 0:
		await _sleep(CAPTION_GAP)


## 场上现在有几行字。测试和调试用。
func caption_lines() -> int:
	if _caption == null:
		return 0
	return _caption.get_child_count()


## 收掉屏幕中央的字。
func clear_caption() -> void:
	if _caption == null:
		return
	for child: Node in _caption.get_children():
		_caption.remove_child(child)
		child.queue_free()


## 淡出之后收掉。跟 `show_caption()` 配着用：浮上来 → 停一会儿 → 淡下去。
##
## `time` 为 0 直接收 —— 即时模式走的这条。
func hide_caption(time: float = 0.5) -> void:
	if _caption == null or _caption.get_child_count() == 0:
		return
	if time <= 0.0:
		clear_caption()
		return
	var fall := create_tween()
	fall.set_parallel(true)
	for child: Node in _caption.get_children():
		if child is CanvasItem:
			fall.tween_property(child, "modulate:a", 0.0, time)
	await fall.finished
	clear_caption()


# ---------------------------------------------------------------- 章标题

## 屏幕中央的一行大字：淡入、停一会儿、淡出。整段跑完才返回。
func show_banner(text: String, hold: float = 1.6, fade: float = 0.5) -> void:
	setup()
	if text == "":
		return

	_banner.text = text
	_banner.visible = true
	_banner.modulate.a = 0.0

	if fade > 0.0:
		var rise := create_tween()
		rise.tween_property(_banner, "modulate:a", 1.0, fade)
		await rise.finished
	else:
		_banner.modulate.a = 1.0

	if hold > 0.0:
		await _sleep(hold)

	if fade > 0.0:
		var fall := create_tween()
		fall.tween_property(_banner, "modulate:a", 0.0, fade)
		await fall.finished

	_banner.visible = false


# ---------------------------------------------------------------- 大图

## 屏幕中央放一张图，淡入。`path` 读不到就当没有，返回 false。
##
## **它挂在 `PICTURE_LAYER`（9）、对话框下面** ——「CG 还挂着，人物在上面对话」
## 是成立的，而且这是 CG 最常见的用法。见那个常量。
##
## 摆上/收起都会发 `picture_changed`，别的东西据此让开位置（背包图标）。
##
## `fill` 为真时**铺满整屏**。CG 那张图本来就是按 16:9 画的，
## 按「缩到屏幕内」画的话四周会留一圈黑边、气势全没了（2026-09-24 策划报的）。
## 素材比例和视口一致，所以直接拉到视口大小不会变形。
## 道具图那种（猫的照片）还是用不铺满的默认值。
func show_image(path: String, fade: float = 0.4, fill: bool = false) -> bool:
	setup()
	var texture := _load_texture(path)
	if texture == null:
		return false
	if not fill:
		var pixels := texture.get_image()
		if pixels != null:
			var used := pixels.get_used_rect()
			if used.has_area() and used.size != pixels.get_size():
				var crop := AtlasTexture.new()
				crop.atlas = texture
				crop.region = Rect2(used)
				texture = crop

	var view := _view_size()
	var picture := texture.get_size()
	var drawn := picture
	if fill:
		_image.stretch_mode = TextureRect.STRETCH_SCALE
		drawn = view
	else:
		_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 道具近景完整放在对话框上方；最大面板高度也不能压住图片下半截。
		var limit := Vector2(view.x * IMAGE_MAX_WIDTH_RATIO,
			maxf(view.y - DialogueBox.BOX_MAX_HEIGHT - IMAGE_MARGIN * 2.0, 1.0))
		var factor := minf(limit.x / maxf(picture.x, 1.0), limit.y / maxf(picture.y, 1.0))
		drawn = picture * factor

	_image.texture = texture
	_image.size = drawn
	_image.position = Vector2.ZERO if fill else Vector2((view.x - drawn.x) * 0.5,
		(view.y - DialogueBox.BOX_MAX_HEIGHT - drawn.y) * 0.5)
	_image.visible = true
	_image.modulate.a = 0.0
	# **图一摆上就报信**，不等淡完 —— 别的东西（背包图标）要在它开始浮现的
	# 那一刻就让开，而不是等淡入完再让。
	picture_changed.emit(true)

	if fade > 0.0:
		var tween := create_tween()
		tween.tween_property(_image, "modulate:a", 1.0, fade)
		await tween.finished
	else:
		_image.modulate.a = 1.0
	return true


## 大图淡出，然后藏起来。
func hide_image(fade: float = 0.4) -> void:
	setup()
	if not _image.visible:
		return
	if fade > 0.0:
		var tween := create_tween()
		tween.tween_property(_image, "modulate:a", 0.0, fade)
		await tween.finished
	_image.visible = false
	_image.texture = null
	picture_changed.emit(false)


func has_image() -> bool:
	return _image != null and _image.visible


## 现在挂在屏上的章标题。没有就返回空串。
## 烟测与调试用 —— 字有没有真的上屏，光看代码看不出来。
func banner_text() -> String:
	if _banner == null or not _banner.visible:
		return ""
	return _banner.text


# ---------------------------------------------------------------- 睁眼

## 睁眼：黑幕中间一个椭圆先睁开、眨两下，再完全亮起来。
##
## **调用方要先把幕布揭开**（`fade to clear`，时间为 0），不然椭圆里
## 看见的还是幕布那层黑。理由写在 `ui/screen_eye.gd` 的文件头。
func eye_open(blinks: int = 2) -> void:
	if _eye == null:
		return
	await _eye.play(blinks)


## 直接当成「已经睁完了」。即时模式（无头测试）走这条。
func eye_finish() -> void:
	if _eye != null:
		_eye.finish()


# ---------------------------------------------------------------- 破碎

## 把当前画面切成碎片，让它飞散开。
##
## **每一片都是画面自己的一部分** —— 截一张当前画面，按格子裁成小块，
## 再让这些小块各自飘走。所以看上去是「这一屏碎掉了」，
## 而不是「盖了一层碎玻璃的素材」。
##
## 分两步，原因是顺序很要紧：**先切片盖上去，再把底黑掉**。
## 反过来的话截图截到的就是黑的。碎片自己盖满整屏，
## 所以黑底那一刻画面上看不出变化，等碎片飞散才露出来。
func shatter_begin() -> bool:
	setup()
	var texture := await _grab_screen()
	if texture == null:
		# 截不到画面（无头模式、或者渲染还没起来）。
		# 不能让整段演出停在这儿，当成「已经碎完了」直接往下走。
		push_warning("[演出] 截不到画面，破碎特效跳过")
		return false

	var picture := texture.get_size()
	if picture.x <= 0.0 or picture.y <= 0.0:
		return false

	var view := _view_size()
	# 截图比逻辑尺寸大多少倍。截图是窗口分辨率的，逻辑是 320x180。
	var k := picture.x / maxf(view.x, 1.0)

	_clear_tiles()
	for row: int in SHATTER_ROWS:
		for col: int in SHATTER_COLS:
			var x0 := int(float(col) * picture.x / float(SHATTER_COLS))
			var x1 := int(float(col + 1) * picture.x / float(SHATTER_COLS))
			var y0 := int(float(row) * picture.y / float(SHATTER_ROWS))
			var y1 := int(float(row + 1) * picture.y / float(SHATTER_ROWS))
			if x1 <= x0 or y1 <= y0:
				continue

			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(x0, y0, x1 - x0, y1 - y0)

			var tile := TextureRect.new()
			tile.texture = atlas
			tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tile.stretch_mode = TextureRect.STRETCH_SCALE
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.size = Vector2(float(x1 - x0) / k, float(y1 - y0) / k)
			tile.position = Vector2(float(x0) / k, float(y0) / k)
			tile.pivot_offset = tile.size * 0.5
			_root.add_child(tile)
			_tiles.append(tile)

	return not _tiles.is_empty()


## 让碎片飞散开，整段跑完才返回。
func shatter_play(time: float = 1.0) -> void:
	if _tiles.is_empty():
		return

	var tween := create_tween()
	tween.set_parallel(true)
	for tile: TextureRect in _tiles:
		# 往下掉为主，左右散开 —— 只往上飞会像爆炸，往下掉才像塌
		var away := Vector2(randf_range(-26.0, 26.0), randf_range(6.0, 46.0))
		tween.tween_property(tile, "position", tile.position + away, time) \
			.set_ease(Tween.EASE_IN)
		tween.tween_property(tile, "rotation", randf_range(-0.7, 0.7), time)
		tween.tween_property(tile, "modulate:a", 0.0, time * 0.65).set_delay(time * 0.35)

	await tween.finished
	_clear_tiles()


## 一步到位：切片、飞散。不需要在黑底之前插别的动作时用它。
func shatter(time: float = 1.0) -> void:
	if not await shatter_begin():
		return
	await shatter_play(time)


func is_shattering() -> bool:
	return not _tiles.is_empty()


# ---------------------------------------------------------------- 碎玻璃（新）

## 叠一层碎玻璃：从正中炸开 → 停一会儿 → 淡掉。整段跑完才返回。
##
## 和上面那套`grab_screen` 切瓦片的分工：
##   - 这套是**碎玻璃**，玻璃裂开的样子（素材自带裂纹和碎片）
##   - 那套是**画面本身碎掉**，切片飞散
## 两个可以叠着用，也可以只用其中一个。
func glass_burst(hold: float = 0.6, fade: float = 0.5) -> void:
	setup()
	if _shatter == null:
		return
	await _shatter.play(hold, fade)


## 立刻摆出「已经碎好了、停在场上」的样子，不做动画。
## 即时模式和截图用 —— 那两种场合没有帧循环，tween 推不动。
func glass_show() -> void:
	setup()
	if _shatter != null:
		_shatter.show_burst()


func is_glass() -> bool:
	return _shatter != null and _shatter.is_playing()


## 把裂纹摆到某个扩散位置，不做动画。截图用。
func set_glass_spread(v: float) -> void:
	setup()
	if _shatter != null:
		_shatter.set_spread(v)


# ---------------------------------------------------------------- 收尾

## 把这一层收干净。演出被打断、切场景、回标题时调用。
func clear() -> void:
	if _root == null:
		return
	_banner.visible = false
	_banner.modulate.a = 0.0
	# 睁眼的黑幕也一起收 —— 不收的话它盖在所有东西上面，换完场景一片黑。
	if _eye != null:
		_eye.finish()
	var had_picture := _image.visible
	_image.visible = false
	_image.texture = null
	# 收掉大图也要报信 —— 不报的话「背包图标让开」那个状态会一直挂着，
	# 换场景回来图标就再也不出现了。
	if had_picture:
		picture_changed.emit(false)
	# 屏幕中央那几行字也得收 —— 它是这一局的最后一句，
	# 回标题时还留着就会盖在标题上面（这一层是 26，标题才 21）。
	clear_caption()
	_clear_tiles()
	if _shatter != null:
		_shatter.stop()


# ---------------------------------------------------------------- 内部

func _clear_tiles() -> void:
	for tile: TextureRect in _tiles:
		if is_instance_valid(tile):
			tile.queue_free()
	_tiles.clear()


## 截当前这一帧的画面。
##
## 要等 `frame_post_draw` —— 在帧中间截会拿到上一帧或者空白。
func _grab_screen() -> Texture2D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	await RenderingServer.frame_post_draw
	# 拿完这一帧可能会被换掉，重新取一次
	viewport = get_viewport()
	if viewport == null:
		return null
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _load_texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[演出] 找不到图：%s" % path)
		return null
	var res: Resource = load(path)
	if res is Texture2D:
		return res
	push_warning("[演出] 不是图片：%s" % path)
	return null


func _sleep(seconds: float) -> void:
	# **先问在不在树里。** 直接拿 `get_tree()` 的话，节点没进树时它会一边
	# 返回 null 一边喷 `Parameter "data.tree" is null` —— 那行报错跟字幕
	# 对不对没有关系，只会把真问题淹掉。
	#
	# 拿不到树就别等：静默抛出去会把整段协程打断，
	# 表现出来是「字写上了但一直不消失」或者反过来。
	if not is_inside_tree():
		push_warning("[演出] 不在树里，这一步的等待被跳过")
		return
	# 第二个参数 `false` = 暂停时不走。屏幕正中那两行字也是演出的一部分，
	# 玩家按了 ESC 它不该自顾自演完。理由同 `Cutscene._sleep`。
	await get_tree().create_timer(seconds, false).timeout


func _view_size() -> Vector2:
	# 尺寸取自项目设置的固定分辨率，**不去查 viewport**
	# —— viewport 尺寸在 `--script` 模式下取不准（节点刚进树时是 0）。
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 320.0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 180.0))
	)
