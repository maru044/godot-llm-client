extends Node

## 阶段3 · 更新工具测试：让模型用 update_character_file 修改"外观与着装"分栏。
## 前提：char_511469 已存在（由 tool_test 创建）。
## 用法：--headless --scene res://tools/tool_update_test.tscn

const TEST_CHAR := "char_511469"
const TEST_CHAR_NAME := "沙耶"
var _done := false
var _timeout := 0.0

func _ready() -> void:
	print("[UPDTEST] 开始更新工具测试，目标: ", TEST_CHAR)
	var dm = get_node_or_null("/root/DataManager")
	var c = dm.get_character(TEST_CHAR)
	print("[UPDTEST] 更新前角色: ", c.get("header", {}).get("name", "未知"))

	EventBus.llm_response_finished.connect(func(t): print("[UPDTEST] 回复: ", t))
	EventBus.system_error_occurred.connect(func(m): print("[UPDTEST] ❌ 错误: ", m))
	EventBus.character_updated.connect(func(cid): print("[UPDTEST] 角色更新: ", cid))

	print("[UPDTEST] 引导模型修改外观分栏...")
	LLMClient.send_chat("请把角色 char_511469（沙耶）的【外观与着装】分栏更新为新内容：发色改为金色长发，瞳色改为碧绿色。请用 update_character_file 工具，char_id 填 char_511469，section 填【外观与着装】。")

func _process(dt: float) -> void:
	if _done:
		return
	_timeout += dt
	if _timeout > 40.0:
		print("[UPDTEST] ⏱ 超时")
		get_tree().quit(0)
