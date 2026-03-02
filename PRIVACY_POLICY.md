# Privacy Policy for Oval

**Last updated:** March 2, 2026

## Overview

Oval is a native macOS client for Open WebUI servers. It connects to self-hosted AI servers that you configure. Oval does not collect, store, or transmit any personal data to third parties.

## Data Collection

**Oval does not collect any data.** Specifically:

- No analytics or telemetry
- No crash reporting to external services
- No advertising identifiers
- No user tracking
- No data shared with third parties

## Data Storage

All data is stored locally on your Mac:

- **Server credentials** (URL, API key, or authentication token) are stored in the app's sandboxed container at `~/Library/Application Support/OpenWebUI/`
- **No data is stored in iCloud** or any cloud service controlled by the developer

## Network Communication

Oval communicates exclusively with the Open WebUI server(s) that you configure. All network traffic goes directly between your Mac and your server. No data is routed through any intermediary service.

The following network requests are made:
- Authentication with your Open WebUI server
- Fetching available AI models
- Loading and saving conversations
- Streaming chat completions
- Uploading files/images you attach to messages
- Generating conversation titles

## Permissions

Oval requests the following system permissions:

- **Microphone:** Used for on-device speech-to-text input. Audio is processed locally using Apple's Speech framework and is never sent to the developer.
- **Speech Recognition:** Used for on-device transcription of voice input.
- **Network (Client):** Required to connect to your Open WebUI server.
- **User Selected Files (Read):** Required to attach files and images to messages.

## Third-Party Services

Oval does not integrate with any third-party analytics, advertising, or tracking services. The only external service Oval communicates with is the Open WebUI server you configure, which is under your control.

## Children's Privacy

Oval does not knowingly collect any information from children under the age of 13.

## Changes to This Policy

We may update this privacy policy from time to time. Any changes will be reflected in the "Last updated" date above.

## Contact

If you have any questions about this privacy policy, please open an issue at:
https://github.com/shreyaspapi/Oval/issues

---

**Disclaimer:** Oval is an independent, third-party application and is not officially affiliated with the Open WebUI project.
