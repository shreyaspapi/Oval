import SwiftUI

/// Modal confirmation dialog with Liquid Glass and Open WebUI colors.
/// Prefer using `.confirmationDialog()` modifier in new code.
/// This view is kept for compatibility where `.confirmationDialog` doesn't fit.
struct ConfirmDialogView: View {
    let title: String
    let message: String
    var cancelLabel: String = "Cancel"
    var confirmLabel: String = "Confirm"
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            // Dialog card — Liquid Glass
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(AppFont.semibold(size: 15))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.bottom, 10)

                Text(message)
                    .font(AppFont.body(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Spacer()

                    Button(cancelLabel) {
                        onCancel()
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)

                    Button(confirmLabel, role: .destructive) {
                        onConfirm()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(AppColors.red500)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 16)
            }
            .padding(24)
            .frame(maxWidth: 380)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .shadow(radius: 16)
        }
    }
}
