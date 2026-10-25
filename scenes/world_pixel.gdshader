// 世界画面共用的像素标尺。格子随地图标尺投影，人物格子随自身移动。
// 用 UV 导数逆推取样点，支持旋转、翻转和高清 AtlasTexture；不处理 UI。
// 染色只用于人物；可选局部细节仅按亮度等比缩放 RGB，保留色相与透明轮廓。
shader_type canvas_item;

uniform float cell_size = 0.25;
uniform bool actor = false;
uniform float detail_strength = 0.0;
uniform vec4 uv_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec3 ambient = vec3(1.0);
uniform float exposure = 1.0;
uniform float saturation = 1.0;
varying vec2 grid_position;
varying vec4 item_color;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec2 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	grid_position = actor ? world - origin : world;
	item_color = COLOR;
}

void fragment() {
	vec2 delta = (floor(grid_position / cell_size) + 0.5) * cell_size - grid_position;
	vec2 dx = dFdx(grid_position);
	vec2 dy = dFdy(grid_position);
	float det = dx.x * dy.y - dx.y * dy.x;
	vec2 uv = UV;
	if (abs(det) > 0.00000001) {
		vec2 screen_delta = vec2(delta.x * dy.y - delta.y * dy.x,
			dx.x * delta.y - dx.y * delta.x) / det;
		uv += dFdx(UV) * screen_delta.x + dFdy(UV) * screen_delta.y;
	}
	uv = clamp(uv, uv_bounds.xy + TEXTURE_PIXEL_SIZE * 0.5,
		uv_bounds.zw - TEXTURE_PIXEL_SIZE * 0.5);
	vec4 pixel = texture(TEXTURE, uv);
	float luminance = dot(pixel.rgb, vec3(0.2126, 0.7152, 0.0722));
	if (detail_strength > 0.0) {
		vec2 low = uv_bounds.xy + TEXTURE_PIXEL_SIZE * 0.5;
		vec2 high = uv_bounds.zw - TEXTURE_PIXEL_SIZE * 0.5;
		vec2 step_x = dFdx(UV);
		vec2 step_y = dFdy(UV);
		vec3 neighbors = texture(TEXTURE, clamp(uv + step_x, low, high)).rgb;
		neighbors += texture(TEXTURE, clamp(uv - step_x, low, high)).rgb;
		neighbors += texture(TEXTURE, clamp(uv + step_y, low, high)).rgb;
		neighbors += texture(TEXTURE, clamp(uv - step_y, low, high)).rgb;
		float detail = luminance - dot(neighbors * 0.25, vec3(0.2126, 0.7152, 0.0722));
		float adjustment = clamp(detail * detail_strength, -0.025, 0.025)
			* smoothstep(0.004, 0.018, abs(detail));
		float brightest = max(max(pixel.r, pixel.g), pixel.b);
		float gain = clamp((luminance + adjustment) / max(luminance, 0.001),
			0.8, min(1.2, 1.0 / max(brightest, 0.001)));
		pixel.rgb *= gain;
		luminance = dot(pixel.rgb, vec3(0.2126, 0.7152, 0.0722));
	}
	pixel.rgb = mix(vec3(luminance), pixel.rgb, saturation) * ambient * exposure;
	COLOR = pixel * item_color;
}
