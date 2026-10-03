extends "res://scripts/SaveManager.gd"

var fault := ""

func _copy_dir_recursive(source: String, dest: String) -> bool:
	if fault == "copy":
		return _error("测试注入：复制失败")
	return super._copy_dir_recursive(source, dest)

func _write_metadata(path: String, meta: Dictionary) -> bool:
	if fault == "write":
		return _error("测试注入：写入失败")
	return super._write_metadata(path, meta)

func _rename_dir(source: String, dest: String) -> Error:
	if fault == "backup" and dest.ends_with(".backup"):
		return ERR_CANT_CREATE
	if fault in ["promote", "rollback"] and source.ends_with(".pending"):
		return ERR_CANT_CREATE
	if fault == "rollback" and source.ends_with(".backup"):
		return ERR_CANT_CREATE
	return super._rename_dir(source, dest)
