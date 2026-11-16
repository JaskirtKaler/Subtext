import AVFoundation
import Foundation
import Observation

struct RecordedAudio: Sendable {
    let filename: String
    let duration: TimeInterval
}

struct ActiveRecordingMetadata: Codable, Sendable {
    let filename: String
    let startedAt: Date
}

enum AudioRecordingError: LocalizedError {
    case microphoneDenied
    case alreadyRecording
    case noRecording
    case unableToStart
    case cannotResume
    case unreadableRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is off. Allow Subtext to use the microphone in Settings."
        case .alreadyRecording: "Save the current recording before starting another."
        case .noRecording: "There is no recording to save."
        case .unableToStart: "The microphone could not start. Check the audio input and try again."
        case .cannotResume: "This recording cannot resume after the audio system stopped. Save it, then start a new recording."
        case .unreadableRecording: "The audio file could not be read. It has been kept on this device for recovery."
        }
    }
}

/// Owns a single local recording. `isRecording` remains true while paused until `finish()` succeeds.
@MainActor
@Observable
final class AudioRecorder: NSObject {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = []
    private(set) var inputName = "iPhone microphone"
    private(set) var activeFilename: String?
    var errorMessage: String?

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var canResume = true
    @ObservationIgnored private var isStarting = false

    init(directory: URL) {
        self.directory = directory
        super.init()
        observeAudioSession()
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    @discardableResult
    func start() async throws -> String {
        guard !isRecording, !isStarting else { throw AudioRecordingError.alreadyRecording }
        isStarting = true
        defer { isStarting = false }
        errorMessage = nil

        do {
            let granted = await AVAudioApplication.requestRecordPermission()
            try Task.checkCancellation()
            guard granted else { throw AudioRecordingError.microphoneDenied }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let session = AVAudioSession.sharedInstance()
            try configureSession(session)
            guard session.isInputAvailable else { throw AudioRecordingError.unableToStart }

            let filename = "recording-\(UUID().uuidString.lowercased()).m4a"
            let url = directory.appendingPathComponent(filename)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 128_000
            ]
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            guard newRecorder.prepareToRecord(), newRecorder.record() else {
                throw AudioRecordingError.unableToStart
            }

            // A recovery hint, not a guarantee that an interrupted MPEG-4 file is playable.
            do {
                let metadata = ActiveRecordingMetadata(filename: filename, startedAt: Date())
                try JSONEncoder().encode(metadata).write(to: Self.markerURL(in: directory), options: .atomic)
            } catch {
                newRecorder.stop()
                // Keep the file even if writing its recovery metadata failed.
                throw error
            }

            recorder = newRecorder
            activeFilename = filename
            elapsed = 0
            levels = []
            canResume = true
            isPaused = false
            isRecording = true
            updateInputName()
            startTimer()
            return filename
        } catch {
            errorMessage = error.localizedDescription
            if !isRecording { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            throw error
        }
    }

    func pause() {
        guard isRecording, !isPaused, let recorder else { return }
        elapsed = max(elapsed, recorder.currentTime)
        recorder.pause()
        isPaused = true
        stopTimer()
    }

    func resume() throws {
        guard isRecording, isPaused, let recorder else { return }
        do {
            guard canResume else { throw AudioRecordingError.cannotResume }
            try configureSession(AVAudioSession.sharedInstance())
            guard AVAudioSession.sharedInstance().isInputAvailable, recorder.record() else {
                throw AudioRecordingError.unableToStart
            }
            isPaused = false
            errorMessage = nil
            updateInputName()
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func addBookmarkTime() -> TimeInterval {
        if !isPaused, let recorder { elapsed = max(elapsed, recorder.currentTime) }
        return elapsed
    }

    func finish() throws -> RecordedAudio {
        guard let recorder, let filename = activeFilename else { throw AudioRecordingError.noRecording }
        elapsed = max(elapsed, recorder.currentTime)
        stopTimer()
        recorder.stop()
        isPaused = true
        canResume = false

        do {
            let audio = try Self.readRecording(filename: filename, in: directory)
            self.recorder = nil
            activeFilename = nil
            elapsed = audio.duration
            isRecording = false
            isPaused = false
            errorMessage = nil
            // The readable file is finalized before removing its recovery hint.
            do { try Self.clearRecoveryMetadata(in: directory) }
            catch { errorMessage = "The recording is saved, but its recovery marker could not be cleared." }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return audio
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Closes a failed capture while keeping its file and recovery marker for later inspection.
    /// The returned duration is the best observed recording time, not a file validation result.
    func keepFileAndClose() -> RecordedAudio? {
        let filename = activeFilename
        elapsed = max(elapsed, recorder?.currentTime ?? 0)
        stopTimer()
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        activeFilename = nil
        isRecording = false
        isPaused = false
        canResume = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let filename else { return nil }
        return RecordedAudio(filename: filename, duration: elapsed.isFinite ? max(0, elapsed) : 0)
    }

    /// Leaves metadata in place until the caller has added the recovered file to its library.
    static func recoverableRecording(in directory: URL) throws -> RecordedAudio? {
        guard let metadata = try recoveryMetadata(in: directory) else { return nil }
        return try readRecording(filename: metadata.filename, in: directory)
    }

    static func recoveryMetadata(in directory: URL) throws -> ActiveRecordingMetadata? {
        let url = markerURL(in: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ActiveRecordingMetadata.self, from: Data(contentsOf: url))
    }

    static func clearRecoveryMetadata(in directory: URL) throws {
        let url = markerURL(in: directory)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private static func markerURL(in directory: URL) -> URL {
        directory.appendingPathComponent("ActiveRecording.json")
    }

    private static func readRecording(filename: String, in directory: URL) throws -> RecordedAudio {
        // Recovery metadata must only refer to a file directly inside the recordings directory.
        guard !filename.isEmpty, URL(fileURLWithPath: filename).lastPathComponent == filename else {
            throw AudioRecordingError.unreadableRecording
        }
        let url = directory.appendingPathComponent(filename)
        guard let audio = try? AVAudioPlayer(contentsOf: url), audio.duration.isFinite, audio.duration > 0 else {
            throw AudioRecordingError.unreadableRecording
        }
        return RecordedAudio(filename: filename, duration: audio.duration)
    }

    private func configureSession(_ session: AVAudioSession) throws {
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sampleMeters() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func sampleMeters() {
        guard isRecording, !isPaused, let recorder else { return }
        guard recorder.isRecording else {
            pauseForAudioChange("Recording stopped unexpectedly. Save this recording before starting another.", canResume: false)
            return
        }
        elapsed = max(elapsed, recorder.currentTime)
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)
        let amplitude = pow(10, max(-60, decibels) / 20)
        levels.append(min(1, max(0, amplitude)))
        if levels.count > 72 { levels.removeFirst(levels.count - 72) }
    }

    private func updateInputName() {
        inputName = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "Microphone unavailable"
    }

    private func pauseForAudioChange(_ message: String, canResume: Bool = true) {
        guard isRecording else { return }
        pause()
        // Once finalized or invalidated, this file must never be reopened for recording.
        self.canResume = self.canResume && canResume
        isPaused = true
        errorMessage = message
        updateInputName()
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.pauseForAudioChange("Recording paused by an audio interruption. Tap resume when you are ready.")
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            Task { @MainActor [weak self] in
                self?.updateInputName()
                if reason == .oldDeviceUnavailable || reason == .noSuitableRouteForCategory {
                    self?.pauseForAudioChange("The audio input changed. Recording is paused; check the microphone, then resume.")
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pauseForAudioChange("The audio system restarted. Save this recording, then start a new one.", canResume: false)
            }
        })
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder, self.isRecording else { return }
            self.pauseForAudioChange(flag ? "Recording stopped. Save this recording before starting another." : "Recording stopped because of an audio error. The file has been kept; try saving it.", canResume: false)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let message = error?.localizedDescription ?? "An audio encoding error occurred. The recording file has been kept."
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.pauseForAudioChange(message, canResume: false)
        }
    }
}
