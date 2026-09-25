// 屏幕破碎特效：把一张**纯黑底的碎玻璃图**叠加到画面上。
//
// 黑底怎么消掉：`blend_add`（加法混合）。黑是 0，加 0 等于没加，
// 所以黑色部分天然「透明」，亮的裂纹直接加到画面上，看着像发光。
//
// **Godot 没有「滤色 / Screen」这个混合模式**（只有 mix / add / sub / mul），
// 网上说的「改混合模式为滤色」在这里落成 `blend_add`。两者的差别很小：
// 滤色是 `1-(1-a)(1-b)`，加法是 `a+b` —— 加法在亮部更容易过曝。
// 碎玻璃要的就是「过曝的那一下亮」，所以加法更合适，不必自己去写滤色。
//
// 素材的暗部不是精确的 0（压缩带来的，几十个亮度级），
// 直接加会把整个画面蒙上一层灰。`floor_cut` 把低于它的亮度压回 0。
shader_type canvas_item;
render_mode blend_add;

// 裂纹从中心炸开到了哪儿。0 = 还看不见，1.15 左右 = 铺满全屏。
uniform float spread : hint_range(0.0, 1.6) = 1.15;
// 扩散边缘的柔度。太小会留下一圈生硬的圆环，太大就看不出「是从中间出来的」。
uniform float softness : hint_range(0.02, 0.6) = 0.24;
// 整体亮度倍数。1.0 是原样，调上去裂纹更亮。
uniform float strength : hint_range(0.0, 4.0) = 1.0;
// 炸开那一瞬间，画面正中亮一团的强度（0~1）。
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// 黑底清理阈值。亮度低于它的当纯黑（不加到画面上）。
//
// **这个值调过。** 素材的黑底不干净（压缩噪点 + 暗玻璃反光），
// 0.05 的时候有三分之一的画布都在「加东西」，整屏像蒙了一层蓝紫的雾；
// 0.18 之后只剩裂纹主干和亮碎片，画面还看得清。
// 别按「黑底是纯黑」想当然地写 0 —— 加了之后才知道差在哪儿。
uniform float floor_cut : hint_range(0.0, 0.3) = 0.18;

void fragment() {
	vec3 src = texture(TEXTURE, UV).rgb;

	// 1) 压掉暗部的灰
	float lum = max(src.r, max(src.g, src.b));
	src *= smoothstep(floor_cut, floor_cut + 0.06, lum);

	// 2) 从画面正中往外推的遮罩：距离越远越晚出现
	float d = distance(UV, vec2(0.5));
	float edge = spread * 0.85;
	float grow = smoothstep(edge, max(edge - softness, 0.0), d);

	vec3 col = src * grow * strength;

	// 3) 炸开那一下，正中亮一团白
	col += vec3(1.0) * flash * smoothstep(0.30, 0.0, d);

	// `COLOR` 进 fragment 时是 modulate × 顶点色。
	// 乘上去，`modulate.a` 就成了整体强度（add 混合下 alpha 是权重）——
	// 淡出就是把它从 1 拉到 0。
	COLOR = vec4(col, 1.0) * COLOR;
}
