# Shimbar

A native macOS menu bar utility for the `codex-shim` local proxy daemon. **Shimbar** provides a clean, visual interface directly in your Apple menu bar to control the local proxy server, configure model providers, switch active coding models in real-time, and patch Codex Desktop.

[![Download Shimbar](https://img.shields.io/badge/Download-Latest_Release-indigo.svg?style=for-the-badge&logo=apple)](https://github.com/knightfolk/Shimbar/releases)

---

## Preview

### Menu Companion
<img src="assets/menu_bar_view.png" width="320" alt="Shimbar Menu Companion">

### Settings & Preferences Panels
| Providers Manager | Models Manager | Auto Router |
| :---: | :---: | :---: |
| <img src="assets/providers_tab.png" width="280" alt="Providers"> | <img src="assets/models_tab.png" width="280" alt="Models"> | <img src="assets/advanced_tab.png" width="280" alt="Advanced"> |

---

## Features

- **Native macOS User Interface**: Clean integration into the macOS menu bar with automatic light/dark mode support and native SF Symbols.
- **Onboard Provider Wizard**: Visual setup grid supporting **12 built-in providers**:
  - *OpenAI*, *Anthropic*, *DeepSeek*, *Google Gemini*, *Z.AI (Zhipu)*, *MiniMax*, *Qwen (Alibaba)*, *Moonshot (Kimi)*, *OpenRouter*, *Together AI*, *Fireworks AI*, and *Custom Endpoints*.
- **Live API Key Validation**: Dynamic testing of your keys with automatic extraction and onboarding of available model IDs from upstream endpoints.
- **Keychain Integration**: Stores all API keys in the secure macOS Keychain. Your credentials are never written to disk or transmitted elsewhere.
- **On-the-fly Model Switching**: Change your active AI model directly from the menu bar with immediate `models.json` updates and background daemon reload.
- **Auto Router**: Per-task smart model routing. Configure a classifier model that evaluates each prompt and dispatches it to the cheapest candidate model that can handle it. Add candidates, set cost tiers, capability cards, and a confidence threshold — all from a dedicated UI tab.
- **`/health` JSON API**: Real-time health monitoring via `GET /health` returning structured JSON (`{ok, models, chatgpt_passthrough, cursor_passthrough, auto_router}`). The UI polls this endpoint and reflects live daemon state.
- **`/v1/models` Live Discovery**: Fetches the OpenAI-compatible `{object: "list", data: [{id, object, created, owned_by}]}` endpoint served by the running shim. Distinguishes ChatGPT passthrough, Cursor passthrough, Auto Router, and BYOK models at a glance.
- **`--settings` Flag Support**: Configure a custom path to the codex-shim config file. When set, all CLI invocations pass `--settings <path>`, enabling multiple named configurations.
- **CLI Task Runner**: Run one-off `codex-shim codex -- <prompt>` tasks directly from the Advanced tab with streaming output in a monospaced scroll pane.
- **ChatGPT & Cursor Passthrough**: Transparently route ChatGPT and Cursor/Composer traffic through the shim proxy. Passthrough availability is detected from the `/health` response and surfaced in the UI.
- **Zencoder Sync**: Export providers and models to Zencoder's `~/.zencoder/settings.json` so they appear as first-party model options.
- **Diagnostics Log Stream**: Monospaced diagnostics scroll pane displaying live updates from your `shim.log` file.
- **Electron Application Patching**: Easily patch and restore Codex Desktop to route its traffic through Shimbar's local port.
- **Automatic `codex-shim` Upgrades**: Background checking of the upstream repository for updates with one-click, in-app installation. It features intelligent rebase merging to preserve local edits, native `uv tool` upgrade support, and sandboxed/elevated ownership chown resolution.
- **Launch at Login**: Integrates with ServiceManagement to run automatically at macOS startup.

---

## Requirements & Tech Stack

- **macOS Sonoma (14.0+)** or later.
- **Xcode 16.0+** with Swift 5.10.
- **XcodeGen** (utility to generate the `.xcodeproj` file from `project.yml`).
- **codex-shim** CLI binary.

---

## Getting Started

### Quick Install (Recommended)

1. Go to the [Releases](https://github.com/knightfolk/Shimbar/releases) section on GitHub.
2. Download the latest **`Shimbar-Beta.dmg`** package.
3. Mount the DMG and drag **Shimbar** to your **Applications** folder to install.

### Building from Source

#### 1. Generate the Xcode Project

Generate the native `.xcodeproj` bundle from our declarative `project.yml` file:

```bash
make generate
```

#### 2. Build the Application

Build the debug bundle using the command line or open `Shimbar.xcodeproj` in Xcode to run, test, and profile:

```bash
make build
```

#### 3. Run Shimbar

Launch the compiled `.app` package:

```bash
make run
```

---

## Project Structure

| File | Purpose |
|------|---------|
| `project.yml` | Declares targets, configurations, frameworks, and source files for XcodeGen. |
| `ShimbarApp.swift` | `@main` entry point — initializes the MenuBarExtra window and lifecycle bootstrapping. |
| `ShimManager.swift` | Observable manager orchestrating daemon lifecycle, shell command dispatching, environment resolution, `/health` polling, and `/v1/models` discovery. |
| `KeychainManager.swift` | Swift Security framework wrapper performing GenericPassword operations securely. |
| `ApiKeyValidator.swift` | Async network validator for credentials and dynamic model discovery. |
| `ModelsJsonManager.swift` | Local parser loading and saving `~/.codex-shim/models.json` atomically with backup streams and router config support. |
| `ProcessRunner.swift` | Actor-based async shell command runner with `--port` / `--settings` injection and elevated privilege support. |
| `ShimUpdater.swift` | Upstream `codex-shim` repository checker and one-click installer. |
| `ZencoderSettingsManager.swift` | Syncs providers and models to `~/.zencoder/settings.json`. |
| `ZenflowWorkflowManager.swift` | Manages Zenflow workflow templates and execution. |
| `ShimModel.swift` | Core model types: `ShimModel`, `RouterConfig`, `RouterCandidate`, `ModelsFile`. |
| `ShimStatus.swift` | `ShimStatus` enum, `HealthResponse`, `LiveModel`, and `LiveModelsResponse` types. |
| **Views/** | |
| `ShimMenuView.swift` | Main menu bar popover — status, model switching, patch toggle, update banner. |
| `SettingsView.swift` | Multi-tab preference window container. |
| `AutoRouterSettingsTab.swift` | Auto Router configuration UI — classifier selection, threshold tuning, candidate management. |
| `AdvancedSettingsTab.swift` | CLI Task Runner, `--settings` path config, diagnostics log viewer, passthrough toggle. |
| `ProviderSetupWizard.swift` | Setup wizard grid and credential validations. |
| `ModelEditorSheet.swift` | Fine-grained configuration manager for individual models. |

---

## API Reference

Shimbar communicates with the running `codex-shim` daemon over HTTP on `127.0.0.1:{port}` (default `8765`):

### `GET /health`

Returns structured daemon health:

```json
{
  "ok": true,
  "models": 5,
  "chatgpt_passthrough": true,
  "cursor_passthrough": false,
  "auto_router": true
}
```

### `GET /v1/models`

Returns the OpenAI-compatible model list reflecting what the shim currently serves:

```json
{
  "object": "list",
  "data": [
    {"id": "gpt-4o", "object": "model", "created": 1700000000, "owned_by": "codex-shim"},
    {"id": "gpt-5.5", "object": "model", "created": 1700000000, "owned_by": "chatgpt"},
    {"id": "codex-auto", "object": "model", "created": 1700000000, "owned_by": "codex-shim-auto"}
  ]
}
```

---

## Security

All credentials are saved securely using native macOS **Keychain Services** for robust local backup. In addition, credentials are saved in the local `~/.codex-shim/models.json` file so that the background `codex-shim` proxy daemon can read them to authenticate requests with upstream LLM providers. Please keep your `models.json` file private as it contains these credentials in plaintext.

---

## License

Shimbar is released under the MIT License. Developed by Antigravity.
