extends Node

## 诊断：末尾格式要求(depth=0) 是否被 build_system_context 正确包含
## 用法：--headless --scene res://tools/depth_check_test.tscn

func _ready() -> void:
	var ps = get_node_or_null("/root/PromptSchema")
	print("[DEPTH] 诊断开始")

	# 1. 列出所有条目及其 depth / role / enabled
	print("[DEPTH] 所有条目:")
	for e in ps.list_entries():
		print("    file=", e.get("file",""), " depth=", e.get("depth","?"), " role=", e.get("role","?"), " enabled=", e.get("enabled","?"))

	# 2. 构建 system context，检查末尾格式要求是否包含
	var ctx = ps.build_system_context()
	var has_story_plot = ctx.find("<story plot>") != -1
	var has_format = ctx.find("必须严格遵循") != -1
	print("[DEPTH] build_system_context 长度: ", ctx.length())
	print("[DEPTH] 含 <story plot>: ", has_story_plot, " 含'必须严格遵循': ", has_format)

	# 3. 检查深度0条目是否进入 system_entries
	# 末尾格式要求原文含 "</story plot>"
	print("[DEPTH] 含 </story plot>: ", ctx.find("</story plot>") != -1)

	get_tree().quit(0)
