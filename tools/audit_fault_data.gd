extends "res://scripts/DataManager.gd"

var fault := ""

func _write_pending_character_file(path: String, content: String) -> bool:
	if fault == "write":
		return _write_error("测试注入：角色写入失败")
	return super._write_pending_character_file(path, content)

func _rename_character_file(source: String, dest: String) -> Error:
	if fault == "backup" and dest.ends_with(".backup"):
		return ERR_CANT_CREATE
	if fault in ["promote", "rollback"] and source.ends_with(".pending"):
		return ERR_CANT_CREATE
	if fault == "rollback" and source.ends_with(".backup"):
		return ERR_CANT_CREATE
	return super._rename_character_file(source, dest)
