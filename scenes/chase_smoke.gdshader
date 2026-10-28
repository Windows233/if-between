// 雾流只作用于背部和尾部；头部与眼睛保持稳定，时间由追逐帧驱动以支持暂停。
shader_type canvas_item;
uniform float smoke_time = 0.0;
varying vec4 sprite_tint;
void vertex() {
	sprite_tint = COLOR;
}
void fragment() {
	float tail = 1.0 - smoothstep(0.45, 0.82, UV.x);
	vec2 flow = UV;
	flow.y += tail * (sin(UV.x * 19.0 - smoke_time * 5.0) * 0.012
		+ sin(UV.x * 33.0 + smoke_time * 3.0) * 0.005);
	flow.x += tail * sin(UV.y * 22.0 - smoke_time * 4.0) * 0.006;
	COLOR = sprite_tint * texture(TEXTURE, clamp(flow, vec2(0.0), vec2(1.0)));
}
