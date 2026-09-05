extends Node

## 超时识别单测：验证 RESULT_TIMEOUT 被单独提示「请求超时（180 秒）」，
## 不再与「网络断开」混淆。
## 用法：--headless --scene res://tools/timeout_test.tscn
##
## 方案：直接调用 LLMClient._describe_http_error()（静态纯函数），
## 用多组 (result, response_code) 断言超时与断网被区分提示。
## 无需真实网络、无需替换 HTTPRequest，单测秒级完成。

const LLM := preload("res://scripts/LLMClient.gd")

var _failed := false

func _check(name: String, hint: String, expect_contains: Array, expect_not_contains: Array) -> void:
	var ok := true
	for s in expect_contains:
		if not hint.contains(s):
			ok = false
	for s in expect_not_contains:
		if hint.contains(s):
			ok = false
	if ok:
		print("[TIMEOUTTEST] ✅ ", name, " → ", hint)
	else:
		_failed = true
		print("[TIMEOUTTEST] ❌ ", name, " → ", hint, "（预期含 ", expect_contains, "、不含 ", expect_not_contains, "）")


func _ready() -> void:
	print("[TIMEOUTTEST] 开始超时识别测试（纯函数单测）")

	# 1. 超时：result=RESULT_TIMEOUT(13), response_code=0 → 提示「请求超时（180 秒）」
	_check(
		"RESULT_TIMEOUT",
		LLM._describe_http_error(HTTPRequest.RESULT_TIMEOUT, 0, 180.0),
		["请求超时", "180"],
		["网络断开"]
	)

	# 2. 网络断开：result=RESULT_CANT_CONNECT(2), response_code=0 → 仍提示「网络断开」
	_check(
		"断网(RESULT_CANT_CONNECT)",
		LLM._describe_http_error(HTTPRequest.RESULT_CANT_CONNECT, 0, 180.0),
		["网络断开"],
		["请求超时", "180"]
	)

	# 3. 连接错误：result=RESULT_CONNECTION_ERROR(4), response_code=0 → 仍提示「网络断开」
	_check(
		"连接错误(RESULT_CONNECTION_ERROR)",
		LLM._describe_http_error(HTTPRequest.RESULT_CONNECTION_ERROR, 0, 180.0),
		["网络断开"],
		["请求超时"]
	)

	# 4. 无响应：result=RESULT_NO_RESPONSE(6), response_code=0 → 仍提示「网络断开」
	_check(
		"无响应(RESULT_NO_RESPONSE)",
		LLM._describe_http_error(HTTPRequest.RESULT_NO_RESPONSE, 0, 180.0),
		["网络断开"],
		["请求超时"]
	)

	# 5. 超时但超时秒数可配：输入非 180 的秒数，文案跟随 → 证明不是硬编码
	_check(
		"超时时长可变(300s)",
		LLM._describe_http_error(HTTPRequest.RESULT_TIMEOUT, 0, 300.0),
		["请求超时", "300"],
		["180"]
	)

	# 6. HTTP 401（未超时，result=RESULT_SUCCESS）→ 提示「API Key 无效」，不受影响
	_check(
		"HTTP 401 未受影响",
		LLM._describe_http_error(HTTPRequest.RESULT_SUCCESS, 401, 180.0),
		["API Key 无效"],
		["请求超时", "网络断开"]
	)

	# 7. HTTP 429（未超时）→ 提示「并发或余额受限」
	_check(
		"HTTP 429 未受影响",
		LLM._describe_http_error(HTTPRequest.RESULT_SUCCESS, 429, 180.0),
		["并发或余额受限"],
		["请求超时", "网络断开"]
	)

	# 8. 未知 code（未超时）→ 提示「未知错误」
	_check(
		"未知 code(666)",
		LLM._describe_http_error(HTTPRequest.RESULT_SUCCESS, 666, 180.0),
		["未知错误"],
		["请求超时", "网络断开"]
	)

	if _failed:
		print("[TIMEOUTTEST] ❌ FAIL：存在未通过的断言")
		get_tree().quit(1)
	else:
		print("[TIMEOUTTEST] ✅ ALL PASS")
		get_tree().quit(0)