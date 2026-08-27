extends Node

## 阶段6 · 角色档案注入上下文测试：角色详细正文应在 system 前部
## 用法：--headless --scene res://tools/roster_inject_test.tscn

func _ready() -> void:
	print("[RI] 开始角色档案注入测试")
	var dm = get_node_or_null("/root/DataManager")
	var tool = get_node_or_null("/root/LLMToolExecutor")
	var ps = get_node_or_null("/root/PromptSchema")

	# 建一个含详细正文的角色
	tool._handler_write_character({
		"name": "档案测试角色",
		"content": "### 外观与着装\n银白长发\n### 性格与深层性癖\n外冷内淫",
	})

	var ctx = ps.build_system_context()
	print("[RI] 上下文长度: ", ctx.length())
	var has_header = ctx.find("已建档角色档案") != -1
	var has_name = ctx.find("档案测试角色") != -1
	var has_section = ctx.find("### 外观与着装") != -1

	if has_header and has_name and has_section:
		print("[RI] ✅ 角色档案已注入上下文（含详细 ### 正文）")
	else:
		print("[RI] ❌ 注入缺失 header=", has_header, " name=", has_name, " section=", has_section)

	# 位置验证：depth=950，应排在开篇(999)/角色信息(980)/核心设定(979) 之后、其余(世界规则4等)之前
	var roster_pos = ctx.find("已建档角色档案")
	var core_pos = ctx.find("二次元性奴隶黄油世界基础设定")  # 核心设定集(979) 特征
	var world_pos = ctx.find("游戏中使用")  # 世界规则(4) 特征
	print("[RI] roster_pos=", roster_pos, " core_pos=", core_pos, " world_pos=", world_pos)
	if roster_pos >= 0 and roster_pos > core_pos and (world_pos == -1 or roster_pos < world_pos):
		print("[RI] ✅ 角色档案位于核心设定之后、其余之前（depth≈950 位置正确）")
	else:
		print("[RI] ⚠ 位置需检查: roster_pos=", roster_pos, " core_pos=", core_pos, " world_pos=", world_pos)

	get_tree().quit(0)
