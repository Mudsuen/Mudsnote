import AVFoundation
import Foundation
import Speech

struct RecordedAudio: Sendable {
    var data: Data
    var temporaryURL: URL
}

@MainActor
final class AudioCaptureService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var startID: UUID?

    func start() async throws {
        let operationID = UUID()
        startID = operationID
        guard await Self.requestMicrophonePermission() else {
            if startID == operationID { startID = nil }
            throw AudioCaptureError.microphonePermissionDenied
        }
        try Task.checkCancellation()
        guard startID == operationID else { throw CancellationError() }

        let session = AVAudioSession.sharedInstance()
        var pendingRecorder: AVAudioRecorder?
        var pendingURL: URL?
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker]
            )
            try session.setActive(true)
            try Task.checkCancellation()
            guard startID == operationID else { throw CancellationError() }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mudsnote-recording-\(UUID().uuidString).m4a")
            pendingURL = url
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            pendingRecorder = recorder
            guard recorder.prepareToRecord(), recorder.record() else {
                try? FileManager.default.removeItem(at: url)
                throw AudioCaptureError.couldNotStart
            }
            try Task.checkCancellation()
            guard startID == operationID else { throw CancellationError() }
            self.recorder = recorder
            self.fileURL = url
            self.isRecording = true
            startID = nil
            pendingRecorder = nil
            pendingURL = nil
        } catch {
            pendingRecorder?.stop()
            if let pendingURL {
                try? FileManager.default.removeItem(at: pendingURL)
            }
            if startID == operationID {
                self.recorder?.stop()
                self.recorder = nil
                isRecording = false
                if let fileURL {
                    try? FileManager.default.removeItem(at: fileURL)
                }
                fileURL = nil
                startID = nil
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            throw error
        }
    }

    func stop() async throws -> RecordedAudio? {
        startID = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let fileURL else { return nil }
        self.fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = values.fileSize,
                   fileSize > CaptureAttachmentPolicy.maximumAudioBytes {
                    throw CaptureAttachmentError.tooLarge(
                        maximumBytes: CaptureAttachmentPolicy.maximumAudioBytes
                    )
                }
                return try Data(contentsOf: fileURL, options: .mappedIfSafe)
            }.value
            return RecordedAudio(data: data, temporaryURL: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }
    }

    func cancel() {
        startID = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func transcribe(url: URL, locale: Locale = .autoupdatingCurrent) async throws -> String {
        let authorizationStatus = await Self.requestSpeechAuthorization()
        guard authorizationStatus == .authorized else {
            throw SpeechTranscriptionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        let state = SpeechRecognitionState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        state.finish(.failure(error))
                        return
                    }

                    guard let result, result.isFinal else { return }
                    state.finish(.success(result.bestTranscription.formattedString))
                }
                state.install(task)

                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 45) {
                    state.finish(.failure(SpeechTranscriptionError.timedOut))
                }
            }
        } onCancel: {
            state.finish(.failure(CancellationError()))
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

enum SpeechTranscriptionError: LocalizedError, Equatable {
    case notAuthorized
    case recognizerUnavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            String(localized: "Speech recognition permission is required for transcription.")
        case .recognizerUnavailable:
            String(localized: "Speech recognition is temporarily unavailable.")
        case .timedOut:
            String(localized: "Transcription timed out. The audio is still attached.")
        }
    }
}

private final class SpeechRecognitionState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isFinished = false

    func install(_ continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        if isFinished {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func install(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        if isFinished {
            lock.unlock()
            task.cancel()
            return
        }
        recognitionTask = task
        lock.unlock()
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = continuation
        self.continuation = nil
        let recognitionTask = recognitionTask
        self.recognitionTask = nil
        lock.unlock()

        recognitionTask?.cancel()
        continuation?.resume(with: result)
    }
}
