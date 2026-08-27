extends Node

## 连通性测试（作为场景运行，autoload 已加载，EventBus 全局可用）
## 用法：godot --headless --scene res://tools/connectivity_test.tscn

var _done := false

func _ready() -> void:
	print("[TEST] 开始连通性测试")
	print("[TEST] Config: ", ConfigManager.api_url, " | ", ConfigManager.model, " | key_len=", ConfigManager.api_key.length())
	print("[TEST] Prompt entries: ", PromptSchema.list_entries().size())

	EventBus.llm_response_finished.connect(_on_reply)
	EventBus.system_error_occurred.connect(_on_error)

	print("[TEST] Sending...")
	LLMClient.send_chat("你好，请只用一句话回复我。")

func _on_reply(content: String) -> void:
	print("[TEST] ✅ 收到回复: ", content)
	_done = true
	get_tree().quit(0)

func _on_error(msg: String) -> void:
	print("[TEST] ❌ 错误: ", msg)
	get_tree().quit(1)

func _process(_dt: float) -> void:
	if _done:
		return
	# 15 秒超时兜底
	_timeout += _dt
	if _timeout > 15.0:
		print("[TEST] ⏱ 超时，未收到回复")
		get_tree().quit(2)

var _timeout := 0.0
