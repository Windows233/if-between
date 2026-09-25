// 睁眼：一整屏黑幕，中间抠出一个椭圆，椭圆里能看见底下的场景。
//
// **为什么用 shader 而不是一张椭圆贴图**：这个椭圆要连续地压扁 / 伸展
//（眨眼的整个过程），贴图只能整体缩放 —— 缩到很扁的时候边缘会糊成一片。
// 这里按「像素离画面中心多远」现算，多扁都干净。
//
// **不读 `TEXTURE`** —— 它不吃任何素材，整屏都是算出来的。所以挂在一个
// `ColorRect` 上就行（挂 `TextureRect` 还得塞一张没用的图）。
shader_type canvas_item;

// 椭圆的两个半径（UV 比例）：x 是横向、y 是纵向。
//
// y 压到 0.012 就是一条缝（闭眼），0.26 上下是睁着，
// 撑到 1.3 以上整个画面都进椭圆里（黑被推出屏幕，等于全亮）。
uniform vec2 aperture = vec2(0.30, 0.012);
// 边缘柔化多少（UV 比例）。0 是刀子切的硬边，0.03 上下像眼皮的边。
uniform float softness : hint_range(0.0, 0.2) = 0.03;
// 黑幕的颜色。**不用纯黑** —— 和幕布、转场遮罩对齐（`ScreenFade.COLOR`）。
uniform vec4 shade : source_color = vec4(0.02, 0.02, 0.03, 1.0);

void fragment() {
	// 把坐标按椭圆半径归一化：`r < 1` 就在椭圆里面
	vec2 d = (UV - vec2(0.5)) / max(aperture, vec2(0.0005));
	float r = length(d);

	// 里面透明（a=0，看得见场景）、外面不透明（a=1，是黑的）
	float a = smoothstep(1.0 - softness, 1.0 + softness, r);
	COLOR = vec4(shade.rgb, shade.a * a);
}
