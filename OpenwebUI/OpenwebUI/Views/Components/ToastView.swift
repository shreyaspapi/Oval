import SwiftUI

/// A single toast notification model.
struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: Style

    enum Style {
        case success
        case error
        case info
        case warning

        var iconName: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .success: return AppColors.green400
            case .error: return AppColors.red500
            case .info: return AppColors.textSecondary
            case .warning: return .orange
            }
        }
    }
}

/// Observable toast manager — add toasts from anywhere, they auto-dismiss.
@MainActor
@Observable
final class ToastManager {
    var toasts: [ToastItem] = []

    func show(_ message: String, style: ToastItem.Style = .info) {
        let toast = ToastItem(message: message, style: style)
        withAnimation(.spring(duration: 0.3)) {
            toasts.append(toast)
        }

        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.spring(duration: 0.3)) {
                toasts.removeAll { $0.id == toast.id }
            }
        }
    }
}

/// Overlay view that displays toasts with Liquid Glass.
struct ToastOverlayView: View {
    let toasts: [ToastItem]

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer()
            ForEach(toasts) { toast in
                HStack(spacing: 8) {
                    Image(systemName: toast.style.iconName)
                        .foregroundStyle(toast.style.iconColor)
                        .font(.system(size: 14))

                    Text(toast.message)
                        .font(AppFont.body(size: 13))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(
                    .regular.tint(AppColors.toastGlass.opacity(0.5)),
                    in: .rect(cornerRadius: 10)
                )
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
