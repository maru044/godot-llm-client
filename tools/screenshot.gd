extends SceneTree
## 截图工具：加载主场景，分别截取标题读取存档面板 与 游戏内保存存档面板
## 用法：godot --path . --script res://tools/screenshot.gd

var scenes: Node

func _initialize() -> void:
	var dir := DirAccess.open("D:/LLM客户端/llm-client/")
	if dir:
		if not dir.dir_exists("docs"):
			dir.make_dir("docs")

	scenes = load("res://scenes/main.tscn").instantiate()
	root.add_child(scenes)
	await process_frame
	await process_frame
	await process_frame

	# 1. 标题界面 → 读取游戏（load 模式存档面板）
	scenes.open_save_panel("load")
	await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("D:/LLM客户端/llm-client/docs/shot_save_load.png")
	print("[Shot] save_load saved")
	scenes.close_overlay("overlay-save")

	# 2. 切到游戏 → 存档（save 模式存档面板）
	scenes.show_screen("screen-chat")
	await process_frame
	await process_frame
	await process_frame
	scenes.open_save_panel("save")
	await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("D:/LLM客户端/llm-client/docs/shot_save_save.png")
	print("[Shot] save_save saved")
	quit()