extends Node

## 阶段3 · 工具调用链测试：让模型真实调用 write_character_file 和 update_character_file。
## 用法：--headless --scene res://tools/tool_test.tscn

var _done := false
var _timeout := 0.0

func _ready() -> void:
	print("[TOOLTEST] 开始工具调用链测试")
	var dm = get_node_or_null("/root/DataManager")
	print("[TOOLTEST] 当前角色数: ", dm.get_all_characters().size())

	EventBus.llm_response_finished.connect(func(c): print("[TOOLTEST] 回复: ", c))
	EventBus.system_error_occurred.connect(func(m): print("[TOOLTEST] ❌ 错误: ", m))
	EventBus.character_updated.connect(func(cid): print("[TOOLTEST] 角色更新: ", cid))

	print("[TOOLTEST] 引导模型创建角色...")
	LLMClient.send_chat("请新建一个角色：名字叫【沙耶】，身份是修女。请用 write_character_file 工具创建她，正文分栏写外观与着装、性格与深层性癖、背景与战斗特质。创建好后告诉我她的 id。")

func _process(dt: float) -> void:
	if _done:
		return
	_timeout += dt
	if _timeout > 40.0:
		print("[TOOLTEST] ⏱ 超时，工具调用后未完成")
		get_tree().quit(0)
