// 雾流只作用于背部和尾部；头部与眼睛保持稳定，时间由追逐帧驱动以支持暂停。
shader_type canvas_item;
uniform float smoke_time = 0.0;
uniform float vertical_facing = 0.0;
varying vec4 sprite_tint;
void vertex() {
	sprite_tint = COLOR;
}
void fragment() {
	float tail = 1.0 - smoothstep(0.45, 0.82, UV.x);
	if (vertical_facing > 0.5) { tail = smoothstep(0.35, 0.7, UV.y); }
	if (vertical_facing < -0.5) { tail = 1.0 - smoothstep(0.35, 0.7, UV.y); }
	vec2 flow = UV;
	flow.y += tail * sin(UV.x * 12.0 - smoke_time * 1.6) * 0.003;
	flow.x += tail * sin(UV.y * 14.0 - smoke_time * 1.2) * 0.002;
	COLOR = sprite_tint * texture(TEXTURE, clamp(flow, vec2(0.0), vec2(1.0)));
}
