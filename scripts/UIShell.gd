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
var _send_button: Button             # 发送按钮（用于思考中禁用）
var _model_reply_count: int = 0    # 当前模型回复槽位，便于追加

# --- 预设面板运行期引用 ---
var _preset_list_container: VBoxContainer          # 列表容器（动态生成）
var _preset_title_lbl: Label                        # 编辑区标题
var _preset_depth_edit: LineEdit                    # depth 输入
var _preset_name_edit: LineEdit                     # name 输入
var _preset_body_edit: TextEdit                     # 正文编辑
var _preset_selected_file: String = ""              # 当前选中的文件

# --- 角色卡面板运行期引用 ---
var _char_list_container: VBoxContainer             # 角色列表容器
var _char_detail_vbox: VBoxContainer                # 详情区容器
var _selected_char_id: String = ""                  # 当前选中角色 id

# --- API 配置弹窗运行期引用 ---
var _api_url_edit: LineEdit
var _api_key_edit: LineEdit
var _api_model_edit: LineEdit
var _api_temp_edit: LineEdit
var _api_topp_edit: LineEdit
var _api_selected_key: String = ""   # 当前选中的预设 key（gemini/deepseek/custom）

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
	b_user.pressed.connect(_on_open_user_dir)
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
	b_rollback.pressed.connect(_on_rollback)
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

	# 不再放示例假气泡；聊天页消息由真实对话/读档动态生成

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
	_send_button = b_send

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
	rtl.selection_enabled = true          # 允许选中复制
	rtl.context_menu_enabled = true       # 右键复制菜单
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
	lv.name = "PresetList"
	lv.add_theme_constant_override("separation", 8)
	list.add_child(lv)
	lv.add_child(UI.label("预设文件", 15, Palette.BA_DEEP, 700))
	_preset_list_container = lv

	var b_new := UI.button("＋ 新建条目", false, false, 13, 9, 14)
	b_new.pressed.connect(_on_preset_new)
	lv.add_child(b_new)

	_refresh_preset_list()

	var edit := UI.glass_panel_static(0, 0, 12)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(edit)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 10)
	edit.add_child(ev)

	_preset_title_lbl = UI.label("（选择条目后编辑）", 16, Palette.BA_DEEP, 700)
	ev.add_child(_preset_title_lbl)

	var fm := HBoxContainer.new()
	fm.add_theme_constant_override("separation", 10)
	ev.add_child(fm)
	var depth_box := _field("depth", "0", 180)
	fm.add_child(depth_box)
	_preset_depth_edit = depth_box.get_meta("edit") as LineEdit
	var name_box := _field("name", "新条目", 480)
	fm.add_child(name_box)
	_preset_name_edit = name_box.get_meta("edit") as LineEdit

	# 正文编辑器：TextEdit（可编辑)
	var body := TextEdit.new()
	body.name = "BodyEditor"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("font", UI.font(15, 400, true))
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Palette.BA_TEXT)
	body.add_theme_stylebox_override("normal", UI.body_editor_box())
	body.text = ""
	body.placeholder_text = "在此输入提示词正文..."
	body.wrap_mode = 1  # TextEdit.LineWrappingMode.WRAP_WORD
	ev.add_child(body)
	_preset_body_edit = body

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	ev.add_child(actions)
	var b_save := UI.button("保存", true, false, 13, 9, 20)
	b_save.pressed.connect(_on_preset_save)
	actions.add_child(b_save)

## 构建带 label 的输入框，返回 VBoxContainer；LineEdit 存于 box 的 meta "edit"
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
	box.set_meta("edit", le)
	return box

## 刷新预设列表：从 PromptSchema.list_entries 动态生成（按 depth 排序）
func _refresh_preset_list() -> void:
	if _preset_list_container == null:
		return
	for child in _preset_list_container.get_children():
		if child is Button:
			child.queue_free()
	var ps = get_node_or_null("/root/PromptSchema")
	if ps == null:
		return
	var entries = ps.list_entries()
	for e in entries:
		var file: String = e.get("file", "")
		var name: String = e.get("name", file)
		var depth: int = int(e.get("depth", 0))
		var active: bool = (file == _preset_selected_file)
		var item := _make_preset_list_item(name, "depth %02d" % depth, active, file)
		_preset_list_container.add_child(item)


## 生成一个预设列表项
func _make_preset_list_item(name: String, sub: String, active: bool, file: String) -> Button:
	var item := Button.new()
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size = Vector2(0, 44)
	item.add_theme_stylebox_override("normal", UI.list_item(active))
	item.add_theme_stylebox_override("hover", UI.list_item(active, true))
	item.add_theme_stylebox_override("pressed", UI.list_item(active))
	item.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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
	item.pressed.connect(func(): _on_preset_select(file))
	return item

# ================= 预设面板 · 动作 =================

## 选中列表项，加载条目到编辑器
func _on_preset_select(file: String) -> void:
	var ps = get_node_or_null("/root/PromptSchema")
	if ps == null or _preset_body_edit == null:
		return
	var body = ps.get_entry_body(file)
	if body.is_empty():
		return
	_preset_selected_file = file
	if _preset_title_lbl:
		_preset_title_lbl.text = String(body.get("name", file))
	if _preset_name_edit:
		_preset_name_edit.text = String(body.get("name", file))
	if _preset_depth_edit:
		_preset_depth_edit.text = str(int(body.get("depth", 0)))
	if _preset_body_edit:
		_preset_body_edit.text = String(body.get("content", ""))
	_refresh_preset_list()

## 保存当前条目（有选中文件=更新；无选中文件=新建）
func _on_preset_save() -> void:
	var ps = get_node_or_null("/root/PromptSchema")
	if ps == null:
		return
	if _preset_selected_file == "":
		# 新建模式：创建新条目
		_create_entry_from_editor()
		return
	var name = _preset_name_edit.text if _preset_name_edit else ""
	var depth = _preset_depth_edit.text.strip_edges().to_int() if _preset_depth_edit else 0
	var content = _preset_body_edit.text if _preset_body_edit else ""
	var ok = ps.update_entry(_preset_selected_file, name, depth, "system", content)
	toast("已保存预设" if ok else "保存失败")
	if ok:
		_refresh_preset_list()

## 新建条目：弹窗输入名称+深度
func _on_preset_new() -> void:
	var ps = get_node_or_null("/root/PromptSchema")
	if ps == null:
		return
	# 直接进入编辑模式新建：清空编辑器，提示在新条目输入名称/深度
	_preset_selected_file = ""
	_preset_title_lbl.text = "（新条目：填写名称与深度后保存）"
	_preset_name_edit.text = ""
	_preset_depth_edit.text = "0"
	_preset_body_edit.text = ""
	_preset_name_edit.grab_focus()
	toast("新建：填写名称和深度后点击保存")

## 新建实际的保存动作（按名称+深度自动填充文件头，role 默认 system）
## 由 _on_preset_save 在无选中文件时触发新建
func _create_entry_from_editor() -> void:
	var ps = get_node_or_null("/root/PromptSchema")
	if ps == null:
		return
	var name = _preset_name_edit.text.strip_edges() if _preset_name_edit else ""
	if name == "":
		toast("新建条目需先填写名称")
		return
	var depth = _preset_depth_edit.text.strip_edges().to_int() if _preset_depth_edit else 0
	var content = _preset_body_edit.text if _preset_body_edit else ""
	var file = ps.create_entry(name, depth, "system", content)
	if file != "":
		toast("已创建条目: " + name)
		_preset_selected_file = file
		_refresh_preset_list()
	else:
		toast("创建失败")

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
	var sub := UI.label("  LLM 生成角色（来自 DataManager）", 12, Palette.BA_TEXT_DIM, 400)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	topbar.add_child(sub)

	var layout := HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 16)
	vbox.add_child(layout)

	var list := UI.glass_panel_static(300, 0, 12)
	layout.add_child(list)
	var lv := VBoxContainer.new()
	lv.name = "CharList"
	lv.add_theme_constant_override("separation", 8)
	list.add_child(lv)
	lv.add_child(UI.label("角色列表", 15, Palette.BA_DEEP, 700))
	_char_list_container = lv

	var detail := UI.glass_panel_static(0, 0, 12)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(detail)
	var dv := VBoxContainer.new()
	dv.name = "CharDetail"
	dv.add_theme_constant_override("separation", 12)
	detail.add_child(dv)
	_char_detail_vbox = dv

	_refresh_char_list()

## 刷新角色列表：从 DataManager 动态读取，点击加载详情
func _refresh_char_list() -> void:
	if _char_list_container == null:
		return
	for child in _char_list_container.get_children():
		if child is Button:
			child.queue_free()
	var dm = get_node_or_null("/root/DataManager")
	if dm == null:
		return
	var headers = dm.get_all_characters()
	for h in headers:
		var cid: String = h.get("id", "")
		var name: String = h.get("name", "未知")
		var race: String = h.get("race", "")
		var active: bool = (cid == _selected_char_id)
		var item := _make_char_list_item(cid, name, race, active)
		_char_list_container.add_child(item)
	# 默认选中第一个（若有）
	if headers.size() > 0 and _selected_char_id == "":
		_on_char_select(String(headers[0].get("id", "")))


## 生成单个角色列表项
func _make_char_list_item(cid: String, name: String, race: String, active: bool) -> Button:
	var item := Button.new()
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size = Vector2(0, 56)
	item.add_theme_stylebox_override("normal", UI.list_item(active))
	item.add_theme_stylebox_override("hover", UI.list_item(active, true))
	item.add_theme_stylebox_override("pressed", UI.list_item(active))
	item.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 10)
	item.add_child(h)
	var initial := String(name).substr(0, 1).to_upper()
	var av := UI.avatar(initial, Palette.GRAD_BLUE_FROM, Palette.GRAD_BLUE_TO, 34, 9, 14)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var vb := VBoxContainer.new()
	h.add_child(vb)
	vb.add_child(UI.label(name, 14, Palette.BA_TEXT, 400))
	vb.add_child(UI.label(race if race != "" else "角色", 12, Palette.BA_TEXT_DIM, 400))
	item.pressed.connect(func(): _on_char_select(cid))
	return item


## 选中角色，加载详情（header + 正文）
func _on_char_select(cid: String) -> void:
	var dm = get_node_or_null("/root/DataManager")
	if dm == null or _char_detail_vbox == null:
		return
	_selected_char_id = cid
	# 清空详情
	for child in _char_detail_vbox.get_children():
		child.queue_free()

	var c = dm.get_character(cid)
	if c.is_empty():
		_char_detail_vbox.add_child(UI.label("（未找到该角色）", 14, Palette.BA_TEXT_DIM, 400))
		_refresh_char_list()
		return
	var header: Dictionary = c.get("header", {})
	var body: String = c.get("body", "")
	var name: String = header.get("name", cid)
	var race: String = header.get("race", "")
	var cls: String = header.get("class", "")

	# 头部
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_char_detail_vbox.add_child(head)
	var initial := String(name).substr(0, 1).to_upper()
	var av := UI.avatar(initial, Palette.GRAD_BLUE_FROM, Palette.GRAD_BLUE_TO, 60, 16, 26)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(av)
	var hb := VBoxContainer.new()
	head.add_child(hb)
	hb.add_child(UI.label(name, 24, Palette.BA_DEEP, 800))
	hb.add_child(UI.label("种族：%s / 职业：%s / ID:%s" % [race if race != "" else "未知", cls if cls != "" else "未知", cid], 13, Palette.BA_TEXT_DIM, 400))

	# 正文分栏（若 body 有内容，按 ### 分栏展示）
	if body.strip_edges() != "":
		_char_detail_vbox.add_child(_section("角色正文", body))
	else:
		_char_detail_vbox.add_child(UI.label("（该角色暂无正文内容）", 14, Palette.BA_TEXT_DIM, 400))

	_refresh_char_list()

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

	var url_box := _field("API URL", "", 0)
	vbox.add_child(url_box)
	_api_url_edit = url_box.get_meta("edit") as LineEdit
	var key_box := _field("API Key", "", 0)
	vbox.add_child(key_box)
	_api_key_edit = key_box.get_meta("edit") as LineEdit
	var model_box := _field("模型", "", 0)
	vbox.add_child(model_box)
	_api_model_edit = model_box.get_meta("edit") as LineEdit

	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 10)
	vbox.add_child(h2)
	var temp_box := _field("温度", "", 300)
	h2.add_child(temp_box)
	_api_temp_edit = temp_box.get_meta("edit") as LineEdit
	var topp_box := _field("Top P", "", 300)
	h2.add_child(topp_box)
	_api_topp_edit = topp_box.get_meta("edit") as LineEdit

	var note := UI.label("配置将保存/加载自 user://config.cfg",
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
	b_save.pressed.connect(_on_api_save)
	actions.add_child(b_save)

	# 打开面板时预填当前配置
	_prefill_api_fields()

func _switch_api_tab(tabs: HBoxContainer, clicked: Button) -> void:
	for child in tabs.get_children():
		if child is Button:
			var active := child == clicked
			child.add_theme_stylebox_override("normal", UI.api_tab(active))
			child.add_theme_stylebox_override("pressed", UI.api_tab(active))
	# 点击 Tab 时，把对应预设的 URL/模型/温度/topP 填充到输入框（不覆盖用户 key）
	var tab_key := _tab_text_to_key(clicked.text)
	if tab_key != "":
		_api_selected_key = tab_key
		_apply_preset_to_fields(tab_key)


## Tab 文字 → ConfigManager.presets key 映射
func _tab_text_to_key(text: String) -> String:
	match text:
		"Gemini":
			return "gemini"
		"DeepSeek":
			return "deepseek"
		"自定义":
			return "custom"
	return ""


## 把指定预设的 url/model/temp/top_p 填入输入框（保留当前 api_key）
func _apply_preset_to_fields(key: String) -> void:
	var cm = get_node_or_null("/root/ConfigManager")
	if cm == null:
		return
	var p: Dictionary = cm.presets.get(key, {})
	if p.is_empty():
		return
	if _api_url_edit:
		_api_url_edit.text = String(p.get("url", ""))
	if _api_model_edit:
		_api_model_edit.text = String(p.get("model", ""))
	if _api_temp_edit:
		_api_temp_edit.text = str(p.get("temp", 1.0))
	if _api_topp_edit:
		_api_topp_edit.text = str(p.get("top_p", 0.88))

## 打开弹窗时从 ConfigManager 预填字段
func _prefill_api_fields() -> void:
	var cm = get_node_or_null("/root/ConfigManager")
	if cm == null:
		return
	if _api_url_edit:
		_api_url_edit.text = cm.api_url
	if _api_key_edit:
		_api_key_edit.text = cm.api_key
	if _api_model_edit:
		_api_model_edit.text = cm.model
	if _api_temp_edit:
		_api_temp_edit.text = str(cm.api_temp)
	if _api_topp_edit:
		_api_topp_edit.text = str(cm.api_top_p)

## 保存配置到 ConfigManager 并落盘
func _on_api_save() -> void:
	var cm = get_node_or_null("/root/ConfigManager")
	if cm == null:
		return
	# 若用户切换了预设 Tab，保存时同步 active_api 及其模型固有属性
	if _api_selected_key != "":
		cm.active_api = _api_selected_key
		var p: Dictionary = cm.presets.get(_api_selected_key, {})
		if not p.is_empty():
			cm.thinking_disabled = p.get("thinking_disabled", false)
			cm.supports_vision = p.get("supports_vision", true)
	if _api_url_edit:
		cm.api_url = _api_url_edit.text.strip_edges()
	if _api_key_edit:
		cm.api_key = _api_key_edit.text.strip_edges()
	if _api_model_edit:
		cm.model = _api_model_edit.text.strip_edges()
	if _api_temp_edit:
		cm.api_temp = _api_temp_edit.text.strip_edges().to_float()
	if _api_topp_edit:
		cm.api_top_p = _api_topp_edit.text.strip_edges().to_float()
	cm.save_config()
	# 同步 LLMClient 通信参数
	var llm = get_node_or_null("/root/LLMClient")
	if llm:
		llm.refresh_config()
	toast("API 配置已保存")
	close_overlay("overlay-api")

## 打开 user:// 数据目录（资源管理器）
## 注意：OS.shell_open 需要真实绝对路径，不能用虚拟 user:// 路径
func _on_open_user_dir() -> void:
	var abs := ProjectSettings.globalize_path("user://")
	if abs != "":
		OS.shell_open(abs)
	else:
		toast("无法定位 user 目录")

# ================= 存档槽位 =================
func _refresh_save_slots() -> void:
	var ov: Control = _overlays["overlay-save"]
	var slots: VBoxContainer = ov.find_child("SlotsBox", true, false)
	for child in slots.get_children():
		child.queue_free()
	# 从 SaveManager 读取真实槽位数据（空槽位于多 slot 对应位置返回 null）
	var sm = get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var slot_infos = sm.get_slots_info()
	if slot_infos.size() > 0:
		for i in range(slot_infos.size()):
			slots.add_child(_make_save_slot(i, slot_infos[i]))
	else:
		# 兜底：至少显示 MAX_SLOTS 个槽位
		for i in range(SaveManagerClass.MAX_SLOTS):
			slots.add_child(_make_save_slot(i, null))

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
		var created = String(slot.get("created_at", "未知"))
		var msg_count = int(slot.get("msg_count", 0))
		info.text = "#%d  |  %s  |  %d 条消息" % [idx + 1, created, msg_count]
	else:
		info.text = "#%d  |  [color=#6d8cae][ 空槽位 ][/color]" % (idx + 1)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	h.add_child(actions)

	if slot:
		actions.add_child(_slot_button("读取", Palette.SLOT_LOAD, "载入槽位 #%d" % (idx + 1), func(): _on_load_slot(idx)))
	if _save_mode == "save":
		actions.add_child(_slot_button("保存", Palette.SLOT_SAVE, "保存到槽位 #%d" % (idx + 1), func(): _on_save_slot(idx)))
	if slot:
		actions.add_child(_slot_button("删除", Palette.SLOT_DELETE, "删除槽位 #%d" % (idx + 1), func(): _on_delete_slot(idx)))
	return row

func _slot_button(text: String, color: Color, msg: String, handler: Callable = Callable()) -> Button:
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
	if handler.is_valid():
		b.pressed.connect(func(): handler.call())
	else:
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

## LLM 开始请求：禁用发送按钮，变为"思考中"
func _on_llm_started() -> void:
	if _send_button:
		_send_button.disabled = true
		_send_button.text = "思考中…"
	if _input_line:
		_input_line.editable = false

## LLM 回复完成：恢复发送按钮 + 追加回复气泡
func _on_llm_finished(content: String) -> void:
	if _send_button:
		_send_button.disabled = false
		_send_button.text = "发送"
	if _input_line:
		_input_line.editable = true
	if _msg_box:
		_add_chat_message(_msg_box, "char", content)
		_scroll_to_bottom()

## 倒回：回退会话历史 + 用历史重建全部气泡（保证 UI 与历史一致，停在 assistant）
func _on_rollback() -> void:
	var llm = get_node_or_null("/root/LLMClient")
	if llm == null:
		return
	var rolled_text = llm.rollback_history()
	# 回填输入框（若倒回成功）
	if rolled_text != "" and _input_line:
		_input_line.text = rolled_text
		toast("已倒回上一轮")
	# 依历史重建气泡，绝不残留多余气泡（关键：回滚后 UI 末尾=历史末尾的 assistant）
	_rebuild_chat_from_history(llm._chat_history)

## 系统错误：弹出红色 Toast
func _on_system_error(msg: String) -> void:
	toast(msg, true)

# ================= 存档操作 =================

## 保存当前游戏到槽位
func _on_save_slot(idx: int) -> void:
	var sm = get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var ok = sm.save_current_game(idx)
	toast("已存入槽位 #%d" % (idx + 1) if ok else "保存失败")
	_refresh_save_slots()

## 从槽位读取游戏并还原历史气泡
func _on_load_slot(idx: int) -> void:
	var sm = get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var data = sm.load_game_from_slot(idx)
	if data.is_empty():
		toast("槽位 #%d 为空" % (idx + 1))
		return
	# 还原历史上下文气泡
	_rebuild_chat_from_history(data.get("chat_history", []))
	toast("已载入槽位 #%d" % (idx + 1))
	_refresh_save_slots()

## 删除指定槽位
func _on_delete_slot(idx: int) -> void:
	var sm = get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	sm.delete_slot(idx)
	toast("已删除槽位 #%d" % (idx + 1))
	_refresh_save_slots()

## 依据会话历史重建消息气泡（读档/还原用）
## 只渲染 user / assistant 的纯文本 content，跳过 tool/system/prefill 信息
func _rebuild_chat_from_history(history: Array) -> void:
	if _msg_box == null:
		return
	# 清空当前消息区
	for child in _msg_box.get_children():
		child.queue_free()

	for m in history:
		var role = (m as Dictionary).get("role", "")
		if role == "user":
			var txt = String(m.get("content", ""))
			var clean = _strip_user_wrap(txt)
			if clean.strip_edges() != "":
				_add_chat_message(_msg_box, "user", clean)
		elif role == "assistant":
			var txt = String(m.get("content", ""))
			# 跳过 tool_calls 的 assistant（无正文）与 prefill 残留
			if txt.strip_edges() != "" and not txt.begins_with("</think>"):
				var clean = txt.replace("<content>", "").replace("</content>", "").replace("[使用简体中文开始游戏:]", "").strip_edges()
				if clean.strip_edges() != "":
					_add_chat_message(_msg_box, "char", clean)
	_scroll_to_bottom()

## 去除用户消息包装 {[Master最新行动/语言：...]} ｝，还原原始输入
func _strip_user_wrap(txt: String) -> String:
	var out = txt
	# 找到包装前缀 {[Master最新行动/语言：，取其之后内容
	var idx = out.find("：")
	if idx != -1:
		out = out.substr(idx + 1)
	# 去掉包装后缀 ]} ｝（注意是 ]} ｝ 而非 } ｝）
	out = out.replace("]} ｝", "").strip_edges()
	return out

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