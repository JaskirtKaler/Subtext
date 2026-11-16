import Foundation
import Observation
import Speech

/// Selected for a single explicitly disclosed request. Permitting Apple's service
/// allows the framework to send audio to Apple; it does not force server use.
enum SpeechRecognitionMode: Equatable, Sendable {
    case onDevice
    case appleServiceAllowed

    var requiresOnDeviceRecognition: Bool { self == .onDevice }

    func validateAvailability(supportsOnDeviceRecognition: Bool, isAvailable: Bool) throws {
        if requiresOnDeviceRecognition && !supportsOnDeviceRecognition {
            throw SpeechTranscriptionError.onDeviceUnavailable
        }
        guard isAvailable else { throw SpeechTranscriptionError.unavailable }
    }
}

enum SpeechTranscriptionError: LocalizedError {
    case busy
    case permissionDenied
    case restricted
    case unsupportedLanguage
    case onDeviceUnavailable
    case unavailable
    case emptyResult
    case timedOut
    case missingAudio
    case appleServiceUnsupported

    var errorDescription: String? {
        switch self {
        case .busy: "A transcription is already in progress."
        case .permissionDenied: "Speech recognition access is off. Allow Subtext to use Speech Recognition in Settings."
        case .restricted: "Speech recognition is restricted on this device."
        case .unsupportedLanguage: "Speech recognition does not support the selected language. Choose another transcription language."
        case .onDeviceUnavailable:
            #if targetEnvironment(simulator)
            "This simulator does not have an on-device speech model for the selected language. Choose Apple service transcription or Cloud transcript, speakers & AI review, or test local transcription on an iPhone with the language downloaded. Audio has not been sent to a server."
            #else
            "An on-device speech model is unavailable for the selected language or this iPhone. Check the language and iPhone Dictation settings, or choose Apple service transcription or Cloud transcript, speakers & AI review. Audio has not been sent to a server."
            #endif
        case .unavailable: "Apple speech recognition is unavailable right now. Check the selected language, downloaded language support, and internet connection for service transcription, then retry."
        case .emptyResult: "No speech was recognized. Replay the recording, check the transcription language, and try a short sample with one clear voice. Overlapping voices or background media can prevent recognition. The original audio is unchanged."
        case .timedOut: "Apple speech recognition took too long to finish this part. Retry with a short, clear recording and check the selected language. The original audio is unchanged."
        case .missingAudio: "The audio file could not be found."
        case .appleServiceUnsupported: "This transcription provider does not support Apple service transcription. Choose on-device transcription or a provider that supports this request."
        }
    }
}

@MainActor
protocol SpeechTranscribing: AnyObject {
    var isTranscribing: Bool { get }
    var localeIdentifier: String { get set }
    var progress: Double { get }
    var warningMessage: String? { get }
    func transcribe(url: URL) async throws -> [TranscribedTurn]
    func transcribe(url: URL, mode: SpeechRecognitionMode) async throws -> [TranscribedTurn]
    func cancel()
}

extension SpeechTranscribing {
    var localeIdentifier: String {
        get { Locale.current.identifier }
        set { }
    }
    var progress: Double { 0 }
    var warningMessage: String? { nil }

    /// Existing local providers cannot silently opt into a server-capable request.
    func transcribe(url: URL, mode: SpeechRecognitionMode) async throws -> [TranscribedTurn] {
        guard mode == .onDevice else { throw SpeechTranscriptionError.appleServiceUnsupported }
        return try await transcribe(url: url)
    }
}

@MainActor
@Observable
final class SpeechTranscriber: SpeechTranscribing {
    private(set) var isTranscribing = false
    private(set) var progress: Double = 0
    private(set) var warningMessage: String?
    var localeIdentifier: String

    @ObservationIgnored private var operation: RecognitionOperation?
    @ObservationIgnored private var cancellationRequested = false
    @ObservationIgnored private var preparationCancellation: (@Sendable () -> Void)?

    init(localeIdentifier: String = Locale.current.identifier) {
        self.localeIdentifier = localeIdentifier
    }

    /// These locales support Apple's Speech API; on-device model availability is checked at use.
    static var supportedLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales().sorted {
            let left = Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
            let right = Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    func transcribe(url: URL) async throws -> [TranscribedTurn] {
        try await transcribe(url: url, mode: .onDevice)
    }

    func transcribe(url: URL, mode: SpeechRecognitionMode) async throws -> [TranscribedTurn] {
        guard !isTranscribing else { throw SpeechTranscriptionError.busy }
        try Task.checkCancellation()
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { throw SpeechTranscriptionError.missingAudio }
        isTranscribing = true
        cancellationRequested = false
        progress = 0
        warningMessage = nil
        let selectedLocale = localeIdentifier
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SubtextSpeech-\(UUID().uuidString)", isDirectory: true)
        defer {
            preparationCancellation = nil
            operation = nil
            isTranscribing = false
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        // Validate and decode locally before asking for Speech access. Digital silence needs no request.
        let audio = try await prepareInBackground { try SpeechAudioChunker.inspect(url: url) }
        let ranges = try SpeechTranscriptSupport.chunks(duration: audio.duration)
        var recognizer: SFSpeechRecognizer?
        var chunkResults: [[TranscribedTurn]] = []
        var unrecognizedRanges: [SpeechChunkRange] = []

        for range in ranges {
            try checkCancellation()
            let chunk = try await prepareInBackground {
                try SpeechAudioChunker.prepare(url: url, range: range, directory: temporaryDirectory)
            }
            defer { try? FileManager.default.removeItem(at: chunk.url) }
            guard chunk.containsAudibleSamples else {
                progress = min(1, range.endTime / audio.duration)
                continue
            }
            if recognizer == nil {
                let normalizedIdentifier = SpeechTranscriptSupport.recognitionLocaleIdentifier(selectedLocale)
                guard let supportedLocale = SFSpeechRecognizer.supportedLocales().first(where: {
                    SpeechTranscriptSupport.recognitionLocaleIdentifier($0.identifier) == normalizedIdentifier
                }) else { throw SpeechTranscriptionError.unsupportedLanguage }
                try await authorizeSpeech()
                try checkCancellation()
                guard let candidate = SFSpeechRecognizer(locale: supportedLocale),
                      SpeechTranscriptSupport.recognitionLocaleIdentifier(candidate.locale.identifier) == normalizedIdentifier else {
                    throw SpeechTranscriptionError.unsupportedLanguage
                }
                try mode.validateAvailability(supportsOnDeviceRecognition: candidate.supportsOnDeviceRecognition,
                                              isAvailable: candidate.isAvailable)
                candidate.queue = .main
                recognizer = candidate
            }
            guard let recognizer else { throw SpeechTranscriptionError.unavailable }
            do {
                let turns = try await recognize(chunk: chunk, recognizer: recognizer, selectedLocale: selectedLocale, audioDuration: audio.duration, mode: mode)
                if turns.isEmpty {
                    // A completed request can still produce no text. Treat that audible
                    // interval exactly like an explicit no-speech response so a later
                    // successful chunk cannot make an incomplete recording look complete.
                    unrecognizedRanges.append(range)
                } else {
                    chunkResults.append(turns)
                }
            } catch let failure as SpeechRecognitionFailure where failure.isNoSpeech {
                // A silent/no-speech part must not hide later speech in a long recording.
                unrecognizedRanges.append(range)
            }
            progress = min(1, range.endTime / audio.duration)
        }
        try checkCancellation()
        let turns = try SpeechTranscriptSupport.joinedTurns(chunkResults, audioDuration: audio.duration)
        guard !turns.isEmpty else {
            throw SpeechTranscriptionError.emptyResult
        }
        warningMessage = try SpeechTranscriptSupport.noSpeechWarning(for: unrecognizedRanges)
        progress = 1
        return turns
    }

    func cancel() {
        cancellationRequested = true
        preparationCancellation?()
        operation?.abort(CancellationError())
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        if cancellationRequested { throw CancellationError() }
    }

    private func prepareInBackground<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        try checkCancellation()
        let worker = Task.detached(priority: .userInitiated, operation: work)
        preparationCancellation = { worker.cancel() }
        defer { preparationCancellation = nil }
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            try checkCancellation()
            return value
        } onCancel: {
            worker.cancel()
        }
    }

    private func authorizeSpeech() async throws {
        var authorization = SFSpeechRecognizer.authorizationStatus()
        if authorization == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        try checkCancellation()
        switch authorization {
        case .authorized: return
        case .restricted: throw SpeechTranscriptionError.restricted
        default: throw SpeechTranscriptionError.permissionDenied
        }
    }

    static func recognitionRequest(url: URL, mode: SpeechRecognitionMode) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = mode.requiresOnDeviceRecognition
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        return request
    }

    private func recognize(chunk: PreparedSpeechChunk, recognizer: SFSpeechRecognizer, selectedLocale: String, audioDuration: TimeInterval, mode: SpeechRecognitionMode) async throws -> [TranscribedTurn] {
        try checkCancellation()
        try mode.validateAvailability(supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition,
                                      isAvailable: recognizer.isAvailable)
        let identifier = UUID()
        let request = Self.recognitionRequest(url: chunk.url, mode: mode)

        return try await withTaskCancellationHandler {
            try checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let operation = RecognitionOperation(identifier: identifier, recognizer: recognizer, chunk: chunk, localeIdentifier: selectedLocale, continuation: continuation) { [weak self] duration in
                    self?.progress = min(0.99, max(self?.progress ?? 0, (chunk.startTime + duration) / audioDuration))
                }
                self.operation = operation
                operation.timeout = Task { @MainActor [weak operation] in
                    do { try await Task.sleep(for: .seconds(120)) }
                    catch { return }
                    operation?.abort(SpeechTranscriptionError.timedOut)
                }
                operation.task = recognizer.recognitionTask(with: request, delegate: operation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.operation?.identifier == identifier else { return }
                self?.operation?.abort(CancellationError())
            }
        }
    }
}

/// Retained by the service because SFSpeechRecognitionTask does not retain its delegate.
/// The recognizer's delegate queue is explicitly OperationQueue.main.
@MainActor
private final class RecognitionOperation: NSObject, SFSpeechRecognitionTaskDelegate {
    let identifier: UUID
    var task: SFSpeechRecognitionTask?
    var timeout: Task<Void, Never>?
    private let recognizer: SFSpeechRecognizer
    private let chunk: PreparedSpeechChunk
    private let localeIdentifier: String
    private let progressHandler: (TimeInterval) -> Void
    private var recognizedText: RecognizedSpeechText?
    private var continuation: CheckedContinuation<[TranscribedTurn], Error>?

    init(identifier: UUID, recognizer: SFSpeechRecognizer, chunk: PreparedSpeechChunk, localeIdentifier: String, continuation: CheckedContinuation<[TranscribedTurn], Error>, progressHandler: @escaping (TimeInterval) -> Void) {
        self.identifier = identifier
        self.recognizer = recognizer
        self.chunk = chunk
        self.localeIdentifier = localeIdentifier
        self.continuation = continuation
        self.progressHandler = progressHandler
    }

    func abort(_ error: Error) {
        finish(.failure(error), cancelTask: true)
    }

    private func finish(_ result: Result<[TranscribedTurn], Error>, cancelTask: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        let task = self.task
        self.task = nil
        if cancelTask { task?.cancel() }
        continuation.resume(with: result)
    }

    nonisolated func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        // Copy framework objects into Sendable values on the callback queue before actor isolation.
        let transcription = recognitionResult.bestTranscription
        let text = RecognizedSpeechText(formattedString: transcription.formattedString, segments: transcription.segments.map {
            SpeechWordSegment(timestamp: $0.timestamp, duration: $0.duration, substringRange: $0.substringRange)
        })
        MainActor.assumeIsolated {
            guard continuation != nil else { return }
            recognizedText = text
        }
    }

    nonisolated func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        let recognitionError = (task.error as NSError?) ?? NSError(domain: "SubtextSpeechRecognition", code: 1)
        MainActor.assumeIsolated {
            guard continuation != nil else { return }
            guard successfully else {
                finish(.failure(SpeechRecognitionFailure(error: recognitionError, localeIdentifier: localeIdentifier, offset: chunk.startTime)))
                return
            }
            do {
                let turns: [TranscribedTurn]
                if let recognizedText {
                    turns = try SpeechTranscriptSupport.turns(formattedString: recognizedText.formattedString, segments: recognizedText.segments, offset: chunk.startTime, chunkDuration: chunk.duration)
                } else {
                    turns = []
                }
                // Wait for the complete task lifecycle; don't cancel a successful request before the next chunk.
                finish(.success(turns))
            } catch {
                finish(.failure(error))
            }
        }
    }

    nonisolated func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {
        let recognitionError = (task.error as NSError?) ?? NSError(domain: "kLSRErrorDomain", code: 301)
        MainActor.assumeIsolated {
            finish(.failure(SpeechRecognitionFailure(error: recognitionError, localeIdentifier: localeIdentifier, offset: chunk.startTime)))
        }
    }

    nonisolated func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didProcessAudioDuration duration: TimeInterval) {
        MainActor.assumeIsolated {
            guard continuation != nil, duration.isFinite, duration >= 0 else { return }
            progressHandler(min(chunk.duration, duration))
        }
    }
}

private struct RecognizedSpeechText: Sendable {
    let formattedString: String
    let segments: [SpeechWordSegment]
}
