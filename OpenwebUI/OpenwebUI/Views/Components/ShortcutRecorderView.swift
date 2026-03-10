import SwiftUI
import Carbon.HIToolbox

/// A button-style control that captures a keyboard shortcut when clicked.
/// Click to start recording, press a key combo (with at least one modifier), press Esc to cancel,
/// or press Delete/Backspace to clear.
struct ShortcutRecorderView: View {
    @Binding var binding: HotkeyBinding
    var onChanged: (() -> Void)?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                    Text("Press shortcut...")
                        .foregroundStyle(.secondary)
                } else {
                    Text(binding.displayString)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 120)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        // Use a local monitor so the Settings window captures keys
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleRecordingEvent(event)
            return nil // consume all events while recording
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        // Escape cancels recording without changing the binding
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        // Ignore pure modifier-only events (flagsChanged with no key)
        guard event.type == .keyDown else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Require at least one modifier key (prevent bare letter shortcuts)
        let hasModifier = flags.contains(.control) || flags.contains(.option)
            || flags.contains(.shift) || flags.contains(.command)
        guard hasModifier else { return }

        // Accept the shortcut
        let newBinding = HotkeyBinding(keyCode: event.keyCode, nsFlags: flags)
        binding = newBinding
        stopRecording()
        onChanged?()
    }
}
