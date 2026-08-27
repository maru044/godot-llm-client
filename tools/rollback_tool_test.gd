extends Node

## 阶段6 · 倒回遇 tool 测试：精确验证 rollback_history 删除了哪些消息
## 用法：--headless --scene res://tools/rollback_tool_test.tscn

func _ready() -> void:
	var llm = get_node_or_null("/root/LLMClient")
	print("[RBTL] 开始倒回+tool 测试")

	# 构造典型历史: user1, assistant1(纯文本), user2, assistant2(带tool_calls), tool, assistant3(纯文本)
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：喂]} ｝"},
		{"role": "assistant", "content": "在的~"},
		{"role": "user", "content": "{[Master最新行动/语言：建个角色]} ｝"},
		{"role": "assistant", "content": "我来建", "tool_calls": [{"id": "c1", "function": {"name": "write_character_file", "arguments": "{}"}}]},
		{"role": "tool", "tool_call_id": "c1", "name": "write_character_file", "content": '{"status":"success"}'},
		{"role": "assistant", "content": "角色建好了~"},
	]
	print("[RBTL] 回滚前序列: ", _roles(llm._chat_history))

	# 记录回滚前 size，逐个 pop 前打印
	var rolled = llm.rollback_history()
	print("[RBTL] 回滚后序列: ", _roles(llm._chat_history))
	print("[RBTL] 回滚返回文本: [", rolled, "]")

	# 期望只剩 user1, assistant1（只撤销 user2 轮次）
	var expect: Array = ["user", "assistant"]
	var got: Array = _roles(llm._chat_history)
	if got == expect:
		print("[RBTL] ✅ 正确：只撤销了最后一个 user 轮次（4条 → 2条），剩余 ", got)
	else:
		print("[RBTL] ❌ 异常：剩余 ", got, "（期望 ", expect, "）")

	# 再测一次：tool 轮次末尾是 user 时
	llm._chat_history = [
		{"role": "user", "content": "uu1"},
		{"role": "assistant", "content": "aa1"},
		{"role": "user", "content": "uu2"},
		{"role": "assistant", "tool_calls": [{"id": "c2", "function": {"name": "write_character_file", "arguments": "{}"}}]},
		{"role": "tool", "tool_call_id": "c2", "name": "write_character_file", "content": '{}'},
	]
	var roll2 = llm.rollback_history()
	print("[RBTL] 用例2 回滚后: ", _roles(llm._chat_history), " 返回=[", roll2, "]")

	get_tree().quit(0)

func _roles(arr: Array) -> Array:
	var r := []
	for m in arr:
		r.append(m.get("role", ""))
	return r
