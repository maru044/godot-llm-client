extends Node
## 配置管理（Autoload 单例）：API 配置 + 游戏设置（音量 / 分辨率 / 自动保存）。
## 持久化到 user://config.cfg
## 从参考项目 config_manager.gd 规范化迁移，保留默认模型预设不变。

const CONFIG_PATH := "user://config.cfg"

var active_api: String = "gemini"
var api_url: String = ""
var api_key: String = ""
var model: String = ""
var api_temp: float = 1.0
var api_top_p: float = 0.88
var supports_vision: bool = true  # 模型是否支持图片输入（DS 等不支持）
var thinking_disabled: bool = false  # 模型中是否需关闭思考模式（DeepSeek V4 需为 true）

# 预置 API 配置（URL / 模型 / 温度 / topP 照抄参考项目）
var presets: Dictionary = {
	"gemini": {
		"url": "https://gcli.ggchan.dev/v1/chat/completions",
		"model": "gemini-3.1-pro-preview",
		"supports_vision": true,
		"thinking_disabled": false,
		"temp": 1.3,
		"top_p": 0.88,
	},
	"deepseek": {
		"url": "https://api.deepseek.com/chat/completions",
		"model": "deepseek-v4-flash",
		"supports_vision": false,
		"thinking_disabled": true,
		"temp": 1.0,
		"top_p": 0.9,
	},
	"custom": {
		"url": "",
		"model": "",
		"supports_vision": true,
		"thinking_disabled": false,
		"temp": 1.0,
		"top_p": 0.9,
	},
}

# ---------- 游戏设置 ----------
var volume: float = 0.8                    # 0.0 ~ 1.0
var resolution: Vector2i = Vector2i(1920, 1080)
var autosave_interval: String = "monthly"  # monthly / quarterly / yearly


func _ready() -> void:
	load_config()


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		apply_preset("gemini")
		return
	active_api = cfg.get_value("llm", "active_api", "gemini")
	api_url = cfg.get_value("llm", "api_url", api_url)
	api_key = cfg.get_value("llm", "api_key", api_key)
	model = cfg.get_value("llm", "model", model)
	api_temp = cfg.get_value("llm", "api_temp", api_temp)
	api_top_p = cfg.get_value("llm", "api_top_p", api_top_p)
	supports_vision = cfg.get_value("llm", "supports_vision", supports_vision)
	thinking_disabled = cfg.get_value("llm", "thinking_disabled", thinking_disabled)
	volume = cfg.get_value("settings", "volume", volume)
	resolution = cfg.get_value("settings", "resolution", resolution)
	autosave_interval = cfg.get_value("settings", "autosave_interval", autosave_interval)
	# 若自定义字段为空，回退到预设
	if api_url.is_empty() or model.is_empty():
		apply_preset(active_api)

	# thinking_disabled / supports_vision 是模型固有属性，按当前预设兜底（即便旧 cfg 有旧值）
	var p: Dictionary = presets.get(active_api, presets["gemini"])
	thinking_disabled = p.get("thinking_disabled", thinking_disabled)
	supports_vision = p.get("supports_vision", supports_vision)


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("llm", "active_api", active_api)
	cfg.set_value("llm", "api_url", api_url)
	cfg.set_value("llm", "api_key", api_key)
	cfg.set_value("llm", "model", model)
	cfg.set_value("llm", "api_temp", api_temp)
	cfg.set_value("llm", "api_top_p", api_top_p)
	cfg.set_value("llm", "supports_vision", supports_vision)
	cfg.set_value("llm", "thinking_disabled", thinking_disabled)
	cfg.set_value("settings", "volume", volume)
	cfg.set_value("settings", "resolution", resolution)
	cfg.set_value("settings", "autosave_interval", autosave_interval)
	cfg.save(CONFIG_PATH)


## 应用预置配置
func apply_preset(type_str: String) -> void:
	active_api = type_str
	var p: Dictionary = presets.get(type_str, presets["gemini"])
	api_url = p.get("url", "")
	model = p.get("model", "")
	api_temp = p.get("temp", 1.3)
	api_top_p = p.get("top_p", 0.88)
	supports_vision = p.get("supports_vision", true)
	thinking_disabled = p.get("thinking_disabled", false)


func has_valid_config() -> bool:
	return not api_url.is_empty() and not api_key.is_empty() and not model.is_empty()
