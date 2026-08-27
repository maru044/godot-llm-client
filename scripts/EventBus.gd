extends Node
## ==========================================
## 全局信号总线 (EventBus)
## 基座通用层：UI 交互 + LLM 核心信号
## ==========================================

# -- UI 交互信号 --
signal nav_button_clicked(panel_name: String)
signal chat_message_sent(text: String)

# -- 对话核心信号 --
signal llm_response_started()
signal llm_response_finished(content: String)
signal system_error_occurred(error_msg: String)

# -- 数据与存档信号 --
signal active_save_changed(save_id: String)
signal character_updated(char_id: String)
signal roster_updated()

# -- 预设面板信号 --
signal prompt_entries_changed()
