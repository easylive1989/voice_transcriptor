import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine

class AudioRecorder: NSObject, ObservableObject {
    enum RecordingState {
        case idle
        case recording(type: RecordingType)
        case processing
    }

    enum RecordingType {
        case microphone
        case system
    }

    @Published var state: RecordingState = .idle
    private var audioRecorder: AVAudioRecorder?
    private var stream: SCStream?
    private var audioFileStream: AudioFileStreamID?
    private var outputFileHandle: FileHandle?

    // Audio settings for Whisper (16kHz, Mono, WAV)
    private let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false
    ]

    // Store the URL of the current recording
    private(set) var currentRecordingURL: URL?

    func startMicRecording() throws -> URL {
        guard case .idle = state else { throw NSError(domain: "Recorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Already recording"]) }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("mic_recording_\(UUID().uuidString).wav")
        self.currentRecordingURL = fileURL

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record()
            state = .recording(type: .microphone)
            return fileURL
        } catch {
            print("Could not start microphone recording: \(error)")
            throw error
        }
    }

    func stopMicRecording() -> URL? {
        guard case .recording(let type) = state, type == .microphone else { return nil }

        audioRecorder?.stop()
        audioRecorder = nil
        state = .idle
        return currentRecordingURL
    }

    @MainActor
    func startSystemRecording() async throws -> URL {
        guard case .idle = state else { throw NSError(domain: "Recorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Already recording"]) }

        // Basic check for screen recording permission (macOS 14+)
        // Note: In a real app, we handle the alert triggering if permission is denied via SCShareableContent.current

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("sys_recording_\(UUID().uuidString).wav")
        self.currentRecordingURL = fileURL

        // Initialize file for writing (Raw PCM for SCStream, requires manual WAV header later or AVAssetWriter)
        // For simplicity in this spec, we will use AVAssetWriter to write the buffer to a file.

        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = availableContent.displays.first else {
             throw NSError(domain: "Recorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.capturesVideo = false
        config.sampleRate = 16000
        config.channelCount = 1

        stream = SCStream(filter: filter, configuration: config, delegate: nil)

        // Output setup
        // Note: Real implementation needs a robust SCStreamOutput delegate to write samples to file.
        // We will implement a simplified delegate.
        let output = StreamOutput(fileURL: fileURL)
        try await output.prepare()

        // Use a serial queue for audio sample processing to avoid race conditions in AVAssetWriter
        let audioQueue = DispatchQueue(label: "com.voicetranscriptor.audio", qos: .userInitiated)
        try stream?.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)

        try await stream?.startCapture()
        state = .recording(type: .system)

        // Store output reference to stop later
        self.streamOutput = output
        return fileURL
    }

    private var streamOutput: StreamOutput?

    func stopSystemRecording() async -> URL? {
        guard case .recording(let type) = state, type == .system else { return nil }

        try? await stream?.stopCapture()
        stream = nil
        if let output = streamOutput {
            await output.finish()
        }
        streamOutput = nil
        state = .idle
        return currentRecordingURL
    }
}

// Helper class to handle SCStream output writing
class StreamOutput: NSObject, SCStreamOutput {
    let fileURL: URL
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var started = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func prepare() throws {
        assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .wav)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        audioInput?.expectsMediaDataInRealTime = true

        if let writer = assetWriter, let input = audioInput {
            if writer.canAdd(input) {
                writer.add(input)
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let writer = assetWriter, let input = audioInput else { return }

        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            started = true
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func finish() async {
        audioInput?.markAsFinished()
        await withCheckedContinuation { continuation in
            assetWriter?.finishWriting {
                continuation.resume()
            }
        }
    }
}
