extends Node

## 阶段5 · 存读档往返测试：保存 chat_history -> 清空 -> 读档还原
## 用法：--headless --scene res://tools/save_load_test.tscn

func _ready() -> void:
	var sm = get_node_or_null("/root/SaveManager")
	var llm = get_node_or_null("/root/LLMClient")
	print("[SL] 开始存读档往返测试")

	# 1. 构造一份对话历史
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：你好]} ｝"},
		{"role": "assistant", "content": "你好呀，Master~"},
		{"role": "user", "content": "{[Master最新行动/语言：介绍个修女]} ｝"},
		{"role": "assistant", "content": "好的，这位是沙耶修女~"},
	]
	var before_count: int = llm._chat_history.size()
	print("[SL] 保存前消息数: ", before_count)

	# 2. 保存到槽位 0
	var saved: bool = sm.save_current_game(0)
	print("[SL] 保存返回: ", saved)

	# 3. 清空当前运行历史（模拟重开/切换）
	llm._chat_history = []
	print("[SL] 清空后消息数: ", llm._chat_history.size())

	# 4. 读档还原
	var data = sm.load_game_from_slot(0)
	var restored: Array = data.get("chat_history", [])
	print("[SL] 读档后 chat_history 条数: ", restored.size())
	print("[SL] data.msg_count: ", data.get("msg_count", -1))

	# 5. 校验
	if restored.size() == before_count:
		print("[SL] ✅ 读档还原 chat_history 数量一致 (", restored.size(), ")")
	else:
		print("[SL] ❌ 还原数量不一致: 期望 ", before_count, " 实际 ", restored.size())

	# 6. 校验内容完整性（角色序列）
	var roles_ok := true
	var expect_roles := ["user", "assistant", "user", "assistant"]
	for i in expect_roles.size():
		if String(restored[i].get("role", "")) != expect_roles[i]:
			roles_ok = false
	print("[SL] 角色序列: ", _roles(restored))
	print("[SL] 角色序列正确" if roles_ok else "[SL] ❌ 角色序列错误")

	# 7. 校验槽位 info 已带上 msg_count
	var slots = sm.get_slots_info()
	print("[SL] slot0 info: ", slots[0])
	if slots[0] != null and int(slots[0].get("msg_count", 0)) > 0:
		print("[SL] ✅ 槽位信息带 msg_count，UI 可显示")
	else:
		print("[SL] ❌ 槽位信息缺 msg_count")

	get_tree().quit(0)

func _roles(arr: Array) -> Array:
	var r := []
	for m in arr:
		r.append(m.get("role", ""))
	return r
