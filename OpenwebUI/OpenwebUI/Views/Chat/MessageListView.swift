import SwiftUI

/// Scrollable message list with auto-scroll to bottom.
struct MessageListView: View {
    @Bindable var appState: AppState

    /// Pre-computed once per render instead of O(n) per message.
    private var lastAssistantMessageId: String? {
        appState.chatMessages.last(where: { $0.role == "assistant" })?.id
    }

    /// Pre-computed once per render instead of per-message.
    private var lastMessageId: String? {
        appState.chatMessages.last?.id
    }

    var body: some View {
        let lastAssistantId = lastAssistantMessageId
        let lastId = lastMessageId
        let isCurrentlyStreaming = appState.isStreaming

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
                    } else if appState.chatMessages.isEmpty && appState.selectedConversationID != nil {
                        // Conversation selected but no messages yet — trigger a load
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.regular)
                            Spacer()
                        }
                        .padding(.top, 40)
                        .onAppear {
                            // Re-fetch: the cache was likely stale/empty from a decode failure
                            Task { await appState.retryLoadChat() }
                        }
                    } else {
                        ForEach(appState.chatMessages) { message in
                            MessageBubbleView(
                                message: message,
                                isStreaming: isCurrentlyStreaming && message.id == lastId && message.role == "assistant",
                                isLastAssistant: message.role == "assistant" && message.id == lastAssistantId,
                                onEdit: { messageId, newContent, resubmit in
                                    Task { await appState.editMessage(messageId, newContent: newContent, resubmit: resubmit) }
                                },
                                onRegenerate: { messageId in
                                    Task { await appState.regenerateResponse(messageId: messageId) }
                                },
                                onSpeak: { content, messageId in
                                    appState.speakMessage(content)
                                    appState.ttsManager.speakingMessageId = messageId
                                },
                                onStopSpeaking: {
                                    appState.stopSpeaking()
                                },
                                onFollowUp: { text in
                                    appState.messageInput = text
                                    Task { await appState.sendMessage() }
                                },
                                isSpeakingThis: appState.ttsManager.speakingMessageId == message.id && appState.ttsManager.isSpeaking
                            )
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

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastId = appState.chatMessages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}
