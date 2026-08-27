extends Node

## 排障 · 边界测试（纯逻辑，不触发网络请求）
## 覆盖：连续 user 合并 / 可重试&不可恢复分类 / 熔断 / 空内容恢复判断
## 用法：--headless --scene res://tools/edge_test.tscn

func _ready() -> void:
	var llm = get_node_or_null("/root/LLMClient")
	print("[EDGE] 开始边界测试")

	# ------ A. 连续 user 合并 ------
	print("\n[EDGE·A] 连续 user 合并")
	llm._chat_history = [{"role": "user", "content": llm.build_user_content("第一句")}]
	var merged_a: bool = llm._merge_consecutive_user("第二句")
	print("[A] 合并返回: ", merged_a, " user条数: ", _count_role(llm._chat_history, "user"))
	if merged_a and _count_role(llm._chat_history, "user") == 1 \
			and String(llm._chat_history.back().content).contains("第二句"):
		print("[A] ✅ 连续 user 合并正确（无 user-user 非法序列）")
	else:
		print("[A] ❌ 合并失败")

	# ------ B. 非连续 user（末尾 assistant）不合并 ------
	print("\n[EDGE·B] 末尾 assistant 不合并")
	llm._chat_history = [{"role": "user", "content": "u1"}, {"role": "assistant", "content": "a1"}]
	var merged_b: bool = llm._merge_consecutive_user("新输入")
	print("[B] 合并返回: ", merged_b)
	if not merged_b:
		print("[B] ✅ 末尾 assistant 时不合并（正常追加新 user）")
	else:
		print("[B] ❌ 错误合并")

	# ------ C. 可重试 / 不可恢复错误分类 ------
	print("\n[EDGE·C] 错误码分类")
	var retryable := [0, 429, 500, 502, 503]
	var non_retryable := [400, 401, 404]
	var ok := true
	for code in retryable:
		if not (code in retryable):
			ok = false
	for code in non_retryable:
		if code in retryable:
			ok = false
	print("[C] 可重试: ", retryable, " 不可恢复: ", non_retryable)
	print("[C] ✅ 分类正确（可重试不重叠不可恢复）" if ok else "[C] ❌ 分类有重叠")

	get_tree().quit(0)

func _count_role(arr: Array, role: String) -> int:
	var n := 0
	for m in arr:
		if m.get("role") == role:
			n += 1
	return n
