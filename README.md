# LLM Client (Godot)

A general-purpose, reusable **LLM chat client base** built with **Godot 4.6**, designed to be dropped into any game / role-play project. It provides a full chat pipeline (non-streaming HTTP + ReAct tool loop), a modern glass-morphism UI, prompt management with `user://` priority, character-card persistence, generic save/load, and robust error handling — while keeping the **core layer free of game-specific knowledge**.

---

## ✨ Highlights

- **Chat + ReAct loop** — text / text+tool / pure-tool responses, Prefill injection, tool-call circuit breaker.
- **Tool execution (registry-based)** — register `{name, description, parameters, handler}` tools; ships with `write_character_file` / `update_character_file`.
- **Prompt management** — `res://` → `user://` bootstrap, `depth`-sorted system context, editable presets, per-version folders.
- **Character cards** — Markdown (`###` sections) storage, **role-name file naming**, injected into system context at high weight (`depth≈950`) so the LLM always sees characters.
- **Generic save/load** — 6 slots + `temp_run`, game-owned `game_state`, chat-history restore, instant enter-game after load.
- **Modern, resizable UI** — frost-glass style, gradient avatars (generated textures), multi-line input (`Enter` send / `Shift+Enter` newline), copyable bubbles.
- **Robust error handling** — retryable / non-retryable error codes, **timeout vs. network loss distinguished**, clean rollback (tool-safe), stale-history cleanup, UI error toast, DeepSeek thinking-mode compatibility.

---

## 🧱 Architecture (layered)

```
┌───────────────────────────────────────────┐
│ Game layer (yours)                        │  products / characters / custom tools
│   register tools · inject dynamic context │  define game_state snapshot
├───────────────────────────────────────────┤
│ LLM Core (this repo, reusable)            │  zero game knowledge
│   LLMClient     HTTP + ReAct loop         │
│   PromptSchema  prompt bootstrap + system │
│   LLMToolExecutor  registry-based tools   │
│   DataManager   character persistence     │
│   SaveManager   generic snapshot save     │
│   ResponseParser  <thinking>/<content>    │
├───────────────────────────────────────────┤
│ Shell / UI                                │  glass-morphism, screens + overlays
│   UIShell · UITheme · Palette             │
└───────────────────────────────────────────┘
```

Core autoloads (registered in `project.godot`):
`ConfigManager` → `EventBus` → `SaveManager` → `DataManager` → `PromptSchema` → `LLMToolExecutor` → `LLMClient`.

---

## 🚀 Getting started

1. **Godot 4.6+** — open `project.godot`.
2. **Configure an API** — on the title screen press **API Config**, pick a preset (Gemini / DeepSeek / Custom), enter your key, save. Config is stored in `user://config.cfg`.
   - *Note: your API key never enters the repo — it lives only in `user://`.*
3. **Press Start Game** — a fresh `temp_run` session begins.
4. Type a message. `Enter` sends, `Shift+Enter` inserts a newline.

---

## 🛠 Tools included

| Tool | Description |
|------|-------------|
| `write_character_file(name, content)` | Create a new character card (name unique, `content` suggested in `###` sections) |
| `update_character_file(char_id, section, content)` | Replace one `###` section of a character |

Register your own tools with `LLMToolExecutor.register_tool({...})`.

---

## 🪟 UI overlays

Beyond the main chat screen, the shell ships several overlay panels (all built dynamically from `UIShell.gd`):

| Overlay | Capabilities |
|---------|--------------|
| **Presets** | List / create / update / delete prompt entries (JSON front-matter `name` / `depth` / `role`), edit via inline editor |
| **Characters** | List characters, inspect header (stats, race, etc.) + full `###` body, toggle favorite |
| **Save / Load** | 6 slots + `temp_run`, save-to-slot / load-from-slot / delete-slot, instant enter-game after load |
| **API config** | Gemini / DeepSeek / Custom preset tabs, live-fills URL / model / temp / top_p, keeps key, persists to `user://config.cfg`, "open data dir" helper |

The overlays are wired to `EventBus` signals so the chat, save, and roster views stay in sync.

---

## 📁 Key files / folders

| Path | Purpose |
|------|---------|
| `scripts/LLMClient.gd` | HTTP + ReAct loop, error handling, tool dispatch |
| `scripts/PromptSchema.gd` | prompt bootstrap, depth-sorted system context, roster injection |
| `scripts/LLMToolExecutor.gd` | registry-based tool executor + built-in character tools |
| `scripts/DataManager.gd` | character persistence (role-name `.md` files) |
| `scripts/SaveManager.gd` | 6-slot save + `temp_run`, generic `game_state` |
| `scripts/UIShell.gd` / `UITheme.gd` / `Palette.gd` | glass UI, theme factory, palette |
| `data/prompts/v1.0/` | prompt presets (`.md` + JSON front-matter `depth`/`name`) |
| `tools/` | headless test scripts (run via `--headless --scene ...`) |
| `shaders/` | background / glass-blur shaders |

---

## 🗂 Prompt presets

Prompts live under `res://data/prompts/<version>/`. On first run they are copied to `user://Data/Prompts/<version>/`; after that **`user://` wins** (editable). Each `.md` has a JSON front-matter:

```jsonc
{ "depth": 500, "name": "My Prompt", "role": "system", "enabled": true }
```

Higher `depth` → earlier in the system context. The built-in `末尾格式要求.md` enforces the `<thinking>`/`[使用简体中文开始游戏:]`/`<content>` output format.

---

## ⚙️ Notes / compatibility

- **DeepSeek V4 (thinking model)**: the client injects `"thinking":{"type":"disabled"}` when `ConfigManager.thinking_disabled` is true (preset for DeepSeek). This keeps Prefill + tools compatible.
- **Timeout vs. network loss are distinguished**: when `HTTPRequest` reports `RESULT_TIMEOUT`, the UI shows "请求超时（N 秒）" (N = configured `HTTPRequest.timeout`, default 180) instead of the generic "网络断开". Genuine connection failures still show "网络断开". Errors are additionally classified into retryable (network loss / 429 / 5xx) and non-retryable (400 / 401 / 404).
- **`config.cfg`** contains your private API key and is `gitignore`d — never commit it.

---

## 🧪 Tests

Runs headless via Godot's console/headless binary — no GPU window needed:

```bash
# Windows (adjust path to your Godot 4.6+ binary)
"<path-to-godot>/Godot_v4.6.2-stable_win64_console.exe" --headless ^
  --path "llm-client" --scene res://tools/<name>_test.tscn
```

Scenarios in `tools/` (each `<name>_test.gd` + `<name>_test.tscn`):

| Test | Covers |
|------|--------|
| `timeout_test` | HTTP timeout (`RESULT_TIMEOUT`) reported separately from network loss — 8 assertions |
| `error_test` | Bad API key → 401 non-retryable, failed-round cleanup |
| `connectivity_test` | Request-timeout fallback in the test harness |
| `rollback_test` / `rollback_tool_test` / `rollback_ui_test` / `rollback_ui_tool_test` | Clean rollback, tool-safe, UI rebuild after rollback |
| `history_clean_test` / `user_dedup_test` | Stale-history cleanup, consecutive-user merge |
| `save_load_test` / `load_game_flow_test` / `start_game_test` / `new_game_clean_test` | Slot save/load, `temp_run` lifecycle, enter-game flow |
| `roster_inject_test` / `char_hotload_test` / `handler_write_test` / `tool_test` / `tool_update_test` | Character roster injection, tools wiring, write/update handlers |
| `parse_diag_test` / `thinking_check_test` | `<thinking>`/`<content>` parser, format-error reminder |
| `preset_add_test` / `depth_check_test` | Prompt preset create, depth ordering |
| `api_tab_test` / `home_button_test` / `multiline_input_test` / `bubble_restore_test` / `ui_fix_test` / `ui_integration_test` | UI overlays, navigation, input, bubble restore |
| `edge_test` | Edge cases (see file) |

---

## 🔒 Security

- API key is only read from `user://config.cfg`, never hardcoded in the repo.
- `.gitignore` excludes `config.cfg`, agent memory, and key-named files.

---

## 📄 License

MIT License — see [LICENSE](LICENSE).

---

## 🤝 Contributing / Feedback

Ideas, issues, and PRs welcome. This base is intentionally game-agnostic — adapt the **game layer** (tools/context/save shape) for your own project.
