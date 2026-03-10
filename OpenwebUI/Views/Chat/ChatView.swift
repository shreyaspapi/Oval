import SwiftUI

/// Main chat interface with Discord-style server rail + sidebar + detail.
/// Layout: ServerRail (56px) | Sidebar (260px) | Detail (flex)
/// Uses a flat HStack instead of NavigationSplitView to avoid system
/// vibrancy/material on the sidebar column that creates color mismatches.
struct ChatView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Server Rail (Discord-style, always visible)
            ServerRailView(appState: appState)

            // MARK: - Sidebar (conversations list)
            if appState.isSidebarVisible {
                ChatSidebarView(appState: appState)
                    .frame(width: 260)

                // Separator between sidebar and detail
                Rectangle()
                    .fill(AppColors.borderColor)
                    .frame(width: 1)
            }

            // MARK: - Detail (chat area)
            ChatAreaView(appState: appState)
        }
        .background(AppColors.sidebarBg)
        .toolbar {
            // MARK: Leading — Toggle Sidebar
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.isSidebarVisible.toggle()
                    }
                } label: {
                    Label(String(localized: "toolbar.toggleSidebar"), systemImage: "sidebar.left")
                }
                .help(String(localized: "toolbar.toggleSidebar.help"))
            }

            // MARK: — New Chat
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.newConversation()
                } label: {
                    Label(String(localized: "toolbar.newChat"), systemImage: "square.and.pencil")
                }
                .help(String(localized: "toolbar.newChat.help"))
            }

            // MARK: Principal — Model Selector
            ToolbarItem(placement: .principal) {
                ModelSelectorView(appState: appState)
            }
        }
        .sheet(isPresented: $appState.showAddServer) {
            AddServerSheet(appState: appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            if !appState.isSidebarVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isSidebarVisible = true
                }
            }
        }
    }
}

// MARK: - Add Server Sheet

/// Sheet presented when user taps "+" to add a server.
struct AddServerSheet: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var email = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var authMethod: AuthMethod = .emailPassword
    @State private var error: String?
    @State private var isConnecting = false
    @State private var serverName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(String(localized: "addServer.title"))
                .font(AppFont.semibold(size: 16))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Form {
                // Server name
                TextField(String(localized: "addServer.serverName"), text: $serverName, prompt: Text(String(localized: "addServer.serverNamePlaceholder")))

                // Server URL
                TextField(String(localized: "addServer.serverURL"), text: $url, prompt: Text("http://localhost:8080"))

                // Auth method picker
                Picker(String(localized: "addServer.authentication"), selection: $authMethod) {
                    Label(String(localized: "addServer.emailOption"), systemImage: "envelope").tag(AuthMethod.emailPassword)
                    Label(String(localized: "addServer.apiKeyOption"), systemImage: "key").tag(AuthMethod.apiKey)
                }
                .pickerStyle(.segmented)

                // Auth fields
                if authMethod == .emailPassword {
                    TextField(String(localized: "addServer.email"), text: $email)
                        .textContentType(.emailAddress)
                    SecureField(String(localized: "addServer.password"), text: $password)
                } else {
                    SecureField(String(localized: "addServer.apiKeyPlaceholder"), text: $apiKey)
                    Text(String(localized: "addServer.apiKeyHint"))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                // Error
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AppColors.red500)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.visible)

            // Buttons
            HStack {
                Button(String(localized: "addServer.cancel"), role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    Task { await addServer() }
                } label: {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isConnecting ? String(localized: "addServer.connecting") : String(localized: "addServer.addServer"))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isConnecting)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420, height: 460)
    }

    private func addServer() async {
        let serverURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverURL.isEmpty else {
            error = String(localized: "addServer.errorEnterURL")
            return
        }

        isConnecting = true
        error = nil

        let token: String
        let resolvedAuthMethod: AuthMethod
        var userEmail: String?

        switch authMethod {
        case .emailPassword:
            let emailVal = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !emailVal.isEmpty else { error = String(localized: "addServer.errorEnterEmail"); isConnecting = false; return }
            guard !password.isEmpty else { error = String(localized: "addServer.errorEnterPassword"); isConnecting = false; return }

            do {
                let resp = try await OpenWebUIClient.signIn(baseURL: serverURL, email: emailVal, password: password)
                token = resp.token
                resolvedAuthMethod = .emailPassword
                userEmail = emailVal
            } catch {
                self.error = error.localizedDescription
                isConnecting = false
                return
            }

        case .apiKey:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { error = String(localized: "addServer.errorEnterAPIKey"); isConnecting = false; return }
            token = key
            resolvedAuthMethod = .apiKey

        case .sso:
            error = String(localized: "addServer.ssoNote")
            isConnecting = false
            return
        }

        let name = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = ServerConfig(
            name: name.isEmpty ? serverURL : name,
            url: serverURL,
            apiKey: token,
            authMethod: resolvedAuthMethod,
            email: userEmail
        )

        await appState.addServer(server)
        isConnecting = false
        dismiss()
    }
}
