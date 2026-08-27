extends Node

## 阶段5 · 气泡还原逻辑测试：把 chat_history 重建为 user/assistant 气泡
## 直接测 UIShell 的解析核心：_strip_user_wrap + 气泡判定
## 用法：--headless --scene res://tools/bubble_restore_test.tscn

func _ready() -> void:
	# 手动实例化一个 UIShell 以调用其方法
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.add_child(shell)

	var history: Array = [
		{"role": "user", "content": "{[Master最新行动/语言：你好]} ｝"},
		{"role": "assistant", "content": "<content>你好呀，Master~</content>"},
		{"role": "user", "content": "{[Master最新行动/语言：介绍个修女]} ｝"},
		{"role": "assistant", "content": "好的，这位是沙耶修女~"},
	]

	# 建一个临时 msg_box 容器
	var mb = VBoxContainer.new()
	shell._msg_box = mb

	# 调用气泡还原
	shell._rebuild_chat_from_history(history)
	# 需要一帧让 queue_free/布局生效，直接数子节点
	var child_count := mb.get_child_count()
	print("[BR] 还原后气泡数量: ", child_count, "（期望4）")

	# 验证每条气泡文本是否正确（去包装/去标签）
	var ok := true
	var texts := []
	for c in mb.get_children():
		var rtl = _find_rtl(c)
		if rtl:
			texts.append(rtl.text)
	print("[BR] 气泡文本: ", texts)

	if texts.size() == 4 and texts[0] == "你好" and texts[1].contains("你好呀，Master"):
		print("[BR] ✅ 气泡还原正确：用户消息去掉包装，assistant 去掉 <content> 标签")
	else:
		print("[BR] ❌ 气泡还原有误")

	shell.free()
	get_tree().quit(0)

func _find_rtl(node: Node) -> RichTextLabel:
	if node is RichTextLabel:
		return node
	for c in node.get_children():
		var r = _find_rtl(c)
		if r:
			return r
	return null
