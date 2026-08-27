extends Node
class_name DataManagerClass

## 数据持久化层（解耦版）
## 负责角色的 JSON-Frontmatter 解析、保存，以及角色列表的管理。
## 依赖业务：当前保存路径由 SaveManager 提供（通过 get_current_save_path）。
## 去掉了原参考实现对 GameManager/CombatEngine 的硬依赖，聚焦于角色文件读写。

# 内存缓存，避免频繁读盘
# 结构: { char_id: { "header": Dictionary, "body": String, "file_path": String } }
var _characters_cache: Dictionary = {}

var viewing_char_id: String = ""


func _ready() -> void:
	EventBus.active_save_changed.connect(_on_save_changed)
	# 启动时主动加载当前保存路径下的角色文件（否则缓存为空，工具调用读不到）
	_load_all_characters()


func _on_save_changed(save_id: String) -> void:
	print("[DataManager] 存档已切换，开始重载数据...")
	_characters_cache.clear()
	_load_all_characters()
	EventBus.roster_updated.emit()


## ==================================================
## 核心 IO：读取与解析
## ==================================================

func _get_current_save_path() -> String:
	var sm = get_node_or_null("/root/SaveManager")
	if sm:
		return sm.get_current_save_path()
	return "user://saves/temp_run/"


func _load_all_characters() -> void:
	var path = _get_current_save_path()
	if path == "":
		return

	var char_dir = path + "characters/"
	var dir = DirAccess.open(char_dir)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".md"):
			_parse_character_file(char_dir + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _parse_character_file(full_path: String) -> void:
	var content = FileAccess.get_file_as_string(full_path)

	var header = {}
	var body = content

	if content.begins_with("---"):
		var parts = content.split("---", true, 2)
		if parts.size() >= 3:
			var header_str = parts[1].strip_edges()
			if header_str.begins_with("{") and header_str.ends_with("}"):
				var test_json = JSON.parse_string(header_str)
				if typeof(test_json) == TYPE_DICTIONARY:
					header = test_json
					body = parts[2].strip_edges()

	var char_id = header.get("id", "")
	if char_id != "":
		_characters_cache[char_id] = {
			"header": header,
			"body": body,
			"file_path": full_path
		}


## ==================================================
## API: 供游戏逻辑或大模型调用
## ==================================================

func get_all_characters() -> Array:
	var list = []
	for cid in _characters_cache:
		list.append(_characters_cache[cid]["header"])
	return list


func get_character(char_id: String) -> Dictionary:
	return _characters_cache.get(char_id, {})


## 写入一个全新的角色（由程序生成骨架后调用）
func create_new_character(header: Dictionary) -> void:
	var char_id = header.get("id", "")
	if char_id == "":
		return

	var path = _get_current_save_path()
	if not DirAccess.dir_exists_absolute(path + "characters/"):
		DirAccess.make_dir_recursive_absolute(path + "characters/")
	var full_path = path + "characters/" + char_id + ".md"

	_characters_cache[char_id] = {
		"header": header,
		"body": "",
		"file_path": full_path
	}

	_flush_to_disk(char_id)
	EventBus.roster_updated.emit()


## 一次性写入新角色（骨架 + 正文一次落盘，避免分两次 _flush_to_disk）
## 供 write_character_file 等工具使用；同时写内存缓存，避免重复落盘
func create_character_with_body(header: Dictionary, body: String) -> void:
	var char_id = header.get("id", "")
	if char_id == "":
		return

	var path = _get_current_save_path()
	if not DirAccess.dir_exists_absolute(path + "characters/"):
		DirAccess.make_dir_recursive_absolute(path + "characters/")
	var full_path = path + "characters/" + char_id + ".md"

	_characters_cache[char_id] = {
		"header": header,
		"body": body,
		"file_path": full_path,
	}

	_flush_to_disk(char_id)
	EventBus.character_updated.emit(char_id)
	EventBus.roster_updated.emit()


func is_favorited(char_id: String) -> bool:
	if not _characters_cache.has(char_id):
		return false
	return _characters_cache[char_id]["header"].get("favorited", false)


func toggle_favorite(char_id: String) -> bool:
	if not _characters_cache.has(char_id):
		return false
	var header = _characters_cache[char_id]["header"]
	header["favorited"] = not header.get("favorited", false)
	_flush_to_disk(char_id)
	EventBus.character_updated.emit(char_id)
	EventBus.roster_updated.emit()
	return header["favorited"]


func update_character_header(char_id: String, new_header: Dictionary) -> void:
	if not _characters_cache.has(char_id):
		return
	_characters_cache[char_id]["header"] = new_header
	_flush_to_disk(char_id)
	EventBus.character_updated.emit(char_id)


## 大模型专用工具：追加 Markdown 正文（通常只在捕获时调用一次）
func llm_append_body(char_id: String, content: String) -> bool:
	if not _characters_cache.has(char_id):
		return false

	var old_body = _characters_cache[char_id]["body"]
	_characters_cache[char_id]["body"] = old_body + "\n\n" + content

	_flush_to_disk(char_id)
	EventBus.character_updated.emit(char_id)
	return true


## 大模型专用工具：替换某个 ### 分栏的内容
func llm_update_section(char_id: String, section_name: String, content: String) -> bool:
	if not _characters_cache.has(char_id):
		return false

	var body = _characters_cache[char_id]["body"]
	var marker = "### " + section_name
	var idx = body.find(marker)

	if idx == -1:
		# 没找到栏目，追加到末尾
		body += "\n\n" + marker + "\n" + content
	else:
		# 找到栏目开始位置，找下一个 ### 或末尾
		var content_start = body.find("\n", idx) + 1  # 跳过 ### 行
		var next_section = body.find("\n### ", content_start)
		if next_section == -1:
			body = body.substr(0, content_start) + content + "\n"
		else:
			body = body.substr(0, content_start) + content + "\n" + body.substr(next_section)

	_characters_cache[char_id]["body"] = body
	_flush_to_disk(char_id)
	EventBus.character_updated.emit(char_id)
	return true


## ==================================================
## 内部写盘逻辑
## ==================================================

func _flush_to_disk(char_id: String) -> void:
	if not _characters_cache.has(char_id):
		return
	var data = _characters_cache[char_id]
	var full_path = data["file_path"]

	var json_str = JSON.stringify(data["header"], "  ")

	var final_content = "---\n" + json_str + "\n---\n\n" + data["body"]

	var fw = FileAccess.open(full_path, FileAccess.WRITE)
	if fw:
		fw.store_string(final_content)
		print("[DataManager] 成功写盘: ", char_id)
	else:
		push_error("[DataManager] 写入失败: ", full_path)
