extends Node
## 提示词编辑与上下文组装（解耦版）
## 注意：作为 autoload 使用，故不声明 class_name（避免与 autoload 单例名冲突）。

## 提示词编辑与上下文组装（解耦版）
## 核心机制：首次运行从 res:// 复制到 user://，之后一律读 user://。
## 支持预设面板的 list / create / update / delete / reload。

const CURRENT_PROMPT_VERSION := "v1.0"
const RES_PROMPT_DIR := "res://Data/Prompts/"      # res 只做初始化兜底
const USER_PROMPT_BASE := "user://Data/Prompts/"   # user 是读写主目录

# 缓存：{ filename: { depth:int, role:String, content:String, enabled:bool, name:String } }
var _entries_cache: Dictionary = {}
var _active_version_dir: String = ""
var _dice_cache: String = ""   # 每轮对话生成一次，供 build_system_context 注入


func _ready() -> void:
	_init_directories()
	reload()


## 建立 user:// 目录，若不存在则从 res:// 复制预置提示词
func _init_directories() -> void:
	_active_version_dir = USER_PROMPT_BASE + CURRENT_PROMPT_VERSION + "/"

	var base_dir := USER_PROMPT_BASE + CURRENT_PROMPT_VERSION + "/"
	if not DirAccess.dir_exists_absolute(base_dir):
		print("[PromptSchema] 初始化默认提示词到: ", base_dir)
		DirAccess.make_dir_recursive_absolute(base_dir)
		_copy_res_to_user(RES_PROMPT_DIR + CURRENT_PROMPT_VERSION + "/", base_dir)


## 从 res:// 复制 .md 到 user:// 指定目录
func _copy_res_to_user(from_dir: String, to_dir: String) -> void:
	var dir := DirAccess.open(from_dir)
	if not dir:
		push_warning("[PromptSchema] 无法打开内部资源目录: " + from_dir)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".md"):
			var content := FileAccess.get_file_as_string(from_dir + file_name)
			var fw := FileAccess.open(to_dir + file_name, FileAccess.WRITE)
			if fw:
				fw.store_string(content)
		file_name = dir.get_next()
	dir.list_dir_end()


## 重新加载所有提示词条目（预设面板改动后调用）
func reload() -> void:
	_entries_cache.clear()
	var dir := DirAccess.open(_active_version_dir)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".md"):
			_parse_and_cache_file(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	print("[PromptSchema] 已加载提示词条目: ", _entries_cache.size())


## 解析单个 .md 文件（支持 JSON Frontmatter / --- Frontmatter）
func _parse_and_cache_file(file_name: String) -> void:
	var full_path := _active_version_dir + file_name
	var content := FileAccess.get_file_as_string(full_path)

	var header_json := {}
	var body_text := content

	if content.begins_with("{"):
		var first_brace := content.find("{")
		var last_brace := content.find("}\n---")
		if last_brace == -1:
			last_brace = content.find("}\r\n---")
		if first_brace != -1 and last_brace != -1:
			var header_str := content.substr(first_brace, last_brace - first_brace + 1).strip_edges()
			var test_json: Variant = JSON.parse_string(header_str)
			if typeof(test_json) == TYPE_DICTIONARY:
				header_json = test_json
				var remaining := content.substr(last_brace + 1)
				var dash_idx := remaining.find("---")
				if dash_idx != -1:
					body_text = remaining.substr(dash_idx + 3).strip_edges()
	elif content.begins_with("---"):
		var parts := content.split("---", true, 2)
		if parts.size() >= 3:
			var header_str := parts[1].strip_edges()
			if header_str.begins_with("{") and header_str.ends_with("}"):
				var test_json: Variant = JSON.parse_string(header_str)
				if typeof(test_json) == TYPE_DICTIONARY:
					header_json = test_json
					body_text = parts[2].strip_edges()

	var enabled: Variant = header_json.get("enabled", true)
	_entries_cache[file_name] = {
		"depth": header_json.get("depth", 500),
		"role": header_json.get("role", "system"),
		"name": header_json.get("name", file_name.replace(".md", "")),
		"content": body_text,
		"enabled": enabled,
		"file": file_name,
	}


## ---------- 预设面板 API ----------

## 返回全部条目（按 depth 降序）
func list_entries() -> Array:
	var arr: Array = []
	for file_name in _entries_cache:
		arr.append(_entries_cache[file_name])
	arr.sort_custom(func(a, b): return a["depth"] > b["depth"])
	return arr


## 创建新条目，返回文件名（失败返回空串）
func create_entry(name: String, depth: int, role: String, content: String) -> String:
	if name.strip_edges() == "":
		return ""
	var safe_name := name.strip_edges()
	var base_target := _active_version_dir + safe_name + ".md"
	var target := base_target
	var counter := 1
	while FileAccess.file_exists(target):
		target = _active_version_dir + safe_name + "_%d.md" % counter
		counter += 1

	var front := "{ \"depth\": %d, \"name\": \"%s\", \"role\": \"%s\", \"enabled\": true }\n---\n\n" % [depth, safe_name, role]
	var fw := FileAccess.open(target, FileAccess.WRITE)
	if fw:
		fw.store_string(front + content)
		fw = null  # 释放文件锁，确保写盘落定后再 reload
		reload()
		EventBus.prompt_entries_changed.emit()
		return safe_name + ".md"
	return ""


## 更新条目（按文件名定位）
func update_entry(file_name: String, name: String, depth: int, role: String, content: String) -> bool:
	var path := _active_version_dir + file_name
	if not FileAccess.file_exists(path):
		return false
	var safe_name := name.strip_edges() if name != "" else file_name.replace(".md", "")
	var front := "{ \"depth\": %d, \"name\": \"%s\", \"role\": \"%s\", \"enabled\": true }\n---\n\n" % [depth, safe_name, role]
	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw:
		fw.store_string(front + content)
		fw = null  # 释放文件锁，确保写盘落定后再 reload
		reload()
		EventBus.prompt_entries_changed.emit()
		return true
	return false


## 删除条目（删除 .md 文件）
func delete_entry(file_name: String) -> bool:
	var path := _active_version_dir + file_name
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open(_active_version_dir)
	if dir and dir.remove(file_name) == OK:
		reload()
		EventBus.prompt_entries_changed.emit()
		return true
	return false


## 读取单条正文（供编辑器加载）
func get_entry_body(file_name: String) -> Dictionary:
	if _entries_cache.has(file_name):
		return _entries_cache[file_name].duplicate()
	return {}


## ---------- 上下文组装 ----------

## 每轮对话生成一次骰子缓存（5 个 1~100 的随机数，供格式模板注入）
func _ensure_dice() -> void:
	if _dice_cache == "":
		_dice_cache = "(%d, %d, %d, %d, %d)" % [randi() % 100, randi() % 100, randi() % 100, randi() % 100, randi() % 100]

## 新的一轮对话开始时调用，重置骰子缓存
func reset_dice() -> void:
	_dice_cache = ""

## 按 depth 降序拼接系统上下文（仅 role == system 的启用条目）
## dynamic_data 由游戏注入，做容错替换
func build_system_context(dynamic_data: Dictionary = {}) -> String:
	_ensure_dice()
	var merge := dynamic_data.duplicate()
	if not merge.has("dice_rolls"):
		merge["dice_rolls"] = _dice_cache

	var system_entries: Array = []
	for file_name in _entries_cache:
		var p: Dictionary = _entries_cache[file_name]
		if p["enabled"] and p["role"] == "system":
			system_entries.append(p)

	# 角色详细档案合成一条高权重条目（depth≈950，位于角色信息/核心设定之后、其余之前）
	var roster_block := _build_roster_block()
	if roster_block != "":
		system_entries.append({"depth": 950, "content": roster_block})

	system_entries.sort_custom(func(a, b): return a["depth"] > b["depth"])

	var final_str := ""
	for p in system_entries:
		var raw: String = p["content"]
		var parsed := _safe_format(raw, merge)
		if parsed.strip_edges() != "":
			final_str += parsed + "\n\n"

	return final_str.strip_edges()


## 从 DataManager 读取所有角色，生成完整档案块（含 ### 详细正文）
## 放在上下文前部（高权重），让 LLM 能看到每个角色的完整设定
func _build_roster_block() -> String:
	var dm = get_node_or_null("/root/DataManager")
	if dm == null:
		return ""
	var chars = dm.get_all_characters()
	if chars.is_empty():
		return ""
	var out := "[已建档角色档案]\n"
	for c in chars:
		var cid = c.get("id", "Unknown")
		var n = c.get("name", "Unknown")
		var r = c.get("race", "")
		var cls = c.get("class", "")
		var full = dm.get_character(cid)
		var body: String = full.get("body", "")
		out += "### 角色: %s (id=%s)\n" % [n, cid]
		if r != "" or cls != "":
			out += "属性: %s %s\n" % [r, cls]
		if body.strip_edges() != "":
			out += body + "\n"
		out += "\n"
	return out.strip_edges()


## 容错 format：Godot 的 String.format 对缺失的占位符会原样保留、不崩溃，
## 因此直接用内置实现即可保证模板缺 key 时不报错、不残留异常。
func _safe_format(template: String, data: Dictionary) -> String:
	return template.format(data)
