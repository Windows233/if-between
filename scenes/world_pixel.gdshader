// 世界画面共用的像素标尺。格子随地图标尺投影，人物格子随自身移动。
// 用 UV 导数逆推取样点，支持旋转、翻转和高清 AtlasTexture；不处理 UI。
// 染色只用于人物，保留节点原有的淡入淡出及透明轮廓。
shader_type canvas_item;

uniform float cell_size = 0.5;
uniform bool actor = false;
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
	pixel.rgb = mix(vec3(luminance), pixel.rgb, saturation) * ambient * exposure;
	COLOR = pixel * item_color;
}
