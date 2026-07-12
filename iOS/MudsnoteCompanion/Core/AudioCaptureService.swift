import AVFoundation
import Foundation
import Speech

struct RecordedAudio {
    var data: Data
    var temporaryURL: URL
}

@MainActor
final class AudioCaptureService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() async throws {
        guard await Self.requestMicrophonePermission() else {
            throw AudioCaptureError.microphonePermissionDenied
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-recording-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.prepareToRecord(), recorder.record() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? FileManager.default.removeItem(at: url)
            throw AudioCaptureError.couldNotStart
        }
        self.recorder = recorder
        self.fileURL = url
        self.isRecording = true
    }

    func stop() throws -> RecordedAudio? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let fileURL else { return nil }
        self.fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return try RecordedAudio(data: Data(contentsOf: fileURL), temporaryURL: fileURL)
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func transcribe(url: URL, locale: Locale = Locale(identifier: "zh_CN")) async throws -> String {
        let authorizationStatus = await Self.requestSpeechAuthorization()
        guard authorizationStatus == .authorized else {
            throw SpeechTranscriptionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            final class ResumeBox {
                var didResume = false
            }
            let box = ResumeBox()

            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard !box.didResume else { return }
                    box.didResume = true
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else { return }
                guard !box.didResume else { return }
                box.didResume = true
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum AudioCaptureError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            String(localized: "Microphone access is required to record audio.")
        case .couldNotStart:
            String(localized: "Audio recording could not start. Try again.")
        }
    }
}

enum SpeechTranscriptionError: Error {
    case notAuthorized
    case recognizerUnavailable
}
