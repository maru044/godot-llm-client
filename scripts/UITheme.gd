extends RefCounted
## UI 样式 / 控件工厂（全静态）
## 与 ui_prototype/index.html 的 CSS 类一一对应

const Palette := preload("res://scripts/Palette.gd")

static var _font_cache: Dictionary = {}
static var _grad_cache: Dictionary = {}

# ================= 字体（SystemFont，可设字重 / 等宽） =================
static func font(size: int, weight: int = 400, mono: bool = false) -> Font:
	var key := "%d|%d|%s" % [size, weight, str(mono)]
	if _font_cache.has(key):
		return _font_cache[key]
	var f := SystemFont.new()
	if mono:
		f.font_names = PackedStringArray(["Consolas", "SF Mono", "Menlo", "Courier New", "Microsoft YaHei"])
	else:
		f.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans SC", "WenQuanYi Micro Hei", "Segoe UI"])
	f.font_weight = weight
	_font_cache[key] = f
	return f


static func label(text: String, size: int, color: Color, weight: int = 400, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(size, weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

# ================= StyleBox 基底 =================
static func _flat(bg: Color, radius: int, border: Color, border_w: int, shadow: Color = Color(0, 0, 0, 0),
		shadow_size: int = 0, m_l: int = 0, m_r: int = 0, m_t: int = 0, m_b: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.shadow_color = shadow
	sb.shadow_size = shadow_size
	sb.content_margin_left = m_l
	sb.content_margin_right = m_r
	sb.content_margin_top = m_t
	sb.content_margin_bottom = m_b
	return sb

# ================= 玻璃样式 =================
## .glass（pad = 内边距）
static func glass(radius: int = Palette.RADIUS, pad: int = 12) -> StyleBoxFlat:
	return _flat(Palette.BA_CARD, radius, Palette.BA_BORDER, 1, Palette.BA_SHADOW, 30, pad, pad, pad, pad)

## .glass-strong（弹窗/大面板框架）
static func glass_strong_frame(radius: int = Palette.RADIUS, bg: Color = Color(1, 1, 1, 0.32), pad: int = 22) -> StyleBoxFlat:
	return _flat(bg, radius, Palette.BA_BORDER, 1, Palette.BA_SHADOW, 34, pad, pad, pad, pad)

## 静态玻璃面板（不带 blur：内嵌容器 / 列表 / 气泡等内部区域用）
static func glass_panel_static(min_w: float, min_h: float, radius: int = Palette.RADIUS) -> PanelContainer:
	var pc := PanelContainer.new()
	if min_w > 0.0:
		pc.custom_minimum_size = Vector2(min_w, maxf(min_h, 0.0))
	elif min_h > 0.0:
		pc.custom_minimum_size = Vector2(0.0, min_h)
	pc.add_theme_stylebox_override("panel", glass(radius))
	return pc

# ================= 按钮 =================
## .btn（胶囊按钮，hover 提亮 + 蓝影）
static func btn_box(primary: bool = false, ghost: bool = false, hover: bool = false, pad_v: int = 9, pad_h: int = 20) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(1)
	if primary:
		sb.bg_color = Palette.PRIMARY_HOVER if hover else Palette.BA_BLUE
		sb.border_color = Color(1, 1, 1, 0.6)
		sb.shadow_color = Color(0.369, 0.655, 1.0, 0.45)
		sb.shadow_size = 18 if hover else 0
	elif ghost:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Palette.BA_BORDER
	else:
		sb.bg_color = Color(1, 1, 1, 0.95) if hover else Color(1, 1, 1, 0.75)
		sb.border_color = Palette.BA_BORDER
		sb.shadow_color = Palette.SHADOW_BLUE
		sb.shadow_size = 14 if hover else 0
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb

static func button(text: String, primary: bool = false, ghost: bool = false, font_size: int = 14,
		pad_v: int = 9, pad_h: int = 20, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", btn_box(primary, ghost, false, pad_v, pad_h))
	b.add_theme_stylebox_override("hover", btn_box(primary, ghost, true, pad_v, pad_h))
	b.add_theme_stylebox_override("pressed", btn_box(primary, ghost, false, pad_v, pad_h))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", font(font_size, 500 if primary else 400))
	b.add_theme_font_size_override("font_size", font_size)
	var fc := Color.WHITE if primary else Palette.BA_DEEP
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	if min_w > 0.0:
		b.custom_minimum_size = Vector2(min_w, 0)
	return b

# ================= 渐变头像 / 徽标 =================
static func _gradient_texture(from: Color, to: Color) -> GradientTexture2D:
	var key := "%s|%s" % [from.to_html(), to.to_html()]
	if _grad_cache.has(key):
		return _grad_cache[key]
	var g := Gradient.new()
	g.colors = PackedColorArray([from, to])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	_grad_cache[key] = gt
	return gt

## 生成带圆角 alpha 的渐变图像（逐像素，尺寸小开销可忽略）
static func _rounded_gradient_texture(size: Vector2, radius: int, from: Color, to: Color) -> ImageTexture:
	var w := int(size.x)
	var h := int(size.y)
	var r := float(radius)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var t := float(y) / maxf(float(h - 1), 1.0)
			var col := from.lerp(to, t)
			# 圆角 alpha：四个角超出圆弧的像素透明
			var a := 1.0
			if r > 0.0:
				var cx := float(x) + 0.5
				var cy := float(y) + 0.5
				# 顶部左 / 右
				if cy < r and cx < r:
					var dx := r - cx
					var dy := r - cy
					if dx * dx + dy * dy > r * r: a = 0.0
				elif cy < r and cx > float(w) - r:
					var dx := cx - (float(w) - r)
					var dy := r - cy
					if dx * dx + dy * dy > r * r: a = 0.0
				# 底部左 / 右
				elif cy > float(h) - r and cx < r:
					var dx := r - cx
					var dy := cy - (float(h) - r)
					if dx * dx + dy * dy > r * r: a = 0.0
				elif cy > float(h) - r and cx > float(w) - r:
					var dx := cx - (float(w) - r)
					var dy := cy - (float(h) - r)
					if dx * dx + dy * dy > r * r: a = 0.0
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)

## 渐变圆角头像 / 徽标（直接产出圆角纹理，TextureRect 显示）
static func _gradient_round(size: Vector2, radius: int, from: Color, to: Color) -> Control:
	var tr := TextureRect.new()
	tr.custom_minimum_size = size
	tr.texture = _rounded_gradient_texture(size, radius, from, to)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## 渐变圆角头像（135° 蓝 / 橙）
static func avatar(text: String, from: Color, to: Color, size: int, radius: int, font_size: int) -> Control:
	var c := _gradient_round(Vector2(size, size), radius, from, to)
	var l := label(text, font_size, Color.WHITE, 800)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(l)
	return c

## 渐变圆角 Panel（Logo 徽标等）
static func gradient_panel(from: Color, to: Color, radius: int = 0) -> Control:
	return _gradient_round(Vector2(96, 96), radius, from, to)

# ================= 输入 / 列表 / 胶囊 =================
## .field input
static func input_box(focused: bool, radius: int = 10, pad_v: int = 11, pad_h: int = 14) -> StyleBoxFlat:
	return _flat(Color(1, 1, 1, 0.8), radius, Palette.BA_BLUE if focused else Palette.BA_BORDER, 1)

## .preset-item / .char-card-item / .save-slot
static func list_item(active: bool = false, hover: bool = false) -> StyleBoxFlat:
	return _flat(Palette.BA_CARD_TINT if (active or hover) else Color(1, 1, 1, 0.6),
		12, Palette.BA_BORDER_BLUE if active else Palette.BA_BORDER, 1, Color(0, 0, 0, 0), 0, 14, 14, 12, 12)

## .stat-cell
static func stat_cell() -> StyleBoxFlat:
	return _flat(Color(1, 1, 1, 0.7), 10, Palette.BA_BORDER, 1, Color(0, 0, 0, 0), 0, 12, 14, 12, 12)

## 胶囊 chip（model-tag / roll-tag）
static func chip(bg: Color, border: Color) -> StyleBoxFlat:
	return _flat(bg, 999, border, 1, Color(0, 0, 0, 0), 0, 12, 12, 6, 6)

## .slot-btn
static func slot_btn(color: Color) -> StyleBoxFlat:
	return _flat(color, 999, Color(1, 1, 1, 0.0), 0, Color(0, 0, 0, 0), 0, 18, 18, 7, 7)

## .body-editor
static func body_editor_box() -> StyleBoxFlat:
	return _flat(Color(1, 1, 1, 0.72), 12, Palette.BA_BORDER, 1, Color(0, 0, 0, 0), 0, 18, 18, 14, 14)

## .api-tab
static func api_tab(active: bool) -> StyleBoxFlat:
	if active:
		return _flat(Palette.BA_CARD_TINT, 10, Palette.BA_BORDER_BLUE, 1, Color(0, 0, 0, 0), 0, 10, 10, 10, 10)
	return _flat(Color(1, 1, 1, 0.55), 10, Palette.BA_BORDER, 1, Color(0, 0, 0, 0), 0, 10, 10, 10, 10)

## 气泡（.msg.char / .msg.user）
static func bubble_char() -> StyleBoxFlat:
	return _flat(Color(1, 1, 1, 0.8), 14, Palette.BA_BORDER, 1, Color(0, 0, 0, 0), 0, 18, 18, 14, 14)

static func bubble_user() -> StyleBoxFlat:
	return _flat(Palette.BA_CARD_TINT, 16, Palette.BA_BORDER_BLUE, 1, Color(0, 0, 0, 0), 0, 16, 16, 12, 12)

## Toast
static func toast_box() -> StyleBoxFlat:
	return _flat(Color(0.16, 0.28, 0.42, 0.92), 999, Color(1, 1, 1, 0.25), 1, Color(0, 0, 0, 0.2), 8, 16, 16, 9, 9)