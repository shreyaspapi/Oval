# Changelog

All notable changes to Oval will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.9.3] - 2026-03-19

### Security

- **GPG-signed commit history**: All commits in the repository are now GPG-signed with a verified key for supply chain integrity

## [1.9.2] - 2026-03-19

### Fixed

- **Chat load delay (1-6s) on sidebar click**: Root cause was actor contention — prefetch tasks flooding the `OpenWebUIClient` actor queue, blocking user-initiated requests. Prefetch tasks are now cancelled when a conversation is selected, and stagger increased to 100ms to reduce saturation
- **Sparkle auto-update restored**: Re-linked Sparkle framework to the target so `canImport(Sparkle)` resolves to `true` and the real `SPUStandardUpdaterController` is active again. "Check for Updates" menu item works, appcast.xml feed is live

## [1.9.1] - 2026-03-19

### Fixed

- **Stream error "cannot decode raw data"**: Replaced `URLSession.AsyncBytes.lines` with a manual byte-level SSE line reader that tolerates non-UTF-8 bytes and split multi-byte sequences ([#45](https://github.com/shreyaspapi/Oval/issues/45))
- **Conversations not loading from sidebar**: Made `ChatHistory` decode messages individually so a single malformed message no longer prevents the entire conversation from loading; added resilient `try?` wrappers for nested decodable fields (`files`, `toolCalls`, `statusHistory`, `sources`, `usage`, `error`)
- **Blank chat area on conversation switch**: Empty cached results from prior decode failures are now treated as cache misses and re-fetched; added a self-healing retry when the view detects a blank state

### Improved

- **Chat switching speed**: Skip redundant `chatMessages` assignment when cached data is identical (avoids full SwiftUI view diff); added shared `NSCache`-backed caches for parsed message content (regex results) and decoded base64 images so switching back to previously viewed conversations is instant
- **Prefetch coverage**: Increased from 20 to 50 conversations; first 10 fire at medium priority for fast warm-up
- **Background refresh debounce**: 300ms delay before stale-cache refresh so the cached render completes smoothly without a second diff pass
- **Decode error diagnostics**: Detailed `DecodingError` logging (type mismatch, key not found, data corrupted) with full coding path for easier debugging

## [1.9.0] - 2026-03-18

### Added

- **Textual markdown rendering**: Migrated from hand-rolled markdown parser to the [Textual](https://github.com/gonzalezreal/textual) library for richer structured text rendering (headings, lists, tables, blockquotes, inline code, links)
- **Toggle server sidebar visibility**: New "Show Server Sidebar" toggle in Preferences > Behavior lets single-server users hide the 56px server rail to reclaim space ([#44](https://github.com/shreyaspapi/Oval/issues/44))

### Fixed

- **Code block copy button not clickable**: Code blocks are now rendered outside Textual's text-selection overlay so the "Copy code" button works reliably
- **Code block horizontal scroll**: Long code lines can now be scrolled horizontally instead of being clipped
- **Code fence parsing**: Closing fence detection now follows CommonMark spec — only bare backtick lines close a fence, preventing misparse when code blocks demonstrate nested fences

### Improved

- **Chat switching speed**: Prefetch increased from 5 to 20 conversations with staggered requests; 30-second cache TTL avoids redundant fetches; in-flight loads are cancelled when switching away
- **Pre-compiled regexes**: Tool call, reasoning block, and attribute extraction regexes are compiled once as static properties instead of per-call
- **Debug log cleanup**: Removed verbose statusHistory debug logging from AppState and raw JSON logging from OpenWebUIClient

## [1.8.5] - 2026-03-18

### Fixed

- **Mac App Store hotkey compliance**: Replaced raw keyboard event capture with Carbon event hotkeys so global shortcuts no longer depend on Accessibility access
- **Quick Chat default shortcut conflict**: Changed the default Quick Chat shortcut from `Ctrl+Space` to `Ctrl+Shift+Space` to avoid common macOS input-source conflicts

## [1.8.4] - 2026-03-16

### Fixed

- **Chat switching performance**: Cached expensive regex-based parsing (tool calls, reasoning blocks, markdown) in message views so it only runs when content changes instead of every render. Pre-computed last-assistant-message ID once per render instead of scanning per-message (O(n^2) to O(n)). Added Equatable to MarkdownTextView so SwiftUI skips unchanged re-renders. Skip redundant UI updates when background refresh returns identical messages.
- **CI: switch to macOS 26 runner**: Xcode 26.3's ibtoold asset catalog agent crashes on macOS 15 runners due to dyld symbol mismatches in CoreMedia/MediaToolbox frameworks. Switched both build and release workflows from `macos-15` to `macos-26` runners to match the deployment target.

## [1.8.1] - 2026-03-16

### Fixed

- **Chat switching performance**: Optimized chat switching speed by parallelizing API calls (tags and task IDs fetched concurrently), removing expensive recursive message list computation from render path, and eliminating unnecessary DOM destruction/recreation of message components when switching between conversations

## [1.8.0] - 2026-03-12

### Added

- **Temporary/ephemeral chat mode**: Start chats that are not saved to history, with option to save mid-conversation ([#16](https://github.com/shreyaspapi/Oval/issues/16), [#43](https://github.com/shreyaspapi/Oval/pull/43))
- **Conversation tags**: Tag-based filtering in the sidebar with search support ([#42](https://github.com/shreyaspapi/Oval/pull/42))
- **CI build workflow**: GitHub Actions workflow that builds and tests the project on every pull request to `main`, catching build failures early
- **Automated release workflow**: GitHub Actions workflow triggered on tag push (`v*`) that archives, signs, notarizes, creates a DMG, and publishes a GitHub Release with notes from CHANGELOG.md

### Removed

- **RunAnywhereAI SDK dependency**: Removed RunAnywhereAI SDK to simplify the build and reduce binary size

## [1.7.1] - 2026-03-12

### Fixed

- **Hotkeys stop working after window close**: Global hotkeys (Quick Chat, Toggle Window, Paste to Chat) now persist when the main window is closed ([#41](https://github.com/shreyaspapi/Oval/issues/41))
- **Menu bar icon disappears after window close**: Tray icon and menu now survive the main window being closed
- **Toggle Window hotkey with no window**: Pressing the Toggle Window hotkey after closing the window now re-activates the app and recreates the window

## [1.7.0] - 2026-03-11

### Added

- **Full localization**: All UI strings localized across 10 languages — English, German, French, Italian, Spanish, Dutch, Russian, Simplified Chinese, Traditional Chinese, and Korean
- **In-app language picker**: New Language section in Settings lets you switch the app language without changing macOS system language (requires restart to apply)
- **Localized strings files**: Complete `.lproj/Localizable.strings` for all 10 languages covering menus, toolbar, connect/login screen, sidebar, chat input, voice mode, live transcription, message bubbles, settings, and about views

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
