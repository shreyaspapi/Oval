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

    /// Track the previous message count so we can distinguish a chat switch
    /// (count goes from N → 0 → M) from a new message arriving (count N → N+1).
    @State private var previousMessageCount: Int = 0

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
            .onChange(of: appState.chatMessages.count) { oldCount, newCount in
                // When switching chats the count jumps (e.g. 50 → 0 → 30).
                // Only animate when a new message is appended to the SAME chat
                // (count increases by a small amount). For chat switches, snap
                // instantly to avoid a slow animated scroll through the new list.
                let isChatSwitch = newCount == 0 || (previousMessageCount == 0 && newCount > 1)
                previousMessageCount = newCount
                if isChatSwitch {
                    scrollToBottom(proxy: proxy, animated: false)
                } else {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: appState.streamingContent) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let lastId = appState.chatMessages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}
