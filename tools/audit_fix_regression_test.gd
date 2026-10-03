extends Node

## 仅经 run_reliability_tests.cjs 执行；所有配置、角色和存档均来自隔离副本。
var checks: Array = []
var failures := 0
var char_signals := 0
var roster_signals := 0

func _check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _ready() -> void:
	if not FileAccess.file_exists("res://.reliability-isolated"):
		print("Run through tools/run_reliability_tests.cjs; real saves must not be used.")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	_check(SaveManager.create_new_game(), "创建六项修复的隔离测试运行区")
	EventBus.character_updated.connect(func(_id): char_signals += 1)
	EventBus.roster_updated.connect(func(): roster_signals += 1)
	_test_sections()
	_test_persistence()
	var shell = load("res://scripts/UIShell.gd").new()
	get_tree().root.add_child(shell)
	await get_tree().process_frame
	await _test_display(shell)
	await _test_rollback(shell)
	_test_presets(shell)
	var output := FileAccess.open("res://audit-fix-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	output.close()
	print("AUDIT_FIX_CHECKS=", checks.size(), " FAILURES=", failures)
	shell.free()
	get_tree().quit(1 if failures else 0)

func _test_sections() -> void:
	var cases := [
		{"label":"空栏目保留下一栏目", "before":"### A\n### B\nKEEP_B\n### C\nKEEP_C", "section":"A", "after":"### A\nNEW\n### B\nKEEP_B\n### C\nKEEP_C"},
		{"label":"相似栏目名精确匹配", "before":"### 背景补充\nKEEP\n### 背景\nOLD\n### 性格\nTAIL", "section":"背景", "after":"### 背景补充\nKEEP\n### 背景\nNEW\n### 性格\nTAIL"},
		{"label":"缺失栏目追加而非前缀替换", "before":"### 背景补充\nKEEP", "section":"背景", "after":"### 背景补充\nKEEP\n\n### 背景\nNEW"},
		{"label":"末尾无换行标题可更新", "before":"### A", "section":"A", "after":"### A\nNEW\n"},
		{"label":"正文内标题文字不作为栏目", "before":"正文提到 ### A\nKEEP\n### B\nTAIL", "section":"A", "after":"正文提到 ### A\nKEEP\n### B\nTAIL\n\n### A\nNEW"},
		{"label":"CRLF 空栏目保留后文", "before":"### A\r\n### B\r\nKEEP", "section":"A", "after":"### A\r\nNEW\n### B\r\nKEEP"},
	]
	for index in range(cases.size()):
		var test: Dictionary = cases[index]
		var cid := "section_%d" % index
		_check(DataManager.create_character_with_body({"id":cid,"name":cid}, test.before), test.label + " 建卡成功")
		_check(DataManager.llm_update_section(cid, test.section, "NEW") and DataManager.get_character(cid).body == test.after, test.label)
		DataManager.reload_characters()
		_check(DataManager.get_character(cid).body == test.after.strip_edges(), test.label + " 重载保留修改")

func _test_persistence() -> void:
	var original := DataManager
	original.name = "OriginalDataManager"
	var broken = load("res://tools/audit_fault_data.gd").new()
	broken.name = "DataManager"
	get_tree().root.add_child(broken)
	_check(broken.create_character_with_body({"id":"persist","name":"Persist"}, "### A\nOLD"), "准备角色写入故障基线")
	var path: String = broken.get_character("persist").file_path
	var old_file := FileAccess.get_file_as_string(path)
	var old_cache: Dictionary = broken.get_character("persist").duplicate(true)
	for fault in ["write", "backup", "promote"]:
		broken.fault = fault
		var before_char := char_signals
		var before_roster := roster_signals
		var result = JSON.parse_string(LLMToolExecutor.execute_tool("update_character_file", '{"char_id":"persist","section":"A","content":"NEW"}'))
		_check(result.status == "error" and result.message != "Character not found.", fault + " 工具返回真实写入错误")
		_check(FileAccess.get_file_as_string(path) == old_file, fault + " 保留旧磁盘内容")
		_check(broken.get_character("persist") == old_cache, fault + " 保留旧缓存")
		_check(char_signals == before_char and roster_signals == before_roster, fault + " 不发送成功更新信号")
	broken.fault = "write"
	var before_char := char_signals
	var before_roster := roster_signals
	var created = JSON.parse_string(LLMToolExecutor.execute_tool("write_character_file", '{"name":"FailedNew","content":"BODY"}'))
	_check(created.status == "error" and not created.has("char_id"), "新角色写入失败不返回成功 id")
	_check(broken.get_all_characters().size() == original.get_all_characters().size() + 1 and not FileAccess.file_exists(path.get_base_dir().path_join("FailedNew.md")), "创建失败不留下缓存或正式文件")
	_check(char_signals == before_char and roster_signals == before_roster, "创建失败不发送更新信号")
	_check(not broken.llm_append_body("persist", "APPEND") and broken.get_character("persist") == old_cache, "追加失败不修改缓存")
	_check(not broken.update_character_header("persist", {"id":"persist","name":"CHANGED"}) and broken.get_character("persist") == old_cache, "头部更新失败不修改缓存")
	_check(not broken.toggle_favorite("persist") and broken.get_character("persist") == old_cache, "收藏写入失败保留旧状态")
	broken.fault = "rollback"
	_check(not broken.llm_update_section("persist", "A", "NEW"), "替换与恢复均失败时返回失败")
	_check(FileAccess.get_file_as_string(path + ".backup") == old_file and broken.get_character("persist") == old_cache, "恢复失败保留旧备份和缓存")
	broken.fault = ""
	broken.reload_characters()
	_check(FileAccess.get_file_as_string(path) == old_file and broken.get_character("persist").body == "### A\nOLD", "加载时恢复中断的角色替换")
	_check(not FileAccess.file_exists(path + ".backup") and not FileAccess.file_exists(path + ".pending"), "恢复后清理替换残留")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir().path_join("Blocked.md"))
	var blocked = JSON.parse_string(LLMToolExecutor.execute_tool("write_character_file", '{"name":"Blocked","content":"BODY"}'))
	_check(blocked.status == "error", "真实目录占用造成写入失败时返回错误")
	DirAccess.remove_absolute(path.get_base_dir().path_join("Blocked.md"))
	before_char = char_signals
	_check(broken.llm_update_section("persist", "A", "NEW"), "恢复故障后可成功写入")
	_check(char_signals == before_char + 1, "成功写入恰好发出一次更新信号")
	broken.reload_characters()
	_check(broken.get_character("persist").body == "### A\nNEW", "成功写入重载一致")
	broken.free()
	original.name = "DataManager"
	original.reload_characters()

func _test_display(shell: Control) -> void:
	var cases := [
		{"label":"完整 thinking 与 content", "raw":"<thinking>SECRET</thinking>[使用简体中文开始游戏:]<content>VISIBLE</content>", "body":"VISIBLE"},
		{"label":"未闭合 content", "raw":"<thinking>SECRET</thinking><content>VISIBLE", "body":"VISIBLE"},
		{"label":"旧纯文本", "raw":"PLAIN_REPLY", "body":"PLAIN_REPLY"},
		{"label":"无 content 的已闭合思考", "raw":"<thinking>SECRET</thinking>PLAIN_REPLY", "body":"PLAIN_REPLY"},
		{"label":"prefill 续写", "raw":"SECRET</thinking>PLAIN_REPLY", "body":"PLAIN_REPLY", "thinking":"SECRET"},
		{"label":"纯思考不显示", "raw":"<thinking>SECRET</thinking>", "body":""},
		{"label":"未闭合思考不显示", "raw":"<thinking>SECRET", "body":""},
		{"label":"带 prefill 的旧回复", "raw":LLMClient.PREFILL_MAGIC + "SECRET</thinking><content>VISIBLE</content>", "body":"VISIBLE"},
		{"label":"旧格式提醒不混入显示", "raw":"PLAIN_REPLY\n\n" + LLMClient.FORMAT_CORRECTION_MESSAGE, "body":"PLAIN_REPLY"},
		{"label":"思考内 content 不当正文", "raw":"<thinking><content>SECRET</content></thinking><content>VISIBLE</content>", "body":"VISIBLE"},
	]
	var parser = load("res://scripts/ResponseParser.gd").new()
	var live: Array = []
	var thinking: Array = []
	parser.content_extracted.connect(func(text): live.append(text))
	parser.thinking_extracted.connect(func(text): thinking.append(text))
	for test in cases:
		live.clear()
		thinking.clear()
		parser.parse_full_response(test.raw)
		var expected: Array = [] if test.body == "" else [test.body]
		_check(live == expected, test.label + " 实时正文正确")
		if test.has("thinking"):
			_check(thinking == [test.thinking], test.label + " 保留思考提取信号")
		shell._rebuild_chat_from_history([{"role":"assistant","content":test.raw}])
		await get_tree().process_frame
		_check(_texts(shell._msg_box) == expected, test.label + " 历史显示与实时一致")
	parser.free()
	shell._rebuild_chat_from_history([
		{"role":"user","content":null},
		{"role":"assistant","content":null},
		{"role":"assistant","content":null,"tool_calls":[]},
	])
	await get_tree().process_frame
	_check(_texts(shell._msg_box).is_empty(), "空正文及工具声明不产生气泡或字符串转换错误")
	var raw: String = cases[0].raw
	LLMClient.begin_session([{"role":"user","content":LLMClient.build_user_content("LOAD_ME")},{"role":"assistant","content":raw}])
	_check(SaveManager.save_current_game(2), "保存含思考的真实历史")
	shell._on_load_slot(2)
	await get_tree().process_frame
	_check(_texts(shell._msg_box) == ["LOAD_ME", "VISIBLE"], "保存读取完整流程仅显示正文")
	_check(LLMClient._chat_history.back().content == raw, "正文渲染保留原始模型上下文")

func _test_rollback(shell: Control) -> void:
	var setting := {"role":"system","content":"KEEP_SETTING"}
	var first := [{"role":"user","content":LLMClient.build_user_content("FIRST")},{"role":"assistant","content":"<content>FIRST_REPLY</content>"}]
	var legacy: Array = [setting]
	legacy.append_array(first)
	legacy.append_array([
		{"role":"user","content":LLMClient.build_user_content("LIMIT_INPUT")},
		{"role":"assistant","content":null,"tool_calls":[{"id":"call","function":{"name":"probe","arguments":"{}"}}]},
		{"role":"tool","tool_call_id":"call","content":"{}"},
		{"role":"system","content":LLMClient.TOOL_LIMIT_MESSAGE},
		{"role":"assistant","content":"<thinking>SECRET</thinking><content>FINAL</content>"},
	])
	_check(SaveManager.save_game_to_slot(3, {}, legacy), "准备包含旧工具上限提示的存档")
	shell._on_load_slot(3)
	await get_tree().process_frame
	_check(LLMClient._chat_history.size() == legacy.size() - 1 and LLMClient._chat_history[0] == setting, "读取旧存档仅清理精确上限提示")
	_check(_texts(shell._msg_box) == ["FIRST","FIRST_REPLY","LIMIT_INPUT","FINAL"], "旧工具存档读取时完整显示正文并跳过空工具消息")
	shell._on_rollback()
	await get_tree().process_frame
	_check(LLMClient._chat_history == [setting, first[0], first[1]], "倒回移除用户及配套工具回复并保留前轮设定")
	_check(shell._input_line.text == "LIMIT_INPUT" and _texts(shell._msg_box) == ["FIRST","FIRST_REPLY"], "倒回回填输入并重建正确气泡")
	LLMClient._chat_history = legacy.duplicate(true)
	_check(LLMClient.rollback_history() == "LIMIT_INPUT" and LLMClient._chat_history.size() == 3, "未经过读取的旧历史也能倒回")
	LLMClient.begin_session([first[0], setting, first[1]])
	var before: Array = LLMClient._chat_history.duplicate(true)
	_check(LLMClient.rollback_history() == "" and LLMClient._chat_history == before, "普通 system 边界阻止倒回时历史完全不变")
	LLMClient.begin_session([first[1]])
	before = LLMClient._chat_history.duplicate(true)
	_check(LLMClient.rollback_history() == "" and LLMClient._chat_history == before, "没有用户轮次时不误删回复")
	LLMClient.begin_session()

func _test_presets(shell: Control) -> void:
	var first := PromptSchema.create_entry("DuplicateFix", 101, "system", "FIRST")
	var second := PromptSchema.create_entry("DuplicateFix", 102, "system", "SECOND")
	_check(first != "" and second != "" and first != second, "同名预设返回各自实际文件名")
	_check(PromptSchema.get_entry_body(second).content == "SECOND", "新预设返回值准确定位新正文")
	shell._on_preset_select(second)
	_check(shell._preset_body_edit.text == "SECOND", "UI 选中新建同名预设")
	shell._preset_name_edit.text = 'Say "Hi"'
	shell._preset_depth_edit.text = "777"
	shell._preset_body_edit.text = "CHANGED"
	shell._on_preset_save()
	PromptSchema.reload()
	var changed := PromptSchema.get_entry_body(second)
	_check(changed.name == 'Say "Hi"' and changed.depth == 777 and changed.content == "CHANGED", "含引号名称经 UI 保存重载后头部及正文完整")
	_check(PromptSchema.get_entry_body(first).content == "FIRST", "编辑新同名预设不覆盖旧预设")
	_check(PromptSchema.update_entry(second, "反斜杠\\名称\t测试", 888, "system", "UPDATED"), "特殊字符名称序列化成功")
	changed = PromptSchema.get_entry_body(second)
	_check(changed.name == "反斜杠\\名称\t测试" and changed.depth == 888 and changed.content == "UPDATED", "特殊字符名称重载不变")

func _texts(node: Node) -> Array:
	var texts: Array = []
	if node is RichTextLabel:
		texts.append(node.text)
	for child in node.get_children():
		texts.append_array(_texts(child))
	return texts
