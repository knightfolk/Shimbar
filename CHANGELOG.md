# Changelog

All notable changes to Shimbar are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.1] - 2025-06-05

### Added

- Auto Router with per-task classifier-driven model routing, candidate management, confidence thresholds, and statistics tracking
- Zenflow auto router integration with workflow templates and project-scoped routing
- Router stats tracking with usage history, cache hit rates, and destination counts
- Live model usage stats parsed from `shim.log` with routing decision tracking
- `/health` JSON API for real-time daemon monitoring (`{ok, models, chatgpt_passthrough, cursor_passthrough, auto_router}`)
- `/v1/models` Live Discovery endpoint reflecting current shim model list
- `--settings` flag support for custom config file paths
- CLI Task Runner for one-off `codex-shim codex -- <prompt>` tasks from the Advanced tab
- ChatGPT passthrough with transparent desktop traffic routing through the proxy
- Cursor passthrough with availability auto-detection
- Native Swift `ShimServer` wired into the SwiftUI menu bar app
- Codex Desktop ASAR patching with automatic secure OS-level elevation (Touch ID / password)
- Patch/restore toggle with colored status indicators
- Dynamic model discovery for all providers with automatic model ID extraction
- `codex-shim` auto-update support
- Diagnostics log stream showing live `shim.log` output
- One-time legacy Python shim migration with cleanup banner

### Changed

- Patched state now displays as read-only in the menu bar popover with "Controlled by Codex" badge
- Settings layout redesigned with native macOS card design
- Provider deletion logic improved to match by normalized base URL and slug prefix
- Z.AI (Zhipu) default base URL updated to active coding plan endpoint
- Model display names condensed for Z.AI and OpenCode providers

### Fixed

- Resolved SwiftUI ViewBuilder compile error in standard models selection view
- Fixed removeProvider matching for Custom providers by base URL
- Fixed Z.AI (Zhipu) default base URL to use correct `paas/v4` endpoint
- Fixed zsh invocation to run as login shell for NVM/Node/npx profile sourcing
- Fixed dynamic patch signature robustness in `app.asar` check
- Fixed auto-router catalog injection and fallback state handling
- Fixed resolved model tracking in `shim.log` and `[router]` routing decision parsing
- Fixed process and save of dynamically discovered models in setup completion

## [1.0.0] - 2025-05-28

### Added

- Native macOS menu bar utility for `codex-shim` local proxy daemon
- Onboard Provider Wizard with 12+ built-in providers: OpenAI, Anthropic, DeepSeek, Google Gemini, Z.AI (Zhipu), MiniMax, Qwen, Moonshot, OpenRouter, Together AI, Fireworks AI, OLMX, OpenCode-Go, and Custom Endpoints
- Live API key validation with dynamic model discovery
- macOS Keychain integration for secure credential storage
- On-the-fly model switching from menu bar
- Provider setup wizard in standalone `NSWindow` to prevent transient dismissal
- Startup onboarding and dependency validation system
- Full Disk Access request flow with step-by-step NSAlert instructions
- Automatic light/dark mode support with native SF Symbols
- `project.yml` (XcodeGen) build system
- Comprehensive test suite (124 tests at launch)
- README with preview screenshots, API reference, and build instructions
