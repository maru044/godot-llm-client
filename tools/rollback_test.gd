extends Node

## 阶段4 · 倒回功能测试：直接构造混合历史，验证 rollback_history 能正确回退。
## 包含 tool 消息场景。
## 用法：--headless --scene res://tools/rollback_test.tscn

func _ready() -> void:
	var llm = get_node_or_null("/root/LLMClient")
	print("[RB] 开始倒回测试")

	# 构造一段含 tool_calls + tool 混合的历史
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：喊我]} ｝"},
		{"role": "assistant", "content": "好的", "tool_calls": [{"id": "call_1", "type": "function", "function": {"name": "write_character_file", "arguments": "{\"name\":\"A\"}"}}]},
		{"role": "tool", "tool_call_id": "call_1", "name": "write_character_file", "content": '{"status":"success"}'},
		{"role": "assistant", "content": "创建完成啦~"},
		{"role": "user", "content": "{[Master最新行动/语言：再来]} ｝"},
		{"role": "assistant", "content": "再创建B"},
	]
	print("[RB] 倒回前历史条数: ", llm._chat_history.size())

	# 倒回一次：应移除最后 assistant "再创建B" + user "再来"
	var rolled = llm.rollback_history()
	print("[RB] 倒回内容: [", rolled, "]")
	print("[RB] 倒回后历史条数: ", llm._chat_history.size())
	print("[RB] 倒回后末尾: ", llm._chat_history.back())

	# 倒回第二次：应移除 assistant "创建完成啦" + tool + assistant(含tool_calls) + user "喊我"
	var rolled2 = llm.rollback_history()
	print("[RB] 第二次倒回内容: [", rolled2, "]")
	print("[RB] 第二次后历史条数: ", llm._chat_history.size(), "（应为0）")
	print("[RB] 第二次后末尾: ", llm._chat_history.back() if llm._chat_history.size() > 0 else "空")

	get_tree().quit(0)
