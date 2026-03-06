import SwiftUI

/// Model picker for the toolbar — a rich popover with search, filter tabs,
/// model metadata (parameter size, loaded status, tags), profile images,
/// and a "Set as Default" action. Matches the Open WebUI web experience
/// in a native macOS style.
struct ModelSelectorView: View {
    @Bindable var appState: AppState

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                if let model = appState.selectedModel {
                    ModelAvatarView(
                        model: model,
                        serverURL: appState.serverURL,
                        apiKey: appState.activeServer?.apiKey ?? "",
                        size: 20
                    )
                }
                Text(appState.selectedModel?.displayName ?? "Select Model")
                    .font(.callout)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            ModelPickerContent(appState: appState, onSelect: {
                showPicker = false
            })
        }
    }
}

// MARK: - Model Picker Content (shared between toolbar and mini chat)

/// The inner content of the model picker popover — search, filter tabs, model list, actions.
/// Extracted as a standalone view so it can be reused in MiniChatView.
struct ModelPickerContent: View {
    @Bindable var appState: AppState
    var onSelect: () -> Void

    @State private var searchText = ""
    @State private var selectedFilter: ModelFilter = .all

    /// Available filter tabs based on what connection types exist in the model list.
    private var availableFilters: [ModelFilter] {
        var filters: [ModelFilter] = [.all]
        let categories = Set(appState.models.map(\.connectionCategory))
        if categories.contains(.local) { filters.append(.local) }
        if categories.contains(.external) { filters.append(.external) }
        return filters
    }

    /// Models after applying search and filter.
    private var filteredModels: [AIModel] {
        var result = appState.models

        // Filter by connection type
        if selectedFilter != .all {
            let category: ModelConnectionCategory = selectedFilter == .local ? .local : .external
            result = result.filter { $0.connectionCategory == category }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { model in
                model.displayName.lowercased().contains(query)
                || model.id.lowercased().contains(query)
                || model.tagNames.contains { $0.lowercased().contains(query) }
            }
        }

        return result
    }

    /// Unique tag names across all models for additional filter chips.
    private var allTags: [String] {
        let tagSet = Set(appState.models.flatMap { $0.tagNames })
        return tagSet.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // MARK: - Filter Tabs
            if availableFilters.count > 1 || !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        // Connection type filters
                        ForEach(availableFilters, id: \.self) { filter in
                            FilterChip(
                                label: filter.label,
                                icon: filter.icon,
                                isSelected: selectedFilter == filter
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedFilter = filter
                                }
                            }
                        }

                        // Tag filters
                        if !allTags.isEmpty {
                            Divider()
                                .frame(height: 16)
                                .padding(.horizontal, 2)

                            ForEach(allTags, id: \.self) { tag in
                                FilterChip(
                                    label: tag.count > 16 ? String(tag.prefix(14)) + "..." : tag,
                                    icon: "tag",
                                    isSelected: false
                                ) {
                                    searchText = tag
                                }
                                .help(tag)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }

                Divider()
            }

            // MARK: - Model List
            if filteredModels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(appState.models.isEmpty ? "No models available" : "No matching models")
                        .font(.callout)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredModels) { model in
                            ModelRow(
                                model: model,
                                appState: appState,
                                isSelected: model.id == appState.selectedModel?.id,
                                onSelect: {
                                    appState.selectedModel = model
                                    onSelect()
                                }
                            )
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 400)
            }

            // MARK: - Bottom Actions
            if appState.selectedModel != nil {
                Divider()

                HStack(spacing: 12) {
                    // Set as default
                    Button {
                        if let model = appState.selectedModel {
                            if appState.isDefaultModel(model) {
                                appState.setDefaultModel(nil)
                            } else {
                                appState.setDefaultModel(model)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: appState.selectedModel.map { appState.isDefaultModel($0) } ?? false
                                  ? "star.fill" : "star")
                                .font(.system(size: 11))
                            Text(appState.selectedModel.map { appState.isDefaultModel($0) } ?? false
                                 ? "Default Model" : "Set as Default")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(appState.selectedModel.map { appState.isDefaultModel($0) } ?? false
                                         ? AppColors.accentBlue : AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Pin toggle
                    if let model = appState.selectedModel {
                        Button {
                            appState.togglePinModel(model)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: appState.isModelPinned(model) ? "pin.slash" : "pin")
                                    .font(.system(size: 11))
                                Text(appState.isModelPinned(model) ? "Unpin" : "Pin to Sidebar")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 320)
    }
}

// MARK: - Filter Type

private enum ModelFilter: Hashable {
    case all
    case local
    case external

    var label: String {
        switch self {
        case .all:      return "All"
        case .local:    return "Local"
        case .external: return "External"
        }
    }

    var icon: String {
        switch self {
        case .all:      return "square.grid.2x2"
        case .local:    return "cpu"
        case .external: return "cloud"
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? AppColors.accentBlue : AppColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? AppColors.accentBlue.opacity(0.12) : AppColors.hoverBg.opacity(0.5))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: AIModel
    @Bindable var appState: AppState
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Avatar
                ModelAvatarView(
                    model: model,
                    serverURL: appState.serverURL,
                    apiKey: appState.activeServer?.apiKey ?? "",
                    size: 26
                )

                // Name + metadata
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)

                        // Loaded indicator (green dot for Ollama models in memory)
                        if model.isLoaded {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                                .help("Model loaded in memory")
                        }
                    }

                    // Subtitle: owned_by or connection type
                    if let owner = model.owned_by, owner != model.id {
                        Text(owner)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Parameter size badge
                if let paramSize = model.parameterSize {
                    Text(paramSize)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.hoverBg)
                        .clipShape(Capsule())
                        .help(sizeTooltip)
                }

                // Tags indicator
                if !model.tagNames.isEmpty {
                    Image(systemName: "tag")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                        .help(model.tagNames.joined(separator: ", "))
                }

                // Description indicator
                if model.descriptionText != nil {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                        .help(model.descriptionText ?? "")
                }

                // Default star
                if appState.isDefaultModel(model) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.accentBlue)
                        .help("Default model")
                }

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.accentBlue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? AppColors.selectedBg : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Right-click context menu
            Button {
                appState.togglePinModel(model)
            } label: {
                Label(appState.isModelPinned(model) ? "Unpin from Sidebar" : "Pin to Sidebar",
                      systemImage: appState.isModelPinned(model) ? "pin.slash" : "pin")
            }

            Button {
                if appState.isDefaultModel(model) {
                    appState.setDefaultModel(nil)
                } else {
                    appState.setDefaultModel(model)
                }
            } label: {
                Label(appState.isDefaultModel(model) ? "Remove as Default" : "Set as Default",
                      systemImage: appState.isDefaultModel(model) ? "star.slash" : "star")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.id, forType: .string)
                appState.toastManager.show("Model ID copied", style: .success)
            } label: {
                Label("Copy Model ID", systemImage: "doc.on.doc")
            }
        }
    }

    private var sizeTooltip: String {
        var parts: [String] = []
        if let paramSize = model.parameterSize {
            parts.append(paramSize)
        }
        if let quant = model.quantizationLevel {
            parts.append(quant)
        }
        if let bytes = model.fileSize {
            let gb = Double(bytes) / 1_073_741_824
            parts.append(String(format: "%.1f GB", gb))
        }
        return parts.joined(separator: " / ")
    }
}
