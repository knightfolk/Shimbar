# Contributing to Shimbar

Thanks for your interest in contributing! This guide covers everything you need to get started.

## Prerequisites

- **macOS Sonoma 14.0+** (or later)
- **Xcode 16.0+** with Swift 5.10
- **XcodeGen** — install via Homebrew:

```bash
brew install xcodegen
```

## Getting Started

### 1. Clone and Generate the Project

```bash
git clone https://github.com/knightfolk/Shimbar.git
cd Shimbar
make generate
```

### 2. Build

```bash
make build
```

Or open `Shimbar.xcodeproj` in Xcode and press **Cmd+R**.

### 3. Run Tests

```bash
make test
```

All 331 tests should pass. If they don't, open an issue before submitting a PR.

## Project Architecture

Shimbar follows a clear separation of concerns:

- **Models/** — Data types (`ShimModel`, `ShimStatus`, `RouterStats`, `ProviderCatalog`, `AppSettings`)
- **Views/** — SwiftUI views (`ShimMenuView`, `SettingsView`, tabs and wizards)
- **ServerKit/** — HTTP server, catalog writers, ASAR patching, upstream handlers
- **Manager singletons** — `ShimManager`, `ModelsJsonManager`, `ZenflowRouterManager`, `RouterStatsManager`, etc.

Key patterns used throughout the codebase:

- **`@Observable`** (Observation framework) for SwiftUI state management
- **Singleton `.shared`** instances on manager classes
- **`@MainActor`** on UI-facing managers
- **`ProcessRunner`** (actor) for async shell command execution
- **Atomic file writes** with `.bak` backups and `0o600` permissions
- **macOS Keychain** for credential storage — **never** store API keys in plaintext outside `models.json`

## Code Style

- **Swift 5.10** — no Swift 6 features yet
- **Zero external dependencies** — use only Apple frameworks (Foundation, Security, ServiceManagement, os.log)
- **No force unwraps** in production code (acceptable only for static regex compilation)
- **No comments** unless the logic is genuinely non-obvious
- **Atomic writes** for all file I/O — use `.atomic` write option with backup
- **Error handling** — use typed errors with `LocalizedError`, surface via `lastError` on managers
- **Thread safety** — use `DispatchQueue` for sync access to shared state, `actor` for isolated workers

## Submitting Changes

### Issues

- Search existing issues before opening a new one
- Include macOS version, Shimbar version, and steps to reproduce
- For bugs, attach relevant logs from `~/Library/Logs/shimbar_debug.log`

### Pull Requests

1. **Fork** the repository
2. Create a **feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. Make your changes
4. **Run the full test suite** and ensure all tests pass:
   ```bash
   make test
   ```
5. **Build cleanly** with no new warnings:
   ```bash
   make build
   ```
6. Push your branch and open a PR against `main`

### PR Guidelines

- **One logical change per PR** — avoid mixing features and refactors
- **Include tests** for new functionality
- **Update `README.md`** if you've added user-facing features or changed the project structure table
- **Keep the PR description clear** — explain what, why, and any trade-offs

## Development Tips

### XcodeGen

The `.xcodeproj` is generated from `project.yml`. **Never edit the `.xcodeproj` directly.** After changing `project.yml`:

```bash
make generate
```

### Testing

- Tests live in `ShimbarTests/` and mirror the source structure
- Use `@testable import Shimbar` to access internal types
- Mock network responses with `MockURLProtocol` (see existing test files for patterns)
- Use temp directories for file I/O tests — clean up in `tearDown`

### Debug Logging

`DebugLogger.log()` writes to `~/Library/Logs/shimbar_debug.log` in debug builds only. Use it for development diagnostics.

### Entitlements

Shimbar runs with App Sandbox **disabled** (required for process management). The hardened runtime is enabled. Do not add sandbox entitlements.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
