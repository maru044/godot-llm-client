extends Node

## 阶段6 · write_character_file handler 单元测试：直接调用，验证只落盘一次
## 用法：--headless --scene res://tools/handler_write_test.tscn

func _ready() -> void:
	var dm = get_node_or_null("/root/DataManager")
	var tool = get_node_or_null("/root/LLMToolExecutor")
	print("[HWT] 开始 handler 单元测试")
	var before: int = dm.get_all_characters().size()
	print("[HWT] 测试前角色数: ", before)

	var res = tool._handler_write_character({
		"name": "测试角色X",
		"content": "### 外观与着装\n测试内容\n### 性格与深层性癖\n测试性格\n### 背景与战斗特质\n测试背景",
	})
	print("[HWT] handler 返回: ", res)

	var after: int = dm.get_all_characters().size()
	print("[HWT] 测试后角色数: ", after)
	# 从返回解析 char_id，检查文件
	var j = JSON.parse_string(res)
	if j and j.has("char_id"):
		var cid = j["char_id"]
		var c = dm.get_character(cid)
		print("[HWT] 角色 body 前20: ", String(c.get("body", "")).substr(0, 20))
		print("[HWT] body 是否包含三栏: ", String(c.get("body","")).find("### 背景与战斗特质") != -1)

	if after == before + 1:
		print("[HWT] ✅ 只新建了 1 个角色（一次落盘）")
	else:
		print("[HWT] ❌ 角色数异常: ", after, " expected ", before + 1)

	get_tree().quit(0)
