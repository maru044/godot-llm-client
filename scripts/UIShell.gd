extends Control
## ============================================================
## LLM 客户端 · UI 壳（完全移植 ui_prototype/index.html）
## 纯壳：无业务逻辑，只有界面展示与占位交互
## ============================================================

const Palette = preload("res://scripts/Palette.gd")
const UI = preload("res://scripts/UITheme.gd")
const BG_SHADER = preload("res://shaders/background.gdshader")

var _screens: Dictionary = {}       # id -> Control
var _overlays: Dictionary = {}      # id -> Control
var _screen_stack: Array = []
var _save_mode: String = "load"

# --- 聊天页运行期引用（供追加消息 / 读取输入） ---
var _msg_box: VBoxContainer
var _input_line: LineEdit
var _model_reply_count: int = 0    # 当前模型回复槽位，便于追加

const FAKE_SLOTS: Array = [
	{"day": 3, "created": "2026-08-25 21:14"},
	null,
	{"day": 1, "created": "2026-08-24 09:02"},
	null,
	null,
	null,
]

func _ready() -> void:
	_build_background()
	_build_screens()
	_build_overlay_preset()
	_build_overlay_char()
	_build_overlay_save()
	_build_overlay_api()

	# 接通 LLM 核心信号 → UI
	EventBus.llm_response_started.connect(_on_llm_started)
	EventBus.llm_response_finished.connect(_on_llm_finished)
	EventBus.system_error_occurred.connect(_on_system_error)

# ================= 背景 =================
func _build_background() -> void:
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.texture = _dummy_white_texture()
	var mat := ShaderMaterial.new()
	mat.shader = BG_SHADER
	bg.material = mat
	add_child(bg)

func _dummy_white_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	return ImageTexture.create_from_image(img)

# ================= 屏幕容器 =================
func _build_screens() -> void:
	for id in ["screen-title", "screen-chat"]:
		var c := Control.new()
		c.name = id
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.visible = (id == "screen-title")
		add_child(c)
		_screens[id] = c
	_build_title_screen()
	_build_chat_screen()

# ================= 通用：玻璃面板（PanelContainer 管理内容，布局可靠） =================
## 玻璃卡片：半透明白色 StyleBoxFlat + 圆角 + 阴影（还原 backdrop-filter 观感）
func _glass(radius: int = Palette.RADIUS, pad: int = 12) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.glass(radius, pad))
	return pc

# ================= 标题界面 =================
func _build_title_screen() -> void:
	var root: Control = _screens["screen-title"]
	var wrap := VBoxContainer.new()
	wrap.name = "Wrap"
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 40)
	root.add_child(wrap)

	# logo 徽标
	var logo := UI.gradient_panel(Palette.GRAD_BLUE_FROM, Palette.GRAD_BLUE_TO, 30)
	logo.custom_minimum_size = Vector2(96, 96)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var logo_l := UI.label("LL", 44, Color.WHITE, 800)
	logo_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logo.add_child(logo_l)
	wrap.add_child(logo)

	# 大标题（text-shadow 效果）
	var h1 := UI.label("LLM 客户端", 52, Palette.BA_DEEP, 800)
	h1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h1.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.6))
	h1.add_theme_constant_override("shadow_offset_x", 2)
	h1.add_theme_constant_override("shadow_offset_y", 12)
	wrap.add_child(h1)

	# 副标题
	var sub := UI.label("R O L E P L A Y   S T U D I O", 15, Palette.BA_TEXT_DIM, 400)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(sub)

	# 菜单按钮
	var menu := HBoxContainer.new()
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 16)
	wrap.add_child(menu)

	var b_start := UI.button("开始游戏", true, false, 17, 15, 34, 170)
	b_start.pressed.connect(func(): show_screen("screen-chat"))
	menu.add_child(b_start)

	var b_load := UI.button("读取游戏", false, false, 17, 15, 34, 170)
	b_load.pressed.connect(func(): open_save_panel("load"))
	menu.add_child(b_load)

	var b_user := UI.button("打开 user 文件夹", false, false, 17, 15, 34, 170)
	b_user.pressed.connect(func(): toast("（占位）打开 user 文件夹"))
	menu.add_child(b_user)

	var b_api := UI.button("API 配置", false, false, 17, 15, 34, 170)
	b_api.pressed.connect(func(): open_overlay("overlay-api"))
	menu.add_child(b_api)

	# 底部注释
	var note := UI.label("美术展示稿 · 无实际功能 · 1920x1080 横屏基准 · Blue Archive Frosted Glass",
		12, Color(80.0 / 255.0, 120.0 / 255.0, 170.0 / 255.0, 0.6), 400)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	note.position = Vector2(0, 1048)
	note.custom_minimum_size = Vector2(1920, 20)
	root.add_child(note)

# ================= 聊天界面 =================
func _build_chat_screen() -> void:
	var root: Control = _screens["screen-chat"]
	var shell := VBoxContainer.new()
	shell.name = "Shell"
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = 360
	shell.offset_top = 10
	shell.offset_right = -360
	shell.offset_bottom = -10
	shell.add_theme_constant_override("separation", 12)
	root.add_child(shell)

	# ------ 头栏 ------
	var header := _glass(18, 18)
	header.name = "Header"
	shell.add_child(header)

	var hrow := HBoxContainer.new()
	hrow.name = "Row"
	hrow.add_theme_constant_override("separation", 12)
	header.add_child(hrow)

	# 左：头像 + 名称
	var avatar := UI.avatar("M", Palette.GRAD_BLUE_FROM, Palette.GRAD_BLUE_TO, 42, 12, 19)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(avatar)

	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_box.add_theme_constant_override("separation", 0)
	hrow.add_child(name_box)
	name_box.add_child(UI.label("Miku · 初音未来", 16, Palette.BA_DEEP, 700))
	name_box.add_child(UI.label("管理员 · 虚拟偶像", 12, Palette.BA_TEXT_DIM, 400))

	# 右：model-tag + 操作按钮
	var right := HBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 8)
	hrow.add_child(right)

	var tag := Label.new()
	tag.name = "ModelTag"
	tag.text = "Gemini"
	tag.add_theme_font_override("font", UI.font(12, 500))
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", Palette.BA_DEEP)
	tag.add_theme_stylebox_override("normal", UI.chip(Palette.BA_CARD_TINT, Palette.BA_BORDER_BLUE))
	right.add_child(tag)

	var b_rollback := UI.button("↩ 倒回", false, false, 13, 8, 16)
	b_rollback.pressed.connect(func(): toast("（占位）倒回：回到最近一次 model 回复"))
	right.add_child(b_rollback)

	var b_save := UI.button("💾 存档", false, false, 13, 8, 16)
	b_save.pressed.connect(func(): open_save_panel("save"))
	right.add_child(b_save)

	var b_preset := UI.button("预设", false, false, 13, 8, 16)
	b_preset.pressed.connect(func(): open_overlay("overlay-preset"))
	right.add_child(b_preset)

	var b_char := UI.button("角色卡", false, false, 13, 8, 16)
	b_char.pressed.connect(func(): open_overlay("overlay-char"))
	right.add_child(b_char)

	# ------ 消息区 ------
	var msg_panel := _glass(18, 0)
	msg_panel.name = "Messages"
	msg_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(msg_panel)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	msg_panel.add_child(scroll)

	var msg_box := VBoxContainer.new()
	msg_box.name = "MsgBox"
	msg_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_box.add_theme_constant_override("separation", 14)
	scroll.add_child(msg_box)
	_msg_box = msg_box

	# 5 条示例对话（与 HTML 一致）
	_add_chat_message(msg_box, "char", "喵哈哈，Master 终于来了~ 今天想玩点什么？世界观设定我们已经聊了不少哦！")
	_add_chat_message(msg_box, "user", "今天我想继续上次的海岛别墅设定，Miku 有什么新点子吗？")
	_add_chat_message(msg_box, "char",
		"唔…让我想想~ 上次我们说到别墅二楼的主卧室有个超大的圆形床呢。\n\n要不今天我们给花园的废墟区加点料？比如月光下会发光的古代遗迹，很适合偶遇新角色~",
		{"roll": "🎲 检定 45 → 成功"})
	_add_chat_message(msg_box, "user", "好呀，那就让它变成一个邂逅场景吧！")
	_add_chat_message(msg_box, "char",
		"OKnya！那就这么定了，我会把它写进世界书里~ 黄昏时分的遗迹，远处传来隐约的歌声，Master 走近一看……是一位从未见过的少女，正对着月光轻轻哼唱呢。\n\n少女似乎察觉到了脚步声，缓缓回过头来，银色的发丝在月光下微微发亮。啊，Master，我们是不是邂逅了一个了不得的角色呀？")

	# ------ 输入栏 ------
	var input_bar := _glass(18, 14)
	input_bar.name = "InputBar"
	shell.add_child(input_bar)

	var irow := HBoxContainer.new()
	irow.name = "Row"
	irow.add_theme_constant_override("separation", 10)
	input_bar.add_child(irow)

	var input := LineEdit.new()
	input.name = "Input"
	input.placeholder_text = "输入消息…"
	input.custom_minimum_size = Vector2(0, 46)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_override("font", UI.font(15, 400))
	input.add_theme_font_size_override("font_size", 15)
	input.add_theme_color_override("font_color", Palette.BA_TEXT)
	input.add_theme_color_override("font_placeholder_color", Palette.PLACEHOLDER)
	input.add_theme_color_override("caret_color", Palette.BA_BLUE)
	input.add_theme_stylebox_override("normal", UI.input_box(false, 14, 11, 16))
	input.add_theme_stylebox_override("focus", UI.input_box(true, 14, 11, 16))
	irow.add_child(input)
	_input_line = input
	# 回车发送
	input.text_submitted.connect(_on_input_submitted)

	var b_send := UI.button("发送", true, false, 15, 13, 28)
	b_send.pressed.connect(_on_send_pressed)
	irow.add_child(b_send)

## 生成一条示例消息（与 HTML .msg.char / .msg.user 一致）
## char：头像在左、白气泡撑满；user：气泡靠右、头像在最右
func _add_chat_message(box: VBoxContainer, kind: String, text: String, extra: Variant = null) -> void:
	if extra == null:
		extra = {}
	var is_user := kind == "user"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	# user 行：左侧占位把内容推到右边
	if is_user:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

	# 头像（char 在左 / user 在右，SHRINK 防止被拉长）
	var avatar := UI.avatar("U" if is_user else "M",
		Palette.GRAD_ORANGE_FROM if is_user else Palette.GRAD_BLUE_FROM,
		Palette.GRAD_ORANGE_TO if is_user else Palette.GRAD_BLUE_TO, 36, 10, 15)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if not is_user:
		row.add_child(avatar)

	# 气泡
	var bubble := PanelContainer.new()
	if is_user:
		bubble.add_theme_stylebox_override("panel", UI.bubble_user())
		bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		bubble.add_theme_stylebox_override("panel", UI.bubble_char())
		bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(bubble)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	bubble.add_child(vb)

	# 正文：fit_content 让气泡贴合内容高度（不撑满）
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.add_theme_font_override("normal_font", UI.font(15, 400))
	rtl.add_theme_font_size_override("normal_font_size", 15)
	rtl.add_theme_color_override("default_color", Palette.BA_TEXT)
	if is_user:
		# 对应 CSS max-width:55%，限制宽度触发换行
		rtl.custom_minimum_size = Vector2(620, 0)
		rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.text = text
	vb.add_child(rtl)

	if extra.has("roll"):
		var tag_row := HBoxContainer.new()
		vb.add_child(tag_row)
		var roll := Label.new()
		roll.text = extra["roll"]
		roll.add_theme_font_override("font", UI.font(13, 400))
		roll.add_theme_font_size_override("font_size", 13)
		roll.add_theme_color_override("font_color", Palette.BA_BLUE)
		roll.add_theme_stylebox_override("normal", UI.chip(Color(94.0 / 255.0, 167.0 / 255.0, 255.0 / 255.0, 0.14), Palette.BA_BORDER_BLUE))
		tag_row.add_child(roll)

	# user 头像追加到行尾（最右）
	if is_user:
		row.add_child(avatar)

# ================= 预设面板 =================
func _build_overlay_preset() -> void:
	var ov := Control.new()
	ov.name = "overlay-preset"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.visible = false
	add_child(ov)
	_overlays["overlay-preset"] = ov

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Palette.OVERLAY_BG
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(dim)

	var panel := _glass(18, 22)
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -750
	panel.offset_top = -410
	panel.offset_right = 750
	panel.offset_bottom = 410
	ov.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var topbar := HBoxContainer.new()
	topbar.add_theme_constant_override("separation", 14)
	vbox.add_child(topbar)
	var b_back := UI.button("← 返回聊天", true, false, 13, 9, 16)
	b_back.pressed.connect(func(): close_overlay("overlay-preset"))
	topbar.add_child(b_back)
	topbar.add_child(UI.label("预设管理", 18, Palette.BA_DEEP, 800))
	var sub := UI.label("  v1.1 · 按文件头 depth 排序", 12, Palette.BA_TEXT_DIM, 400)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	topbar.add_child(sub)

	var layout := HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 16)
	vbox.add_child(layout)

	var list := UI.glass_panel_static(320, 0, 12)
	layout.add_child(list)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	list.add_child(lv)
	lv.add_child(UI.label("预设文件", 15, Palette.BA_DEEP, 700))

	_add_preset_item(lv, "开篇伪装对话", "depth 00", true)
	_add_preset_item(lv, "Miku 角色信息", "depth 10", false)
	_add_preset_item(lv, "世界规则", "depth 20", false)
	_add_preset_item(lv, "末尾格式要求", "depth 90", false)

	var b_new := UI.button("＋ 新建条目", false, false, 13, 9, 14)
	b_new.pressed.connect(func(): toast("（占位）新建：弹窗填写名称/深度"))
	lv.add_child(b_new)

	var edit := UI.glass_panel_static(0, 0, 12)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(edit)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 10)
	edit.add_child(ev)

	ev.add_child(UI.label("Miku 角色信息", 16, Palette.BA_DEEP, 700))

	var fm := HBoxContainer.new()
	fm.add_theme_constant_override("separation", 10)
	ev.add_child(fm)
	fm.add_child(_field("depth", "10", 180))
	fm.add_child(_field("name", "Miku 角色信息", 480))

	var body := RichTextLabel.new()
	body.name = "BodyEditor"
	body.bbcode_enabled = true
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.scroll_active = true
	body.add_theme_font_override("normal_font", UI.font(15, 400, true))
	body.add_theme_font_size_override("normal_font_size", 15)
	body.add_theme_color_override("default_color", Palette.BA_TEXT)
	body.add_theme_stylebox_override("normal", UI.body_editor_box())
	body.text = "[color=#5ea7ff]### 身份与种族[/color]\nAI 助手 · 虚拟偶像（初音未来）\n\n[color=#5ea7ff]### 性格[/color]\n[color=#5ea7ff]### 能力[/color]\n【打破第四面墙】系统管理员权限\n【欲梦编织】性癖世界沙盒\n\n[color=#5ea7ff]### 禁区[/color]\n禁止不可逆死亡 / 永久伤害 / 精神崩溃"
	ev.add_child(body)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	ev.add_child(actions)
	var b_save := UI.button("保存", true, false, 13, 9, 20)
	b_save.pressed.connect(func(): toast("（占位）保存到 user 当前版本目录"))
	actions.add_child(b_save)

func _field(label_text: String, value: String, min_w: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(min_w, 0)
	box.add_theme_constant_override("separation", 4)
	var l := UI.label(label_text, 12, Palette.BA_TEXT_DIM, 400)
	box.add_child(l)
	var le := LineEdit.new()
	le.text = value
	le.add_theme_font_override("font", UI.font(14, 400))
	le.add_theme_font_size_override("font_size", 14)
	le.add_theme_color_override("font_color", Palette.BA_TEXT)
	le.add_theme_color_override("font_placeholder_color", Palette.PLACEHOLDER)
	le.add_theme_color_override("caret_color", Palette.BA_BLUE)
	le.add_theme_stylebox_override("normal", UI.input_box(false, 8, 9, 12))
	le.add_theme_stylebox_override("focus", UI.input_box(true, 8, 9, 12))
	box.add_child(le)
	return box

func _add_preset_item(list: VBoxContainer, name: String, sub: String, active: bool) -> void:
	var item := Button.new()
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size = Vector2(0, 44)
	item.add_theme_stylebox_override("normal", UI.list_item(active))
	item.add_theme_stylebox_override("hover", UI.list_item(active, true))
	item.add_theme_stylebox_override("pressed", UI.list_item(active))
	item.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	list.add_child(item)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(h)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vb)
	vb.add_child(UI.label(name, 14, Palette.BA_TEXT, 400))
	vb.add_child(UI.label(sub, 12, Palette.BA_TEXT_DIM, 400))
	var lock := UI.label("●", 12, Palette.BA_BLUE, 400)
	lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(lock)
	item.pressed.connect(func(): toast("（占位）编辑：" + name))

# ================= 角色卡面板 =================
func _build_overlay_char() -> void:
	var ov := Control.new()
	ov.name = "overlay-char"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.visible = false
	add_child(ov)
	_overlays["overlay-char"] = ov

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Palette.OVERLAY_BG
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(dim)

	var panel := _glass(18, 22)
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -750
	panel.offset_top = -410
	panel.offset_right = 750
	panel.offset_bottom = 410
	ov.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var topbar := HBoxContainer.new()
	topbar.add_theme_constant_override("separation", 14)
	vbox.add_child(topbar)
	var b_back := UI.button("← 返回聊天", true, false, 13, 9, 16)
	b_back.pressed.connect(func(): close_overlay("overlay-char"))
	topbar.add_child(b_back)
	topbar.add_child(UI.label("角色卡", 18, Palette.BA_DEEP, 800))
	var sub := UI.label("  LLM 生成角色 · 占位数据", 12, Palette.BA_TEXT_DIM, 400)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	topbar.add_child(sub)

	var layout := HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 16)
	vbox.add_child(layout)

	var list := UI.glass_panel_static(300, 0, 12)
	layout.add_child(list)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	list.add_child(lv)
	lv.add_child(UI.label("角色列表", 15, Palette.BA_DEEP, 700))

	_add_char_item(lv, "M", "Miku", "虚拟偶像", true)
	_add_char_item(lv, "S", "沙耶", "修女", false)
	_add_char_item(lv, "L", "凛音", "忍者", false)

	var detail := UI.glass_panel_static(0, 0, 12)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 12)
	detail.add_child(dv)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	dv.add_child(head)
	var av := UI.avatar("M", Palette.GRAD_BLUE_FROM, Palette.GRAD_BLUE_TO, 60, 16, 26)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(av)
	var hb := VBoxContainer.new()
	head.add_child(hb)
	hb.add_child(UI.label("Miku · 初音未来", 24, Palette.BA_DEEP, 800))
	hb.add_child(UI.label("身份：AI助手 / 种族：虚拟偶像 · 管理员权限", 13, Palette.BA_TEXT_DIM, 400))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	dv.add_child(stats)
	for s in [["80", "智力 INT"], ["75", "魅力 CHA"], ["60", "感知 WIS"]]:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_stylebox_override("panel", UI.stat_cell())
		stats.add_child(cell)
		var cb := VBoxContainer.new()
		cb.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(cb)
		var v := UI.label(s[0], 20, Palette.BA_BLUE, 800)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cb.add_child(v)
		var k := UI.label(s[1], 12, Palette.BA_TEXT_DIM, 400)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cb.add_child(k)

	dv.add_child(_section("### 性格与深层性癖",
		"吐槽式对话 + 萌 + 高性能。辅助型，自慰展示癖，侍奉以口交/手交为主，对直接性交保有贞操。"))
	dv.add_child(_section("### 背景与战斗特质",
		"作为系统管理员维护乐园运行，擅长沙盒管理。战斗中倾向于辅助与支援位。"))

func _add_char_item(list: VBoxContainer, avatar_char: String, name: String, race: String, active: bool) -> void:
	var item := Button.new()
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size = Vector2(0, 56)
	item.add_theme_stylebox_override("normal", UI.list_item(active))
	item.add_theme_stylebox_override("hover", UI.list_item(active, true))
	item.add_theme_stylebox_override("pressed", UI.list_item(active))
	item.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	list.add_child(item)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 10)
	item.add_child(h)
	var av := UI.avatar(avatar_char, Palette.GRAD_BLUE_FROM, Palette.GRAD_BLUE_TO, 34, 9, 14)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var vb := VBoxContainer.new()
	h.add_child(vb)
	vb.add_child(UI.label(name, 14, Palette.BA_TEXT, 400))
	vb.add_child(UI.label(race, 12, Palette.BA_TEXT_DIM, 400))
	item.pressed.connect(func(): toast("（占位）查看角色：" + name))

func _section(title: String, body: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.add_child(UI.label(title, 17, Palette.BA_BLUE, 700))
	var sep := ColorRect.new()
	sep.color = Palette.BA_BORDER
	sep.custom_minimum_size = Vector2(0, 1)
	vb.add_child(sep)
	var b := UI.label(body, 15, Palette.BA_TEXT, 400)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(b)
	return vb

# ================= 存档面板 =================
func _build_overlay_save() -> void:
	var ov := Control.new()
	ov.name = "overlay-save"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.visible = false
	add_child(ov)
	_overlays["overlay-save"] = ov

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Palette.OVERLAY_BG
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(dim)

	var panel := _glass(18, 22)
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -560
	panel.offset_top = -400
	panel.offset_right = 560
	panel.offset_bottom = 400
	ov.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var topbar := HBoxContainer.new()
	topbar.add_theme_constant_override("separation", 14)
	vbox.add_child(topbar)
	var b_back := UI.button("← 返回", true, false, 13, 9, 16)
	b_back.pressed.connect(func(): close_overlay("overlay-save"))
	topbar.add_child(b_back)
	topbar.add_child(UI.label("存档管理", 18, Palette.BA_DEEP, 800))
	var lbl := UI.label("读取模式", 12, Palette.BA_TEXT_DIM, 400)
	lbl.name = "ModeLabel"
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	topbar.add_child(lbl)

	var scroll_pc := UI.glass_panel_static(0, 0, 12)
	scroll_pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll_pc)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_pc.add_child(scroll)
	var slots_box := VBoxContainer.new()
	slots_box.name = "SlotsBox"
	slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_box.add_theme_constant_override("separation", 10)
	scroll.add_child(slots_box)

	_refresh_save_slots()

# ================= API 配置弹窗 =================
func _build_overlay_api() -> void:
	var ov := Control.new()
	ov.name = "overlay-api"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.visible = false
	add_child(ov)
	_overlays["overlay-api"] = ov

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Palette.OVERLAY_BG
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(dim)

	var panel := _glass(18, 22)
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -330
	panel.offset_top = -300
	panel.offset_right = 330
	panel.offset_bottom = 300
	ov.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	vbox.add_child(UI.label("API 配置", 18, Palette.BA_DEEP, 800))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vbox.add_child(tabs)
	for tab_name in ["Gemini", "DeepSeek", "自定义"]:
		var tb := Button.new()
		tb.text = tab_name
		tb.focus_mode = Control.FOCUS_NONE
		tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_stylebox_override("normal", UI.api_tab(false))
		tb.add_theme_stylebox_override("hover", UI.api_tab(false))
		tb.add_theme_stylebox_override("pressed", UI.api_tab(true))
		tb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		tb.add_theme_font_override("font", UI.font(14, 400))
		tb.add_theme_font_size_override("font_size", 14)
		tb.add_theme_color_override("font_color", Palette.BA_DEEP)
		tb.add_theme_color_override("font_hover_color", Palette.BA_DEEP)
		tb.add_theme_color_override("font_pressed_color", Palette.BA_DEEP)
		tb.pressed.connect(func(): _switch_api_tab(tabs, tb))
		tabs.add_child(tb)

	vbox.add_child(_field("API URL", "https://gcli.ggchan.dev/v1/chat/completions", 0))
	vbox.add_child(_field("API Key", "", 0))
	vbox.add_child(_field("模型", "gemini-3.1-pro-preview", 0))

	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 10)
	vbox.add_child(h2)
	h2.add_child(_field("温度", "1.3", 300))
	h2.add_child(_field("Top P", "0.88", 300))

	var note := UI.label("配置将保存到 user://config.cfg（占位说明，仅作美术参考，无实际保存功能）",
		12, Palette.BA_TEXT_DIM, 400)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(note)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(actions)
	var b_cancel := UI.button("取消", false, false, 13, 9, 20)
	b_cancel.pressed.connect(func(): close_overlay("overlay-api"))
	actions.add_child(b_cancel)
	var b_save := UI.button("保存", true, false, 13, 9, 20)
	b_save.pressed.connect(func(): close_overlay("overlay-api"))
	actions.add_child(b_save)

func _switch_api_tab(tabs: HBoxContainer, clicked: Button) -> void:
	for child in tabs.get_children():
		if child is Button:
			var active := child == clicked
			child.add_theme_stylebox_override("normal", UI.api_tab(active))
			child.add_theme_stylebox_override("pressed", UI.api_tab(active))

# ================= 存档槽位 =================
func _refresh_save_slots() -> void:
	var ov: Control = _overlays["overlay-save"]
	var slots: VBoxContainer = ov.find_child("SlotsBox", true, false)
	for child in slots.get_children():
		child.queue_free()
	for i in range(FAKE_SLOTS.size()):
		slots.add_child(_make_save_slot(i, FAKE_SLOTS[i]))

func _make_save_slot(idx: int, slot) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 56)
	row.add_theme_stylebox_override("panel", UI.glass(12, 16))
	# 关键：不要对子节点设 anchors（PanelContainer 会自动布局），否则内边距丢失、文字贴边
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	# RichTextLabel 不解析 &nbsp; 实体，改用普通空格分隔；并设置 default_color 避免白色字融入玻璃
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_font_override("normal_font", UI.font(15, 400))
	info.add_theme_font_size_override("normal_font_size", 15)
	info.add_theme_color_override("default_color", Palette.BA_TEXT)
	h.add_child(info)

	if slot:
		info.text = "#%d  |  Day %d  |  %s" % [idx + 1, slot["day"], slot["created"]]
	else:
		info.text = "#%d  |  [color=#6d8cae][ 空槽位 ][/color]" % (idx + 1)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	h.add_child(actions)

	if slot:
		actions.add_child(_slot_button("读取", Palette.SLOT_LOAD, "（占位）读取槽位 #%d" % (idx + 1)))
	if _save_mode == "save":
		actions.add_child(_slot_button("保存", Palette.SLOT_SAVE, "（占位）保存到槽位 #%d" % (idx + 1)))
	if slot:
		actions.add_child(_slot_button("删除", Palette.SLOT_DELETE, "（占位）删除槽位 #%d" % (idx + 1)))
	return row

func _slot_button(text: String, color: Color, msg: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", UI.slot_btn(color))
	b.add_theme_stylebox_override("hover", UI.slot_btn(color))
	b.add_theme_stylebox_override("pressed", UI.slot_btn(color))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", UI.font(13, 500))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(func(): toast(msg))
	return b

# ================= 对话发送与响应 =================

## 输入框回车提交
func _on_input_submitted(text: String) -> void:
	if text.strip_edges() != "":
		send_message(text)

## 发送按钮点击
func _on_send_pressed() -> void:
	var text = _input_line.text if _input_line else ""
	if text.strip_edges() != "":
		send_message(text)

## 统一发送入口：把用户消息渲染到 UI 并交给 LLMClient
func send_message(text: String) -> void:
	if _input_line:
		_input_line.text = ""
	if _msg_box:
		_add_chat_message(_msg_box, "user", text)
	var llm = get_node_or_null("/root/LLMClient")
	if llm:
		llm.send_chat(text)

## LLM 开始请求
func _on_llm_started() -> void:
	pass  # 可在此显示"生成中"状态

## LLM 回复完成：追加到底部
func _on_llm_finished(content: String) -> void:
	if _msg_box:
		_add_chat_message(_msg_box, "char", content)
		_scroll_to_bottom()

## 系统错误：弹出红色 Toast
func _on_system_error(msg: String) -> void:
	toast(msg, true)

## 滚动到消息区底部
func _scroll_to_bottom() -> void:
	if _msg_box:
		var sc: ScrollContainer = _msg_box.get_parent() as ScrollContainer
		if sc:
			sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)

# ================= 交互 =================
func show_screen(id: String) -> void:
	for key in _screens:
		_screens[key].visible = (key == id)
	_screen_stack.clear()
	_screen_stack.append(id)

func open_overlay(id: String) -> void:
	if _overlays.has(id):
		_overlays[id].visible = true

func close_overlay(id: String) -> void:
	if _overlays.has(id):
		_overlays[id].visible = false

func open_save_panel(mode: String) -> void:
	_save_mode = mode
	var ov: Control = _overlays["overlay-save"]
	var lbl: Label = ov.find_child("ModeLabel", true, false)
	lbl.text = "保存 / 读取 / 删除" if mode == "save" else "读取 / 删除"
	_refresh_save_slots()
	open_overlay("overlay-save")

func toast(text: String, is_error: bool = false) -> void:
	var t := Label.new()
	t.text = text
	t.add_theme_font_override("font", UI.font(14, 400))
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", Color.WHITE)
	t.add_theme_stylebox_override("normal", UI.error_toast_box() if is_error else UI.toast_box())
	t.modulate = Color(1, 1, 1, 0)
	t.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	t.position = Vector2(960 - 220, 990)
	t.custom_minimum_size = Vector2(440, 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(t)
	var tw := create_tween()
	tw.tween_property(t, "modulate", Color(1, 1, 1, 1), 0.2)
	tw.tween_interval(1.6)
	tw.tween_property(t, "modulate", Color(1, 1, 1, 0), 0.4)
	tw.tween_callback(t.queue_free)