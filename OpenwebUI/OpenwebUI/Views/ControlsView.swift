import SwiftUI

/// macOS Settings window (Cmd+,) using TabView for HIG compliance.
/// Replaces the in-app custom settings screen with a proper native Settings scene.
struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            VoiceModelSettingsView()
                .tabItem {
                    Label("Voice", systemImage: "waveform")
                }

            AboutView(appState: appState)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 560)
    }
}

/// Legacy ControlsView — redirects to Settings window.
/// Kept for backward compatibility with AppState.goToSettings() references.
struct ControlsView: View {
    @Bindable var appState: AppState

    var body: some View {
        // This should no longer be shown — redirect to chat
        ChatView(appState: appState)
            .onAppear {
                appState.currentScreen = .chat
                // Open Settings window
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
    }
}
