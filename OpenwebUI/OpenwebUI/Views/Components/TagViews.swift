import SwiftUI

// MARK: - Tag Chip

/// A small pill-shaped tag label, matching the Open WebUI tag style.
/// Optionally shows a remove button.
struct TagChip: View {
    let name: String
    var removable: Bool = false
    var onRemove: (() -> Void)?
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            Text(name)
                .font(AppFont.body(size: 10))
                .lineLimit(1)

            if removable {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(AppColors.accentBlue)
        .background(AppColors.accentBlue.opacity(0.12))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Sidebar Search Field with tag: Autocomplete

/// Observable ref object that bridges autocomplete state between SidebarSearchField
/// and the parent ChatSidebarView (which renders the dropdown in an overlay).
@MainActor
@Observable
final class SidebarSearchFieldRef {
    var showAutocomplete: Bool = false
    var suggestions: [TagSuggestion] = []
    /// Callback to select a tag from the autocomplete.
    var onSelectTag: ((TagSuggestion) -> Void)?
}

/// A search field that supports structured search prefixes like `tag:`.
/// When the user types `tag:`, a dropdown autocomplete appears listing all available tags.
/// Matches the Open WebUI web app behavior where tag filtering is done via search syntax.
struct SidebarSearchField: View {
    @Bindable var appState: AppState
    var ref: SidebarSearchFieldRef
    @State private var isAutocompleteVisible: Bool = false
    @State private var highlightedIndex: Int = 0
    @FocusState private var isFieldFocused: Bool

    /// Tags that match the current `tag:` prefix typed by the user.
    private var filteredTags: [TagSuggestion] {
        let text = appState.searchText
        // Find the last `tag:` token in the search text
        guard let range = text.range(of: "tag:", options: .backwards) else { return [] }
        let afterTag = String(text[range.upperBound...])
        // If there's a space after the tag value, the token is complete — no autocomplete
        if afterTag.contains(" ") && !afterTag.trimmingCharacters(in: .whitespaces).isEmpty {
            // Check if there's another incomplete tag: token after
            let remaining = afterTag
            guard remaining.range(of: "tag:", options: .backwards) != nil else { return [] }
        }

        let partial = afterTag.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()

        var suggestions: [TagSuggestion] = appState.allTags
            .filter { tag in
                let tagId = tag.replacingOccurrences(of: " ", with: "_").lowercased()
                if partial.isEmpty { return true }
                // Don't suggest if already fully typed
                if tagId == partial { return false }
                return tagId.hasPrefix(partial)
            }
            .map { TagSuggestion(id: $0, name: $0) }

        // Add "Untagged" option
        let untaggedId = "none"
        let untaggedName = String(localized: "tags.untagged")
        if partial.isEmpty || untaggedId.hasPrefix(partial) || untaggedName.lowercased().hasPrefix(partial) {
            suggestions.append(TagSuggestion(id: untaggedId, name: untaggedName))
        }

        return suggestions
    }

    /// Search prefixes shown when the field is focused and has certain text patterns.
    private var showPrefixHints: Bool {
        isFieldFocused && appState.searchText.isEmpty && !appState.allTags.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
                TextField(String(localized: "sidebar.searchPlaceholder"), text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(AppFont.body(size: 13))
                    .focused($isFieldFocused)
                    .onChange(of: appState.searchText) { _, newValue in
                        updateAutocomplete(for: newValue)
                    }
                    .onSubmit {
                        // If autocomplete is showing and user presses Enter, select highlighted
                        if ref.showAutocomplete && !filteredTags.isEmpty {
                            selectTag(filteredTags[min(highlightedIndex, filteredTags.count - 1)])
                        }
                    }
                if !appState.searchText.isEmpty {
                    Button {
                        appState.searchText = ""
                        ref.showAutocomplete = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppColors.searchFieldBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Search prefix hints when field is empty and focused
            if showPrefixHints {
                HStack(spacing: 6) {
                    searchPrefixHint("tag:", description: String(localized: "tags.searchForTags"))
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Autocomplete State Sync

    /// Update the ref's autocomplete state so the parent can render the dropdown.
    private func updateAutocomplete(for text: String) {
        let tags = filteredTags
        if text.contains("tag:") && !tags.isEmpty {
            highlightedIndex = 0
            ref.suggestions = tags
            ref.showAutocomplete = true
            // Capture appState for the callback (struct value semantics safe)
            let state = appState
            let refObj = ref
            ref.onSelectTag = { tag in
                // Replace the partial `tag:...` with the completed `tag:<id> `
                var searchText = state.searchText
                if let range = searchText.range(of: "tag:", options: .backwards) {
                    searchText = String(searchText[searchText.startIndex..<range.lowerBound])
                    searchText += "tag:\(tag.id) "
                }
                state.searchText = searchText
                refObj.showAutocomplete = false
                refObj.suggestions = []
            }
        } else {
            ref.showAutocomplete = false
            ref.suggestions = []
        }
    }

    // MARK: - Search Prefix Hint

    private func searchPrefixHint(_ prefix: String, description: String) -> some View {
        Button {
            appState.searchText = prefix
            isFieldFocused = true
        } label: {
            HStack(spacing: 4) {
                Text(prefix)
                    .font(AppFont.semibold(size: 10))
                    .foregroundStyle(AppColors.accentBlue)
                Text(description)
                    .font(AppFont.body(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.accentBlue.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tag Selection

    private func selectTag(_ tag: TagSuggestion) {
        // Replace the partial `tag:...` with the completed `tag:<id> `
        var text = appState.searchText
        if let range = text.range(of: "tag:", options: .backwards) {
            text = String(text[text.startIndex..<range.lowerBound])
            text += "tag:\(tag.id) "
        }
        appState.searchText = text
        isAutocompleteVisible = false
    }
}

/// A tag suggestion item for the autocomplete dropdown.
struct TagSuggestion: Identifiable {
    let id: String
    let name: String
}

// MARK: - Tag Autocomplete Dropdown

/// Standalone autocomplete dropdown rendered at the sidebar level so it floats
/// above the NSOutlineView-backed List. Uses native NSScrollView for proper macOS scrolling.
struct TagAutocompleteDropdown: View {
    let suggestions: [TagSuggestion]
    let onSelect: (TagSuggestion) -> Void

    var body: some View {
        NSScrollViewWrapper {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { tag in
                    Button {
                        onSelect(tag)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "tag")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                            Text(tag.name)
                                .font(AppFont.body(size: 12))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 240)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

// MARK: - NSScrollView Wrapper

/// Wraps SwiftUI content in a native NSScrollView for proper macOS scrolling.
/// Used for the tag autocomplete dropdown so it scrolls natively and isn't clipped.
struct NSScrollViewWrapper<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: documentView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])

        scrollView.documentView = documentView

        // Pin the document view's width to the scroll view's content width
        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let documentView = scrollView.documentView,
           let hostingView = documentView.subviews.first as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}

// MARK: - Tag Editor Sheet

/// A sheet for adding/removing tags on a conversation.
struct TagEditorSheet: View {
    @Bindable var appState: AppState
    let conversationId: String
    @State private var newTagText: String = ""
    @Environment(\.dismiss) private var dismiss

    /// Tags for this specific conversation.
    private var conversationTags: [String] {
        appState.conversations.first(where: { $0.id == conversationId })?.tagList ?? []
    }

    /// Suggestions: all known tags not already on this conversation.
    private var suggestions: [String] {
        appState.allTags.filter { !conversationTags.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (fixed, not scrollable)
            HStack {
                Text(String(localized: "tags.editorTitle"))
                    .font(AppFont.semibold(size: 14))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            // Add new tag (fixed, always visible)
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
                TextField(String(localized: "tags.addPlaceholder"), text: $newTagText)
                    .textFieldStyle(.plain)
                    .font(AppFont.body(size: 13))
                    .onSubmit {
                        addTag()
                    }
                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.textTertiary : AppColors.accentBlue)
                }
                .buttonStyle(.plain)
                .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.searchFieldBg.opacity(0.5))

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Current tags
                    if !conversationTags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "tags.currentTags"))
                                .font(AppFont.semibold(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
                                .textCase(.uppercase)

                            FlowLayout(spacing: 5) {
                                ForEach(conversationTags, id: \.self) { tag in
                                    TagChip(name: tag, removable: true, onRemove: {
                                        Task { await appState.removeTag(from: conversationId, tagName: tag) }
                                    })
                                }
                            }
                        }
                    } else {
                        Text("No tags yet. Add one above or pick a suggestion.")
                            .font(AppFont.body(size: 12))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }

                    // Suggestions
                    if !suggestions.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "tags.suggestions"))
                                .font(AppFont.semibold(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
                                .textCase(.uppercase)

                            FlowLayout(spacing: 5) {
                                ForEach(suggestions, id: \.self) { tag in
                                    TagChip(name: tag, onTap: {
                                        Task { await appState.addTag(to: conversationId, tagName: tag) }
                                    })
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 340, height: 360)
    }

    private func addTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tag.isEmpty else { return }
        Task {
            await appState.addTag(to: conversationId, tagName: tag)
            newTagText = ""
        }
    }
}

// NOTE: FlowLayout is defined in SearchStatusView.swift and reused here.
