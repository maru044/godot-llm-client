extends Node

## 必须经 run_reliability_tests.cjs 在隔离目录运行，故障用例会修改测试存档。
var checks: Array = []
var failures := 0
var failed_signals := 0
var finished_signals := 0
var probe_calls := 0
var base_url := ""
var elapsed := 0.0

func _check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _process(dt: float) -> void:
	elapsed += dt
	if elapsed > 55.0:
		get_tree().quit(1)

func _pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _wait_done() -> void:
	var waited := 0.0
	while LLMClient.is_busy() and waited < 10.0:
		await _pause(0.05)
		waited += 0.05
	_check(not LLMClient.is_busy(), "请求在时限内结束")

func _wait_received(route: String) -> void:
	var path := "res://http-received" + route.replace("/", "_")
	var waited := 0.0
	while not FileAccess.file_exists(path) and waited < 3.0:
		await _pause(0.01)
		waited += 0.01
	_check(FileAccess.file_exists(path), route + " 已到达模拟服务再测试取消")

func _probe(_args: Dictionary) -> String:
	probe_calls += 1
	var file := FileAccess.open(SaveManager.TEMP_RUN_DIR + "probe.txt", FileAccess.WRITE)
	file.store_string("tool executed")
	return "{}"

func _send(route: String) -> void:
	LLMClient.begin_session()
	LLMClient.api_url = base_url + route
	LLMClient.send_chat("test")

func _ready() -> void:
	if not FileAccess.file_exists("res://.reliability-isolated"):
		print("Run through tools/run_reliability_tests.cjs; real saves must not be used.")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	base_url = LLMClient.api_url.trim_suffix("/text")
	EventBus.llm_response_failed.connect(func(): failed_signals += 1)
	EventBus.llm_response_finished.connect(func(_text): finished_signals += 1)
	LLMToolExecutor.register_tool({"name": "reliability_probe", "description": "offline probe", "parameters": {"type": "object"}, "handler": _probe})
	_check(SaveManager.create_new_game(), "创建测试运行区")
	LLMClient.begin_session([{"role": "user", "content": "SAVED"}, {"role": "assistant", "content": "SAVED_REPLY"}])
	_check(SaveManager.save_current_game(0, {"value": "OLD"}), "保存初始快照")
	var old_meta := FileAccess.get_file_as_string(SaveManager.SAVES_DIR + "slot_1/metadata.json")
	var marker := SaveManager.TEMP_RUN_DIR + "characters/keep.md"
	file_write(marker, "KEEP")
	await _test_save_failures(old_meta, marker)
	await _test_session_isolation()
	await _test_responses()
	await _test_retries()
	var output := FileAccess.open("res://reliability-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	output.close()
	print("RELIABILITY_CHECKS=", checks.size(), " FAILURES=", failures)
	get_tree().quit(1 if failures else 0)

func _test_save_failures(old_meta: String, marker: String) -> void:
	var broken = load("res://tools/reliability_fault_save.gd").new()
	add_child(broken)
	for fault in ["copy", "write", "backup", "promote"]:
		broken.fault = fault
		_check(not broken.save_game_to_slot(0, {"value": "NEW"}), fault + " 故障返回失败")
		_check(FileAccess.get_file_as_string(SaveManager.SAVES_DIR + "slot_1/metadata.json") == old_meta, fault + " 故障保留旧槽位")
	broken.fault = "copy"
	var history: Array = LLMClient._chat_history.duplicate(true)
	_check(broken.load_game_from_slot(0).is_empty(), "读档复制失败返回失败")
	_check(FileAccess.get_file_as_string(marker) == "KEEP" and LLMClient._chat_history == history, "读档失败保留运行区及历史")
	broken.fault = "write"
	_check(not broken.create_new_game(), "新游戏写入失败返回失败")
	_check(FileAccess.get_file_as_string(marker) == "KEEP" and LLMClient._chat_history == history, "新游戏失败保留运行区及历史")
	broken.fault = "rollback"
	_check(not broken.save_game_to_slot(0), "替换与回滚同时失败返回失败")
	var target := SaveManager.SAVES_DIR + "slot_1"
	_check(FileAccess.get_file_as_string(target + ".backup/metadata.json") == old_meta, "回滚失败保留可恢复备份")
	broken.fault = ""
	broken._ready()
	_check(FileAccess.get_file_as_string(target + "/metadata.json") == old_meta, "启动恢复中断替换")
	_check(not DirAccess.dir_exists_absolute(target + ".pending") and not DirAccess.dir_exists_absolute(target + ".backup"), "恢复后清理残留")
	_check(broken._copy_dir_recursive(target, target + ".backup"), "准备提交后的备份残留")
	broken._ready()
	_check(FileAccess.get_file_as_string(target + "/metadata.json") == old_meta and not DirAccess.dir_exists_absolute(target + ".backup"), "启动保留已提交存档并清理备份")
	_check(SaveManager.save_current_game(1), "准备损坏读档用例")
	file_write(SaveManager.SAVES_DIR + "slot_2/metadata.json", "[]")
	_check(SaveManager.load_game_from_slot(1).is_empty(), "损坏存档读取失败")
	_check(FileAccess.get_file_as_string(marker) == "KEEP" and LLMClient._chat_history == history, "损坏读档保留运行区及历史")
	_check(not SaveManager.save_current_game(-1) and SaveManager.load_game_from_slot(6).is_empty(), "拒绝越界槽位")
	broken.queue_free()

func file_write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _test_session_isolation() -> void:
	_send("/late-load")
	await _wait_received("/late-load")
	await _pause(0.1)
	_check(not SaveManager.save_current_game(0), "忙碌时核心拒绝保存")
	_check(not SaveManager.load_game_from_slot(0).is_empty(), "请求期间允许读档并取消旧请求")
	var loaded: Array = LLMClient._chat_history.duplicate(true)
	LLMClient.api_url = base_url + "/slow"
	LLMClient.send_chat("NEW")
	await _pause(0.4)
	_check(LLMClient.is_busy() and probe_calls == 0, "旧响应不能执行工具或解除新请求的忙碌状态")
	await _wait_done()
	_check(LLMClient._chat_history.size() == loaded.size() + 2 and not FileAccess.file_exists(SaveManager.TEMP_RUN_DIR + "probe.txt"), "旧请求不能写入新存档")
	_send("/late-new")
	await _wait_received("/late-new")
	await _pause(0.1)
	_check(SaveManager.create_new_game(), "在请求期间新建会话")
	await _pause(0.4)
	_check(not LLMClient.is_busy() and LLMClient._chat_history.is_empty() and probe_calls == 0, "新建会话丢弃旧回复及旧工具")
	_send("/late-reset")
	await _wait_received("/late-reset")
	await _pause(0.1)
	LLMClient.reset_history()
	await _pause(0.4)
	_check(not LLMClient.is_busy() and LLMClient._chat_history.is_empty() and probe_calls == 0, "直接重置历史同样隔离请求")
	_send("/retry-cancel")
	await _wait_received("/retry-cancel")
	await _pause(0.2)
	LLMClient.begin_session()
	LLMClient.api_url = base_url + "/slow"
	LLMClient.send_chat("NEW_RETRY")
	await _wait_done()
	await _pause(0.5)
	_check(LLMClient._chat_history.size() == 2 and probe_calls == 0, "取消后的退避重试不再发送或修改新历史")

func _test_responses() -> void:
	for index in range(15):
		var before_failed := failed_signals
		var before_finished := finished_signals
		_send("/invalid/%d" % index)
		await _wait_done()
		_check(failed_signals == before_failed + 1 and finished_signals == before_finished, "异常响应 %d 恰好一次失败收尾" % index)
		_check(probe_calls == 0, "异常响应 %d 未执行任何工具" % index)
	var before := failed_signals
	_send("/bad-json")
	await _wait_done()
	_check(failed_signals == before + 1, "非 JSON 响应释放忙碌状态")
	before = finished_signals
	_send("/text")
	await _wait_done()
	_check(finished_signals == before + 1, "异常后可以再次发送并成功")

func _test_retries() -> void:
	var before := failed_signals
	_send("/exhaust")
	await _wait_done()
	_check(failed_signals == before + 1, "网络重试耗尽只失败收尾一次")
	for route in ["/retry-tool", "/empty-tool"]:
		var previous := probe_calls
		var finished := finished_signals
		_send(route)
		await _wait_done()
		_check(probe_calls == previous + 1 and finished_signals == finished + 1, route + " 重试后仍可调用工具并成功")
		_check(not JSON.stringify(LLMClient._chat_history).contains("达到工具调用上限"), route + " 重试不加入工具上限指令")
	var previous := probe_calls
	_send("/tool-limit")
	await _wait_done()
	_check(probe_calls == previous + 5 and JSON.stringify(LLMClient._chat_history).contains("达到工具调用上限"), "真正的五轮工具调用仍触发上限")
