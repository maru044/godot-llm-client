extends Node
## LLM Tool Executor（注册制）
## 注意：作为 autoload 使用，故不声明 class_name（避免与 autoload 单例名冲突）。

## LLM Tool Executor（注册制）
## 游戏或基座向本模块注册工具 {name, description, parameters, handler}，
## 本模块负责：把注册表转成 OpenAI 兼容的 tools schema，并分发 tool_calls 给对应 handler。
## 内置两个通用"写/改角色文件"工具，可复用到任意游戏。

# 注册表: { name: { description:String, parameters:Dictionary, handler:Callable } }
var _tool_registry: Dictionary = {}
var _tool_call_seq: int = 0


func _ready() -> void:
	_register_builtin_tools()


## 注册一个工具
## entry = { name:String, description:String, parameters:Dictionary, handler:Callable }
func register_tool(entry: Dictionary) -> void:
	var name: String = entry.get("name", "")
	if name == "":
		return
	_tool_registry[name] = {
		"description": entry.get("description", ""),
		"parameters": entry.get("parameters", {}),
		"handler": entry.get("handler", Callable()),
	}


## 内置两个可复用工具：写/改角色文件（底层即 DataManager）
func _register_builtin_tools() -> void:
	register_tool({
		"name": "write_character_file",
		"description": "新建一张角色卡。引擎自动生成角色 id 并建立档案骨架，随后把你提供的内容写入角色正文。Master 让你新建角色或剧情遇到新人物时使用。name 必须唯一，重名会被拒绝。",
		"parameters": {
			"type": "object",
			"properties": {
				"name": {"type": "string", "description": "角色名，必须唯一"},
				"content": {"type": "string", "description": "角色初始内容，建议包含 ### 分栏（外观与着装 / 性格与深层性癖 / 背景与战斗特质）"},
			},
			"required": ["name", "content"],
		},
		"handler": _handler_write_character,
	})

	register_tool({
		"name": "update_character_file",
		"description": "修改角色卡某个 ### 分栏的内容，会替换整个栏目，保留其他栏目不变。栏目不存在时会在末尾自动新建。",
		"parameters": {
			"type": "object",
			"properties": {
				"char_id": {"type": "string", "description": "目标角色的 id"},
				"section": {"type": "string", "description": "要替换的 ### 分栏名"},
				"content": {"type": "string", "description": "该栏目新的 Markdown 内容（不含栏目标题）"},
			},
			"required": ["char_id", "section", "content"],
		},
		"handler": _handler_update_character,
	})


## 生成 OpenAI 兼容的 tools schema
func get_tools_schema() -> Array:
	var result = []
	for name in _tool_registry:
		var t = _tool_registry[name]
		result.append({
			"type": "function",
			"function": {
				"name": name,
				"description": t["description"],
				"parameters": t["parameters"],
			}
		})
	return result


## 分发一个 tool_call
func execute_tool(func_name: String, args_str: String) -> String:
	var args = {}
	if args_str != "":
		var parsed = JSON.parse_string(args_str)
		if typeof(parsed) == TYPE_DICTIONARY:
			args = parsed

	print("[LLMToolExecutor] Execute: ", func_name, " args: ", args)

	if not _tool_registry.has(func_name):
		return '{"status": "error", "message": "Unknown function: ' + func_name + '"}'

	var handler: Callable = _tool_registry[func_name]["handler"]
	if handler.is_valid():
		var res = handler.call(args)
		return res if res is String else JSON.stringify(res)
	return '{"status": "error", "message": "handler not valid"}'


## ---------- 内置 handler ----------

func _handler_write_character(args: Dictionary) -> String:
	var name: String = args.get("name", "")
	var content: String = args.get("content", "")
	if name.strip_edges() == "":
		return '{"status": "error", "message": "name cannot be empty"}'

	# 重名检查
	var dm = get_node_or_null("/root/DataManager")
	if dm == null:
		return '{"status": "error", "message": "DataManager not found"}'

	var existing = dm.get_all_characters()
	for c in existing:
		if c.get("name", "") == name:
			return '{"status": "error", "message": "name already used, choose a different one"}'

	var char_id = "char_" + str(randi() % 1000000).pad_zeros(6)
	var header = {
		"id": char_id,
		"name": name,
		"status": "Idle",
	}
	dm.create_new_character(header)
	dm.llm_append_body(char_id, content)

	return JSON.stringify({"status": "success", "char_id": char_id})


func _handler_update_character(args: Dictionary) -> String:
	var char_id = args.get("char_id", "")
	var section = args.get("section", "")
	var content = args.get("content", "")
	var dm = get_node_or_null("/root/DataManager")
	if dm == null:
		return '{"status": "error", "message": "DataManager not found"}'

	var ok = dm.llm_update_section(char_id, section, content)
	if ok:
		return '{"status": "success", "message": "Section updated."}'
	return '{"status": "error", "message": "Character not found."}'


## 预留：生成一个 tool_call id（若需要手动构造）
func next_tool_call_id() -> String:
	_tool_call_seq += 1
	return "call_%d" % _tool_call_seq
