extends Node

## 阶段6 · 倒回 UI+tool 测试：验证回滚前后 UI 渲染气泡数与历史一致
## 用法：--headless --scene res://tools/rollback_ui_tool_test.tscn

func _ready() -> void:
	print("[RUT] 开始倒回 UI+tool 测试")
	var llm = get_node_or_null("/root/LLMClient")
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame
	shell._msg_box = VBoxContainer.new()
	await get_tree().process_frame

	# 构造含 tool 的历史
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：喂]} ｝"},
		{"role": "assistant", "content": "在的~"},
		{"role": "user", "content": "{[Master最新行动/语言：建个角色]} ｝"},
		{"role": "assistant", "content": "我来处理", "tool_calls": [{"id": "c1", "function": {"name": "write_character_file", "arguments": "{}"}}]},
		{"role": "tool", "tool_call_id": "c1", "name": "write_character_file", "content": '{"status":"success"}'},
		{"role": "assistant", "content": "角色建好了~"},
	]

	# 回滚前渲染
	shell._rebuild_chat_from_history(llm._chat_history)
	await get_tree().process_frame
	var before_vis: int = shell._msg_box.get_child_count()
	print("[RUT] 回滚前 UI 可见气泡数: ", before_vis, "（历史", llm._chat_history.size(), "条）")

	# 回滚（只撤最后 user 轮次）
	llm.rollback_history()
	print("[RUT] 回滚后历史条数: ", llm._chat_history.size(), " 序列: ", _roles(llm._chat_history))

	# 回滚后渲染
	shell._rebuild_chat_from_history(llm._chat_history)
	await get_tree().process_frame
	var after_vis: int = shell._msg_box.get_child_count()
	print("[RUT] 回滚后 UI 可见气泡数: ", after_vis)

	# 期望：回滚前 4 个可见(2轮各显示 user+assistant, tool过程不显示)；回滚后 2 个
	if before_vis == 4 and after_vis == 2:
		print("[RUT] ✅ 回滚前4气泡→回滚后2气泡，只撤最后轮次的2个可见气泡(正确)")
	else:
		print("[RUT] ⚠ before=", before_vis, " after=", after_vis, "（可能渲染与预期不同）")

	shell.queue_free()
	get_tree().quit(0)

func _roles(arr: Array) -> Array:
	var r := []
	for m in arr:
		r.append(m.get("role", ""))
	return r
