extends Node

## 阶段6 · 验证 ConfigManager.thinking_disabled 在 deepseek 配置下是否为 true
## 用法：--headless --scene res://tools/thinking_check_test.tscn

func _ready() -> void:
	var cm = get_node_or_null("/root/ConfigManager")
	if cm == null:
		print("[CK] ❌ ConfigManager 不存在")
		get_tree().quit(1)
		return
	print("[CK] active_api=", cm.active_api)
	print("[CK] thinking_disabled=", cm.thinking_disabled, " (deepseek 应为 true)")
	print("[CK] supports_vision=", cm.supports_vision, " (deepseek 应为 false)")
	print("[CK] api_url=", cm.api_url, " | model=", cm.model)

	if cm.active_api == "deepseek" and cm.thinking_disabled == true \
			and cm.supports_vision == false:
		print("[CK] ✅ thinking_disabled/supports_vision 正确同步到 deepseek 预设")
	else:
		print("[CK] ❌ 未正确同步（thinking_disabled=", cm.thinking_disabled, " supports_vision=", cm.supports_vision, "）")

	get_tree().quit(0)
