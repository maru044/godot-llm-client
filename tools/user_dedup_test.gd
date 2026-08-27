extends Node

## 确认正常程序里 user 信息不会重复：
## 用例1：正常完成轮次（末尾 assistant）→ 再输入 → 追加新 user（不重复）
## 用例2：失败后(末尾 user) → 再输入 → 合并为一整条（结构仅1条user，不复制旧内容）
## 用法：--headless --scene res://tools/user_dedup_test.tscn

func _ready() -> void:
	var llm = get_node_or_null("/root/LLMClient")

	# ---- 用例1：正常末尾是 assistant，再输入应追加新 user（不合并） ----
	print("\n[UD·1] 正常轮次末尾 assistant 再输入")
	llm._chat_history = [
		{"role": "user", "content": llm.build_user_content("早上好")},
		{"role": "assistant", "content": "早安~ Master！"},
	]
	# 不触发网络：直接测 _merge_consecutive_user，末尾 assistant 应返回 false
	var dup: bool = llm._merge_consecutive_user("今天天气不错")
	print("[1] 末尾assistant 时合并返回: ", dup, "（应 false → 走正常 append）")
	if not dup:
		print("[1] ✅ 正常轮次末尾assistant → 不合并，会正常追加新user（结构为 user,assistant,user 合法）")
	else:
		print("[1] ❌ 错误合并")

	# ---- 用例2：失败后末尾是 user，再输入应合并，不复制旧内容，不产生 user-user ----
	print("\n[UD·2] 失败后末尾 user 再输入（合并）")
	llm._chat_history = [{"role": "user", "content": llm.build_user_content("第一次输入")}]
	var merged: bool = llm._merge_consecutive_user("第二次输入")
	print("[2] 合并返回: ", merged, " user数: ", _count_role(llm._chat_history, "user"))
	var content = String(llm._chat_history[0].get("content", ""))
	print("[2] 合并后内容含第一次: ", content.contains("第一次输入"), " 含第二次: ", content.contains("第二次输入"))
	print("[2] 内容是否把'第一次输入'复制了两次: ", content.find("第一次输入") != content.rfind("第一次输入"))
	if merged and _count_role(llm._chat_history, "user") == 1 \
			and content.contains("第二次输入") and content.find("第一次输入") == content.rfind("第一次输入"):
		print("[2] ✅ 合并为1条user，追加新输入、未复制旧内容（无user-user，无内容重复）")
	else:
		print("[2] ❌ 有问题")

	get_tree().quit(0)

func _count_role(arr: Array, role: String) -> int:
	var n := 0
	for m in arr:
		if m.get("role") == role:
			n += 1
	return n

func _roles(arr: Array) -> Array:
	var r := []
	for m in arr:
		r.append(m.get("role", ""))
	return r
