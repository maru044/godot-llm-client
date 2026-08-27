extends Node

## 阶段6 · 历史清理修复测试：格式提醒 system 不再污染/误清健康轮
## 用法：--headless --scene res://tools/history_clean_test.tscn

func _ready() -> void:
	var llm = get_node_or_null("/root/LLMClient")
	print("[HC] 开始历史清理测试")

	# 构造健康历史:(模拟纯对话+工具轮, 末尾是系统格式提醒——旧问题场景)
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：自我介绍]} ｝"},
		{"role": "assistant", "content": "我是Miku~"},
		{"role": "user", "content": "{[Master最新行动/语言：建刻晴]} ｝"},
		{"role": "assistant", "content": "我来建", "tool_calls": [{"id": "c1", "function": {"name": "write_character_file", "arguments": "{}"}}]},
		{"role": "tool", "tool_call_id": "c1", "name": "write_character_file", "content": '{"status":"success"}'},
		{"role": "assistant", "content": "刻晴建好啦"},
	]
	var before: int = llm._chat_history.size()
	print("[HC] 测试前历史条数: ", before)

	# 模拟之前BUG: 末尾是 user(健康) 时, _clean_stale 应完全不动
	llm._chat_history.append({"role": "user", "content": "{[Master最新行动/语言：再来]} ｝"})
	llm._clean_stale_history_before_send()
	var n1: int = llm._chat_history.size()
	print("[HC] 末尾 user 清后条数: ", n1, " (应为", before + 1, ", 不删)")
	if n1 == before + 1:
		print("[HC] ✅ 末尾 user 不清理(健康)")
	else:
		print("[HC] ❌ 误清了健康轮")

	# 模拟孤立的 tool(真正的脏数据)应清理
	llm._chat_history = [
		{"role": "user", "content": "u1"},
		{"role": "assistant", "tool_calls": [{"id": "c2", "function": {"name": "write_character_file", "arguments": "{}"}}]},
		{"role": "tool", "tool_call_id": "c2", "name": "write_character_file", "content": '{}'},
	]
	llm._clean_stale_history_before_send()
	var n2: int = llm._chat_history.size()
	print("[HC] 末尾孤立tool 清后条数: ", n2, " (应回到上一条user附近)")
	if n2 == 1 and llm._chat_history[0].get("role") == "user":
		print("[HC] ✅ 孤立 tool 正确清理到上一条 user")
	else:
		print("[HC] ❌ 孤立tool清理异常: ", n2)

	get_tree().quit(0)
