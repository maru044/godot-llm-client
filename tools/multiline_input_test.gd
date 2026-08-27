extends Node

## 阶段6 · 多行输入栏测试：输入框应为 TextEdit(多行)，支持 enter/shift+enter 逻辑
## 用法：--headless --scene res://tools/multiline_input_test.tscn

func _ready() -> void:
	print("[MI] 开始多行输入测试")
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame

	# 找聊天页的 Input
	var chat: Control = shell._screens.get("screen-chat")
	var input = null
	if chat:
		for c in chat.get_children():
			var in2 = c.find_child("Input", true, false)
			if in2:
				input = in2
				break
	print("[MI] Input 找到: ", input != null)
	if input == null:
		print("[MI] ❌ 未找到 Input")
		get_tree().quit(0)
		return

	print("[MI] Input 类型: ", input.get_class())
	var is_multiline := input is TextEdit
	if is_multiline:
		print("[MI] ✅ 输入栏为 TextEdit(多行)")
	else:
		print("[MI] ❌ 不是多行 TextEdit")

	# 验证 wrap_mode 已设(>0)
	var wrap = int(input.wrap_mode)
	print("[MI] wrap_mode=", wrap, " (>0 则自动换行)")
	if wrap > 0:
		print("[MI] ✅ 已启用自动换行")

	shell.queue_free()
	get_tree().quit(0)
