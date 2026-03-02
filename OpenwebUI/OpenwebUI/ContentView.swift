import SwiftUI

/// Root view — routes between Loading, Connect, and Chat screens.
/// Settings is now a separate macOS Settings scene (Cmd+,).
struct ContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .loading:
                LoadingView()
                    .transition(.opacity)

            case .connect:
                ConnectView(appState: appState)
                    .transition(.opacity)

            case .chat:
                ChatView(appState: appState)
                    .transition(.opacity)

            case .controls:
                // Redirect to chat — settings is now a separate window via Cmd+,
                ChatView(appState: appState)
                    .transition(.opacity)
                    .onAppear { appState.currentScreen = .chat }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.currentScreen)
        .overlay {
            ToastOverlayView(toasts: appState.toastManager.toasts)
        }
        // Make the toolbar background transparent for an immersive look
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .task {
            await appState.onAppear()
        }
        .onDisappear {
            appState.onDisappear()
        }
        .onKeyPress(.escape) {
            // Minimize the main window on Esc (orderOut hides it completely
            // and causes the menu bar to disappear since no window is visible)
            if let window = NSApp.keyWindow, !(window is NSPanel) {
                window.miniaturize(nil)
                return .handled
            }
            return .ignored
        }
    }
}

#Preview {
    ContentView(appState: AppState())
}
