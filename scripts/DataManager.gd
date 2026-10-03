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
var last_error: String = ""


func _ready() -> void:
	EventBus.active_save_changed.connect(_on_save_changed)
	# 启动时主动加载当前保存路径下的角色文件（否则缓存为空，工具调用读不到）
	_load_all_characters()


func _on_save_changed(save_id: String) -> void:
	print("[DataManager] 存档已切换，开始重载数据...")
	reload_characters()
	EventBus.roster_updated.emit()


## 强制清空缓存并从当前保存路径重新加载（开始新游戏时调用，时序无关）
func reload_characters() -> void:
	_characters_cache.clear()
	_load_all_characters()


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

	# 中断替换时旧文件留在 .backup；先恢复，再解析正式的 .md。
	for name in dir.get_files():
		if name.ends_with(".md.backup") or name.ends_with(".md.pending"):
			if not _recover_character_file(char_dir + name.get_basename()):
				push_warning(last_error)

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
func create_new_character(header: Dictionary) -> bool:
	var char_id = header.get("id", "")
	if char_id == "":
		return _write_error("角色 id 不能为空")

	var path = _get_current_save_path()
	var full_path = path + "characters/" + char_id + ".md"

	var data := {
		"header": header.duplicate(true),
		"body": "",
		"file_path": full_path
	}

	if not _commit_character(char_id, data):
		return false
	EventBus.roster_updated.emit()
	return true


## 一次性写入新角色（骨架 + 正文作为同一份快照提交）
## 供 write_character_file 等工具使用；同时写内存缓存，避免重复落盘
func create_character_with_body(header: Dictionary, body: String) -> bool:
	var char_id = header.get("id", "")
	if char_id == "":
		return _write_error("角色 id 不能为空")

	# 文件名用角色名（更直观，便于按名 read）；净化非法字符，重名加唯一后缀兜底
	var safe_name := _safe_filename(header.get("name", char_id))
	var path = _get_current_save_path()
	var full_path = path + "characters/" + safe_name + ".md"
	# 若目标文件存在（罕见重名），追加 char_id 后缀避免覆盖
	if FileAccess.file_exists(full_path):
		full_path = path + "characters/" + safe_name + "_" + char_id + ".md"

	var data := {
		"header": header.duplicate(true),
		"body": body,
		"file_path": full_path,
	}

	if not _commit_character(char_id, data):
		return false
	EventBus.character_updated.emit(char_id)
	EventBus.roster_updated.emit()
	return true


## 文件名净化：替换 Windows 非法字符，避免角色名导致路径错误
func _safe_filename(name: String) -> String:
	var bad := ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
	var out := name.strip_edges()
	for b in bad:
		out = out.replace(b, "_")
	if out.strip_edges() == "":
		out = "character"
	return out


func is_favorited(char_id: String) -> bool:
	if not _characters_cache.has(char_id):
		return false
	return _characters_cache[char_id]["header"].get("favorited", false)


func toggle_favorite(char_id: String) -> bool:
	if not _characters_cache.has(char_id):
		return false
	var data: Dictionary = _characters_cache[char_id].duplicate(true)
	var header: Dictionary = data["header"]
	header["favorited"] = not header.get("favorited", false)
	if not _commit_character(char_id, data):
		return is_favorited(char_id)
	EventBus.character_updated.emit(char_id)
	EventBus.roster_updated.emit()
	return header["favorited"]


func update_character_header(char_id: String, new_header: Dictionary) -> bool:
	if not _characters_cache.has(char_id):
		return _write_error("Character not found.")
	var data: Dictionary = _characters_cache[char_id].duplicate(true)
	data["header"] = new_header.duplicate(true)
	if not _commit_character(char_id, data):
		return false
	EventBus.character_updated.emit(char_id)
	return true


## 大模型专用工具：追加 Markdown 正文（通常只在捕获时调用一次）
func llm_append_body(char_id: String, content: String) -> bool:
	if not _characters_cache.has(char_id):
		return _write_error("Character not found.")

	var data: Dictionary = _characters_cache[char_id].duplicate(true)
	data["body"] += "\n\n" + content

	if not _commit_character(char_id, data):
		return false
	EventBus.character_updated.emit(char_id)
	return true


## 大模型专用工具：替换某个 ### 分栏的内容
func llm_update_section(char_id: String, section_name: String, content: String) -> bool:
	if not _characters_cache.has(char_id):
		return _write_error("Character not found.")

	var data: Dictionary = _characters_cache[char_id].duplicate(true)
	var body: String = data["body"]
	var marker := "### " + section_name
	var headings := RegEx.new()
	headings.compile("(?m)^### [^\\r\\n]*(?:\\r?\\n|$)")
	var sections := headings.search_all(body)
	var matched := -1
	for index in range(sections.size()):
		if sections[index].get_string().strip_edges() == marker:
			matched = index
			break

	if matched == -1:
		# 没找到栏目，追加到末尾
		body += "\n\n" + marker + "\n" + content
	else:
		var content_start: int = sections[matched].get_end()
		var next_section: int = sections[matched + 1].get_start() if matched + 1 < sections.size() else body.length()
		var separator := "" if sections[matched].get_string().ends_with("\n") else "\n"
		body = body.substr(0, content_start) + separator + content + "\n" + body.substr(next_section)

	data["body"] = body
	if not _commit_character(char_id, data):
		return false
	EventBus.character_updated.emit(char_id)
	return true


## ==================================================
## 内部写盘逻辑
## ==================================================

func _write_error(message: String) -> bool:
	last_error = message
	print("[DataManager] ", message)
	return false


## 写盘成功才提交缓存；失败时调用方和更新信号都不能宣告成功。
func _commit_character(char_id: String, data: Dictionary) -> bool:
	last_error = ""
	var full_path: String = data["file_path"]
	if DirAccess.make_dir_recursive_absolute(full_path.get_base_dir()) != OK:
		return _write_error("无法创建角色目录")
	if not _recover_character_file(full_path):
		return false
	var pending := full_path + ".pending"
	var backup := full_path + ".backup"
	var serialized: String = "---\n" + JSON.stringify(data["header"], "  ") + "\n---\n\n" + data["body"]
	if not _write_pending_character_file(pending, serialized):
		return false
	var had_old := FileAccess.file_exists(full_path)
	if had_old and _rename_character_file(full_path, backup) != OK:
		return _write_error("无法保留旧角色文件，已停止替换")
	if _rename_character_file(pending, full_path) != OK:
		if had_old and _rename_character_file(backup, full_path) != OK:
			return _write_error("角色替换及恢复失败，旧内容保留在: " + backup)
		return _write_error("角色写入失败，旧内容已保留")
	_characters_cache[char_id] = data
	if had_old and DirAccess.remove_absolute(backup) != OK:
		push_warning("角色已保存，旧备份待下次加载清理: " + backup)
	last_error = ""
	print("[DataManager] 成功写盘: ", char_id)
	return true


func _write_pending_character_file(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _write_error("无法写入角色文件（错误 %d）" % FileAccess.get_open_error())
	file.store_string(content)
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK or FileAccess.get_file_as_string(path) != content:
		return _write_error("角色文件写入或回读校验失败")
	return true


## 包装重命名供隔离测试注入失败，生产路径保持同目录替换。
func _rename_character_file(source: String, dest: String) -> Error:
	return DirAccess.rename_absolute(source, dest)


func _recover_character_file(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return _write_error("角色文件路径被目录占用")
	var backup := path + ".backup"
	var pending := path + ".pending"
	if FileAccess.file_exists(backup):
		if not FileAccess.file_exists(path):
			if _rename_character_file(backup, path) != OK:
				return _write_error("无法恢复角色备份: " + backup)
		elif DirAccess.remove_absolute(backup) != OK:
			return _write_error("无法清理旧角色备份")
	if FileAccess.file_exists(pending) and DirAccess.remove_absolute(pending) != OK:
		return _write_error("无法清理未提交的角色文件")
	return true
