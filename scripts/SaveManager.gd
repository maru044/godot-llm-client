extends Node
class_name SaveManagerClass

## temp_run 是运行区；存读档先准备同目录快照，再通过重命名替换。
## .backup 保留到新目录就位，启动时恢复中断的替换。
const SAVES_DIR = "user://saves/"
const TEMP_RUN_DIR = "user://saves/temp_run/"
const MAX_SLOTS = 6
var current_save_id: String = ""
var last_error: String = ""


func _ready() -> void:
	if DirAccess.make_dir_recursive_absolute(SAVES_DIR) != OK:
		_error("无法创建存档目录")
		return
	for name in ["temp_run", "slot_1", "slot_2", "slot_3", "slot_4", "slot_5", "slot_6"]:
		if not _recover_directory(SAVES_DIR.path_join(name)):
			push_warning(last_error)


func _error(message: String) -> bool:
	last_error = message
	print("[SaveManager] ", message)
	return false


func _slot_path(index: int) -> String:
	return SAVES_DIR.path_join("slot_%d" % (index + 1))


func _valid_slot(index: int) -> bool:
	if index < 0 or index >= MAX_SLOTS:
		return _error("存档槽位无效")
	return true


func get_current_save_path() -> String:
	return TEMP_RUN_DIR


func get_slots_info() -> Array:
	var slots: Array = []
	for index in range(MAX_SLOTS):
		var data := _read_metadata(_slot_path(index))
		if data.is_empty():
			slots.append(null)
		else:
			data["id"] = "slot_%d" % (index + 1)
			slots.append(data)
	return slots


func _read_metadata(path: String) -> Dictionary:
	var file := FileAccess.open(path.path_join("metadata.json"), FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var data = parser.data
	if not data is Dictionary or data.is_empty():
		return {}
	if data.has("game_state") and not data.game_state is Dictionary:
		return {}
	if data.has("chat_history"):
		if not data.chat_history is Array:
			return {}
		for msg in data.chat_history:
			if not msg is Dictionary or not msg.get("role") is String:
				return {}
			if msg.get("content") != null and not msg.content is String:
				return {}
	return data


func _write_metadata(path: String, meta: Dictionary) -> bool:
	var file := FileAccess.open(path.path_join("metadata.json"), FileAccess.WRITE)
	if file == null:
		return _error("无法写入存档信息（错误 %d）" % FileAccess.get_open_error())
	var serialized := JSON.stringify(meta, "\t")
	file.store_string(serialized)
	file.flush()
	var err := file.get_error()
	file.close()
	# JSON 数字回读为 float；直接比较原始 Dictionary 会把正常快照判成失败。
	if err != OK or _read_metadata(path).is_empty() or FileAccess.get_file_as_string(path.path_join("metadata.json")) != serialized:
		return _error("存档信息写入或回读校验失败")
	return true


## 删除操作严格限制在 saves 的子目录中。
func _inside_saves(path: String) -> bool:
	var root := ProjectSettings.globalize_path(SAVES_DIR).simplify_path().trim_suffix("/").to_lower()
	var target := ProjectSettings.globalize_path(path).simplify_path().trim_suffix("/").to_lower()
	return target.begins_with(root + "/")


func _delete_dir_recursive(path: String) -> bool:
	if not _inside_saves(path):
		return _error("拒绝删除存档目录外的路径")
	if not DirAccess.dir_exists_absolute(path):
		return true
	var dir := DirAccess.open(path)
	if dir == null:
		return _error("无法打开待清理的存档目录")
	dir.include_hidden = true
	for name in dir.get_files():
		if DirAccess.remove_absolute(path.path_join(name)) != OK:
			return _error("无法清理存档文件: " + name)
	for name in dir.get_directories():
		if not _delete_dir_recursive(path.path_join(name)):
			return false
	if DirAccess.remove_absolute(path) != OK:
		return _error("无法清理存档目录")
	return true


func _copy_dir_recursive(from_path: String, to_path: String) -> bool:
	var dir := DirAccess.open(from_path)
	if dir == null or not _inside_saves(to_path):
		return _error("无法打开快照源目录")
	if DirAccess.make_dir_recursive_absolute(to_path) != OK:
		return _error("无法创建快照目录")
	dir.include_hidden = true
	for name in dir.get_files():
		var source := from_path.path_join(name)
		var dest := to_path.path_join(name)
		if DirAccess.copy_absolute(source, dest) != OK:
			return _error("复制存档文件失败: " + name)
		var source_hash := FileAccess.get_sha256(source)
		if source_hash == "" or source_hash != FileAccess.get_sha256(dest):
			return _error("存档文件校验失败: " + name)
	for name in dir.get_directories():
		if not _copy_dir_recursive(from_path.path_join(name), to_path.path_join(name)):
			return false
	return true


## 单独包装以便故障注入验证目录替换失败及回滚。
func _rename_dir(source: String, dest: String) -> Error:
	return DirAccess.rename_absolute(source, dest)


func _recover_directory(target: String) -> bool:
	var backup := target + ".backup"
	var pending := target + ".pending"
	if DirAccess.dir_exists_absolute(backup):
		if _read_metadata(target).is_empty():
			if _read_metadata(backup).is_empty():
				return _error("备份与正式存档均无法读取，保留现场: " + target)
			if not _delete_dir_recursive(target) or _rename_dir(backup, target) != OK:
				return _error("恢复存档备份失败，备份已保留: " + backup)
		elif not _delete_dir_recursive(backup):
			return false
	return _delete_dir_recursive(pending)


func _prepare_directory(target: String) -> String:
	if not _recover_directory(target):
		return ""
	var pending := target + ".pending"
	if DirAccess.make_dir_recursive_absolute(pending) != OK:
		_error("无法创建待提交的存档目录")
		return ""
	return pending


func _replace_directory(target: String, pending: String) -> bool:
	var backup := target + ".backup"
	var had_old := DirAccess.dir_exists_absolute(target)
	if had_old and _rename_dir(target, backup) != OK:
		return _error("无法保留旧存档，已停止替换")
	if _rename_dir(pending, target) != OK:
		if had_old and _rename_dir(backup, target) != OK:
			return _error("替换失败且回滚失败，旧数据保留在: " + backup)
		return _error("替换存档失败，旧数据已保留")
	# 此时新数据已经提交；备份清理失败不撤销已成功的保存，启动时再清理。
	if had_old and not _delete_dir_recursive(backup):
		push_warning("存档已提交，旧备份待下次启动清理: " + backup)
	last_error = ""
	return true


func create_new_game() -> bool:
	last_error = ""
	var target := TEMP_RUN_DIR.trim_suffix("/")
	var pending := _prepare_directory(target)
	if pending == "":
		return false
	if DirAccess.make_dir_recursive_absolute(pending.path_join("characters")) != OK:
		return _error("无法创建新游戏角色目录")
	if not _write_metadata(pending, {"created_at": Time.get_datetime_string_from_system(), "chat_history": [], "game_state": {}, "msg_count": 0}):
		return false
	var llm = get_node_or_null("/root/LLMClient")
	if llm:
		llm.cancel_active_request()
	if not _replace_directory(target, pending):
		return false
	if llm:
		llm.begin_session()
	current_save_id = "temp_run"
	EventBus.active_save_changed.emit("temp_run")
	return true


func save_current_game(slot_index: int, game_state: Dictionary = {}) -> bool:
	var llm = get_node_or_null("/root/LLMClient")
	var history: Array = llm._chat_history.duplicate(true) if llm else []
	return save_game_to_slot(slot_index, game_state, history)


func save_game_to_slot(slot_index: int, game_state: Dictionary = {}, chat_history: Array = []) -> bool:
	last_error = ""
	if not _valid_slot(slot_index):
		return false
	var llm = get_node_or_null("/root/LLMClient")
	if llm and llm.is_busy():
		return _error("请等待当前回复完成后再保存")
	var target := _slot_path(slot_index)
	var pending := _prepare_directory(target)
	if pending == "":
		return false
	if DirAccess.dir_exists_absolute(TEMP_RUN_DIR):
		if not _copy_dir_recursive(TEMP_RUN_DIR, pending):
			return false
	var meta := {"created_at": Time.get_datetime_string_from_system(), "game_state": game_state.duplicate(true), "chat_history": chat_history.duplicate(true), "msg_count": chat_history.size()}
	if not _write_metadata(pending, meta):
		return false
	return _replace_directory(target, pending)


func load_game_from_slot(slot_index: int) -> Dictionary:
	last_error = ""
	if not _valid_slot(slot_index):
		return {}
	var source := _slot_path(slot_index)
	if not _recover_directory(source):
		return {}
	var data := _read_metadata(source)
	if data.is_empty():
		_error("槽位为空或存档信息损坏")
		return {}
	var target := TEMP_RUN_DIR.trim_suffix("/")
	var pending := _prepare_directory(target)
	if pending == "" or not _copy_dir_recursive(source, pending):
		return {}
	if _read_metadata(pending).is_empty() or FileAccess.get_sha256(pending.path_join("metadata.json")) != FileAccess.get_sha256(source.path_join("metadata.json")):
		_error("读取快照校验失败")
		return {}
	var llm = get_node_or_null("/root/LLMClient")
	if llm:
		llm.cancel_active_request()
	if not _replace_directory(target, pending):
		return {}
	if llm:
		llm.begin_session(data.get("chat_history", []))
	current_save_id = "temp_run"
	EventBus.active_save_changed.emit("temp_run")
	return data


func delete_slot(slot_index: int) -> bool:
	last_error = ""
	if not _valid_slot(slot_index):
		return false
	var target := _slot_path(slot_index)
	if not _recover_directory(target):
		return false
	return _delete_dir_recursive(target)
