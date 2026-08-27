shader_type canvas_item;
// ============================================================
// 毛玻璃 shader：复刻 CSS backdrop-filter: blur() saturate()
// 采样 hint_screen_texture（上一帧屏幕内容），做高斯模糊 + 提饱和 + 白化
// 用法：挂在面板内部的 TextureRect（blur_region）上
// ============================================================

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float blur_px = 4.0;        // 高斯半径（像素）
uniform float saturation = 1.25;    // 饱和度增强
uniform float whitening = 0.50;     // 玻璃白化（0=原始，1=全白）
uniform float alpha = 1.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * blur_px;
	// 3x3 高斯核
	vec3 sum = vec3(0.0);
	sum += texture(screen_tex, SCREEN_UV + vec2(-px.x, -px.y)).rgb * 0.0625;
	sum += texture(screen_tex, SCREEN_UV + vec2(0.0, -px.y)).rgb * 0.125;
	sum += texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y)).rgb * 0.0625;
	sum += texture(screen_tex, SCREEN_UV + vec2(-px.x, 0.0)).rgb * 0.125;
	sum += texture(screen_tex, SCREEN_UV).rgb * 0.25;
	sum += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb * 0.125;
	sum += texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y)).rgb * 0.0625;
	sum += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb * 0.125;
	sum += texture(screen_tex, SCREEN_UV + vec2(px.x, px.y)).rgb * 0.0625;

	vec3 col = sum;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col = mix(col, vec3(1.0), whitening);
	COLOR = vec4(col, alpha);
}