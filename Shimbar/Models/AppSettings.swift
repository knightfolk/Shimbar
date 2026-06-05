import SwiftUI

// MARK: - AppSettings

/// Observable application settings backed by `UserDefaults`.
///
/// All keys are prefixed with `"shimbar."` to avoid collisions.
/// Access the shared singleton via ``AppSettings/shared``.
///
/// Usage:
/// ```swift
/// let settings = AppSettings.shared
/// settings.port = 9000
/// ```
@Observable
class AppSettings {

    /// Shared singleton instance.
    static let shared = AppSettings()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let shimPath = "shimbar.shimPath"
        static let port = "shimbar.port"
        static let pollingInterval = "shimbar.pollingInterval"
        static let disableChatGPTPassthrough = "shimbar.disableChatGPTPassthrough"
        static let lastActiveModel = "shimbar.lastActiveModel"
        static let collapseModelSection = "shimbar.collapseModelSection"
        static let settingsPath = "shimbar.settingsPath"
        static let useNativeServer = "shimbar.useNativeServer"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let shimPath = "codex-shim"
        static let port = 8765
        static let pollingInterval: Double = 5.0
        static let disableChatGPTPassthrough = false
        static let collapseModelSection = false
        static let useNativeServer = false
    }

    // MARK: - Storage

    private let defaults: UserDefaults

    // MARK: - Properties

    /// Path (or command name) used to locate the codex-shim binary.
    /// When set to `"codex-shim"` (the default), the app searches
    /// the user's `PATH` at launch.
    var shimPath: String {
        didSet { defaults.set(shimPath, forKey: Keys.shimPath) }
    }

    /// The port number the shim daemon listens on.
    var port: Int {
        didSet { defaults.set(port, forKey: Keys.port) }
    }

    /// How often (in seconds) to poll the shim daemon for status.
    var pollingInterval: Double {
        didSet { defaults.set(pollingInterval, forKey: Keys.pollingInterval) }
    }

    /// When `true`, the ChatGPT passthrough model is hidden from
    /// the model list.
    var disableChatGPTPassthrough: Bool {
        didSet { defaults.set(disableChatGPTPassthrough, forKey: Keys.disableChatGPTPassthrough) }
    }

    /// The slug of the last actively selected model, persisted across
    /// app launches.
    var lastActiveModel: String? {
        didSet { defaults.set(lastActiveModel, forKey: Keys.lastActiveModel) }
    }

    /// When `true`, the active model list section is rolled up (collapsed) in the popover.
    var collapseModelSection: Bool {
        didSet { defaults.set(collapseModelSection, forKey: Keys.collapseModelSection) }
    }

    /// Optional custom path to the codex-shim config file. When set, `--settings <path>`
    /// is passed to all shim CLI invocations. Defaults to `nil` (uses shim default).
    var settingsPath: String? {
        didSet { defaults.set(settingsPath, forKey: Keys.settingsPath) }
    }

    /// When `true`, the app uses the in-process native Swift server
    /// instead of spawning the codex-shim CLI subprocess.
    var useNativeServer: Bool {
        didSet { defaults.set(useNativeServer, forKey: Keys.useNativeServer) }
    }

    // MARK: - Initialization

    /// Creates an `AppSettings` instance backed by the given
    /// `UserDefaults` suite.
    ///
    /// - Parameter defaults: The `UserDefaults` instance to use.
    ///   Defaults to `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Register factory defaults so reads always return a value.
        defaults.register(defaults: [
            Keys.shimPath: Defaults.shimPath,
            Keys.port: Defaults.port,
            Keys.pollingInterval: Defaults.pollingInterval,
            Keys.disableChatGPTPassthrough: Defaults.disableChatGPTPassthrough,
            Keys.collapseModelSection: Defaults.collapseModelSection,
            Keys.useNativeServer: Defaults.useNativeServer,
        ])

        self.shimPath = defaults.string(forKey: Keys.shimPath) ?? Defaults.shimPath
        self.port = defaults.integer(forKey: Keys.port) == 0
            ? Defaults.port
            : defaults.integer(forKey: Keys.port)
        self.pollingInterval = defaults.double(forKey: Keys.pollingInterval) == 0
            ? Defaults.pollingInterval
            : defaults.double(forKey: Keys.pollingInterval)
        self.disableChatGPTPassthrough = defaults.bool(forKey: Keys.disableChatGPTPassthrough)
        self.lastActiveModel = defaults.string(forKey: Keys.lastActiveModel)
        self.collapseModelSection = defaults.bool(forKey: Keys.collapseModelSection)
        self.settingsPath = defaults.string(forKey: Keys.settingsPath)
        self.useNativeServer = defaults.bool(forKey: Keys.useNativeServer)
    }
}
