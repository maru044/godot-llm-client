extends Node

## 阶段6 · 读档流程测试：_on_load_slot 应关存档弹窗 + 进入聊天页 + 还原气泡
## 用法：--headless --scene res://tools/load_game_flow_test.tscn

func _ready() -> void:
	print("[LGF] 开始读档流程测试")
	var sm = get_node_or_null("/root/SaveManager")
	var llm = get_node_or_null("/root/LLMClient")

	# 先保存一份带历史的存档到 slot_0
	sm.create_new_game()
	llm._chat_history = [
		{"role": "user", "content": "{[Master最新行动/语言：你好]} ｝"},
		{"role": "assistant", "content": "你好呀~"},
	]
	sm.save_current_game(0)

	# 实例化 UIShell，构造最小环境
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame
	# 构造 _overlays / _screens
	shell._overlays = {"overlay-save": Control.new()}
	shell._screens = {"screen-chat": Control.new()}
	shell._msg_box = VBoxContainer.new()
	get_tree().root.add_child(shell._overlays["overlay-save"])
	get_tree().root.add_child(shell._screens["screen-chat"])
	shell._overlays["overlay-save"].visible = true
	await get_tree().process_frame

	shell._on_load_slot(0)
	await get_tree().process_frame

	# 验证
	var ov_hidden = not shell._overlays["overlay-save"].visible
	var chat_visible = shell._screens["screen-chat"].visible
	var bubble_count = shell._msg_box.get_child_count()
	print("[LGF] 存档弹窗关闭=", ov_hidden, " 聊天页显示=", chat_visible, " 气泡数=", bubble_count)
	if ov_hidden and chat_visible and bubble_count == 2:
		print("[LGF] ✅ 读档后：关弹窗+进入聊天页+还原2气泡")
	else:
		print("[LGF] ❌ 流程异常: ov=", ov_hidden, " chat=", chat_visible, " bubbles=", bubble_count)

	shell.queue_free()
	get_tree().quit(0)
