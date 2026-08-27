extends Node

## 阶段6 · 预设添加条目 + user人设预留文件测试
## 用法：--headless --scene res://tools/preset_add_test.tscn

func _ready() -> void:
	print("[PA] 开始预设添加条目测试")
	var ps = get_node_or_null("/root/PromptSchema")

	# 1. 验证 user人设预留文件被加载(depth 978)
	var found := false
	for e in ps.list_entries():
		var name: String = e.get("name", "")
		var depth: int = int(e.get("depth", 0))
		if name == "玩家(你)的人设" or depth == 978:
			found = true
			print("[PA] 找到预留条目: ", name, " depth=", depth)
	print("[PA] 预留文件加载: ", found)

	# 2. 验证预设面板刷新后"＋ 新建条目"按钮保留
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame
	# 构造列表容器 + 固定按钮(模拟 b_new)
	var lv = VBoxContainer.new()
	var b_new = Button.new()
	b_new.text = "＋ 新建条目"
	b_new.set_meta("fixed", true)  # 无 preset_item 标记 -> 应保留
	lv.add_child(b_new)
	shell._preset_list_container = lv
	# 加一个带 preset_item 标记的条目按钮(应被刷掉)
	var fake_item = Button.new()
	fake_item.set_meta("preset_item", true)
	lv.add_child(fake_item)
	shell._refresh_preset_list()
	await get_tree().process_frame

	var has_new := false
	for c in lv.get_children():
		if c is Button and c.text == "＋ 新建条目":
			has_new = true
	print("[PA] 刷新后'＋ 新建条目'按钮保留: ", has_new)
	if has_new:
		print("[PA] ✅ 按钮保留(只刷新条目按钮)")
	else:
		print("[PA] ❌ 按钮被误删")

	shell.queue_free()
	get_tree().quit(0)
