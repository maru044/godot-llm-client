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

	print("[TOOLTEST] 自然场景：用户提到新角色，不强制工具名...")
	LLMClient.send_chat("我去海边散步时遇到了一个修女，她叫【沙耶】，银白短发琥珀色眼睛，人挺温柔的。我想把她也留在这个岛上，你帮我安排一下吧。")

func _process(dt: float) -> void:
	if _done:
		return
	_timeout += dt
	if _timeout > 40.0:
		print("[TOOLTEST] ⏱ 超时，工具调用后未完成")
		get_tree().quit(0)
