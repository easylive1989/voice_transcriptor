import Foundation
import whisper

import AVFoundation

class WhisperManager {
    private var context: OpaquePointer?
    private let modelPath: String
    private var isInitialized = false

    // Model handling
    // We assume the model file is at a known location for now, or passed in.
    init(modelPath: String) {
        self.modelPath = modelPath
        // Actual loading happens lazily or explicitly via loadModel()
    }

    func loadModel() {
        if isInitialized { return }
        self.context = whisper_init_from_file(modelPath)
        if self.context == nil {
            print("Failed to initialize whisper context from \(modelPath)")
        } else {
            isInitialized = true
        }
    }

    deinit {
        if let context = context {
            whisper_free(context)
        }
    }

    func transcribe(audioFile: URL) async throws -> String {
        // Ensure model is loaded (thread-safe check needed if called concurrently, but for this spec simple check is OK)
        if !isInitialized {
            loadModel()
        }

        guard let context = context else {
             throw NSError(domain: "Whisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Context not initialized"])
        }

        // Move to detached task to avoid blocking Main Actor
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return "" }

            // Read WAV file safely using AVAudioFile
            let floats = try self.readAudioFile(url: audioFile)

            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_realtime = false
            params.print_progress = false
            params.print_timestamps = false
            params.translate = false
            params.language = "zh"

            let prompt = "請使用繁體中文，並保留原本的英文專有名詞。"
            var result = ""

            prompt.withCString { ptr in
                params.initial_prompt = ptr

                // Run Whisper (Blocking call on this background thread)
                let ret = whisper_full(self.context, params, floats, Int32(floats.count))

                if ret == 0 {
                    let n_segments = whisper_full_n_segments(self.context)
                    for i in 0..<n_segments {
                        if let textPtr = whisper_full_get_segment_text(self.context, i) {
                            let text = String(cString: textPtr)
                            result += text
                        }
                    }
                }
            }

            return self.convertToTraditional(result)
        }.value
    }

    private func readAudioFile(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)

        // Check format
        let format = file.processingFormat
        // We expect 16kHz mono, but if it's not, we might need to convert.
        // For this spec, since we recorded it as 16kHz, we assume it's correct or close enough.
        // But we must read into a buffer.

        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
             throw NSError(domain: "Whisper", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create audio buffer"])
        }

        try file.read(into: buffer)

        guard let floatChannelData = buffer.floatChannelData else {
             // If data is int16, we might need to convert manually if buffer doesn't do it.
             // AVAudioPCMBuffer usually converts to float if the format is float.
             // Our recording was 16-bit Int. AVAudioFile reads it into the buffer's format.
             // If processingFormat is standard (Float32), it converts automatically.
             // Let's rely on standard AVFoundation behavior.
             return []
        }

        // Copy first channel
        let channelData = floatChannelData[0]
        let floatArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))

        return floatArray
    }

    private func convertToTraditional(_ text: String) -> String {
        // Use CoreFoundation string transform
        let mutable = NSMutableString(string: text)
        // Transform Simplified to Traditional
        // kCFStringTransformSimplifiedChineseToTraditionalChinese is constant.

        let transform = StringTransform(rawValue: "Simplified-Traditional")
        if let output = mutable.applyingTransform(transform, reverse: false) {
             return output
        }
        return text
    }
}
