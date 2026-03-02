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
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle Sidebar (Ctrl+Cmd+S)")
            }

            // MARK: — New Chat
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.newConversation()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .help("New Chat (Cmd+N)")
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
            Text("Add Server")
                .font(AppFont.semibold(size: 16))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Form {
                // Server name
                TextField("Server Name", text: $serverName, prompt: Text("My Server"))

                // Server URL
                TextField("Server URL", text: $url, prompt: Text("http://localhost:8080"))

                // Auth method picker
                Picker("Authentication", selection: $authMethod) {
                    Label("Email", systemImage: "envelope").tag(AuthMethod.emailPassword)
                    Label("API Key", systemImage: "key").tag(AuthMethod.apiKey)
                }
                .pickerStyle(.segmented)

                // Auth fields
                if authMethod == .emailPassword {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                    SecureField("Password", text: $password)
                } else {
                    SecureField("API Key (sk-...)", text: $apiKey)
                    Text("Settings > Account > API Keys")
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
                Button("Cancel", role: .cancel) {
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
                    Text(isConnecting ? "Connecting..." : "Add Server")
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
            error = "Please enter a server URL"
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
            guard !emailVal.isEmpty else { error = "Enter your email"; isConnecting = false; return }
            guard !password.isEmpty else { error = "Enter your password"; isConnecting = false; return }

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
            guard !key.isEmpty else { error = "Enter your API key"; isConnecting = false; return }
            token = key
            resolvedAuthMethod = .apiKey
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
