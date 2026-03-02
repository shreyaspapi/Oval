import SwiftUI

/// Loading screen — minimal dark background with centered spinner.
/// Toolbar is hidden on this screen for an immersive look.
struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                // Logo
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 72, height: 72)
                    Text("O")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

                ProgressView()
                    .controlSize(.regular)
                    .tint(.white.opacity(0.5))

                Spacer()
            }
        }
    }
}
