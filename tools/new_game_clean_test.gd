extends Node

## 阶段6 · 新开游戏清缓存测试：开始游戏后应将角色缓存清空，不串档
## 用法：--headless --scene res://tools/new_game_clean_test.tscn

func _ready() -> void:
	print("[GC] 开始新游戏清缓存测试")
	var sm = get_node_or_null("/root/SaveManager")
	var dm = get_node_or_null("/root/DataManager")
	var tool = get_node_or_null("/root/LLMToolExecutor")

	# 模拟：游戏内建了一个角色(刻晴)
	sm.create_new_game()
	tool._handler_write_character({"name": "刻晴", "content": "### 外观\n紫色马尾"})
	# 保存到槽位0
	sm.save_current_game(0)
	print("[GC] 保存后 DataManager 缓存角色数=", dm.get_all_characters().size(), " (应为1)")

	# 模拟异常：缓存残留(比如读档后没清)
	# 直接再次 create_new_game + reload_characters，模拟开始新游戏
	sm.create_new_game()
	dm.reload_characters()

	var n: int = dm.get_all_characters().size()
	print("[GC] 新开游戏后角色缓存数=", n, " (应为0)")
	if n == 0:
		print("[GC] ✅ 新开游戏缓存已清空，不串档")
	else:
		print("[GC] ❌ 缓存残留 ", n, " 个角色(串档)")

	get_tree().quit(0)
