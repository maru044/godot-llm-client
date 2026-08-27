extends Node
class_name ResponseParser

## 非流式响应解析器
## 负责将大模型返回的长文本精准分离出 <thinking> 和 <content>

signal thinking_extracted(text: String)
signal content_extracted(text: String)
signal format_error()  # 模型未遵守 <content> 标签规范时触发

var regex_thinking: RegEx
var regex_content: RegEx

func _ensure_regex() -> void:
	if regex_thinking == null:
		regex_thinking = RegEx.new()
		regex_thinking.compile("(?s)<thinking>(.*?)</thinking>")
	if regex_content == null:
		regex_content = RegEx.new()
		regex_content.compile("(?s)<content>(.*?)</content>")

## 处理从 LLM 传来的完整文本
func parse_full_response(full_text: String) -> void:
	_ensure_regex()
	
	var thinking_text = ""
	var content_text = ""
	
	# 1. 提取 Thinking 区域
	var thinking_match = regex_thinking.search(full_text)
	if thinking_match:
		thinking_text = thinking_match.get_string(1).strip_edges()
	else:
		# 容错：如果有 <thinking> 但没闭合
		var t_start = full_text.find("<thinking>")
		var c_start = full_text.find("<content>")
		if t_start != -1:
			if c_start != -1 and c_start > t_start:
				thinking_text = full_text.substr(t_start + 10, c_start - t_start - 10).strip_edges()
			else:
				thinking_text = full_text.substr(t_start + 10).strip_edges()

	if thinking_text != "":
		thinking_extracted.emit(thinking_text)
	else:
		thinking_extracted.emit("（本次无可见思维过程）")

	# 2. 提取 Content 区域
	var content_match = regex_content.search(full_text)
	if content_match:
		content_text = content_match.get_string(1).strip_edges()
	else:
		# 容错：找 <content> 开始
		var c_start = full_text.find("<content>")
		if c_start != -1:
			content_text = full_text.substr(c_start + 9).replace("</content>", "").strip_edges()
		else:
			# 极端容错：模型没有输出 <content> 标签。用全文清理后显示，并标记格式错误
			format_error.emit()
			var fallback = full_text
			fallback = fallback.replace("</think>", "").replace("<thinking>", "").replace("</thinking>", "")
			fallback = fallback.replace("<content>", "").replace("</content>", "")
			fallback = fallback.replace("[使用简体中文开始游戏:]", "")
			content_text = fallback.strip_edges()
			
	if content_text == "" or content_text == "\n":
		return
		
	content_extracted.emit(content_text)
