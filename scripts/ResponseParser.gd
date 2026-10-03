extends Node
class_name ResponseParser

## 非流式响应解析器
## 负责将大模型返回的长文本精准分离出 <thinking> 和 <content>

signal thinking_extracted(text: String)
signal content_extracted(text: String)
signal format_error()  # 模型未遵守 <content> 标签规范时触发

var regex_thinking: RegEx

func _ensure_regex() -> void:
	if regex_thinking == null:
		regex_thinking = RegEx.new()
		regex_thinking.compile("(?s)<thinking>(.*?)</thinking>")


## 实时显示和历史重建共用；只提取正文，不发信号或修改历史。
static func extract_content(full_text: String) -> String:
	var text := full_text
	# 旧版本把格式提醒拼进 assistant 正文，显示时兼容去掉该后缀。
	var correction := text.find("\n\n[System: Format Correction]")
	if correction != -1:
		text = text.substr(0, correction)
	var thinking := RegEx.new()
	thinking.compile("(?s)<thinking>.*?</thinking>|<think>.*?</think>")
	text = thinking.sub(text, "", true)
	var content := RegEx.new()
	content.compile("(?s)<content>(.*?)</content>")
	var matched := content.search(text)
	if matched:
		return matched.get_string(1).strip_edges()
	var start := text.find("<content>")
	if start != -1:
		return text.substr(start + 9).replace("</content>", "").strip_edges()
	# 兼容无标签旧正文及 prefill 续写；未闭合的思考区不能当正文显示。
	for closing in ["</thinking>", "</think>"]:
		var end := text.rfind(closing)
		if end != -1:
			text = text.substr(end + closing.length())
	for opening in ["<thinking>", "<think>"]:
		var thinking_start := text.find(opening)
		if thinking_start != -1:
			text = text.substr(0, thinking_start)
	return text.replace("[使用简体中文开始游戏:]", "").strip_edges()

## 处理从 LLM 传来的完整文本
func parse_full_response(full_text: String) -> void:
	_ensure_regex()
	
	var thinking_text = ""
	
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
		else:
			# prefill 续写可能只有闭合标签，实际思考仍需通过原有信号提供。
			var t_end := full_text.find("</thinking>")
			if t_end != -1:
				thinking_text = full_text.substr(0, t_end).strip_edges()

	if thinking_text != "":
		thinking_extracted.emit(thinking_text)
	else:
		thinking_extracted.emit("（本次无可见思维过程）")

	# 2. 提取正文；缺少 content 标签时仍允许纯文本，但提醒模型修正格式。
	if not full_text.contains("<content>"):
		format_error.emit()
	var content_text := extract_content(full_text)
			
	if content_text == "" or content_text == "\n":
		return
		
	content_extracted.emit(content_text)
