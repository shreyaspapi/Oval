import SwiftUI

/// Displays web search status events below the model name in assistant messages.
/// Matches the Open WebUI web frontend's StatusHistory + WebSearchResults rendering.
struct SearchStatusView: View {
    let statusHistory: [StatusEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(statusHistory) { status in
                StatusItemView(status: status)
            }
        }
    }
}

// MARK: - Status Item

private struct StatusItemView: View {
    let status: StatusEvent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status header (description + spinner/check)
            statusHeader

            // Search query chips
            if let queries = status.queries, !queries.isEmpty {
                queryChips(queries)
            }

            // Expandable URL results
            if let items = status.items, !items.isEmpty, status.done {
                urlResults(items)
            }
        }
    }

    // MARK: - Status Header

    @ViewBuilder
    private var statusHeader: some View {
        HStack(spacing: 6) {
            if !status.done {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            } else if status.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.red500)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.emerald600)
            }

            Text(resolvedDescription)
                .font(AppFont.caption(size: 12))
                .foregroundStyle(status.error ? AppColors.red500 : AppColors.textSecondary)
        }
    }

    /// Resolves i18n-style `{{count}}` and `{{searchQuery}}` placeholders in the description,
    /// mirroring the Svelte frontend's StatusItem logic.
    private var resolvedDescription: String {
        guard let desc = status.description else { return statusDefaultText }

        var result = desc

        // Replace {{count}} with actual items/urls count
        if result.contains("{{count}}") {
            let count = status.items?.count ?? status.urls?.count ?? 0
            result = result.replacingOccurrences(of: "{{count}}", with: "\(count)")
        }

        // Replace {{searchQuery}} with the query if present
        if result.contains("{{searchQuery}}"), let query = status.queries?.first {
            result = result.replacingOccurrences(of: "{{searchQuery}}", with: query)
        }

        return result
    }

    private var statusDefaultText: String {
        switch status.action {
        case "web_search":
            return status.done ? "Search complete" : "Searching"
        case "web_search_queries_generated":
            return "Generated search queries"
        case "knowledge_search":
            return status.done ? "Knowledge search complete" : "Searching knowledge"
        default:
            return status.description ?? status.action
        }
    }

    // MARK: - Query Chips

    private func queryChips(_ queries: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(queries.enumerated()), id: \.offset) { _, query in
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(query)
                        .font(AppFont.caption(size: 12))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.fileAttachmentBg)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppColors.borderColor.opacity(0.5), lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - URL Results

    private func urlResults(_ items: [SearchResultItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Searched \(items.count) site\(items.count == 1 ? "" : "s")")
                        .font(AppFont.caption(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.accentBlue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title ?? domainFrom(item.link))
                                    .font(AppFont.caption(size: 11).weight(.medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                Text(domainFrom(item.link))
                                    .font(AppFont.caption(size: 10))
                                    .foregroundStyle(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func domainFrom(_ urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }
}

// MARK: - Flow Layout

/// A simple flow layout that wraps items to new lines when they don't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(proposal)
            sizes.append(size)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return LayoutResult(
            positions: positions,
            sizes: sizes,
            size: CGSize(width: maxWidth, height: totalHeight)
        )
    }
}
