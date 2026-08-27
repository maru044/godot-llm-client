extends Node
class_name SaveManagerClass

## 存档管理器（通用快照版）
## 负责维护 6 个存档槽位的读取和保存，以及使用 temp_run 作为沙盒运行区。
## 快照内容由游戏自定义序列化成一个 JSON（game_state），Core 不感知具体字段。
## 本地存储路径位于: user://saves/

const SAVES_DIR = "user://saves/"
const TEMP_RUN_DIR = "user://saves/temp_run/"
const MAX_SLOTS = 6
var current_save_id: String = ""


func _ready() -> void:
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(SAVES_DIR):
		dir.make_dir_recursive(SAVES_DIR)


## 获取 6 个槽位的状态，返回一个数组，包含 null(空) 或 metadata 字典
func get_slots_info() -> Array:
	var slots = []
	for i in range(1, MAX_SLOTS + 1):
		var slot_id = "slot_%d" % i
		var meta_path = SAVES_DIR + slot_id + "/metadata.json"
		if FileAccess.file_exists(meta_path):
			var content = FileAccess.get_file_as_string(meta_path)
			var data = JSON.parse_string(content)
			if typeof(data) == TYPE_DICTIONARY:
				data["id"] = slot_id
				slots.append(data)
			else:
				slots.append(null)
		else:
			slots.append(null)
	return slots


## 获取当前存档的绝对路径（永远指向 temp_run）
func get_current_save_path() -> String:
	return TEMP_RUN_DIR


## 安全的递归删除文件夹
func _delete_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir = DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path = path + file_name
			if dir.current_is_dir():
				_delete_dir_recursive(full_path + "/")
			else:
				DirAccess.remove_absolute(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


## 辅助函数：递归拷贝文件夹
func _copy_dir_recursive(from_path: String, to_path: String) -> void:
	var dir = DirAccess.open(from_path)
	if not dir:
		return

	if not DirAccess.dir_exists_absolute(to_path):
		DirAccess.make_dir_recursive_absolute(to_path)

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var src = from_path + file_name
			var dst = to_path + file_name
			if dir.current_is_dir():
				_copy_dir_recursive(src + "/", dst + "/")
			else:
				DirAccess.copy_absolute(src, dst)
		file_name = dir.get_next()
	dir.list_dir_end()


## 创建新游戏（清空 temp_run），并写入基础 metadata
func create_new_game() -> void:
	_delete_dir_recursive(TEMP_RUN_DIR)
	DirAccess.make_dir_recursive_absolute(TEMP_RUN_DIR + "characters/")

	var meta = {
		"created_at": Time.get_datetime_string_from_system(),
	}
	var fw = FileAccess.open(TEMP_RUN_DIR + "metadata.json", FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(meta, "\t"))
		fw = null

	current_save_id = "temp_run"
	EventBus.active_save_changed.emit("temp_run")


## 在指定槽位保存游戏（把 temp_run 复制到 slot_X）
## game_state 由游戏提供其自定义 JSON，chat_history 由 Core 提供
func save_game_to_slot(slot_index: int, game_state: Dictionary = {}, chat_history: Array = []) -> bool:
	var slot_id = "slot_%d" % (slot_index + 1)
	var save_path = SAVES_DIR + slot_id + "/"

	var meta = {
		"created_at": Time.get_datetime_string_from_system(),
		"game_state": game_state,
		"chat_history": chat_history,
	}

	var fw = FileAccess.open(TEMP_RUN_DIR + "metadata.json", FileAccess.WRITE)
	if fw:
		fw.store_string(JSON.stringify(meta, "\t"))
		fw = null

	# 删除旧的槽位数据，全量复制 temp_run
	_delete_dir_recursive(save_path)
	_copy_dir_recursive(TEMP_RUN_DIR, save_path)

	print("[SaveManager] 游戏已保存至槽位: ", slot_id)
	return true


## 从指定槽位读取游戏（把 slot_X 复制到 temp_run）
func load_game_from_slot(slot_index: int) -> Dictionary:
	var slot_id = "slot_%d" % (slot_index + 1)
	var path = SAVES_DIR + slot_id + "/"

	if not DirAccess.dir_exists_absolute(path):
		return {}

	_delete_dir_recursive(TEMP_RUN_DIR)
	_copy_dir_recursive(path, TEMP_RUN_DIR)

	var meta_path = TEMP_RUN_DIR + "metadata.json"
	var result: Dictionary = {}
	if FileAccess.file_exists(meta_path):
		var content = FileAccess.get_file_as_string(meta_path)
		var data = JSON.parse_string(content)
		if typeof(data) == TYPE_DICTIONARY:
			result = data

		# 恢复对话框历史
		var llm = get_node_or_null("/root/LLMClient")
		if llm and data.has("chat_history"):
			llm._chat_history = data["chat_history"]

	current_save_id = "temp_run"
	EventBus.active_save_changed.emit("temp_run")
	return result


## 清空指定槽位
func delete_slot(slot_index: int) -> void:
	var slot_id = "slot_%d" % (slot_index + 1)
	var path = SAVES_DIR + slot_id + "/metadata.json"
	if FileAccess.file_exists(path):
		_delete_dir_recursive(SAVES_DIR + slot_id + "/")
