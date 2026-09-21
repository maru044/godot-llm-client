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
# 请求状态收尾信号：每次请求恰好发出一次（成功走 finished，失败走 failed）。
# 与 system_error_occurred 的区别：后者是「通知」，重试过程中可以发多次，且不改变忙碌状态；
# 本信号只表示「这次请求结束了」，用于让界面解除忙碌。
signal llm_response_failed()

# -- 数据与存档信号 --
signal active_save_changed(save_id: String)
signal character_updated(char_id: String)
signal roster_updated()

# -- 预设面板信号 --
signal prompt_entries_changed()
