// 雾流只作用于背部和尾部；头部与眼睛保持稳定，时间由追逐帧驱动以支持暂停。
shader_type canvas_item;
uniform float smoke_time = 0.0;
uniform float vertical_facing = 0.0;
// 横向素材的紫雾统一成与纵向动作接近的灰黑色，暖色眼睛和耳部不参与调色。
uniform float horizontal_smoke_gray : hint_range(0.0, 1.0) = 1.0;
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
	vec4 texel = texture(TEXTURE, clamp(flow, vec2(0.0), vec2(1.0)));
	if (abs(vertical_facing) < 0.5) {
		float violet = smoothstep(0.035, 0.14, texel.b - texel.g)
			* (1.0 - smoothstep(0.02, 0.08, texel.g - texel.r)) * step(texel.r, texel.b);
		float gray = dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722)) * 0.65;
		texel.rgb = mix(texel.rgb, vec3(0.94, 0.96, 1.0) * gray, violet * horizontal_smoke_gray);
	}
	COLOR = sprite_tint * texel;
}
