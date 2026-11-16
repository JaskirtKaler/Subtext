#if canImport(Subtext)
import XCTest
import Observation
import SubtextCore
@testable import Subtext

@MainActor
final class AppModelWorkflowTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SubtextWorkflow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testCloudActionsExplainMissingConfigurationWithoutClaimingSDKMissing() async throws {
        let cloud = WorkflowCloud()
        cloud.configurationStatus = .configurationMissing
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.analyzeWithCloud(original.id)
        XCTAssertEqual(model.errorMessage, CloudReviewError.firebaseConfigurationMissing.localizedDescription)
        model.errorMessage = nil
        await model.reviewTranscriptWithCloud(original.id)
        XCTAssertEqual(model.errorMessage, CloudReviewError.firebaseConfigurationMissing.localizedDescription)
        XCTAssertEqual(cloud.calls, 0)
        let failed = try XCTUnwrap(model.interview(original.id))
        XCTAssertEqual(failed.segments, original.segments)
        XCTAssertEqual(failed.speakers, original.speakers)
        XCTAssertEqual(failed.notes, original.notes)
        XCTAssertEqual(failed.processingState, .failed)
        XCTAssertEqual(failed.processingError, CloudReviewError.firebaseConfigurationMissing.localizedDescription)
        let relaunched = AppModel(directory: directory, cloudReview: cloud)
        XCTAssertEqual(relaunched.interview(original.id)?.processingError, failed.processingError)
        XCTAssertFalse(model.isProcessing)
    }

    func testExplicitAppleServiceRequestUsesOnlySelectedSpeechMode() async throws {
        let speech = WorkflowSpeech()
        let cloud = WorkflowCloud()
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech)
        let original = try savedInterview(in: model)
        await model.transcribe(original.id, mode: .appleServiceAllowed)
        XCTAssertEqual(speech.requestedModes, [.appleServiceAllowed])
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 0)
        XCTAssertEqual(model.interview(original.id)?.processingState, .ready)
        XCTAssertFalse(try XCTUnwrap(model.interview(original.id)).segments.isEmpty)
        XCTAssertTrue(try XCTUnwrap(model.interview(original.id)).speakers.isEmpty)
        XCTAssertEqual(model.interview(original.id)?.notes, original.notes)
    }

    func testDefaultTranscriptionNeverOptsIntoAppleService() async throws {
        let speech = WorkflowSpeech()
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud(), transcriber: speech)
        let original = try savedInterview(in: model)
        await model.transcribe(original.id)
        XCTAssertEqual(speech.requestedModes, [.onDevice])
    }

    func testAppleServiceFailurePreservesReviewAndPersistsDiagnosticWithoutCloudFallback() async throws {
        let speech = WorkflowSpeech(); speech.fails = true
        let cloud = WorkflowCloud()
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech)
        let original = try savedInterview(in: model)
        await model.transcribe(original.id, mode: .appleServiceAllowed)
        let failed = try XCTUnwrap(model.interview(original.id))
        XCTAssertEqual(failed.segments, original.segments)
        XCTAssertEqual(failed.speakers, original.speakers)
        XCTAssertEqual(failed.notes, original.notes)
        XCTAssertTrue(try XCTUnwrap(failed.processingError).contains("Apple transcription"))
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 0)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("test.wav")), originalAudio)
        let relaunched = AppModel(directory: directory, cloudReview: cloud, transcriber: speech)
        XCTAssertEqual(relaunched.interview(original.id)?.processingError, failed.processingError)
    }

    func testCloudReviewPreservesOriginalAudioNotesAndBookmarksAcrossRelaunch() async throws {
        let cloud = WorkflowCloud()
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.analyzeWithCloud(original.id)
        let reviewed = try XCTUnwrap(model.interview(original.id))
        XCTAssertEqual(reviewed.processingState, .ready)
        XCTAssertEqual(reviewed.notes, original.notes)
        XCTAssertEqual(reviewed.bookmarks, original.bookmarks)
        XCTAssertEqual(reviewed.aiSummary, "The guest described the next community meeting.")
        XCTAssertEqual(reviewed.segments.count, 2)
        XCTAssertEqual(reviewed.speakers.map(\.name), ["Speaker A", "Speaker B"])
        XCTAssertEqual(reviewed.questions.count, 1)
        XCTAssertTrue(reviewed.searchText.contains("community meeting"))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("test.wav")), originalAudio)
        let relaunched = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertEqual(relaunched.interview(original.id), reviewed)
        let export = relaunched.exportText(reviewed)
        XCTAssertTrue(export.contains("Personal editorial note"))
        XCTAssertTrue(export.contains("AI summary"))
        XCTAssertFalse(model.isProcessing)
    }

    func testSpeakerCorrectionReviewFlagsAndFollowUpsSurviveCloudWorkflowAndExport() async throws {
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud())
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.analyzeWithCloud(original.id)
        model.update(original.id) { session in
            session.speakers[1].name = "Alex Guest"
            session.segments[1].isQuote = true
            session.segments[1].needsReview = true
            session.questions[0].followUp = "Ask about the meeting location."
            session.questions[0].status = .partial
        }
        let relaunched = AppModel(directory: directory, cloudReview: WorkflowCloud())
        let reviewed = try XCTUnwrap(relaunched.interview(original.id))
        XCTAssertEqual(reviewed.speakerName(for: reviewed.segments[1].speakerID), "Alex Guest")
        XCTAssertTrue(reviewed.segments[1].isQuote)
        XCTAssertTrue(reviewed.segments[1].needsReview)
        XCTAssertTrue(reviewed.hasFollowUps)
        let exported = relaunched.exportText(reviewed)
        XCTAssertTrue(exported.contains("Alex Guest"))
        XCTAssertTrue(exported.contains("Ask about the meeting location."))
        XCTAssertTrue(exported.contains("Status: partial"))
    }

    func testCloudFailureRetainsExistingReviewAndOriginalFile() async throws {
        let cloud = WorkflowCloud(); cloud.failure = .appCheckRequired
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.analyzeWithCloud(original.id)
        let after = try XCTUnwrap(model.interview(original.id))
        XCTAssertEqual(after.segments, original.segments)
        XCTAssertEqual(after.speakers, original.speakers)
        XCTAssertEqual(after.notes, original.notes)
        XCTAssertEqual(after.aiSummary, original.aiSummary)
        XCTAssertEqual(after.bookmarks, original.bookmarks)
        XCTAssertEqual(after.processingState, .failed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("test.wav")), originalAudio)
        XCTAssertFalse(model.isProcessing)
    }

    func testEmptyCloudResponseCannotErasePriorTranscript() async throws {
        let cloud = WorkflowCloud(); cloud.result = CloudReviewResult(turns: [], summary: "No speech.")
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.analyzeWithCloud(original.id)
        XCTAssertEqual(model.interview(original.id)?.segments, original.segments)
        XCTAssertEqual(model.interview(original.id)?.aiSummary, original.aiSummary)
        XCTAssertEqual(model.interview(original.id)?.processingState, .failed)
    }

    func testCancellingCloudRestoresReviewWithoutDeletingAudio() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        let task = Task { await model.analyzeWithCloud(original.id) }
        await waitForCloud(cloud)
        model.cancelProcessing(for: original.id)
        await task.value
        XCTAssertEqual(model.interview(original.id), original)
        XCTAssertFalse(model.isProcessing)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("test.wav")), originalAudio)
    }

    func testProcessingIsScopedAndPreventsConcurrentRequestsAndDeletion() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        let other = Interview(title: "Other interview", duration: 3, audioFilename: "test.wav")
        XCTAssertTrue(model.save(other))
        XCTAssertTrue(model.setAIConsent(.allowed))
        let task = Task { await model.analyzeWithCloud(original.id) }
        await waitForCloud(cloud)
        XCTAssertTrue(model.isProcessing(original.id))
        XCTAssertFalse(model.isProcessing(other.id))
        XCTAssertFalse(model.delete(original.id))
        await model.analyzeWithCloud(other.id)
        XCTAssertEqual(cloud.calls, 1)
        model.update(other.id) { $0.notes = "Can keep reviewing another interview" }
        XCTAssertEqual(model.interview(other.id)?.notes, "Can keep reviewing another interview")
        model.cancelProcessing(for: other.id)
        XCTAssertTrue(model.isProcessing(original.id))
        model.cancelProcessing(for: original.id)
        await task.value
    }

    func testEditsWhileCloudRunsArePreservedWhenResultArrives() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        let task = Task { await model.analyzeWithCloud(original.id) }
        await waitForCloud(cloud)
        model.update(original.id) { $0.title = "Renamed while processing"; $0.notes = "New personal notes" }
        cloud.release()
        await task.value
        XCTAssertEqual(model.interview(original.id)?.title, "Renamed while processing")
        XCTAssertEqual(model.interview(original.id)?.notes, "New personal notes")
        XCTAssertEqual(model.interview(original.id)?.processingState, .ready)
    }

    func testInitialSaveFailureDoesNotStartCloudRequest() async throws {
        let cloud = WorkflowCloud()
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        try makeIndexUnwritable()
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.analyzeWithCloud(original.id)
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(model.interview(original.id), original)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isProcessing)
    }

    func testFinalSaveFailureKeepsPreviousReviewInMemory() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        let task = Task { await model.analyzeWithCloud(original.id) }
        await waitForCloud(cloud)
        try makeIndexUnwritable()
        cloud.release()
        await task.value
        XCTAssertEqual(model.interview(original.id)?.segments, original.segments)
        XCTAssertEqual(model.interview(original.id)?.notes, original.notes)
        XCTAssertEqual(model.interview(original.id)?.processingState, .failed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isProcessing)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("test.wav")), originalAudio)
    }

    func testLocalTranscriptKeepsUserNotesAndLeavesSpeakersUnassigned() async throws {
        let speech = WorkflowSpeech()
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud(), transcriber: speech)
        let original = try savedInterview(in: model)
        await model.transcribe(original.id)
        let result = try XCTUnwrap(model.interview(original.id))
        XCTAssertEqual(result.processingState, .ready)
        XCTAssertEqual(result.notes, original.notes)
        XCTAssertTrue(result.speakers.isEmpty)
        XCTAssertTrue(result.segments.allSatisfy { $0.speakerID == nil })
        XCTAssertEqual(result.questions.count, 1)
        XCTAssertTrue(result.aiSummary.isEmpty)
    }

    func testFailedLocalTranscriptPreservesExistingText() async throws {
        let speech = WorkflowSpeech(); speech.fails = true
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud(), transcriber: speech)
        let original = try savedInterview(in: model)
        await model.transcribe(original.id)
        XCTAssertEqual(model.interview(original.id)?.segments, original.segments)
        XCTAssertEqual(model.interview(original.id)?.aiSummary, original.aiSummary)
        XCTAssertEqual(model.interview(original.id)?.processingState, .failed)
    }

    func testMissingAudioDoesNotInvokeCloud() async throws {
        let cloud = WorkflowCloud()
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("test.wav"))
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.analyzeWithCloud(original.id)
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(model.interview(original.id), original)
        XCTAssertNotNil(model.errorMessage)
    }

    func testRestartConvertsInterruptedProcessingToRetryableFailure() throws {
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud())
        let original = try savedInterview(in: model)
        model.update(original.id) { $0.processingState = .transcribing }
        let relaunched = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertEqual(relaunched.interview(original.id)?.processingState, .failed)
        XCTAssertEqual(relaunched.interview(original.id)?.segments, original.segments)
        XCTAssertEqual(relaunched.interview(original.id)?.bookmarks, original.bookmarks)
    }

    func testCorruptRecoveryMarkerDoesNotBlockPlayableOrphanAndBookmarkJournal() async throws {
        let wave = wavData()
        try wave.write(to: directory.appendingPathComponent("orphan.wav"))
        try Data("invalid marker".utf8).write(to: directory.appendingPathComponent("ActiveRecording.json"))
        let bookmark = Bookmark(time: 0.5, note: "Recovered moment")
        struct Journal: Encodable { let filename: String; let bookmarks: [Bookmark] }
        try JSONEncoder().encode(Journal(filename: "orphan.wav", bookmarks: [bookmark]))
            .write(to: directory.appendingPathComponent("orphan.wav.bookmarks.json"))
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud())
        await model.recoverRecording()
        XCTAssertEqual(model.interviews.count, 1)
        XCTAssertEqual(model.interviews.first?.audioFilename, "orphan.wav")
        XCTAssertEqual(model.interviews.first?.bookmarks, [bookmark])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("orphan.wav")), wave)
        await model.recoverRecording()
        XCTAssertEqual(model.interviews.count, 1)
    }

    func testValidAudioImportCopiesOriginalAndPersistsDuration() async throws {
        let source = directory.appendingPathComponent("source.wav")
        let wave = wavData()
        try wave.write(to: source)
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud())
        await model.importAudio(source)
        let imported = try XCTUnwrap(model.interviews.first)
        XCTAssertEqual(imported.title, "source")
        XCTAssertEqual(imported.duration, 1, accuracy: 0.02)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(model.audioURL(for: imported))), wave)
        XCTAssertNotNil(model.selectedInterviewID)
        let relaunched = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertEqual(relaunched.interviews.first, imported)
    }

    func testFinishAutomaticallyTranscribesWithoutAIUntilPermission() async throws {
        let speech = WorkflowSpeech()
        let recorder = WorkflowRecorder(filename: "new.wav", duration: 3)
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let cloud = WorkflowCloud()
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech, recorder: recorder)
        model.addRecordingBookmark()
        model.finishRecording()
        let id = try XCTUnwrap(model.selectedInterviewID)
        await waitUntil { speech.calls == 1 && !model.isProcessing && model.interview(id)?.processingState == .ready }
        XCTAssertEqual(speech.calls, 1)
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 0)
        XCTAssertEqual(model.interview(id)?.processingState, .ready)
        XCTAssertEqual(model.interview(id)?.bookmarks.count, 1)
        XCTAssertFalse(model.recordingPresented)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("new.wav")), originalAudio)
    }

    func testAutomaticTranscriptionFailureNeverUploadsAndPersistsRecoveryMessage() async throws {
        let speech = WorkflowSpeech(); speech.fails = true
        let cloud = WorkflowCloud()
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        model.finishRecording()
        let id = try XCTUnwrap(model.selectedInterviewID)
        await waitUntil { model.interview(id)?.processingError != nil }
        XCTAssertEqual(model.interview(id)?.processingState, .failed)
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 0)
        XCTAssertFalse(model.pendingAIReviewIDs.contains(id))
        let relaunched = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertNotNil(relaunched.interview(id)?.processingError)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("new.wav")), originalAudio)
    }

    func testPartialLocalTranscriptPersistsWarningAndDoesNotOfferCompleteTextReview() async throws {
        let speech = WorkflowSpeech(); speech.warningMessage = "Unrecognized audio at 00:45–01:30; only recognized sections are shown."
        let cloud = WorkflowCloud()
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        model.finishRecording()
        let id = try XCTUnwrap(model.selectedInterviewID)
        await waitUntil { model.interview(id)?.transcriptionWarning != nil && !model.isProcessing }
        let partial = try XCTUnwrap(model.interview(id))
        XCTAssertEqual(partial.processingState, .ready)
        XCTAssertTrue(partial.segments.allSatisfy(\.needsReview))
        XCTAssertFalse(model.pendingAIReviewIDs.contains(id))
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 0)
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.reviewTranscriptWithCloud(id)
        XCTAssertEqual(model.interview(id)?.transcriptionWarning, speech.warningMessage)
        let restored = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertEqual(restored.interview(id)?.transcriptionWarning, speech.warningMessage)
        XCTAssertTrue(restored.exportText(try XCTUnwrap(restored.interview(id))).contains("Local transcript warning"))
    }

    func testAudioOnlyPreferencePersistsAndFinishDoesNotRequestSpeech() throws {
        let speech = WorkflowSpeech()
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud(), transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        model.setAutomaticallyTranscribe(false)
        model.setSpeechLocale("en_GB")
        model.finishRecording()
        XCTAssertEqual(speech.calls, 0)
        XCTAssertTrue(model.queuedTranscriptionIDs.isEmpty)
        XCTAssertEqual(model.interviews.first?.processingState, .audioOnly)
        let restoredSpeech = WorkflowSpeech()
        let restored = AppModel(directory: directory, cloudReview: WorkflowCloud(), transcriber: restoredSpeech)
        XCTAssertFalse(restored.automaticallyTranscribeNewRecordings)
        XCTAssertEqual(restoredSpeech.localeIdentifier, "en_GB")
    }

    func testNewRecordingQueuesBehindAnExistingProcessingJob() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true
        let speech = WorkflowSpeech()
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        let task = Task { await model.analyzeWithCloud(original.id) }
        await waitForCloud(cloud)
        model.finishRecording()
        let next = try XCTUnwrap(model.selectedInterviewID)
        XCTAssertTrue(model.queuedTranscriptionIDs.contains(next))
        XCTAssertEqual(speech.calls, 0)
        model.cancelProcessing(for: original.id)
        await task.value
        cloud.release()
        await waitUntil { cloud.calls == 2 && !model.isProcessing && model.interview(next)?.processingState == .ready }
        XCTAssertEqual(speech.calls, 1)
        XCTAssertEqual(model.interview(next)?.processingState, .ready)
    }

    func testTextAIReviewPreservesCorrectionsAndProducesEvidenceLinkedInsightsAndQA() async throws {
        let cloud = WorkflowCloud()
        let model = AppModel(directory: directory, cloudReview: cloud)
        var original = try savedInterview(in: model)
        original.segments[0].text = "Tell me when the neighbors can meet."
        original.segments[0].isQuote = true
        original.segments[0].needsReview = true
        original.segments.append(TranscriptSegment(speakerID: original.speakers[0].id, startTime: 1.1, endTime: 2.9, text: "Tuesday at six in the library."))
        original.questions = [QuestionAnswer(questionSegmentID: original.segments[0].id, status: .partial, followUp: "Keep my follow-up wording.")]
        XCTAssertTrue(model.save(original))
        cloud.analysis = CloudAnalysisResult(summary: "AI perspective on the meeting.", insights: [
            CloudInsight(kind: .needsContext, title: "Confirm the room", detail: "The response names the library without identifying a room.", evidenceTurnIndices: [1])
        ], questions: [CloudQuestion(questionTurnIndex: 0, answerTurnIndices: [1], followUp: "Which room?")])
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.reviewTranscriptWithCloud(original.id)
        let reviewed = try XCTUnwrap(model.interview(original.id))
        XCTAssertEqual(reviewed.segments, original.segments)
        XCTAssertEqual(reviewed.speakers, original.speakers)
        XCTAssertEqual(reviewed.notes, original.notes)
        XCTAssertEqual(reviewed.bookmarks, original.bookmarks)
        XCTAssertEqual(reviewed.aiInsights.first?.segmentIDs, [original.segments[1].id])
        XCTAssertEqual(reviewed.questions[0].status, .partial)
        XCTAssertEqual(reviewed.questions[0].followUp, "Keep my follow-up wording.")
        XCTAssertEqual(reviewed.questions[0].answerSegmentIDs, [original.segments[1].id])
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 1)
        let restored = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertEqual(restored.interview(original.id), reviewed)
        XCTAssertTrue(restored.exportText(reviewed).contains("Confirm the room"))
        XCTAssertTrue(restored.exportText(reviewed).contains("Evidence:"))
    }

    func testTextReviewCanUseSavedTranscriptWithoutAnAudioFile() async throws {
        let cloud = WorkflowCloud()
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("test.wav"))
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.reviewTranscriptWithCloud(original.id)
        XCTAssertEqual(cloud.transcriptCalls, 1)
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(model.interview(original.id)?.processingState, .ready)
        XCTAssertEqual(model.interview(original.id)?.segments, original.segments)
    }

    func testChangedTranscriptRejectsInFlightAIReferences() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        let task = Task { await model.reviewTranscriptWithCloud(original.id) }
        await waitUntil { cloud.transcriptCalls == 1 }
        model.update(original.id) { $0.segments[0].text = "Corrected text during processing." }
        cloud.release()
        await task.value
        XCTAssertEqual(model.interview(original.id)?.segments[0].text, "Corrected text during processing.")
        XCTAssertEqual(model.interview(original.id)?.aiSummary, original.aiSummary)
        XCTAssertTrue(model.interview(original.id)?.aiInsights.isEmpty == true)
        XCTAssertTrue(model.interview(original.id)?.processingError?.contains("changed") == true)
    }

    func testTextReviewFailurePreservesEverythingAndPersistsActionableError() async throws {
        let cloud = WorkflowCloud(); cloud.failure = .apiDisabled
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        await model.reviewTranscriptWithCloud(original.id)
        let after = try XCTUnwrap(model.interview(original.id))
        XCTAssertEqual(after.segments, original.segments)
        XCTAssertEqual(after.aiSummary, original.aiSummary)
        XCTAssertEqual(after.notes, original.notes)
        XCTAssertNotNil(after.processingError)
        XCTAssertEqual(cloud.calls, 0)
        let restored = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertEqual(restored.interview(original.id)?.processingError, after.processingError)
    }

    func testMissingConsentDoesNotAuthorizeCloudOrModifyAnInterview() async throws {
        let cloud = WorkflowCloud(); cloud.configurationStatus = .configurationMissing
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertEqual(model.aiConsentStatus, .notDetermined)
        XCTAssertTrue(model.shouldRequestAIConsent)
        await model.analyzeWithCloud(original.id)
        await model.reviewTranscriptWithCloud(original.id)
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 0)
        XCTAssertEqual(model.interview(original.id), original)
        XCTAssertTrue(model.errorMessage?.contains("AI access is off") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("AIConsent.json").path))
    }

    func testConsentPersistsWithoutUploadingExistingRecordings() async throws {
        let cloud = WorkflowCloud()
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        XCTAssertFalse(model.shouldRequestAIConsent)
        let restored = AppModel(directory: directory, cloudReview: cloud)
        XCTAssertEqual(restored.aiConsentStatus, .allowed)
        XCTAssertTrue(restored.automaticallyTranscribeNewRecordings)
        XCTAssertTrue(restored.queuedTranscriptionIDs.isEmpty)
        XCTAssertEqual(restored.interview(original.id), original)
        await Task.yield()
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 0)
        XCTAssertTrue(restored.setAIConsent(.denied))
        XCTAssertEqual(AppModel(directory: directory, cloudReview: cloud).aiConsentStatus, .denied)
    }

    func testDeniedConsentStillAllowsDefaultAppleTranscription() async throws {
        let cloud = WorkflowCloud()
        let speech = WorkflowSpeech()
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.denied))
        await model.transcribe(original.id)
        XCTAssertEqual(speech.requestedModes, [.onDevice])
        XCTAssertEqual(model.interview(original.id)?.processingState, .ready)
        await model.analyzeWithCloud(original.id)
        await model.reviewTranscriptWithCloud(original.id)
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 0)
        XCTAssertFalse(model.shouldRequestAIConsent)
    }

    func testCorruptConsentFailsClosedWithoutDisablingTheLibrary() throws {
        try Data("malformed private preference".utf8).write(to: directory.appendingPathComponent("AIConsent.json"))
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertEqual(model.aiConsentStatus, .denied)
        XCTAssertTrue(model.canWrite)
        XCTAssertTrue(model.errorMessage?.contains("AI access is off") == true)
        XCTAssertFalse(model.errorMessage?.contains("malformed private preference") == true)
        _ = try savedInterview(in: model)
        XCTAssertEqual(model.interviews.count, 1)
    }

    func testUnsavedGrantDoesNotEnableAI() throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("AIConsent.json"), withIntermediateDirectories: false)
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertEqual(model.aiConsentStatus, .denied)
        XCTAssertFalse(model.setAIConsent(.allowed))
        XCTAssertEqual(model.aiConsentStatus, .denied)
        XCTAssertTrue(model.errorMessage?.contains("was not enabled") == true)
    }

    func testRevocationPersistsWhenAtomicReplacementIsBlockedButGrantIsWritable() throws {
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertTrue(model.setAIConsent(.allowed))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        XCTAssertFalse(FileManager.default.isWritableFile(atPath: directory.path))
        XCTAssertTrue(model.setAIConsent(.denied))
        let stored = try JSONDecoder().decode(AIConsentStatus.self, from: Data(contentsOf: directory.appendingPathComponent("AIConsent.json")))
        XCTAssertEqual(stored, .denied)
        XCTAssertEqual(AppModel(directory: directory, cloudReview: WorkflowCloud()).aiConsentStatus, .denied)
    }

    func testUnwritableStoredGrantFailsClosedAfterAnUnsavedRevocation() throws {
        let model = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertTrue(model.setAIConsent(.allowed))
        let consent = directory.appendingPathComponent("AIConsent.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: consent.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: consent.path)
        }
        XCTAssertFalse(model.setAIConsent(.denied))
        XCTAssertEqual(model.aiConsentStatus, .denied)
        XCTAssertTrue(model.errorMessage?.contains("off for this session") == true)
        let restored = AppModel(directory: directory, cloudReview: WorkflowCloud())
        XCTAssertEqual(restored.aiConsentStatus, .denied)
    }

    func testAllowedFinishRunsAppleBeforeAutomaticAudioReview() async throws {
        let speech = WorkflowSpeech()
        let cloud = WorkflowCloud()
        var events: [String] = []
        speech.onRequest = { events.append("apple") }
        cloud.onAudioRequest = { events.append("cloud") }
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        XCTAssertTrue(model.setAIConsent(.allowed))
        model.finishRecording()
        let id = try XCTUnwrap(model.selectedInterviewID)
        await waitUntil { !model.isAutomaticallyProcessing }
        XCTAssertEqual(events, ["apple", "cloud"])
        XCTAssertEqual(speech.requestedModes, [.onDevice])
        XCTAssertEqual(model.interview(id)?.speakers.count, 2)
        XCTAssertFalse(try XCTUnwrap(model.interview(id)).aiSummary.isEmpty)
        XCTAssertEqual(cloud.transcriptCalls, 0)
        XCTAssertTrue(model.pendingAIReviewIDs.isEmpty)
    }

    func testAllowedFinishFallsBackAfterAppleFailureWithoutPrematureAlert() async throws {
        let speech = WorkflowSpeech(); speech.fails = true
        let cloud = WorkflowCloud(); cloud.suspends = true
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        XCTAssertTrue(model.setAIConsent(.allowed))
        model.finishRecording()
        let id = try XCTUnwrap(model.selectedInterviewID)
        await waitForCloud(cloud)
        XCTAssertEqual(speech.calls, 1)
        XCTAssertNil(model.errorMessage)
        cloud.release()
        await waitUntil { !model.isAutomaticallyProcessing }
        XCTAssertEqual(model.interview(id)?.processingState, .ready)
        XCTAssertFalse(try XCTUnwrap(model.interview(id)).segments.isEmpty)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("new.wav")), originalAudio)
    }

    func testAutomaticCloudFailureKeepsTheAppleDraftAndPersonalNotes() async throws {
        let speech = WorkflowSpeech()
        let cloud = WorkflowCloud(); cloud.failure = .appCheckRequired
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        XCTAssertTrue(model.setAIConsent(.allowed))
        model.finishRecording()
        let id = try XCTUnwrap(model.selectedInterviewID)
        model.update(id) { $0.notes = "Keep the reporter's note." }
        await waitUntil { !model.isAutomaticallyProcessing }
        let result = try XCTUnwrap(model.interview(id))
        XCTAssertEqual(result.processingState, .failed)
        XCTAssertEqual(result.segments.map(\.text), ["What happens next?", "We meet Tuesday."])
        XCTAssertTrue(result.speakers.isEmpty)
        XCTAssertEqual(result.notes, "Keep the reporter's note.")
        XCTAssertTrue(result.processingError?.contains("App Check") == true)
        XCTAssertEqual(cloud.calls, 1)
    }

    func testGrantDuringAppleProcessingDoesNotUploadThatRecording() async throws {
        let speech = WorkflowSpeech(); speech.suspends = true
        let cloud = WorkflowCloud()
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        model.finishRecording()
        await waitUntil { speech.calls == 1 }
        XCTAssertTrue(model.setAIConsent(.allowed))
        speech.release()
        await waitUntil { !model.isAutomaticallyProcessing }
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(model.interviews.first?.processingState, .ready)
    }

    func testRevocationAndRegrantDuringAppleProcessingDoesNotResurrectUpload() async throws {
        let speech = WorkflowSpeech(); speech.suspends = true
        let cloud = WorkflowCloud()
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        XCTAssertTrue(model.setAIConsent(.allowed))
        model.finishRecording()
        await waitUntil { speech.calls == 1 }
        XCTAssertTrue(model.setAIConsent(.denied))
        XCTAssertTrue(model.setAIConsent(.allowed))
        speech.release()
        await waitUntil { !model.isAutomaticallyProcessing }
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(model.interviews.first?.processingState, .ready)
        XCTAssertTrue(model.pendingAIReviewIDs.isEmpty)
    }

    func testGrantDoesNotRetroactivelyAuthorizeAnOlderQueuedRecording() async throws {
        let speech = WorkflowSpeech(); speech.suspends = true
        let cloud = WorkflowCloud()
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        let original = try savedInterview(in: model)
        let manual = Task { await model.transcribe(original.id) }
        await waitUntil { speech.calls == 1 }
        model.finishRecording()
        let newID = try XCTUnwrap(model.selectedInterviewID)
        XCTAssertTrue(model.queuedTranscriptionIDs.contains(newID))
        XCTAssertTrue(model.setAIConsent(.allowed))
        speech.release()
        await manual.value
        await waitUntil { !model.isAutomaticallyProcessing }
        XCTAssertEqual(speech.calls, 2)
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(model.interview(newID)?.processingState, .ready)
    }

    func testRevokingConsentCancelsActiveCloudAndPreservesPriorReview() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        let task = Task { await model.analyzeWithCloud(original.id) }
        await waitForCloud(cloud)
        XCTAssertTrue(model.setAIConsent(.denied))
        XCTAssertTrue(model.setAIConsent(.allowed))
        await task.value
        XCTAssertEqual(model.interview(original.id), original)
        XCTAssertEqual(cloud.calls, 1)
        XCTAssertFalse(model.isProcessing)
        XCTAssertTrue(model.pendingAIReviewIDs.isEmpty)
    }

    func testRevokingConsentCancelsActiveTranscriptReview() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        let task = Task { await model.reviewTranscriptWithCloud(original.id) }
        await waitUntil { cloud.transcriptCalls == 1 }
        XCTAssertTrue(model.setAIConsent(.denied))
        await task.value
        XCTAssertEqual(model.interview(original.id), original)
        XCTAssertEqual(cloud.calls, 0)
        XCTAssertEqual(cloud.transcriptCalls, 1)
        XCTAssertEqual(AppModel(directory: directory, cloudReview: cloud).aiConsentStatus, .denied)
    }

    func testLateProviderResultAfterRevocationAndRegrantCannotReplacePriorReview() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true; cloud.ignoresCancellation = true
        let model = AppModel(directory: directory, cloudReview: cloud)
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        let task = Task { await model.analyzeWithCloud(original.id) }
        await waitForCloud(cloud)
        XCTAssertTrue(model.setAIConsent(.denied))
        XCTAssertTrue(model.setAIConsent(.allowed))
        cloud.release()
        await task.value
        XCTAssertEqual(model.interview(original.id), original)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isProcessing)
    }

    func testRevocationClearsConsentEligibilityForQueuedRecordings() async throws {
        let cloud = WorkflowCloud(); cloud.suspends = true
        let speech = WorkflowSpeech()
        try originalAudio.write(to: directory.appendingPathComponent("new.wav"))
        let model = AppModel(directory: directory, cloudReview: cloud, transcriber: speech,
                             recorder: WorkflowRecorder(filename: "new.wav", duration: 3))
        let original = try savedInterview(in: model)
        XCTAssertTrue(model.setAIConsent(.allowed))
        let manual = Task { await model.analyzeWithCloud(original.id) }
        await waitForCloud(cloud)
        model.finishRecording()
        let queued = try XCTUnwrap(model.selectedInterviewID)
        XCTAssertTrue(model.queuedTranscriptionIDs.contains(queued))
        XCTAssertTrue(model.setAIConsent(.denied))
        XCTAssertTrue(model.setAIConsent(.allowed))
        await manual.value
        await waitUntil { !model.isAutomaticallyProcessing }
        XCTAssertEqual(speech.calls, 1)
        XCTAssertEqual(cloud.calls, 1)
        XCTAssertEqual(model.interview(queued)?.processingState, .ready)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Expected workflow state was not reached", file: file, line: line)
    }

    private let originalAudio = Data("Synthetic audio fixture — never user audio".utf8)
    private func savedInterview(in model: AppModel) throws -> Interview {
        try originalAudio.write(to: directory.appendingPathComponent("test.wav"))
        let speaker = Speaker(name: "Previously named guest")
        let original = Interview(title: "Original title", duration: 3, audioFilename: "test.wav", speakers: [speaker],
            segments: [TranscriptSegment(speakerID: speaker.id, startTime: 0, endTime: 1, text: "Original transcript.")],
            bookmarks: [Bookmark(time: 1, note: "Original bookmark")], notes: "Personal editorial note", aiSummary: "Previous AI summary", processingState: .ready)
        XCTAssertTrue(model.save(original))
        return original
    }
    private func waitForCloud(_ cloud: WorkflowCloud, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 { if cloud.calls > 0 { return }; await Task.yield() }
        XCTFail("Cloud task did not start", file: file, line: line)
    }
    private func makeIndexUnwritable() throws {
        let index = directory.appendingPathComponent("interviews.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
    }
    private func wavData() -> Data {
        let samples = Data(count: 16_000)
        var data = Data()
        func text(_ value: String) { data.append(Data(value.utf8)) }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + samples.count)); text("WAVEfmt "); u32(16); u16(1); u16(1); u32(8_000); u32(16_000); u16(2); u16(16); text("data"); u32(UInt32(samples.count)); data.append(samples)
        return data
    }
}

@MainActor @Observable
private final class WorkflowCloud: CloudReviewProviding {
    var configurationStatus: CloudConfigurationStatus = .ready
    var isAvailable: Bool { configurationStatus == .ready }
    private(set) var isProcessing = false
    private(set) var calls = 0
    private(set) var transcriptCalls = 0
    var analysis = CloudAnalysisResult(summary: "Review of the saved transcript.", insights: [CloudInsight(kind: .keyPoint, title: "A saved statement", detail: "The speaker makes a statement worth revisiting.", evidenceTurnIndices: [0])], questions: [])
    var suspends = false
    var ignoresCancellation = false
    var onAudioRequest: (() -> Void)?
    var failure: CloudReviewError?
    var result = CloudReviewResult(turns: [
        CloudTurn(speaker: "Speaker A", startTime: 0, endTime: 1, text: "When is the next meeting?"),
        CloudTurn(speaker: "Speaker B", startTime: 1.1, endTime: 2.9, text: "The next community meeting is Tuesday.")
    ], summary: "The guest described the next community meeting.")
    func analyzeAudio(url: URL) async throws -> CloudReviewResult {
        isProcessing = true; calls += 1
        onAudioRequest?()
        defer { isProcessing = false }
        while suspends {
            if ignoresCancellation { await Task.yield() }
            else { try await Task.sleep(for: .milliseconds(10)) }
        }
        if let failure { throw failure }
        return result
    }
    func reviewTranscript(_ session: Interview) async throws -> CloudAnalysisResult {
        isProcessing = true; transcriptCalls += 1
        defer { isProcessing = false }
        while suspends { try await Task.sleep(for: .milliseconds(10)) }
        if let failure { throw failure }
        return analysis
    }
    func release() { suspends = false }
}

@MainActor
private final class WorkflowSpeech: SpeechTranscribing {
    private(set) var isTranscribing = false
    var fails = false
    var suspends = false
    var onRequest: (() -> Void)?
    var localeIdentifier = "en_US"
    var warningMessage: String?
    private(set) var calls = 0
    private(set) var requestedModes: [SpeechRecognitionMode] = []
    func transcribe(url: URL, mode: SpeechRecognitionMode) async throws -> [TranscribedTurn] {
        requestedModes.append(mode)
        return try await transcribe(url: url)
    }
    func transcribe(url: URL) async throws -> [TranscribedTurn] {
        isTranscribing = true; calls += 1; defer { isTranscribing = false }
        onRequest?()
        while suspends { try await Task.sleep(for: .milliseconds(10)) }
        if fails { throw SpeechTranscriptionError.emptyResult }
        return [TranscribedTurn(startTime: 0, endTime: 1, text: "What happens next?"), TranscribedTurn(startTime: 1, endTime: 2, text: "We meet Tuesday.")]
    }
    func cancel() {}
    func release() { suspends = false }
}

@MainActor
private final class WorkflowRecorder: RecordingProviding {
    private(set) var isRecording = true
    private(set) var isPaused = false
    let elapsed: TimeInterval
    let levels: [Float] = []
    let inputName = "Test recorder adapter"
    private(set) var activeFilename: String?
    var errorMessage: String?
    private let filename: String
    init(filename: String, duration: TimeInterval) { self.filename = filename; self.elapsed = duration; self.activeFilename = filename }
    func start() async throws -> String { isRecording = true; activeFilename = filename; return filename }
    func pause() { isPaused = true }
    func resume() throws { isPaused = false }
    func finish() throws -> RecordedAudio { isRecording = false; activeFilename = nil; return RecordedAudio(filename: filename, duration: elapsed) }
    func keepFileAndClose() -> RecordedAudio? { try? finish() }
    func addBookmarkTime() -> TimeInterval { elapsed }
}
#endif
