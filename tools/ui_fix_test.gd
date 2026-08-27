extends Node

## 阶段6修复验证：存档槽位真实数据 + 打开user + 聊天气泡 + 真实存读档
## 用法：--headless --scene res://tools/ui_fix_test.tscn

func _ready() -> void:
	var sm = get_node_or_null("/root/SaveManager")
	var llm = get_node_or_null("/root/LLMClient")
	print("[FIX] 验证存档/打开user/存读档")

	# ---- 1. 存档槽位读取真实数据 ----
	print("\n[FIX·存档] get_slots_info（初始）")
	var slots = sm.get_slots_info()
	if slots.size() == SaveManagerClass.MAX_SLOTS:
		print("[FIX·存档] ✅ 槽位数量 = MAX_SLOTS")
	else:
		print("[FIX·存档] ❌ 槽位数量异常")

	# ---- 2. open user dir 用绝对路径 ----
	var abs = ProjectSettings.globalize_path("user://")
	print("\n[FIX·userdir] user:// 绝对路径 = [", abs, "]")
	if abs != "" and not abs.begins_with("user://"):
		print("[FIX·userdir] ✅ 真实绝对路径")
	else:
		print("[FIX·userdir] ❌ 仍是虚拟路径")

	# ---- 3. 真实存读档端到端 ----
	print("\n[FIX·实存] 构造对话并保存到槽位0")
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：你好]} ｝"},
		{"role": "assistant", "content": "你好呀，Master~"},
	]
	var saved = sm.save_current_game(0)
	print("[FIX·实存] 保存返回: ", saved)

	# 重新读槽位，应非空、有 created_at/msg_count
	var slots2 = sm.get_slots_info()
	var s0 = slots2[0]
	print("[FIX·实存] slot#1 数据: ", s0)
	if s0 != null:
		print("[FIX·实存] ✅ 槽位0 非空，created_at=", s0.get("created_at","?"), " msg_count=", s0.get("msg_count","?"))
	else:
		print("[FIX·实存] ❌ 槽位0 仍为空")

	# 清空后读档还原
	llm._chat_history = []
	var data = sm.load_game_from_slot(0)
	var restored = data.get("chat_history", [])
	print("[FIX·实存] 读档还原条数: ", restored.size(), " 应为2")
	if restored.size() == 2:
		print("[FIX·实存] ✅ 存读档往返完整")
	else:
		print("[FIX·实存] ❌ 往返异常")

	get_tree().quit(0)
