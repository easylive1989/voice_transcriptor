import Cocoa
import SwiftUI
import Combine

@main
struct VoiceTranscriptorApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarManager: StatusBarManager?
    var inputManager: InputManager?
    var audioRecorder: AudioRecorder?
    var whisperManager: WhisperManager?
    var cancellables = Set<AnyCancellable>()

    // Default model path (can be overridden by settings)
    let defaultModelName = "ggml-base.bin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Components
        statusBarManager = StatusBarManager()
        inputManager = InputManager()
        audioRecorder = AudioRecorder()

        // Load Model
        setupWhisper()

        // Bind Input to Audio Recorder
        setupBindings()

        // Listen for Settings changes
        setupSettingsObserver()
    }

    private func setupSettingsObserver() {
        // Observe UserDefaults for key binding changes
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, let inputManager = self.inputManager else { return }

                let mic = UserDefaults.standard.integer(forKey: "micKeyCode")
                let sys = UserDefaults.standard.integer(forKey: "sysKeyCode")

                // Only update if valid and changed (simple assignment in InputManager handles it)
                if mic != 0 && sys != 0 {
                    inputManager.updateKeyBindings(mic: mic, sys: sys)
                }
            }
            .store(in: &cancellables)
    }

    private func setupWhisper() {
        // Check Settings for model path
        let storedPath = UserDefaults.standard.string(forKey: "modelPath") ?? ""
        var finalPath = storedPath

        if finalPath.isEmpty {
            // Check bundle or local directory
            let currentDir = FileManager.default.currentDirectoryPath
            let localPath = currentDir + "/" + defaultModelName
            if FileManager.default.fileExists(atPath: localPath) {
                finalPath = localPath
            } else {
                print("Model not found. Please download \(defaultModelName) and set path in Settings.")
            }
        }

        if !finalPath.isEmpty {
            whisperManager = WhisperManager(modelPath: finalPath)
            // Asynchronously warm up the model to avoid main thread block on launch
            Task(priority: .background) {
                whisperManager?.loadModel()
            }
        }
    }

    private func setupBindings() {
        guard let inputManager = inputManager, let audioRecorder = audioRecorder else { return }

        inputManager.keyActionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                self?.handleKeyAction(action)
            }
            .store(in: &cancellables)

        audioRecorder.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                let isRecording = (state != .idle) // simplified check
                // We don't have a distinct processing state in the recorder published prop yet unless we add it
                // Logic: Idle -> Recording -> Idle. Processing happens after recording stops but before Idle is fully ready?
                // Actually, the handleKeyAction will handle the processing phase manually.
                self?.statusBarManager?.updateStatus(recording: caseRecording(state), processing: false)
            }
            .store(in: &cancellables)
    }

    private func caseRecording(_ state: AudioRecorder.RecordingState) -> Bool {
        if case .recording = state { return true }
        return false
    }

    private func handleKeyAction(_ action: InputManager.KeyAction) {
        guard let audioRecorder = audioRecorder else { return }

        Task {
            switch action {
            case .startMic:
                do {
                    _ = try audioRecorder.startMicRecording()
                } catch {
                    print("Failed to start mic: \(error)")
                }
            case .startSystem:
                do {
                    _ = try await audioRecorder.startSystemRecording()
                } catch {
                    print("Failed to start system: \(error)")
                    if error.localizedDescription.contains("No display found") || (error as NSError).code == 2 {
                        await MainActor.run {
                            let alert = NSAlert()
                            alert.messageText = "Screen Recording Permission Required"
                            alert.informativeText = "Please enable Screen Recording permission for this app in System Settings to capture system audio."
                            alert.addButton(withTitle: "Open Settings")
                            alert.addButton(withTitle: "Cancel")
                            if alert.runModal() == .alertFirstButtonReturn {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            case .stopMic:
                if let url = audioRecorder.stopMicRecording() {
                    await processRecording(url: url)
                }

            case .stopSystem:
                if let url = await audioRecorder.stopSystemRecording() {
                    await processRecording(url: url)
                }
            }
        }
    }

    private func processRecording(url: URL) async {
        // UI: Processing
        statusBarManager?.updateStatus(recording: false, processing: true)

        do {
            // Transcribe
            if let whisper = whisperManager {
                let text = try await whisper.transcribe(audioFile: url)
                print("Transcription: \(text)")

                // Copy to clipboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)

                // Cleanup file
                try? FileManager.default.removeItem(at: url)
            } else {
                print("Whisper manager not initialized.")
            }
        } catch {
            print("Processing failed: \(error)")
        }

        // Restore UI
        statusBarManager?.updateStatus(recording: false, processing: false)
    }
}
