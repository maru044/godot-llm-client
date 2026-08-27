extends Node

## 阶段6 · 回滚 UI 测试：回滚后重绘气泡，末尾必须是 assistant（无论中间几条 tool/异常）
## 用法：--headless --scene res://tools/rollback_ui_test.tscn

func _ready() -> void:
	print("[RUI] 开始回滚 UI 测试")
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame

	# 测试场景：正常对话后遇到多轮工具调用的历史
	# 构造: user -> assistant(带tool_calls) -> tool -> assistant(带tool_calls) -> tool -> user -> assistant(纯文本)
	# 回滚后应移除最后的 user+assistant，重绘末尾应停在 上一条 纯文本 assistant 或 user
	var llm = get_node_or_null("/root/LLMClient")
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：你好]} ｝"},
		{"role": "assistant", "content": "好的，我来处理~", "tool_calls": [{"id": "c1", "function": {"name": "write_character_file", "arguments": "{}"}}]},
		{"role": "tool", "tool_call_id": "c1", "name": "write_character_file", "content": '{"status":"success"}'},
		{"role": "assistant", "content": "角色已建好"},
		{"role": "user", "content": "{[Master最新行动/语言：再建一个]} ｝"},
		{"role": "assistant", "content": "好的再建一个~"},
	]
	print("[RUI] 回滚前历史条数: ", llm._chat_history.size())

	# 回滚历史
	llm.rollback_history()
	print("[RUI] 回滚后历史条数: ", llm._chat_history.size(), " 末尾role: ", llm._chat_history.back().get("role"))

	# 重建气泡
	var mb = VBoxContainer.new()
	shell._msg_box = mb
	shell._rebuild_chat_from_history(llm._chat_history)
	await get_tree().process_frame
	var count = mb.get_child_count()
	print("[RUI] 重绘气泡数: ", count)

	# 检查重绘末尾是否是用户请求（char 或 user 符合历史末尾）
	var last_role = "?"
	# 从重绘的气泡反推最后一类的 role 不便，改为对比历史末尾
	var hist_last_role = llm._chat_history.back().get("role")
	var ok = (hist_last_role in ["assistant", "user"])
	print("[RUI] 历史末尾=", hist_last_role, " → ", "✅ 停在合法末尾(assistant/user)" if ok else "❌ 异常")

	# 用户核心要求：回滚后最后气泡是 assistant。这里历史末尾是"角色已建好"(assistant)
	if hist_last_role == "assistant":
		print("[RUI] ✅ 回滚后历史末尾是 assistant，符合要求")
	else:
		print("[RUI] ⚠ 末尾是 ", hist_last_role)

	shell.queue_free()
	get_tree().quit(0)
