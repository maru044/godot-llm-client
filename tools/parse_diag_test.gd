extends Node

## 诊断：create_entry 后 get_entry_body 是否正确
## 用法：--headless --scene res://tools/parse_diag_test.tscn

func _ready() -> void:
	var ps = get_node_or_null("/root/PromptSchema")
	print("[DIAG] 诊断 create->get")

	var file = ps.create_entry("诊断条目2", 88, "system", "诊断正文内容-12345")
	print("[DIAG] create 返回: ", file)

	var body = ps.get_entry_body(file)
	print("[DIAG] get_entry_body: depth=", body.get("depth", "?"), " body=[", body.get("content", ""), "] name=", body.get("name", "?"), " file=", body.get("file", "?"))

	# 遍历缓存确认所有 key
	print("[DIAG] 遍历 list_entries:")
	for e in ps.list_entries():
		print("    file=[", e.get("file", ""), "] depth=", e.get("depth", "?"), " bodylen=", String(e.get("content","")).length())

	get_tree().quit(0)
