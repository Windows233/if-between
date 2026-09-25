## 把「对话框/」里两张没有透明通道的框素材处理成带 alpha 的贴图。
##
## ## 为什么要处理
##
## 原图是全画布不透明的：背景 (15,15,15)、框内填色 (16,17,19) —— **两者几乎一样**，
## 所以不能按键色抠。但背景是「从画布边缘连成一片」的那块，而框内填色被边框线
## 围住 —— 于是用**从四边泛洪**区分：泛洪得到的是背景 → 透明；剩下的一律保留
## （边框亮线 + 框内填色 + 花饰里的暗缝）。
##
## ## 为什么还要「封针孔」
##
## 直接泛洪会漏：边框在名字标签接上去的地方不是像素级闭合的，泛洪会从那一两个
## 像素钻进去，把**整个框内填色也当成背景抠掉**。症状很好认 —— 框外面透明了，
## 框里面也透明了，而名字标签那一小块反倒还留着深色底，两者不一致。
##
## 所以先把「亮线」做一次膨胀（形态学闭），拿膨胀后的结果当泛洪的墙；
## 但**给 alpha 用的仍然是未膨胀的原始亮线**，免得把线本身撑粗。
## 这和 `tools/extract_collision.py` 里 `close_holes()` 处理「一个像素的洞」是同一招。
##
## ## alpha 怎么给
##
## 亮线是「亮色叠在黑底上」画出来的，反锯齿边缘像素本来就比线心暗。直接给
## 半透明会糊成一层灰。所以按亮度推 alpha，再把颜色**反预乘**（rgb / alpha）
## 还原成本来的亮色 —— 这样叠回深色场景上，边缘的观感跟原图一致。
##
## 用法：
##   "<godot>" --headless --path <项目> --script res://tools/make_dialog_frames.gd
##
## 产物：
##   art/ui/dialog_frame_left.png   （主角用，名字标签在左上）
##   art/ui/dialog_frame_right.png  （其他角色用，名字标签在右上）
extends SceneTree

const SRC := {
	"left": "res://对话框/文字框左.PNG",
	"right": "res://对话框/文字框右.png",
}
const DST := {
	"left": "res://art/ui/dialog_frame_left.png",
	"right": "res://art/ui/dialog_frame_right.png",
}

## 判定「这是边框亮线」的亮度门槛。背景和暗缝都在 0.06 上下，亮线 0.5 以上，
## 0.35 两边都留了余量（实测包围盒稳定）。
const FRAME_LUM := 0.35
## 封针孔时亮线向外膨胀几个像素。2 够用；调大会把窄缝也封掉、框内被吃掉。
const SEAL := 2
## 推 alpha 的区间：亮度到 A_LO 就算全透明，到 A_HI 就算全实。
## 上界不取 1.0 是因为最亮的线心其实也不到纯白，取 0.85 能把线拉实。
const A_LO := 0.06
const A_HI := 0.85
## 框内填色那块给的 alpha。和原来代码里的 BG_COLOR 一致（0.92）——
## 留一点点透明，让底下的场景透出来一丝。
const FILL_ALPHA := 0.92
## 裁切时四周多留几个像素，免得把阈值以下的弱边切掉。
const PAD := 6


func _initialize() -> void:
	for key: String in ["left", "right"]:
		_build(key)
	quit(0)


func _build(key: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC[key]))
	if img == null:
		push_error("读不到 %s" % SRC[key])
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()

	# --- 1. 标出亮线 ---
	var frame := PackedByteArray()
	frame.resize(w * h)
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if (c.r + c.g + c.b) / 3.0 > FRAME_LUM:
				frame[y * w + x] = 1

	# --- 2. 膨胀一次，拿它当泛洪的墙 ---
	var wall := _dilate(frame, w, h, SEAL)

	# --- 3. 从四边泛洪，淌到的是背景 ---
	var outside := PackedByteArray()
	outside.resize(w * h)
	var stack: Array[int] = []
	for x in range(w):
		_push_if_bg(wall, outside, stack, x, 0, w)
		_push_if_bg(wall, outside, stack, x, h - 1, w)
	for y in range(h):
		_push_if_bg(wall, outside, stack, 0, y, w)
		_push_if_bg(wall, outside, stack, w - 1, y, w)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % w
		var y := i / w
		if x > 0:
			_push_if_bg(wall, outside, stack, x - 1, y, w)
		if x < w - 1:
			_push_if_bg(wall, outside, stack, x + 1, y, w)
		if y > 0:
			_push_if_bg(wall, outside, stack, x, y - 1, w)
		if y < h - 1:
			_push_if_bg(wall, outside, stack, x, y + 1, w)

	# --- 4. 把封针孔挡掉的那一圈还回去 ---
	#
	# `wall` 比真实亮线粗 SEAL 个像素，所以**紧贴亮线外侧**的那一圈不会淌到、
	# 会被当成「框内」而填上深色 —— 那就是一圈黑边。把 outside 再向外膨胀
	# 同样多，正好补回这一圈。**框内那条双线之间的缝离得更远，吃不到**，
	# 于是它照旧被填成深色（原图那儿本来就是暗的）。
	var open_out := _dilate(outside, w, h, SEAL)

	# --- 5. 逐像素定 alpha ---
	#
	# 亮线用**原始** frame（不是膨胀后的 wall），免得把线撑粗。
	# 背景里的杂点即便够亮也不算亮线 —— 它已经被泛洪标成背景了。
	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			var i := y * w + x
			if frame[i] == 1 and outside[i] == 0:
				var lum := (c.r + c.g + c.b) / 3.0
				var a := clampf((lum - A_LO) / (A_HI - A_LO), 0.04, 1.0)
				# 反预乘：把「亮色叠黑底」还原成直通 alpha 的颜色
				img.set_pixel(x, y, Color(
					minf(c.r / a, 1.0), minf(c.g / a, 1.0), minf(c.b / a, 1.0), a))
			elif open_out[i] == 1:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
			else:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, FILL_ALPHA))
			if open_out[i] == 0 or frame[i] == 1:
				if x < minx: minx = x
				if x > maxx: maxx = x
				if y < miny: miny = y
				if y > maxy: maxy = y

	# --- 6. 裁到有效范围（留 PAD）---
	var bbox := Rect2i(0, 0, w, h)
	if maxx >= 0:
		var rx := maxi(minx - PAD, 0)
		var ry := maxi(miny - PAD, 0)
		bbox = Rect2i(rx, ry, mini(maxx + PAD, w - 1) - rx + 1, mini(maxy + PAD, h - 1) - ry + 1)
		img = img.get_region(bbox)

	var err := img.save_png(ProjectSettings.globalize_path(DST[key]))
	var opaque := 0
	var clear := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a < 0.05:
				clear += 1
			elif img.get_pixel(x, y).a > 0.99:
				opaque += 1
	print("--- ", key)
	print("    原图 ", w, "x", h, "   裁切 ", bbox, " -> ", img.get_width(), "x", img.get_height())
	print("    全透明像素 ", clear, "   全实像素 ", opaque,
		"   占比 %.1f%%" % (100.0 * float(clear) / float(img.get_width() * img.get_height())))
	print("    写出 ", DST[key], "  err=", err)


## 二值膨胀（切比雪夫距离）。横一遍竖一遍，比逐像素开窗口快得多。
##
## 只用来当泛洪的墙，**不参与出图** —— 所以宁可多封一点也不怕。
func _dilate(src: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var tmp := PackedByteArray()
	tmp.resize(w * h)
	for y in range(h):
		var base := y * w
		for x in range(w):
			var hit := 0
			for k in range(maxi(0, x - r), mini(w - 1, x + r) + 1):
				if src[base + k] == 1:
					hit = 1
					break
			tmp[base + x] = hit
	var out := PackedByteArray()
	out.resize(w * h)
	for x in range(w):
		for y in range(h):
			var hit := 0
			for k in range(maxi(0, y - r), mini(h - 1, y + r) + 1):
				if tmp[k * w + x] == 1:
					hit = 1
					break
			out[y * w + x] = hit
	return out


## 泛洪用：这个像素不是墙、还没标记过，就标成背景并入栈。
func _push_if_bg(wall: PackedByteArray, outside: PackedByteArray,
		stack: Array[int], x: int, y: int, w: int) -> void:
	var i := y * w + x
	if outside[i] == 1 or wall[i] == 1:
		return
	outside[i] = 1
	stack.push_back(i)

