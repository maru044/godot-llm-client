extends Node

## 阶段6 · 角色卡面板热加载测试：LLM 新建角色后，每次打开面板应重新读取名单
## 用法：--headless --scene res://tools/char_hotload_test.tscn

func _ready() -> void:
	print("[HL] 开始角色热加载测试")
	var dm = get_node_or_null("/root/DataManager")
	var tool = get_node_or_null("/root/LLMToolExecutor")

	# 先记录初始角色数
	var before: int = dm.get_all_characters().size()
	print("[HL] 初始角色数: ", before)

	# 用 handler 新建一个角色（模拟 LLM 生成）
	var res = tool._handler_write_character({
		"name": "热加载测试角色",
		"content": "### 外观与着装\n测试",
	})
	print("[HL] 新建返回: ", res)
	var after: int = dm.get_all_characters().size()
	print("[HL] 新建后角色数: ", after)

	# 构造一个最小 UIShell + 其列表容器
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame
	shell._char_list_container = VBoxContainer.new()
	shell._char_detail_vbox = VBoxContainer.new()

	# 模拟"打开角色卡面板"（open_overlay 会调 _refresh_char_list）
	shell.open_overlay("overlay-char")
	await get_tree().process_frame

	# 统计列表里的按钮数
	var btn_count := 0
	for c in shell._char_list_container.get_children():
		if c is Button:
			btn_count += 1
	print("[HL] 打开面板后列表项数: ", btn_count)

	var dm_after: int = dm.get_all_characters().size()
	if btn_count == dm_after and dm_after > before:
		print("[HL] ✅ 角色卡面板热加载成功：列表项=", btn_count, " 含新角色（当前", dm_after, "个）")
	else:
		print("[HL] ❌ 列表项(", btn_count, ") 与角色数(", dm_after, ")不一致")

	shell.queue_free()
	get_tree().quit(0)
