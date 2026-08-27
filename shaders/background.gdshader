shader_type canvas_item;
// ============================================================
// 背景 shader：完全复刻 ui_prototype/index.html 的 .bg 与 .bg::after
//   - 165deg 线性渐变（顶部 #c3dcff → 中部 #dceeff → 底部 #eef6ff）
//   - 三个径向光斑（左上 / 右上 / 底部）
//   - 六颗微光点（带呼吸闪烁）
// ============================================================

// 165deg 线性渐变的三段色
uniform vec3 col_top : source_color = vec3(0.7647, 0.8627, 1.0);   // #c3dcff
uniform vec3 col_mid : source_color = vec3(0.8627, 0.9333, 1.0);   // #dceeff
uniform vec3 col_bot : source_color = vec3(0.9333, 0.9647, 1.0);   // #eef6ff

// 三个径向光斑（radial-gradient）
uniform vec3 spot_1 : source_color = vec3(0.9569, 0.9765, 1.0);    // #f4f9ff
uniform vec3 spot_2 : source_color = vec3(0.8118, 0.8980, 1.0);    // #cfe5ff
uniform vec3 spot_3 : source_color = vec3(0.9098, 0.9569, 1.0);    // #e8f4ff

uniform float glow_alpha = 0.9;
uniform float twinkle_speed = 0.5;
uniform float dot_scale = 3.0;   // 微光点放大系数（CSS 原始 3px 过小，微调至可见）

// 六颗微光点：位置 / 直径(px) / 相位（照搬 .bg::after）
const vec2 DOT_POS[6] = vec2[](
	vec2(0.18, 0.28), vec2(0.55, 0.12), vec2(0.78, 0.42),
	vec2(0.30, 0.68), vec2(0.88, 0.78), vec2(0.08, 0.82)
);
const float DOT_SIZE[6] = float[](3.0, 2.0, 3.0, 2.0, 2.0, 3.0);
const float DOT_PHASE[6] = float[](0.0, 1.2, 2.4, 0.8, 2.0, 3.1);

float radial(vec2 uv, vec2 c, vec2 size) {
	vec2 d = (uv - c) / size;
	return exp(-dot(d, d) * 3.0);
}

void fragment() {
	// 使用 SCREEN_UV：全屏坐标与纹理无关，避免无纹理时 UV 未定义
	vec2 uv = SCREEN_UV;
	// 注意：背景 TextureRect 铺满全屏，SCREEN_UV 与 UV 等价，但更可靠

	// —— 165deg 线性渐变（顶部偏蓝 → 底部偏白，微向右倾 6%）——
	float g = clamp(uv.y + (0.5 - uv.x) * 0.06, 0.0, 1.0);
	vec3 base;
	if (g < 0.45) {
		base = mix(col_top, col_mid, g / 0.45);
	} else {
		base = mix(col_mid, col_bot, (g - 0.45) / 0.55);
	}

	// —— 三个径向光斑（尺寸按 1920x1080 下的 CSS px 换算）——
	base = mix(base, spot_1, radial(uv, vec2(0.12, -0.10), vec2(0.45, 0.52)) * 0.9);
	base = mix(base, spot_2, radial(uv, vec2(0.95, 0.15), vec2(0.38, 0.48)) * 0.8);
	base = mix(base, spot_3, radial(uv, vec2(0.50, 1.10), vec2(0.36, 0.45)) * 0.85);

	// —— 六颗微光点，带呼吸 ——
	vec2 px = max(SCREEN_PIXEL_SIZE, vec2(1e-5));
	for (int i = 0; i < 6; i++) {
		vec2 d = (uv - DOT_POS[i]) / px;
		float r2 = dot(d, d);
		float radius = DOT_SIZE[i] * 0.5 * dot_scale;
		float a = exp(-r2 / (radius * radius));
		float tw = 0.78 + 0.22 * sin(TIME * twinkle_speed + DOT_PHASE[i]);
		base = mix(base, vec3(1.0), a * tw * glow_alpha);
	}

	COLOR = vec4(clamp(base, vec3(0.0), vec3(1.0)), 1.0);
}