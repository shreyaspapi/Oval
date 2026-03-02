import SwiftUI

/// Scrollable message list with auto-scroll to bottom.
struct MessageListView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if appState.isLoadingChat {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.regular)
                            Spacer()
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(appState.chatMessages) { message in
                            MessageBubbleView(message: message, isStreaming: isStreamingMessage(message))
                                .id(message.id)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .onChange(of: appState.chatMessages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: appState.streamingContent) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func isStreamingMessage(_ message: ChatMessage) -> Bool {
        appState.isStreaming && message.id == appState.chatMessages.last?.id && message.role == "assistant"
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastId = appState.chatMessages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}
