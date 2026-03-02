import SwiftUI

/// Model picker for the toolbar — uses a Button + popover to avoid
/// the system disclosure arrow that Menu adds automatically.
struct ModelSelectorView: View {
    @Bindable var appState: AppState

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            Text(appState.selectedModel?.displayName ?? "Select Model")
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if appState.models.isEmpty {
                    Text("No models available")
                        .font(.callout)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(12)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(appState.models) { model in
                                let isSelected = model.id == appState.selectedModel?.id
                                Button {
                                    appState.selectedModel = model
                                    showPicker = false
                                } label: {
                                    HStack {
                                        Text(model.displayName)
                                            .font(.callout)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundStyle(AppColors.accentBlue)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? AppColors.selectedBg : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 300)
                }
            }
            .frame(width: 260)
        }
    }
}
