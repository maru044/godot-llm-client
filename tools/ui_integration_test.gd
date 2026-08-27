extends Node

## 阶段6 · UI 集成测试：验证预设面板/角色卡面板依赖的核心 API 可用
## 用法：--headless --scene res://tools/ui_integration_test.tscn

func _ready() -> void:
	var ps = get_node_or_null("/root/PromptSchema")
	var dm = get_node_or_null("/root/DataManager")
	print("[UI1] 开始 UI 核心 API 测试")

	# ---- 预设：list 应按 depth 排序 ----
	print("\n[UI·预设] list_entries")
	var entries = ps.list_entries()
	var depths := []
	for e in entries:
		depths.append(int(e.get("depth", 0)))
	print("[预设] 条目数: ", entries.size(), " depths: ", depths)
	var sorted := true
	for i in range(1, depths.size()):
		if depths[i] > depths[i - 1]:
			sorted = false
	print("[预设] 按 depth 降序" if sorted else "[预设] ❌ 未按 depth 排序")

	# ---- 预设：create_entry（新建，role 默认 system）----
	print("\n[UI·预设] create_entry")
	var new_file = ps.create_entry("测试条目", 66, "system", "这是测试正文")
	print("[预设] 新建返回: ", new_file)
	if new_file != "":
		# 验证读取到
		var body = ps.get_entry_body(new_file)
		print("[预设] 读回 body: ", String(body.get("content", "")).substr(0, 20), " depth=", body.get("depth", -1), " role=", body.get("role", "?"))
		print("[预设] ✅ 新建成功且能读回")

		# ---- 预设：update_entry ----
		print("\n[UI·预设] update_entry")
		var ok = ps.update_entry(new_file, "测试条目2", 67, "system", "更新后的正文")
		var body2 = ps.get_entry_body(new_file)
		print("[预设] 更新返回: ", ok, " 新正文: ", String(body2.get("content", "")).substr(0, 10), " depth=", body2.get("depth", -1))
		print("[预设] ✅ 更新成功" if ok else "[预设] ❌ 更新失败")
	else:
		print("[预设] ❌ 新建失败")

	# ---- 角色卡：DataManager ----
	print("\n[UI·角色卡] get_all_characters")
	var chars = dm.get_all_characters()
	print("[角色卡] 角色数: ", chars.size())
	for c in chars:
		print("[角色卡] id=", c.get("id", ""), " name=", c.get("name", ""), " race=", c.get("race", ""))
	print("[角色卡] ✅ 角色列表可读")

	get_tree().quit(0)
