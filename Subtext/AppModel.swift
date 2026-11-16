import Foundation
import Observation
import AVFoundation
import SubtextCore

enum AIConsentStatus: String, Codable, Sendable {
    case notDetermined
    case allowed
    case denied
}

@MainActor @Observable
final class AppModel {
    private(set) var interviews: [Interview] = []
    var errorMessage: String?
    var recordingPresented = false
    var selectedInterviewID: UUID?
    var startingRecording = false
    let recorder: any RecordingProviding
    let transcriber: any SpeechTranscribing
    let cloudReview: any CloudReviewProviding
    private(set) var processingInterviewID: UUID?
    private(set) var processingKind: ProcessingKind?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    var isProcessing: Bool { processingInterviewID != nil }
    func isProcessing(_ id: UUID) -> Bool { processingInterviewID == id }

    enum ProcessingKind { case localTranscription, appleServiceTranscription, cloudReview, transcriptReview }
    private(set) var automaticallyTranscribeNewRecordings = true
    private(set) var queuedTranscriptionIDs: [UUID] = []
    private(set) var isAutomaticallyProcessing = false
    private(set) var pendingAIReviewIDs: Set<UUID> = []
    private(set) var aiConsentStatus: AIConsentStatus = .notDetermined
    var shouldRequestAIConsent: Bool { aiConsentStatus == .notDetermined }
    @ObservationIgnored private var aiConsentRevision = 0
    @ObservationIgnored private var automaticAIReviewIDs: Set<UUID> = []
    @ObservationIgnored private var automaticQueueTask: Task<Void, Never>?
    private struct ProcessingPreferences: Codable {
        var automaticallyTranscribe: Bool
        var localeIdentifier: String
    }
    let directory: URL
    private let repository: InterviewRepository
    private(set) var canWrite = true
    private var recordingBookmarks: [Bookmark] = []
    private var recoveryChecked = false
    var pendingBookmarks: [Bookmark] { recordingBookmarks }

    init(directory suppliedDirectory: URL? = nil,
         cloudReview suppliedCloud: (any CloudReviewProviding)? = nil,
         transcriber suppliedTranscriber: (any SpeechTranscribing)? = nil,
         recorder suppliedRecorder: (any RecordingProviding)? = nil) {
        cloudReview = suppliedCloud ?? CloudReviewService()
        transcriber = suppliedTranscriber ?? SpeechTranscriber()
        let testMode = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = suppliedDirectory ?? base.appendingPathComponent(testMode ? "SubtextUITests" : "Subtext", isDirectory: true)
        repository = InterviewRepository(directory: directory)
        recorder = suppliedRecorder ?? AudioRecorder(directory: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if suppliedDirectory == nil && testMode && ProcessInfo.processInfo.arguments.contains("--reset") {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("interviews.json"))
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("AIConsent.json"))
            }
            if let data = try? Data(contentsOf: directory.appendingPathComponent("ProcessingPreferences.json")),
               let preferences = try? JSONDecoder().decode(ProcessingPreferences.self, from: data) {
                automaticallyTranscribeNewRecordings = preferences.automaticallyTranscribe
                transcriber.localeIdentifier = preferences.localeIdentifier
            }
            interviews = try repository.load()
            if interviews.contains(where: { $0.processingState == .transcribing }) {
                interviews = interviews.map { session in
                    var restored = session
                    if restored.processingState == .transcribing { restored.processingState = .failed; restored.processingError = "Processing was interrupted. The recording and saved review are intact; retry when ready." }
                    return restored
                }
                try repository.save(interviews)
            }
            if suppliedDirectory == nil && testMode && interviews.isEmpty { interviews = DemoData.interviews }
        } catch {
            canWrite = false
            errorMessage = "Your saved library could not be read. No files have been changed. \(error.localizedDescription)"
        }
        loadAIConsent()
    }

    /// Saves a deliberate choice independently of interview data. Enabling access
    /// never queues existing recordings or starts a provider request.
    @discardableResult
    func setAIConsent(_ status: AIConsentStatus) -> Bool {
        if status != .allowed { applyAIConsent(status) }
        let url = directory.appendingPathComponent("AIConsent.json")
        do {
            let data = try JSONEncoder().encode(status)
            try data.write(to: url, options: .atomic)
            applyAIConsent(status)
            return true
        } catch {
            if status != .allowed {
                // An existing grant can still be writable when its parent cannot
                // atomically replace it. A partial in-place denial fails closed
                // on the next read, so this fallback is safe only for revocation.
                do {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.truncate(atOffset: 0)
                    try handle.write(contentsOf: JSONEncoder().encode(status))
                    try handle.synchronize()
                    let saved = try JSONDecoder().decode(AIConsentStatus.self, from: Data(contentsOf: url))
                    if saved == status { return true }
                } catch { }
                do {
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteNoPermission) }
                    errorMessage = "AI access is off. The privacy choice could not be saved; the app will ask again next time."
                } catch {
                    errorMessage = "AI access is off for this session, but the privacy change could not be saved. An earlier permission may return after restarting. Retry in Settings & privacy when storage is available."
                }
            } else {
                errorMessage = "AI access was not enabled because the privacy choice could not be saved. Your recordings stay on this device."
            }
            return false
        }
    }

    private func loadAIConsent() {
        let url = directory.appendingPathComponent("AIConsent.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let stored = try JSONDecoder().decode(AIConsentStatus.self, from: Data(contentsOf: url))
            if stored == .allowed {
                // Do not trust a grant that the app cannot later revoke.
                let file = try FileManager.default.attributesOfItem(atPath: url.path)
                let parent = try FileManager.default.attributesOfItem(atPath: directory.path)
                guard FileManager.default.isWritableFile(atPath: url.path),
                      FileManager.default.isWritableFile(atPath: directory.path),
                      file[.immutable] as? Bool != true, parent[.immutable] as? Bool != true else {
                    throw CocoaError(.fileWriteNoPermission)
                }
            }
            aiConsentStatus = stored
        } catch {
            aiConsentStatus = .denied
            if errorMessage == nil {
                errorMessage = "The saved AI privacy choice could not be read. AI access is off; choose again in Settings & privacy. Your interview library is unchanged."
            }
        }
    }

    private func applyAIConsent(_ status: AIConsentStatus) {
        if status != aiConsentStatus { aiConsentRevision += 1 }
        aiConsentStatus = status
        guard status != .allowed else { return }
        automaticAIReviewIDs.removeAll()
        pendingAIReviewIDs.removeAll()
        if processingKind == .cloudReview || processingKind == .transcriptReview {
            processingTask?.cancel()
        }
    }

    func interview(_ id: UUID) -> Interview? { interviews.first { $0.id == id } }
    func audioURL(for interview: Interview) -> URL? {
        interview.audioFilename.map { repository.audioURL(filename: $0) }
    }

    @discardableResult
    func save(_ interview: Interview) -> Bool {
        guard canWrite else { errorMessage = "The library is unavailable. Your audio files are still stored on this iPhone."; return false }
        var next = interviews
        if let index = next.firstIndex(where: { $0.id == interview.id }) { next[index] = interview }
        else { next.insert(interview, at: 0) }
        do { try repository.save(next); interviews = next; return true }
        catch { errorMessage = "Changes could not be saved. The original audio has been kept. \(error.localizedDescription)"; return false }
    }

    func update(_ id: UUID, _ body: (inout Interview) -> Void) {
        guard var session = interview(id) else { return }
        body(&session)
        save(session)
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard processingInterviewID != id else {
            errorMessage = "This interview is being processed. Cancel processing or wait for it to finish before deleting it."
            return false
        }
        guard canWrite, let session = interview(id) else { return false }
        let next = interviews.filter { $0.id != id }
        do {
            try repository.save(next)
            interviews = next
            queuedTranscriptionIDs.removeAll { $0 == id }
            automaticAIReviewIDs.remove(id)
            pendingAIReviewIDs.remove(id)
            if let url = audioURL(for: session) {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: draftBookmarksURL(filename: url.lastPathComponent))
            }
            return true
        } catch { errorMessage = "The interview could not be deleted. \(error.localizedDescription)"; return false }
    }

    func loadSamples() {
        for sample in DemoData.interviews where !interviews.contains(where: { $0.id == sample.id }) { save(sample) }
    }

    func startRecording() async {
        guard !startingRecording, !recorder.isRecording, canWrite else { return }
        startingRecording = true
        defer { startingRecording = false }
        do {
            _ = try await recorder.start()
            recordingBookmarks = []
            persistDraftBookmarks()
            recordingPresented = true
        } catch { errorMessage = error.localizedDescription }
    }

    func addRecordingBookmark() {
        recordingBookmarks.append(Bookmark(time: recorder.addBookmarkTime(), note: "Bookmark \(recordingBookmarks.count + 1)"))
        persistDraftBookmarks()
    }
    func editRecordingBookmark(_ id: UUID, note: String) {
        if let index = recordingBookmarks.firstIndex(where: { $0.id == id }) { recordingBookmarks[index].note = note; persistDraftBookmarks() }
    }

    func finishRecording() {
        do {
            let audio = try recorder.finish()
            let session = Interview(title: Interview.defaultTitle(date: Date()), duration: audio.duration,
                                    audioFilename: audio.filename, bookmarks: recordingBookmarks)
            // A finalized audio file remains recoverable even if the library write fails.
            if save(session) {
                recordingPresented = false
                selectedInterviewID = session.id
                recordingBookmarks = []
                try? FileManager.default.removeItem(at: draftBookmarksURL(filename: audio.filename))
                if automaticallyTranscribeNewRecordings {
                    enqueueTranscription(session.id, allowAutomaticAI: aiConsentStatus == .allowed)
                }
            } else {
                recordingPresented = false
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func keepFailedRecording() {
        guard let audio = recorder.keepFileAndClose() else { recordingPresented = false; return }
        let session = Interview(title: "Recording needs review", duration: audio.duration,
                                audioFilename: audio.filename, bookmarks: recordingBookmarks,
                                notes: "Recording ended with an audio error. The original file has been kept. Playback may be unavailable.", processingState: .failed)
        if save(session) {
            try? AudioRecorder.clearRecoveryMetadata(in: directory)
            selectedInterviewID = session.id
        }
        recordingPresented = false
    }

    func recoverRecording() async {
        guard !recoveryChecked, canWrite else { return }
        recoveryChecked = true
        do {
            if let recovered = try AudioRecorder.recoverableRecording(in: directory) {
                if interviews.contains(where: { $0.audioFilename == recovered.filename }) {
                    try AudioRecorder.clearRecoveryMetadata(in: directory)
                } else if save(Interview(title: "Recovered interview", duration: recovered.duration,
                                         audioFilename: recovered.filename, bookmarks: recoveredBookmarks(filename: recovered.filename))) {
                    try AudioRecorder.clearRecoveryMetadata(in: directory)
                }
            }
        } catch {
            errorMessage = "An interrupted recording needs recovery. Its audio has been kept. \(error.localizedDescription)"
        }
        // A malformed marker must not hide unrelated playable orphan files.
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "aac", "aiff", "aif", "caf", "flac"]
            for url in urls where audioExtensions.contains(url.pathExtension.lowercased()) &&
                url.lastPathComponent != recorder.activeFilename &&
                !interviews.contains(where: { $0.audioFilename == url.lastPathComponent }) {
                let asset = AVURLAsset(url: url)
                if let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0,
                   url.lastPathComponent != recorder.activeFilename {
                    save(Interview(title: "Recovered interview", duration: duration.seconds,
                                   audioFilename: url.lastPathComponent, bookmarks: recoveredBookmarks(filename: url.lastPathComponent)))
                }
            }
        } catch {
            errorMessage = "Saved audio could not be scanned for recovery. No files were removed. \(error.localizedDescription)"
        }
    }

    private func draftBookmarksURL(filename: String) -> URL { directory.appendingPathComponent(URL(fileURLWithPath: filename).lastPathComponent + ".bookmarks.json") }
    private struct DraftBookmarks: Codable { let filename: String; let bookmarks: [Bookmark] }
    private func persistDraftBookmarks() {
        guard let filename = recorder.activeFilename else { return }
        do { try JSONEncoder().encode(DraftBookmarks(filename: filename, bookmarks: recordingBookmarks)).write(to: draftBookmarksURL(filename: filename), options: .atomic) }
        catch { recorder.errorMessage = "Audio capture continues, but bookmarks could not be saved. \(error.localizedDescription)" }
    }
    private func recoveredBookmarks(filename: String) -> [Bookmark] {
        guard let data = try? Data(contentsOf: draftBookmarksURL(filename: filename)),
              let draft = try? JSONDecoder().decode(DraftBookmarks.self, from: data), draft.filename == filename else { return [] }
        return draft.bookmarks
    }

    func importAudio(_ url: URL) async {
        guard canWrite else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let filename = UUID().uuidString + "." + url.pathExtension.lowercased()
        let destination = repository.audioURL(filename: filename)
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw ImportError.invalidAudio }
            try FileManager.default.copyItem(at: url, to: destination)
            let session = Interview(title: url.deletingPathExtension().lastPathComponent,
                                    duration: duration, audioFilename: filename)
            if save(session) { selectedInterviewID = session.id }
        } catch { errorMessage = "Audio could not be imported. \(error.localizedDescription)" }
    }

    func transcribe(_ id: UUID, offerAIReview: Bool = false, mode: SpeechRecognitionMode = .onDevice,
                    suppressFailureAlert: Bool = false) async {
        let kind: ProcessingKind = mode == .onDevice ? .localTranscription : .appleServiceTranscription
        guard let (original, url) = beginProcessing(id, kind: kind) else { return }
        let task = Task { @MainActor in
            do {
                let turns = try await transcriber.transcribe(url: url, mode: mode)
                try Task.checkCancellation()
                guard !turns.isEmpty else { throw SpeechTranscriptionError.emptyResult }
                guard var current = interview(id) else { return }
                current.segments = turns.map { TranscriptSegment(startTime: $0.startTime, endTime: $0.endTime, text: $0.text, needsReview: transcriber.warningMessage != nil) }
                current.speakers = []
                current.questions = LocalReview.suggestQuestions(segments: current.segments)
                current.aiSummary = ""
                current.aiInsights = []
                current.transcriptionWarning = transcriber.warningMessage
                current.processingError = nil
                current.processingState = .ready
                if !save(current) { markFailedInMemory(id) }
            } catch is CancellationError {
                restoreProcessingState(id, to: original.processingState)
            } catch {
                let provider = mode == .onDevice ? "On-device transcription" : "Apple transcription"
                recordProcessingFailure(id, message: "\(provider) could not finish. \(error.localizedDescription) Your recording and existing text are kept.", showAlert: !suppressFailureAlert)
            }
        }
        await finishProcessing(task, id: id)
        if offerAIReview, let current = interview(id), current.processingState == .ready,
           !current.segments.isEmpty, current.transcriptionWarning == nil,
           aiConsentStatus == .allowed, cloudReview.isAvailable { pendingAIReviewIDs.insert(id) }
    }

    func analyzeWithCloud(_ id: UUID) async {
        guard requireAIConsent() else { return }
        guard requireCloudConfiguration(for: id) else { return }
        let consentRevision = aiConsentRevision
        guard let (original, url) = beginProcessing(id, kind: .cloudReview) else { return }
        let task = Task { @MainActor in
            do {
                try requireCurrentAIConsent(revision: consentRevision)
                let result = try await cloudReview.analyzeAudio(url: url)
                try Task.checkCancellation()
                try requireCurrentAIConsent(revision: consentRevision)
                guard let current = interview(id) else { return }
                let updated = try ReviewApplication.applying(result, to: current)
                if !save(updated) { markFailedInMemory(id) }
            } catch is CancellationError {
                restoreProcessingState(id, to: original.processingState)
            } catch {
                recordProcessingFailure(id, message: "AI review could not finish. \(error.localizedDescription) Your recording and existing review are kept.")
            }
        }
        await finishProcessing(task, id: id)
    }

    func reviewTranscriptWithCloud(_ id: UUID) async {
        guard requireAIConsent() else { return }
        guard requireCloudConfiguration(for: id) else { return }
        let consentRevision = aiConsentRevision
        guard let source = interview(id), !source.segments.isEmpty else {
            errorMessage = "Create or add a transcript before requesting a text-only AI review."
            return
        }
        guard let (original, _) = beginProcessing(id, kind: .transcriptReview, requiresAudio: false) else { return }
        pendingAIReviewIDs.remove(id)
        let task = Task { @MainActor in
            do {
                try requireCurrentAIConsent(revision: consentRevision)
                let analysis = try await cloudReview.reviewTranscript(source)
                try Task.checkCancellation()
                try requireCurrentAIConsent(revision: consentRevision)
                guard let current = interview(id) else { return }
                guard Self.transcriptMatches(source, current) else { throw AppProcessingError.transcriptChanged }
                let updated = try ReviewApplication.applying(analysis, to: current)
                if !save(updated) { markFailedInMemory(id) }
            } catch is CancellationError {
                restoreProcessingState(id, to: original.processingState)
            } catch {
                recordProcessingFailure(id, message: "AI insights could not finish. \(error.localizedDescription) Your transcript, notes, and recording are kept.")
            }
        }
        await finishProcessing(task, id: id)
    }

    private static func transcriptMatches(_ sent: Interview, _ current: Interview) -> Bool {
        guard sent.segments.count == current.segments.count else { return false }
        return zip(sent.segments, current.segments).allSatisfy {
            $0.id == $1.id && $0.text == $1.text && $0.speakerID == $1.speakerID &&
            $0.startTime == $1.startTime && $0.endTime == $1.endTime
        }
    }

    func dismissAIReviewOffer(_ id: UUID) { pendingAIReviewIDs.remove(id) }
    func cancelQueuedTranscription(_ id: UUID) {
        queuedTranscriptionIDs.removeAll { $0 == id }
        automaticAIReviewIDs.remove(id)
    }
    private func enqueueTranscription(_ id: UUID, allowAutomaticAI: Bool) {
        guard !queuedTranscriptionIDs.contains(id) else { return }
        if allowAutomaticAI { automaticAIReviewIDs.insert(id) }
        queuedTranscriptionIDs.append(id)
        guard automaticQueueTask == nil else { return }
        isAutomaticallyProcessing = true
        automaticQueueTask = Task { @MainActor [weak self] in
            defer { self?.automaticQueueTask = nil; self?.isAutomaticallyProcessing = false }
            while !Task.isCancelled, let self, !self.queuedTranscriptionIDs.isEmpty {
                if self.isProcessing || self.cloudReview.isProcessing || self.cloudReview.isCheckingConnection || self.transcriber.isTranscribing {
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    continue
                }
                let next = self.queuedTranscriptionIDs.removeFirst()
                guard self.interview(next) != nil else { continue }
                let allowAutomaticAI = self.automaticAIReviewIDs.remove(next) != nil && self.aiConsentStatus == .allowed
                let consentRevision = self.aiConsentRevision
                await self.transcribe(next, suppressFailureAlert: allowAutomaticAI)
                guard allowAutomaticAI, self.aiConsentStatus == .allowed,
                      self.aiConsentRevision == consentRevision, !Task.isCancelled,
                      let current = self.interview(next),
                      current.processingState == .ready || current.processingState == .failed else { continue }
                // Only recordings finished while permission was enabled are
                // eligible. Apple remains first; cloud audio supplies speaker
                // grouping and insights or acts as transcription fallback.
                await self.analyzeWithCloud(next)
            }
        }
    }
    func setAutomaticallyTranscribe(_ enabled: Bool) {
        persistPreferences(automatic: enabled, locale: transcriber.localeIdentifier)
    }
    func setSpeechLocale(_ identifier: String) {
        persistPreferences(automatic: automaticallyTranscribeNewRecordings, locale: identifier)
    }
    private func persistPreferences(automatic: Bool, locale: String) {
        do {
            let preferences = ProcessingPreferences(automaticallyTranscribe: automatic, localeIdentifier: locale)
            try JSONEncoder().encode(preferences).write(to: directory.appendingPathComponent("ProcessingPreferences.json"), options: .atomic)
            automaticallyTranscribeNewRecordings = automatic
            transcriber.localeIdentifier = locale
        } catch { errorMessage = "Processing preferences could not be saved. \(error.localizedDescription)" }
    }

    func cancelProcessing(for id: UUID) {
        guard processingInterviewID == id else { return }
        processingTask?.cancel()
        if processingKind == .localTranscription || processingKind == .appleServiceTranscription { transcriber.cancel() }
    }

    private func requireCloudConfiguration(for id: UUID) -> Bool {
        guard cloudReview.isAvailable else {
            let message = (cloudReview.configurationStatus.error ?? .notConfigured).localizedDescription
            if isProcessing { errorMessage = message }
            else { recordProcessingFailure(id, message: message) }
            return false
        }
        return true
    }

    private func requireAIConsent() -> Bool {
        guard aiConsentStatus == .allowed else {
            errorMessage = "AI access is off. Enable AI access in Settings & privacy to share recordings and transcripts with Google for analysis. Apple transcription is still available."
            return false
        }
        return true
    }

    private func requireCurrentAIConsent(revision: Int) throws {
        try Task.checkCancellation()
        guard aiConsentStatus == .allowed, aiConsentRevision == revision else { throw CancellationError() }
    }

    private func beginProcessing(_ id: UUID, kind: ProcessingKind, requiresAudio: Bool = true) -> (Interview, URL)? {
        guard canWrite, !isProcessing, !cloudReview.isProcessing,
              !cloudReview.isCheckingConnection, !transcriber.isTranscribing else { return nil }
        guard let original = interview(id) else { return nil }
        let url = audioURL(for: original) ?? directory.appendingPathComponent("no-audio")
        if requiresAudio && (original.audioFilename == nil || !FileManager.default.fileExists(atPath: url.path)) {
            errorMessage = "The original audio could not be found. Saved text is still available."
            return nil
        }
        var pending = original
        pending.processingError = nil
        pending.processingState = .transcribing
        guard save(pending) else { return nil }
        errorMessage = nil
        processingInterviewID = id
        processingKind = kind
        return (original, url)
    }

    private func finishProcessing(_ task: Task<Void, Never>, id: UUID) async {
        processingTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
        if processingInterviewID == id {
            processingTask = nil
            processingInterviewID = nil
            processingKind = nil
        }
    }

    private func restoreProcessingState(_ id: UUID, to state: ProcessingState) {
        guard var current = interview(id) else { return }
        current.processingState = state == .transcribing ? .failed : state
        if !save(current) { markFailedInMemory(id) }
    }
    private func recordProcessingFailure(_ id: UUID, message: String, showAlert: Bool = true) {
        guard var current = interview(id) else { return }
        current.processingState = .failed
        current.processingError = message
        if !save(current) { markFailedInMemory(id) }
        if showAlert { errorMessage = message }
    }
    private func markFailedInMemory(_ id: UUID) {
        // A full disk can prevent even an error-state write; keep the prior review in memory.
        if let index = interviews.firstIndex(where: { $0.id == id }) {
            interviews[index].processingState = .failed
            interviews[index].processingError = "Processing could not be saved. Your original recording and previous review are kept. Check free space and retry."
        }
    }

    func exportText(_ session: Interview) -> String {
        var lines = [session.title, session.isDemo ? "Sample interview · fictional text, no audio attached" : "Original audio retained on iPhone", session.createdAt.formatted(date: .abbreviated, time: .shortened), "Duration: \(TimeFormatting.duration(session.duration))", "", "Transcript — check against original audio", ""]
        if let warning = session.transcriptionWarning { lines += ["Local transcript warning: " + warning, ""] }
        lines += session.segments.map { "[\(TimeFormatting.timestamp($0.startTime))] \(session.speakerName(for: $0.speakerID)): \($0.text)" }
        if !session.bookmarks.isEmpty {
            lines += ["", "Bookmarks"] + session.bookmarks.map { "[\(TimeFormatting.timestamp($0.time))] \($0.note)" }
        }
        if !session.notes.isEmpty { lines += ["", "Notes", session.notes] }
        if !session.aiSummary.isEmpty { lines += ["", "AI summary — check against original audio", session.aiSummary] }
        if !session.aiInsights.isEmpty {
            lines += ["", "AI perspective — suggestions for review"]
            for insight in session.aiInsights {
                lines += [insight.kind.displayName + ": " + insight.title, insight.detail]
                for id in insight.segmentIDs {
                    if let turn = session.segments.first(where: { $0.id == id }) {
                        lines.append("Evidence: [\(TimeFormatting.timestamp(turn.startTime))] \(session.speakerName(for: turn.speakerID)): \(turn.text)")
                    }
                }
            }
        }
        if !session.questions.isEmpty {
            lines += ["", "Q&A review — suggested pairings"]
            for question in session.questions {
                guard let turn = session.segments.first(where: { $0.id == question.questionSegmentID }) else { continue }
                lines += ["[\(TimeFormatting.timestamp(turn.startTime))] \(turn.text)", "Status: \(question.status.rawValue)"]
                if !question.followUp.isEmpty { lines.append("Follow-up: " + question.followUp) }
            }
        }
        return lines.joined(separator: "\n")
    }
}

private enum ImportError: LocalizedError {
    case invalidAudio
    var errorDescription: String? { "Choose a playable audio file with a nonzero duration." }
}

@MainActor
protocol RecordingProviding: AnyObject {
    var isRecording: Bool { get }
    var isPaused: Bool { get }
    var elapsed: TimeInterval { get }
    var levels: [Float] { get }
    var inputName: String { get }
    var activeFilename: String? { get }
    var errorMessage: String? { get set }
    func start() async throws -> String
    func pause()
    func resume() throws
    func finish() throws -> RecordedAudio
    func keepFileAndClose() -> RecordedAudio?
    func addBookmarkTime() -> TimeInterval
}
extension AudioRecorder: RecordingProviding {}

private enum AppProcessingError: LocalizedError {
    case transcriptChanged
    var errorDescription: String? { "The transcript changed during AI review. Retry to analyze the current version." }
}
