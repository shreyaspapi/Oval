import Combine
import SwiftUI

#if canImport(Sparkle)
import Sparkle

/// Wraps Sparkle's SPUUpdater for SwiftUI.
/// Provides a "Check for Updates" action and automatic background checks.
final class UpdateManager: ObservableObject {

    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manually trigger an update check (from menu item).
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

/// SwiftUI view that provides a "Check for Updates..." menu button.
struct CheckForUpdatesView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        Button("Check for Updates...") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)
    }
}

#else

// MARK: - App Store stub (Sparkle not available)

/// No-op stub when Sparkle is not linked (e.g. Mac App Store builds).
final class UpdateManager: ObservableObject {
    @Published var canCheckForUpdates = false
    func checkForUpdates() {}
}

struct CheckForUpdatesView: View {
    @ObservedObject var updateManager: UpdateManager
    var body: some View { EmptyView() }
}

#endif
