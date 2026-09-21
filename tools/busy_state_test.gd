extends Node

## 忙碌状态契约测试。
## 用例1（离线，不需要外网）：本机起一个只回 500 的袖珍 HTTP 服务，
##   让客户端命中「可重试 → 重试耗尽」这条终止路径，验证：
##   - 错误「通知」可以发多次（每轮重试一次）
##   - 状态「收尾」只能有一次
##   - 忙碌标记最终复位
## 用例2（不需要网络）：直接驱动信号，验证界面在 started 时锁定、
##   在 failed 时解锁且不产生空气泡、在 finished 时解锁并追加一个气泡。
## 用法：--headless --scene res://tools/busy_state_test.tscn

const WATCHDOG_SEC := 60.0
const HTTP_500 := "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

var _server := TCPServer.new()
var _server_port := -1
var _peers: Array = []
var _served := 0

var _err_count := 0
var _failed_count := 0
var _finished_count := 0
var _elapsed := 0.0


func _ready() -> void:
	print("[BS] 开始忙碌状态契约测试")
	await get_tree().process_frame
	await _case1_terminal_signal_once()
	await _case2_ui_contract()
	print("\n[BS] 全部用例结束")
	get_tree().quit(0)


func _process(dt: float) -> void:
	_elapsed += dt
	if _elapsed > WATCHDOG_SEC:
		print("[BS] ⏱ 看门狗超时，强制退出")
		get_tree().quit(1)
	_poll_server()


## ---------- 袖珍 HTTP 服务：只负责回 500 ----------

func _start_server() -> bool:
	for p in range(8801, 8860):
		if _server.listen(p, "127.0.0.1") == OK:
			_server_port = p
			return true
	return false


func _poll_server() -> void:
	if not _server.is_listening():
		return
	# 接受新连接：不读请求（POST 体积可能很大），直接回 500 并声明 Connection: close
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if peer != null:
			peer.poll()
			peer.put_data(HTTP_500.to_utf8_buffer())
			_peers.append(peer)
			_served += 1
	# 客户端读完会主动断开，这里顺手回收
	var still: Array = []
	for peer in _peers:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			still.append(peer)
	_peers = still


func _stop_server() -> void:
	for peer in _peers:
		peer.disconnect_from_host()
	_peers.clear()
	_server.stop()


## ---------- 用例1：终止失败路径必须恰好收尾一次 ----------

func _case1_terminal_signal_once() -> void:
	print("\n[BS·1] 终态出口唯一性（本机 500 服务 → 可重试 → 重试耗尽）")
	var llm = get_node_or_null("/root/LLMClient")
	if llm == null:
		print("[BS·1] ❌ 找不到 LLMClient，跳过")
		return
	if not _start_server():
		print("[BS·1] ❌ 本机端口都被占用，跳过")
		return

	var original_url: String = llm.api_url
	llm.api_url = "http://127.0.0.1:%d/v1/chat/completions" % _server_port

	_err_count = 0
	_failed_count = 0
	_finished_count = 0
	var cb_err := func(_m: String):
		_err_count += 1
	var cb_fail := func():
		_failed_count += 1
	var cb_fin := func(_c: String):
		_finished_count += 1
	EventBus.system_error_occurred.connect(cb_err)
	EventBus.llm_response_failed.connect(cb_fail)
	EventBus.llm_response_finished.connect(cb_fin)

	llm.send_chat("触发终止失败的测试")

	# 每次重试都间隔 1 秒，最多 6 次尝试，留足 25 秒
	var waited := 0.0
	while _failed_count == 0 and waited < 25.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25

	EventBus.system_error_occurred.disconnect(cb_err)
	EventBus.llm_response_failed.disconnect(cb_fail)
	EventBus.llm_response_finished.disconnect(cb_fin)
	llm.api_url = original_url
	_stop_server()

	var busy: bool = llm.is_busy()
	print("[BS·1] 服务端受理=", _served, " 通知=", _err_count, " 收尾failed=", _failed_count, " 收尾finished=", _finished_count, " 忙碌=", busy)
	if _failed_count == 1 and _finished_count == 0 and _err_count >= 2 and not busy:
		print("[BS·1] ✅ 收尾恰好一次、通知可多次、忙碌标记已复位")
	else:
		print("[BS·1] ❌ 期望 failed=1 / finished=0 / 通知≥2 / 不忙碌，实际不符")


## ---------- 用例2：界面忙碌状态的契约 ----------

func _case2_ui_contract() -> void:
	print("\n[BS·2] UI 契约：started 锁定 → failed 解锁（无气泡）→ finished 解锁（加一个气泡）")
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.call_deferred("add_child", shell)
	await get_tree().process_frame
	await get_tree().process_frame

	if shell._send_button == null or shell._input_line == null or shell._msg_box == null:
		print("[BS·2] ❌ UI 控件未就绪，跳过")
		return

	# 1) started → 应进入忙碌
	EventBus.llm_response_started.emit()
	await get_tree().process_frame
	var locked: bool = shell._send_button.disabled \
			and shell._send_button.text == "思考中…" \
			and not shell._input_line.editable
	print("[BS·2] started 后：按钮=", shell._send_button.text, " 锁定=", locked)

	# 2) failed → 应解锁，且不得追加气泡
	var before_fail: int = shell._msg_box.get_child_count()
	EventBus.llm_response_failed.emit()
	await get_tree().process_frame
	var busy_after_fail: bool = shell._send_button.disabled or not shell._input_line.editable
	var after_fail: int = shell._msg_box.get_child_count()
	print("[BS·2] failed 后：仍忙碌=", busy_after_fail, " 气泡 ", before_fail, "→", after_fail, " 按钮=", shell._send_button.text)

	# 3) started + finished → 应解锁并追加一个气泡
	EventBus.llm_response_started.emit()
	EventBus.llm_response_finished.emit("测试正文")
	await get_tree().process_frame
	var busy_after_fin: bool = shell._send_button.disabled or not shell._input_line.editable
	var after_fin: int = shell._msg_box.get_child_count()
	print("[BS·2] finished 后：仍忙碌=", busy_after_fin, " 气泡 ", after_fail, "→", after_fin, " 按钮=", shell._send_button.text)

	var ok: bool = locked and not busy_after_fail and after_fail == before_fail \
			and not busy_after_fin and after_fin == after_fail + 1
	print("[BS·2] ", "✅ 锁定 / 解锁无气泡 / 解锁加气泡 三项都符合契约" if ok else "❌ 契约被破坏")
