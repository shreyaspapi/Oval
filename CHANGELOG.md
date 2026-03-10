# Changelog

All notable changes to Oval will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.6.3] - 2026-03-10

### Added

- **Support section in Settings**: Buy Me a Coffee, GitHub Sponsors, and Star on GitHub buttons in Settings > General
- **Sponsors section in README**: Badge links and placeholder for listing GitHub sponsors
- **Blank issue template**: Users can now file custom issues without a template

## [1.6.2] - 2026-03-10

### Added

- **Automated release script**: `scripts/release.sh` handles the full release workflow locally (build, sign, notarize, DMG, appcast, GitHub release)

## [1.6.1] - 2026-03-10

### Fixed

- **Sparkle auto-update in sandbox**: Added `SUEnableInstallerLauncherService` and mach-lookup entitlements required by Sparkle 2 for sandboxed apps ([#11](https://github.com/shreyaspapi/Oval/issues/11))
- **Xcode 26 build compatibility**: Added RAG linker stubs (`rac_backend_rag_register`, `rac_rag_pipeline_create_standalone`) so the project builds with Xcode 26

## [1.6.0] - 2026-03-10

### Added

- **Customizable hotkeys**: Global keyboard shortcuts (Quick Chat, Toggle Window, Paste to Chat) can now be changed in Settings > General > Keyboard Shortcuts ([#7](https://github.com/shreyaspapi/Oval/issues/7))
- **Shortcut recorder**: Click any shortcut field to record a new key combination interactively; press Esc to cancel
- **Per-shortcut reset**: Each shortcut has a reset button to restore its factory default
- **Persistent preferences**: Custom hotkeys are saved to config.json and restored on launch
- **Dynamic tray labels**: Menu bar shortcut hints update to reflect configured bindings

### Fixed

- **Old shortcut still firing**: Removed hardcoded `.keyboardShortcut` on the Quick Chat menu item that caused Ctrl+Space to trigger even after reassignment

## [1.5.1] - 2026-03-09

### Fixed

- **Thinking content rendering**: Reasoning/thinking blocks now correctly decode HTML entities (`&#x27;`, `&gt;`, etc.) and strip extraneous blockquote markers (`>`), fixing garbled display of model reasoning output ([#5](https://github.com/shreyaspapi/Oval/issues/5))

## [1.5.0] - 2026-03-09

### Fixed

- **Content duplication bug**: Flat `chat:completion` content from the server is now treated as a full replacement instead of being appended, preventing exponential text duplication during web search streaming
- **Status spinners persisting after response**: `statusHistory` was missing from `ChatMessage.Equatable`, so SwiftUI never detected status changes. Search progress (e.g., "Generated search queries") now updates in real-time
- **Status items stuck as loading**: All incomplete status entries are marked done when streaming finishes (safety net for servers that don't send final `done: true`)
- **Socket.IO events dropped**: Relaxed `messageId` requirement in event routing so status events without a message ID are no longer silently discarded
- **`let` vs `var` build error**: Fixed immutable struct mutation in flat content replacement block
- **Race condition**: `SocketStreamContinuationRef` continuation is now set synchronously before any async work

### Added

- **Real-time search status**: Web search progress, query generation, and source retrieval now display progressively during streaming (not all at once after completion)
- **Clickable citation references**: `[1]`, `[2]` in assistant responses are now tappable links that open the corresponding source URL, with domain labels
- **Markdown link support**: `[text](url)` links in assistant messages are now rendered as clickable links
- **18+ Socket.IO event types**: Full handler coverage including `status`, `chat:completion`, `chat:message:delta`, `source`, `citation`, `chat:title`, `notification`, `execute:tool`, `chat:message:files`, `chat:tags`, `chat:message:error`, `chat:tasks:cancel`, `chat:message:follow_ups`, `replace`, `confirmation`, `input`, `execute`
- **Tool call ack dialogs**: Confirmation alerts, text input sheets, and execute error handling for server-driven tool interactions
- **Sources panel**: Collapsible citations/sources section below assistant messages
- **Code execution results**: Collapsible display of code interpreter output
- **Follow-up suggestions**: Tappable chip buttons for server-suggested follow-up questions
- **Token usage display**: Inline prompt/completion token counts on assistant messages
- **Error banners**: Red error banner on messages when server reports `chat:message:error`
- **Stream watchdog**: 90-second timeout that gracefully ends stale streams
- **Reconnection recovery**: Polls server for chat state after Socket.IO reconnect, adopts longer content
- **`sendChatCompleted` API**: Notifies server after streaming ends to trigger post-completion hooks (filters, follow-ups, etc.)
- **Warning toast style**: New `.warning` style for toast notifications

### Changed

- All three streaming paths (`sendMessage`, `editMessage`, `regenerateResponse`) now share consistent behavior: message ID routing, tool call accumulator reset on `.done`, metadata preservation, and chat completed notification
- `ChatCompletionRequest` now includes `id`, `parent_id`, `parent_message`, and `stream_options`
- `ChatBlob` persistence now includes `models`, `system`, `params`, `tags`
- `ChatBlobMessage` now persists `sources`, `codeExecutions`, `followUps`, `usage`, `messageError`, `done`, `modelIdx`

### CI/CD

- Added GitHub Actions workflow for automated release: build, sign with Developer ID, notarize, create DMG, and publish GitHub release on tag push

## [1.0.1] - 2026-03-03

### Added

- Download count, version, license, and platform badges in README
- Direct DMG download link in Installation section
- GitHub Sponsors and Buy Me a Coffee funding links
- Automated release workflow via GitHub Actions
- Release helper script (`scripts/release.sh`)
- CHANGELOG.md for tracking release history

## [1.0.0] - 2026-03-02

### Added

- Multi-server management with connection switching
- Streaming chat completions with model selection
- Conversation history sidebar with caching, lazy loading, and pagination
- Mini Chat (Spotlight-style) overlay window via `Ctrl+Space`
- File and image attachment uploads
- Speech-to-text input using Apple Speech framework
- Text-to-speech for AI responses
- SSO/OAuth, email/password, and API key authentication
- Menu bar tray icon for quick access
- Global hotkeys
- Launch at Login support
- Always on Top window mode
- Message editing and response regeneration
- Markdown rendering in chat messages
- Tool call and reasoning step display
- Demo mode for App Store review
