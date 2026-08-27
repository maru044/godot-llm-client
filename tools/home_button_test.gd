extends Node

## 阶段6 · 回到标题按钮测试：存在、在左上角、点击切回标题
## 用法：--headless --scene res://tools/home_button_test.tscn

func _ready() -> void:
	print("[HB] 开始回到标题按钮测试")
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame

	# 找 screen-chat 里的 HomeButton
	var chat: Control = shell._screens.get("screen-chat")
	var home = null
	if chat:
		for c in chat.get_children():
			if c.name == "HomeButton":
				home = c
				break
	print("[HB] HomeButton 存在: ", home != null)
	if home == null:
		print("[HB] ❌ 未找到 HomeButton")
		get_tree().quit(0)
		return

	# 检查位置（左上角）
	var pos = home.position
	print("[HB] HomeButton 位置: ", pos, " 是否是左上角(靠近0,0): ", pos.x < 100 and pos.y < 80)
	if pos.x < 100 and pos.y < 80:
		print("[HB] ✅ 按钮位于左上角")
	else:
		print("[HB] ❌ 位置异常 ", pos)

	# 切到聊天页，模拟点击
	shell.show_screen("screen-chat")
	await get_tree().process_frame
	print("[HB] 点击前 title 可见: ", shell._screens["screen-title"].visible)
	home.pressed.emit()
	await get_tree().process_frame
	print("[HB] 点击后 title 可见: ", shell._screens["screen-title"].visible)
	if shell._screens["screen-title"].visible:
		print("[HB] ✅ 点击回到标题界面")
	else:
		print("[HB] ❌ 点击后未回标题")

	shell.queue_free()
	get_tree().quit(0)
