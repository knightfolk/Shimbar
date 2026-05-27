import ServiceManagement

// MARK: - LoginItemManager

/// Manages the app's "Launch at Login" registration using the
/// `ServiceManagement` framework.
///
/// Uses `SMAppService.mainApp` which is available on macOS 13+.
/// No helper app or launch agent is required.
struct LoginItemManager {

    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enables or disables launch-at-login registration.
    ///
    /// - Parameter enabled: `true` to register the app as a login
    ///   item; `false` to unregister it.
    /// - Throws: Any error from `SMAppService.register()` or
    ///   `SMAppService.unregister()`.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
