import SwiftUI

/// Connect/login screen matching the Open WebUI desktop installer aesthetic.
///
/// Design (from reference screenshot):
/// - Background: Dark base with a subtle blurred nature image at the top
/// - "Open WebUI" in large serif font, vertically centered-upper
/// - Subtitle text below the title
/// - "OI" badge in the top-right corner
/// - Sign-in form centered below
/// - Toolbar is hidden — traffic lights sit directly on the content
struct ConnectView: View {
    @Bindable var appState: AppState

    // Aurora animation
    @State private var auroraPhase: CGFloat = 0

    // Hidden testing view trigger
    @State private var logoTapCount = 0
    @State private var showTestingView = false

    var body: some View {
        ZStack {
            // MARK: - Background
            background

            // MARK: - OI Badge (top-right)
            VStack {
                HStack {
                    Spacer()
                    Text("O")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 12)
                        .padding(.trailing, 20)
                }
                Spacer()
            }

            // MARK: - Content
            VStack(spacing: 0) {
                Spacer()

                // Title section
                VStack(spacing: 12) {
                    Text("Oval")
                        .font(.system(size: 42, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .onTapGesture {
                            logoTapCount += 1
                            if logoTapCount >= 10 {
                                logoTapCount = 0
                                showTestingView = true
                            }
                        }

                    Text("Sign in to your server to get started.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()
                    .frame(height: 40)

                // MARK: - Sign-in Form
                VStack(spacing: 16) {
                    // Server URL
                    formField(
                        label: "Server URL",
                        icon: "link",
                        content: AnyView(
                            TextField("", text: $appState.urlInput, prompt: Text("http://localhost:8080").foregroundStyle(.white.opacity(0.25)))
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        )
                    )

                    // Auth method toggle
                    HStack(spacing: 0) {
                        authTab(label: "Email", icon: "envelope", method: .emailPassword)
                        authTab(label: "API Key", icon: "key", method: .apiKey)
                        authTab(label: "SSO", icon: "globe", method: .sso)
                    }
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Auth fields
                    Group {
                        switch appState.selectedAuthMethod {
                        case .emailPassword:
                            emailPasswordFields
                        case .apiKey:
                            apiKeyFields
                        case .sso:
                            ssoFields
                        }
                    }
                    .transition(.opacity.combined(with: .blurReplace))

                    // Error
                    if let error = appState.connectionError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.red400)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    // Sign in button
                    Button {
                        Task { await appState.connect() }
                    } label: {
                        HStack(spacing: 8) {
                            if appState.isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(appState.isConnecting ? "Connecting..." : "Sign in")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .disabled(appState.isConnecting)
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 40)

                Spacer()
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showTestingView) {
            ReviewTestingView(appState: appState)
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            // Base black
            Color.black

            // Subtle blurred gradient blobs at the top to mimic the nature photo effect
            VStack {
                ZStack {
                    RadialGradient(
                        colors: [
                            Color(hex: "#1a3a1a").opacity(0.5),
                            Color(hex: "#0a1a0a").opacity(0.3),
                            Color.clear
                        ],
                        center: UnitPoint(
                            x: 0.5 + 0.05 * sin(auroraPhase * .pi / 180),
                            y: 0.3
                        ),
                        startRadius: 20,
                        endRadius: 300
                    )

                    RadialGradient(
                        colors: [
                            Color(hex: "#2a1a0a").opacity(0.3),
                            Color(hex: "#1a1a0a").opacity(0.15),
                            Color.clear
                        ],
                        center: UnitPoint(
                            x: 0.7 + 0.04 * cos(auroraPhase * 0.8 * .pi / 180),
                            y: 0.2
                        ),
                        startRadius: 10,
                        endRadius: 250
                    )

                    RadialGradient(
                        colors: [
                            Color(hex: "#0a2a1a").opacity(0.25),
                            Color.clear
                        ],
                        center: UnitPoint(
                            x: 0.3 + 0.03 * sin(auroraPhase * 1.2 * .pi / 180),
                            y: 0.15
                        ),
                        startRadius: 10,
                        endRadius: 200
                    )
                }
                .frame(height: 280)
                .blur(radius: 40)

                Spacer()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                auroraPhase = 360
            }
        }
    }

    // MARK: - Form Field

    private func formField(label: String, icon: String, content: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(width: 16)

                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: - Auth Tab

    private func authTab(label: String, icon: String, method: AuthMethod) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.selectedAuthMethod = method
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(appState.selectedAuthMethod == method ? .white : .white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                appState.selectedAuthMethod == method
                    ? Color.white.opacity(0.08)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Email/Password Fields

    private var emailPasswordFields: some View {
        VStack(spacing: 12) {
            formField(
                label: "Email",
                icon: "envelope",
                content: AnyView(
                    TextField("", text: $appState.emailInput, prompt: Text("Enter your email").foregroundStyle(.white.opacity(0.25)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .textContentType(.emailAddress)
                )
            )

            formField(
                label: "Password",
                icon: "lock",
                content: AnyView(
                    SecureField("", text: $appState.passwordInput, prompt: Text("Enter your password").foregroundStyle(.white.opacity(0.25)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .onSubmit {
                            Task { await appState.connect() }
                        }
                )
            )
        }
    }

    // MARK: - SSO Fields

    @State private var showSSOWebView = false

    private var ssoFields: some View {
        VStack(spacing: 12) {
            Text("Sign in via your server's OAuth/SSO provider. A browser window will open to complete authentication.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)

            Button {
                let url = appState.urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !url.isEmpty else {
                    appState.connectionError = "Please enter a server URL"
                    return
                }
                showSSOWebView = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                    Text("Open SSO Login")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSSOWebView) {
                SSOWebView(
                    serverURL: appState.urlInput.trimmingCharacters(in: .whitespacesAndNewlines),
                    onTokenCaptured: { token in
                        showSSOWebView = false
                        Task {
                            await appState.connectWithSSO(token: token)
                        }
                    },
                    onCancel: {
                        showSSOWebView = false
                    }
                )
                .frame(width: 480, height: 600)
            }
        }
    }

    // MARK: - API Key Fields

    private var apiKeyFields: some View {
        VStack(spacing: 8) {
            formField(
                label: "API Key",
                icon: "key",
                content: AnyView(
                    SecureField("", text: $appState.apiKeyInput, prompt: Text("sk-...").foregroundStyle(.white.opacity(0.25)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .onSubmit {
                            Task { await appState.connect() }
                        }
                )
            )

            Text("Find your API key in Settings > Account > API Keys")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
    }
}
