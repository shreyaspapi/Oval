import SwiftUI

/// Status dot — green and pulsing when active, gray when inactive.
/// Uses Open WebUI palette: green-400 for active, gray-600 for inactive.
struct PulsingDot: View {
    var isActive: Bool = true

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(AppColors.green400.opacity(0.75))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 2.0 : 1.0)
                    .opacity(isPulsing ? 0 : 0.75)
                    .animation(
                        .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }

            Circle()
                .fill(isActive ? AppColors.green400 : AppColors.textTertiary)
                .frame(width: 8, height: 8)
        }
        .onAppear { isPulsing = true }
    }
}
