extends Node

## 阶段6 · API Tab 切换测试：点 DeepSeek Tab 应填充对应 URL/模型/温度/topP
## 用法：--headless --scene res://tools/api_tab_test.tscn

func _ready() -> void:
	print("[API] 测试 Tab 切换")

	# 用 call_deferred 实例化 UIShell，避免 _ready 时序问题
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame

	# 手动构造 API 输入框成员
	shell._api_url_edit = LineEdit.new()
	shell._api_model_edit = LineEdit.new()
	shell._api_temp_edit = LineEdit.new()
	shell._api_topp_edit = LineEdit.new()
	shell._api_key_edit = LineEdit.new()

	# 模拟点击 DeepSeek Tab：调用 _switch_api_tab 的核心（_tab_text_to_key + _apply_preset_to_fields）
	var key = shell._tab_text_to_key("DeepSeek")
	print("[API] DeepSeek → key: ", key)
	shell._apply_preset_to_fields(key)
	print("[API] url=[", shell._api_url_edit.text, "] model=[", shell._api_model_edit.text, "] temp=[", shell._api_temp_edit.text, "] topp=[", shell._api_topp_edit.text, "]")

	if shell._api_url_edit.text == "https://api.deepseek.com/chat/completions" \
			and shell._api_model_edit.text == "deepseek-v4-flash":
		print("[API] ✅ DeepSeek Tab 填充正确")
	else:
		print("[API] ❌ DeepSeek Tab 填充错误")

	# 模拟点 Gemini
	var key2 = shell._tab_text_to_key("Gemini")
	shell._apply_preset_to_fields(key2)
	print("[API] Gemini url=[", shell._api_url_edit.text, "] model=[", shell._api_model_edit.text, "]")
	if shell._api_url_edit.text == "https://gcli.ggchan.dev/v1/chat/completions":
		print("[API] ✅ Gemini Tab 填充正确")
	else:
		print("[API] ❌ Gemini Tab 填充错误")

	shell.queue_free()
	get_tree().quit(0)
