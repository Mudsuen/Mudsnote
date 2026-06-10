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

    func start() throws {
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
        recorder.record()
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
        return try RecordedAudio(data: Data(contentsOf: fileURL), temporaryURL: fileURL)
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
}

enum SpeechTranscriptionError: Error {
    case notAuthorized
    case recognizerUnavailable
}
