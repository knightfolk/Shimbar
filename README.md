# Shimbar

A native macOS menu bar utility for the `codex-shim` local proxy daemon. **Shimbar** provides a clean, visual interface directly in your Apple menu bar to control the local proxy server, configure model providers, switch active coding models in real-time, and patch Codex Desktop.

[![Download Shimbar](https://img.shields.io/badge/Download-v1.0.1-0052CC.svg?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/knightfolk/Shimbar/releases/latest/download/Shimbar-1.0.1.dmg)
[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![CI](https://github.com/knightfolk/Shimbar/actions/workflows/build.yml/badge.svg)](https://github.com/knightfolk/Shimbar/actions/workflows/build.yml)

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
- **Launch at Login**: Integrates with ServiceManagement to run automatically at macOS startup.

---

## System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **macOS** | Sonoma 14.0 | Sequoia 15.0+ |
| **Architecture** | Apple Silicon (M1+) | Apple Silicon (M1+) |
| **Intel** | Supported | — |
| **Xcode** | 16.0 | 16.4+ |
| **Swift** | 5.10 | 6.0+ |
| **RAM** | 8 GB | 16 GB+ |

### Runtime Dependencies

- **`codex-shim`** CLI binary — the local proxy daemon that Shimbar manages. Install separately via `codex-shim install`.

### Build Dependencies

- **XcodeGen** — generates the `.xcodeproj` from `project.yml`:
  ```bash
  brew install xcodegen
  ```
- **Make** — build orchestration (macOS built-in)

### Tech Stack

- **Language**: Swift 5.10 (Swift 6.0 ready)
- **UI Framework**: SwiftUI with `@Observable` (no Combine dependency)
- **Architecture**: Singleton managers + SwiftUI views, actor-based concurrency
- **Networking**: Native `URLSession` (zero third-party HTTP dependencies)
- **Security**: macOS Keychain Services, Hardened Runtime, Notarized distribution
- **Testing**: XCTest / Swift Testing — 331 tests, 0 failures
- **CI**: GitHub Actions (macOS 15 runner, full build + test suite)

---

## Getting Started

### Quick Install (Recommended)

1. Download the latest **`Shimbar-1.0.1.dmg`** from [**Releases**](https://github.com/knightfolk/Shimbar/releases/latest).
2. Mount the DMG and drag **Shimbar** to your **Applications** folder.
3. On first launch, right-click the app and choose **Open** (required once for Gatekeeper).

> The DMG is **signed** with a Developer ID and **notarized** by Apple. After the first launch, it will open normally.

> **Note:** Shimbar requires the `codex-shim` CLI binary. Install it with `codex-shim install`. If you previously used the Python-based shim, run `codex-shim install --install-without-python`.

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
| `LegacyShimMigration.swift` | One-time migration helper that stops legacy Python shim processes on upgrade. |
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

- **Code-signed** with a Developer ID Application certificate and **notarized** through Apple's notary service — no Gatekeeper warnings on launch.
- **Hardened Runtime** enabled with entitlements for library validation.
- All API credentials are stored in the native macOS **Keychain** — never written to disk in plaintext by Shimbar.
- Credentials are also saved in `~/.codex-shim/models.json` so the background `codex-shim` proxy daemon can authenticate with upstream LLM providers. **Keep this file private.**

---

## License

Shimbar is released under the MIT License. Developed by Antigravity.
