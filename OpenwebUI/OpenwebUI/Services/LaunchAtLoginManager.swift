import ServiceManagement

/// Manages Launch at Login using the modern ServiceManagement API (macOS 13+).
enum LaunchAtLoginManager {

    /// Enable or disable launch at login for the current app.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Non-critical — user can manage via System Settings > General > Login Items
            print("LaunchAtLogin: \(error.localizedDescription)")
        }
    }

    /// Check if the app is currently registered to launch at login.
    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
