extends Node

## 阶段6 · 开始游戏初始化临时存档测试：旧 temp_run/历史应被清空
## 用法：--headless --scene res://tools/start_game_test.tscn

func _ready() -> void:
	print("[SG] 开始游戏初始化测试")
	var sm = get_node_or_null("/root/SaveManager")
	var llm = get_node_or_null("/root/LLMClient")
	var dm = get_node_or_null("/root/DataManager")

	# 先造一个旧角色 + 一份历史（模拟未保存残留）
	sm.create_new_game()
	var tool = get_node_or_null("/root/LLMToolExecutor")
	tool._handler_write_character({"name": "旧角色A", "content": "### 外观\n旧"})
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：旧对话]} ｝"},
		{"role": "assistant", "content": "旧回复"},
	]
	print("[SG] 模拟旧状态: 角色数=", dm.get_all_characters().size(), " 历史条数=", llm._chat_history.size())

	# 实例化 UIShell 并调用开始游戏
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame
	shell._msg_box = VBoxContainer.new()
	shell._msg_box.add_child(Label.new())
	await get_tree().process_frame

	shell._on_start_game()
	await get_tree().process_frame

	# 验证
	var char_n: int = dm.get_all_characters().size()
	var hist_n: int = llm._chat_history.size()
	print("[SG] 开始游戏后: 角色数=", char_n, " 历史条数=", hist_n)
	if char_n == 0 and hist_n == 0:
		print("[SG] ✅ 临时存档已初始化：旧角色与历史被清空")
	else:
		print("[SG] ❌ 未清空（角色=", char_n, " 历史=", hist_n, "）")

	shell.queue_free()
	get_tree().quit(0)
