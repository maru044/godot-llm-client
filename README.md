# LLM Client (Godot)

A general-purpose, reusable **LLM chat client base** built with **Godot 4.6**, primarily maintained for an internal community while remaining freely available for other developers to use and adapt in their own game / role-play projects. When reusing it, remove or replace any internal-community business context and tailored prompt presets. It provides a full chat pipeline (non-streaming HTTP + ReAct tool loop), a modern glass-morphism UI, prompt management with `user://` priority, character-card persistence, generic save/load, and robust error handling — while keeping the **core layer free of game-specific knowledge**.

---

## ✨ Highlights

- **Chat + ReAct loop** — text / text+tool / pure-tool responses, Prefill injection, tool-call circuit breaker.
- **Tool execution (registry-based)** — register `{name, description, parameters, handler}` tools; ships with `write_character_file` / `update_character_file`.
- **Prompt management** — `res://` → `user://` bootstrap, `depth`-sorted system context, editable presets, per-version folders.
- **Character cards** — Markdown (`###` sections) storage, **role-name file naming**, exact section-title updates, verified file replacement, and roster injection into system context (`depth≈950`).
- **Generic save/load** — 6 slots + `temp_run`, game-owned `game_state`, chat-history restore with the same body extraction as live replies, instant enter-game after load.
- **Modern, resizable UI** — frost-glass style, gradient avatars (generated textures), multi-line input (`Enter` send / `Shift+Enter` newline), copyable bubbles.
- **Error handling** — retryable / non-retryable error codes, **timeout vs. network loss distinguished**, whole-turn history rollback (including tool messages), stale-history cleanup, UI error toast, and the DeepSeek thinking-disable preset.

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
| `write_character_file(name, content)` | Create a new character card (name unique, `content` suggested in `###` sections); return an error if persistence fails |
| `update_character_file(char_id, section, content)` | Replace the section with the exact `###` title, or append it if absent; return an error if persistence fails |

Register your own tools with `LLMToolExecutor.register_tool({...})`.

---

## 🪟 UI overlays

Beyond the main chat screen, the shell ships several overlay panels (all built dynamically from `UIShell.gd`):

| Overlay | Capabilities |
|---------|--------------|
| **Presets** | List / create / update prompt entries (JSON front-matter `name` / `depth` / `role`), edit via inline editor |
| **Characters** | List characters, inspect header (stats, race, etc.) + full `###` body |
| **Save / Load** | 6 slots + `temp_run`, save-to-slot / load-from-slot / delete-slot, instant enter-game after load |
| **API config** | Gemini / DeepSeek / Custom preset tabs, live-fills URL / model / temp / top_p, keeps key, persists to `user://config.cfg`, "open data dir" helper |

The overlays are wired to `EventBus` signals so the chat, save, and roster views stay in sync.

Prompt deletion is available through `PromptSchema.delete_entry()`, and favorite persistence through `DataManager.toggle_favorite()`; the current overlays do not expose those actions.

---

## 📁 Key files / folders

| Path | Purpose |
|------|---------|
| `scripts/LLMClient.gd` | HTTP + ReAct loop, error handling, tool dispatch |
| `scripts/PromptSchema.gd` | prompt bootstrap, depth-sorted system context, roster injection |
| `scripts/LLMToolExecutor.gd` | registry-based tool executor + built-in character tools |
| `scripts/DataManager.gd` | verified character persistence and interrupted-file recovery (role-name `.md` files) |
| `scripts/SaveManager.gd` | 6-slot save + `temp_run`, generic `game_state` |
| `scripts/ResponseParser.gd` | shared body extraction for live replies and restored history |
| `scripts/UIShell.gd` / `UITheme.gd` / `Palette.gd` | glass UI, theme factory, palette |
| `data/prompts/v1.0/` | prompt presets (`.md` + JSON front-matter `depth`/`name`) |
| `shaders/` | background / glass-blur shaders |

---

## 🗂 Prompt presets

Prompts live under `res://data/prompts/<version>/`. On first run they are copied to `user://data/prompts/<version>/`; after that **`user://` wins** (editable). Each `.md` has a JSON front-matter:

```markdown
{ "depth": 500, "name": "My Prompt", "role": "system", "enabled": true }
---

Prompt body goes here.
```

Higher `depth` → earlier in the system context. The built-in `末尾格式要求.md` enforces the `<thinking>`/`[使用简体中文开始游戏:]`/`<content>` output format.

Creating another entry with the same name adds a filename suffix such as `_1.md`; the editor selects the newly created file. Edited display names, including quotation marks, are serialized as JSON so they retain their name and depth after reload. New-entry filenames remain subject to operating-system filename rules.

---

## 💾 Persistence and history

- **Character writes**: write and verify a same-directory `.pending` file before replacing the official `.md`. The old file is retained as `.backup` during replacement. Cache changes and update signals are committed only after the replacement succeeds. Failed creation or updates return a tool error with the persistence failure reason. If replacement and restoration both fail, the old content remains in `.backup`; character loading attempts recovery.
- **DataManager results**: `create_new_character()`, `create_character_with_body()`, `update_character_header()`, `llm_append_body()`, and `llm_update_section()` return a success boolean, with details in `DataManager.last_error` on failure. `toggle_favorite()` continues to return the resulting favorite state; failed writes retain the previous state.
- **Displayed replies**: live chat, save restoration, and rollback restoration share body extraction. Thinking blocks are omitted from chat bubbles; plain-text legacy replies and unfinished `<content>` tags are supported. Raw assistant content remains available in model history, and the parser retains its thinking signal.
- **Rollback**: removes the last user message together with its assistant and tool messages, then restores the input text. It works after the five-round tool limit, including histories from older saves containing the generated limit instruction. Ordinary system context is preserved. Rollback affects chat history; it does not undo character-file changes made by tools.
- **Request-only instructions**: the tool-limit instruction and format reminders are added to outgoing request context without becoming displayed reply text. Local format metadata is omitted from API messages.

---

## ⚙️ Notes / compatibility

- **DeepSeek preset**: the client injects `"thinking":{"type":"disabled"}` when `ConfigManager.thinking_disabled` is true (enabled by the DeepSeek preset). The isolated regression suite uses a local mock server and does not certify live provider compatibility.
- **Timeout vs. network loss are distinguished**: when `HTTPRequest` reports `RESULT_TIMEOUT`, the UI shows "请求超时（180 秒）" for the current 180-second per-attempt timeout instead of the generic "网络断开". Genuine connection failures still show "网络断开". Errors are additionally classified into retryable (network loss / 429 / 500 / 502 / 503) and non-retryable (400 / 401 / 404).
- **`config.cfg`** contains your private API key and is `gitignore`d — never commit it.

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
