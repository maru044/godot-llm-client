extends Node

## 阶段4 · F2 干净发送测试：
## 用例1：末尾孤立 tool → 应清理到上一条 user
## 用例2：末尾纯文本 assistant（倒回后正常状态）→ 应不动（不误删）
## 用法：--headless --scene res://tools/f2_test.tscn

func _ready() -> void:
	var llm = get_node_or_null("/root/LLMClient")
	print("[F2] 开始干净发送测试")

	# 用例1：末尾残留孤立 tool（上一轮中断）
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：第一句]} ｝"},
		{"role": "assistant", "content": "回复一"},
		{"role": "user", "content": "{[Master最新行动/语言：第二句]} ｝"},
		{"role": "assistant", "tool_calls": [{"id": "c1", "type": "function", "function": {"name": "write_character_file", "arguments": "{}"}}]},
		{"role": "tool", "tool_call_id": "c1", "name": "write_character_file", "content": '{"status":"success"}'},
	]
	print("[F2·用例1] 发送前条数: ", llm._chat_history.size(), " 末尾: ", llm._chat_history.back().get("role"))
	llm._clean_stale_history_before_send()
	print("[F2·用例1] 清理后条数: ", llm._chat_history.size(), " 末尾: ", llm._chat_history.back().get("role"))
	if llm._chat_history.size() == 3 and llm._chat_history.back().get("role") == "user":
		print("[F2·用例1] ✅ 净化正确：回到上一条 user")
	else:
		print("[F2·用例1] ❌ 净化异常")

	# 用例2：末尾纯文本 assistant（倒回后的正常状态，允许玩家重输）
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：喊我]} ｝"},
		{"role": "assistant", "content": "好的~"},
	]
	print("[F2·用例2] 发送前条数: ", llm._chat_history.size(), " 末尾: ", llm._chat_history.back().get("role"))
	llm._clean_stale_history_before_send()
	print("[F2·用例2] 清理后条数: ", llm._chat_history.size(), " 末尾: ", llm._chat_history.back().get("role"))
	if llm._chat_history.size() == 2 and llm._chat_history.back().get("role") == "assistant":
		print("[F2·用例2] ✅ 未误删：正常 assistant 收尾不动（可倒回/重输）")
	else:
		print("[F2·用例2] ❌ 误删了正常上下文")

	get_tree().quit(0)
