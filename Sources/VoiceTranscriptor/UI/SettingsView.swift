import SwiftUI

struct SettingsView: View {
    @AppStorage("micKeyCode") private var micKeyCode: Int = 122 // Default F1
    @AppStorage("sysKeyCode") private var sysKeyCode: Int = 120 // Default F2
    @AppStorage("modelPath") private var modelPath: String = ""

    var body: some View {
        Form {
            Section(header: Text("Key Bindings")) {
                KeyRecorder(title: "Mic Record Key", keyCode: $micKeyCode)
                KeyRecorder(title: "System Record Key", keyCode: $sysKeyCode)
            }

            Section(header: Text("Model Management")) {
                if !modelPath.isEmpty {
                    Text("Current Model: \(modelPath)")
                } else {
                    Text("No model loaded.")
                        .foregroundColor(.red)
                }

                Button("Select Model File") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.data]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK {
                        modelPath = panel.url?.path ?? ""
                    }
                }

                Link("Download ggml-base.bin", destination: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/tree/main")!)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }
}

struct KeyRecorder: View {
    let title: String
    @Binding var keyCode: Int
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: {
                isRecording.toggle()
            }) {
                Text(isRecording ? "Press Key..." : "Code: \(keyCode)")
                    .frame(width: 80)
            }
            .background(KeyMonitor(isRecording: $isRecording, keyCode: $keyCode))
        }
    }
}

struct KeyMonitor: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            // Monitor local events when recording
            context.coordinator.startMonitoring()
        } else {
            context.coordinator.stopMonitoring()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator {
        var parent: KeyMonitor
        var monitor: Any?

        init(_ parent: KeyMonitor) {
            self.parent = parent
        }

        func startMonitoring() {
            if monitor != nil { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.parent.keyCode = Int(event.keyCode)
                self?.parent.isRecording = false
                return nil // consume event
            }
        }

        func stopMonitoring() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
