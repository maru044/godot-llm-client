extends Node

## 错误处理测试：用非法 API Key 触发 401，验证不盲目重试 + 清理历史。
## 用法：--headless --scene res://tools/error_test.tscn

var _done := false
var _timeout := 0.0

func _ready() -> void:
	print("[ERRTEST] 开始错误处理测试")
	# 强制用错误 key
	LLMClient.api_key = "sk-BAD-KEY-FOR-TEST"
	print("[ERRTEST] 使用错误的 API Key 发送...")
	EventBus.system_error_occurred.connect(func(m): print("[ERRTEST] ❌ system_error: ", m))
	EventBus.llm_response_finished.connect(func(c): print("[ERRTEST] 意外收到回复: ", c))
	LLMClient.send_chat("触发错误的测试")

func _process(dt: float) -> void:
	if _done:
		return
	_timeout += dt
	if _timeout > 20.0:
		print("[ERRTEST] ⏱ 超时")
		get_tree().quit(0)
