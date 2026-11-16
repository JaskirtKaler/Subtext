import Foundation
import XCTest
@testable import SubtextCore

final class StructuredReviewApplicationTests: XCTestCase {
    func testStructuredAudioReviewMapsAIQuestionsAndCitedInsightsIntoSavedWorkflow() throws {
        let original = Interview(
            title: "Budget discussion",
            duration: 20,
            audioFilename: "budget.m4a",
            bookmarks: [Bookmark(time: 5, note: "Review the allocation")],
            notes: "My reporting notes remain separate.",
            processingError: "An earlier attempt failed",
            processingState: .failed
        )
        let result = CloudReviewResult(
            turns: turns,
            summary: "Speakers described a proposed allocation and a pending schedule. Review the original audio.",
            insights: [
                CloudInsight(kind: .keyPoint, title: "Proposed allocation", detail: "Speaker B described a committee proposal.", evidenceTurnIndices: [1]),
                CloudInsight(kind: .needsContext, title: "Schedule remains open", detail: "The discussion does not give a final date; ask for the schedule.", evidenceTurnIndices: [4])
            ],
            questions: [CloudQuestion(questionTurnIndex: 0, answerTurnIndices: [1], followUp: "Ask for the written breakdown.")]
        )

        var reviewed = try ReviewApplication.applying(result, to: original)

        // AI can recognize an implicit question even when punctuation heuristics
        // would miss it. A later question is not invented into the supplied list.
        XCTAssertFalse(reviewed.segments[0].text.hasSuffix("?"))
        XCTAssertEqual(reviewed.questions.count, 1)
        XCTAssertEqual(reviewed.questions[0].questionSegmentID, reviewed.segments[0].id)
        XCTAssertEqual(reviewed.questions[0].answerSegmentIDs, [reviewed.segments[1].id])
        XCTAssertEqual(reviewed.questions[0].status, .needsReview)
        XCTAssertEqual(reviewed.aiInsights.map(\.kind), [.keyPoint, .needsContext])
        XCTAssertEqual(reviewed.aiInsights[0].segmentIDs, [reviewed.segments[1].id])
        XCTAssertEqual(reviewed.aiInsights[1].segmentIDs, [reviewed.segments[4].id])
        XCTAssertEqual(reviewed.notes, original.notes)
        XCTAssertEqual(reviewed.bookmarks, original.bookmarks)
        XCTAssertNil(reviewed.processingError)

        let speakerB = try XCTUnwrap(reviewed.segments[1].speakerID)
        let speakerIndex = try XCTUnwrap(reviewed.speakers.firstIndex { $0.id == speakerB })
        reviewed.speakers[speakerIndex].name = "Riley"
        reviewed.segments[4].speakerID = speakerB
        reviewed.segments[1].isQuote = true
        reviewed.segments[4].needsReview = true
        reviewed.questions[0].status = .partial
        reviewed.questions[0].followUp = "My follow-up: request the committee minutes."

        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = InterviewRepository(directory: directory)
        try repository.save([reviewed])
        let restored = try XCTUnwrap(repository.load().first)

        XCTAssertEqual(restored, reviewed)
        XCTAssertTrue(restored.segments[1].isQuote)
        XCTAssertTrue(restored.segments[4].needsReview)
        XCTAssertEqual(restored.questions[0].status, .partial)
        XCTAssertTrue(restored.searchText.contains("Schedule remains open"))
        XCTAssertTrue(restored.searchText.contains("committee minutes"))
        let exported = restored.exportTranscript()
        XCTAssertTrue(exported.contains("AI draft insights · review against the original audio"))
        XCTAssertTrue(exported.contains("Needs context: Schedule remains open"))
        XCTAssertTrue(exported.contains("Evidence [00:09] Riley: The schedule is pending."))
        XCTAssertTrue(exported.contains("Notes\nMy reporting notes remain separate."))
    }

    func testExplicitEmptyAIQuestionsDoNotFallBackToQuestionMarkHeuristics() throws {
        let result = CloudReviewResult(turns: turns, summary: "A draft summary.", insights: [], questions: [])
        let reviewed = try ReviewApplication.applying(result, to: Interview(duration: 20))
        XCTAssertTrue(reviewed.segments.contains { $0.text.hasSuffix("?") })
        XCTAssertTrue(reviewed.questions.isEmpty)
        let legacy = try ReviewApplication.applying(CloudReviewResult(turns: turns, summary: "Legacy draft."), to: Interview(duration: 20))
        XCTAssertFalse(legacy.questions.isEmpty)
    }

    func testLegacyCloudJSONHasAbsentStructuredArraysWhileExplicitNullIsInvalid() throws {
        let legacy = CloudReviewResult(turns: turns, summary: "Legacy summary")
        let encoded = try JSONEncoder().encode(legacy)
        let restored = try JSONDecoder().decode(CloudReviewResult.self, from: encoded)
        XCTAssertNil(restored.insights)
        XCTAssertNil(restored.questions)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["questions"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(CloudReviewResult.self, from: JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "questions")
        object["insights"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(CloudReviewResult.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testTranscriptAnalysisPreservesCorrectionsAndMergesHumanReview() throws {
        let a = Speaker(name: "Morgan", role: "Reporter", color: .green)
        let b = Speaker(name: "Riley", role: "Coordinator", color: .orange)
        let segments = [
            TranscriptSegment(speakerID: a.id, startTime: 0, endTime: 2, text: "Explain how the proposal changed."),
            TranscriptSegment(speakerID: b.id, startTime: 2, endTime: 5, text: "Our corrected draft includes a reserve.", isQuote: true),
            TranscriptSegment(speakerID: a.id, startTime: 6, endTime: 8, text: "What still needs agreement?", needsReview: true),
            TranscriptSegment(speakerID: b.id, startTime: 8, endTime: 12, text: "The final schedule needs agreement."),
            TranscriptSegment(speakerID: a.id, startTime: 13, endTime: 15, text: "Which record should we request?")
        ]
        let priorInsight = AIInsight(kind: .keyPoint, title: "A reserve was discussed", detail: "The corrected draft includes a reserve.", segmentIDs: [segments[1].id])
        let humanQuestion = QuestionAnswer(questionSegmentID: segments[0].id, answerSegmentIDs: [segments[1].id], status: .answered, followUp: "My exact follow-up wording.")
        let manualQuestion = QuestionAnswer(questionSegmentID: segments[4].id, status: .partial, followUp: "Keep this manually saved question.")
        let original = Interview(
            title: "Corrected transcript",
            duration: 20,
            audioFilename: "source.m4a",
            speakers: [a, b],
            segments: segments,
            bookmarks: [Bookmark(time: 2, note: "Reporter bookmark")],
            questions: [humanQuestion, manualQuestion],
            notes: "Personal notes",
            aiSummary: "Previous AI summary",
            aiInsights: [priorInsight],
            processingError: "Previous processing failure",
            processingState: .failed
        )
        let analysis = CloudAnalysisResult(
            summary: "A new analysis of the corrected transcript.",
            insights: [
                CloudInsight(kind: priorInsight.kind, title: priorInsight.title, detail: priorInsight.detail, evidenceTurnIndices: [1]),
                CloudInsight(kind: .openQuestion, title: "Schedule agreement", detail: "Ask what is needed to agree the final schedule.", evidenceTurnIndices: [2, 3])
            ],
            questions: [
                CloudQuestion(questionTurnIndex: 0, answerTurnIndices: [1, 3], followUp: "AI wording should not replace the reporter's."),
                CloudQuestion(questionTurnIndex: 2, answerTurnIndices: [3], followUp: "Who must agree?")
            ]
        )

        let reviewed = try ReviewApplication.applying(analysis, to: original)

        XCTAssertEqual(reviewed.segments, original.segments)
        XCTAssertEqual(reviewed.speakers, original.speakers)
        XCTAssertEqual(reviewed.audioFilename, original.audioFilename)
        XCTAssertEqual(reviewed.notes, original.notes)
        XCTAssertEqual(reviewed.bookmarks, original.bookmarks)
        XCTAssertEqual(reviewed.questions.map(\.questionSegmentID), [segments[0].id, segments[2].id, segments[4].id])
        XCTAssertEqual(reviewed.questions[0].id, humanQuestion.id)
        XCTAssertEqual(reviewed.questions[0].status, .answered)
        XCTAssertEqual(reviewed.questions[0].followUp, humanQuestion.followUp)
        XCTAssertEqual(reviewed.questions[0].answerSegmentIDs, [segments[1].id, segments[3].id])
        XCTAssertEqual(reviewed.questions[1].status, .needsReview)
        XCTAssertEqual(reviewed.questions[2], manualQuestion)
        XCTAssertEqual(reviewed.aiInsights[0].id, priorInsight.id)
        XCTAssertEqual(reviewed.aiInsights[1].segmentIDs, [segments[2].id, segments[3].id])
        XCTAssertEqual(reviewed.aiSummary, analysis.summary)
        XCTAssertNil(reviewed.processingError)
        XCTAssertEqual(reviewed.processingState, .ready)
        XCTAssertEqual(original.aiSummary, "Previous AI summary")
        XCTAssertEqual(original.processingError, "Previous processing failure")
    }

    func testAITranscriptReviewAddsFollowUpToAnUnreviewedLocalQuestion() throws {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 2, text: "What happens next?"),
            TranscriptSegment(startTime: 2, endTime: 4, text: "We will share a schedule.")
        ]
        let local = LocalReview.suggestQuestions(segments: segments)
        let original = Interview(duration: 5, segments: segments, questions: local)
        let analysis = CloudAnalysisResult(
            summary: "A schedule was discussed.",
            questions: [CloudQuestion(questionTurnIndex: 0, answerTurnIndices: [1], followUp: "When will the schedule be shared?")]
        )

        let reviewed = try ReviewApplication.applying(analysis, to: original)

        XCTAssertEqual(reviewed.questions[0].id, local[0].id)
        XCTAssertEqual(reviewed.questions[0].status, .needsReview)
        XCTAssertEqual(reviewed.questions[0].followUp, "When will the schedule be shared?")
    }

    func testAuthoritativeEmptyAIQuestionsRemoveUntouchedHeuristicsButKeepHumanReview() throws {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 1, text: "A possible question?"),
            TranscriptSegment(startTime: 1, endTime: 2, text: "A possible answer."),
            TranscriptSegment(startTime: 3, endTime: 4, text: "A reviewed question?"),
            TranscriptSegment(startTime: 4, endTime: 5, text: "A reviewed answer."),
            TranscriptSegment(startTime: 6, endTime: 7, text: "A question with a written follow-up?"),
            TranscriptSegment(startTime: 7, endTime: 8, text: "An answer to follow up.")
        ]
        var questions = LocalReview.suggestQuestions(segments: segments)
        questions[1].status = .answered
        questions[2].followUp = "My written follow-up must stay."
        let original = Interview(duration: 10, segments: segments, questions: questions)

        let reviewed = try ReviewApplication.applying(CloudAnalysisResult(summary: "No additional AI question pairs.", questions: []), to: original)

        XCTAssertEqual(reviewed.questions, [questions[1], questions[2]])
        XCTAssertEqual(original.questions.count, 3)
        XCTAssertEqual(reviewed.segments, original.segments)
    }

    func testInvalidStructuredCitationsRejectWholeResultWithoutReplacingOriginal() throws {
        let original = try ReviewApplication.applying(CloudReviewResult(turns: turns, summary: "Original summary"), to: Interview(duration: 20, notes: "Keep this"))
        let invalidInsights = [
            CloudInsight(kind: .keyPoint, title: "Missing evidence", detail: "A detail", evidenceTurnIndices: []),
            CloudInsight(kind: .keyPoint, title: "Negative evidence", detail: "A detail", evidenceTurnIndices: [-1]),
            CloudInsight(kind: .keyPoint, title: "Out of bounds", detail: "A detail", evidenceTurnIndices: [turns.count]),
            CloudInsight(kind: .keyPoint, title: "Duplicate evidence", detail: "A detail", evidenceTurnIndices: [1, 1]),
            CloudInsight(kind: .keyPoint, title: " ", detail: "A detail", evidenceTurnIndices: [1]),
            CloudInsight(kind: .keyPoint, title: "Blank detail", detail: "\n", evidenceTurnIndices: [1])
        ]
        for insight in invalidInsights {
            let audio = CloudReviewResult(turns: turns, summary: "Replacement", insights: [insight], questions: [])
            XCTAssertThrowsError(try ReviewApplication.applying(audio, to: original))
            let transcript = CloudAnalysisResult(summary: "Replacement", insights: [insight], questions: [])
            XCTAssertThrowsError(try ReviewApplication.applying(transcript, to: original))
            XCTAssertEqual(original.aiSummary, "Original summary")
            XCTAssertEqual(original.notes, "Keep this")
            XCTAssertTrue(original.aiInsights.isEmpty)
        }
        let repeated = CloudInsight(kind: .keyPoint, title: "Repeated item", detail: "The same suggestion should appear once.", evidenceTurnIndices: [1])
        XCTAssertThrowsError(try ReviewApplication.applying(CloudAnalysisResult(summary: "Replacement", insights: [repeated, repeated]), to: original))
        let invalidQuestions = [
            [CloudQuestion(questionTurnIndex: -1, answerTurnIndices: [1])],
            [CloudQuestion(questionTurnIndex: turns.count, answerTurnIndices: [])],
            [CloudQuestion(questionTurnIndex: 0, answerTurnIndices: [turns.count])],
            [CloudQuestion(questionTurnIndex: 0, answerTurnIndices: [0])],
            [CloudQuestion(questionTurnIndex: 2, answerTurnIndices: [1])],
            [CloudQuestion(questionTurnIndex: 0, answerTurnIndices: [1, 1])],
            [CloudQuestion(questionTurnIndex: 0, answerTurnIndices: [1]), CloudQuestion(questionTurnIndex: 0, answerTurnIndices: [3])]
        ]
        for questions in invalidQuestions {
            XCTAssertThrowsError(try ReviewApplication.applying(CloudAnalysisResult(summary: "Replacement", questions: questions), to: original))
            XCTAssertEqual(original.aiSummary, "Original summary")
        }
    }

    func testTranscriptAnalysisRejectsTimelineDriftInsteadOfMovingCorrections() {
        let invalidSegments = [TranscriptSegment(startTime: 2, endTime: 25, text: "Edited text beyond the recording")]
        let original = Interview(duration: 20, segments: invalidSegments, notes: "Keep notes")

        XCTAssertThrowsError(try ReviewApplication.applying(CloudAnalysisResult(summary: "A summary"), to: original))

        XCTAssertEqual(original.segments, invalidSegments)
        XCTAssertEqual(original.notes, "Keep notes")
    }

    func testOlderJSONDefaultsInsightsAndProcessingErrorButMalformedFieldsStillFail() throws {
        let original = Interview(title: "Legacy", duration: 10, notes: "User notes")
        let encoded = try JSONEncoder().encode(original)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["aiSummary", "aiInsights", "processingError"] { legacy.removeValue(forKey: key) }
        let migrated = try JSONDecoder().decode(Interview.self, from: JSONSerialization.data(withJSONObject: legacy))

        XCTAssertEqual(migrated.aiSummary, "")
        XCTAssertEqual(migrated.aiInsights, [])
        XCTAssertNil(migrated.processingError)
        XCTAssertEqual(migrated.notes, original.notes)

        var malformedInsights = legacy
        malformedInsights["aiInsights"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(Interview.self, from: JSONSerialization.data(withJSONObject: malformedInsights)))
        var malformedError = legacy
        malformedError["processingError"] = 7
        XCTAssertThrowsError(try JSONDecoder().decode(Interview.self, from: JSONSerialization.data(withJSONObject: malformedError)))
    }

    func testFailureMessageAndInsightEvidenceRoundTripWithoutChangingUserNotes() throws {
        let segment = TranscriptSegment(startTime: 0, endTime: 3, text: "A saved source statement.")
        let original = Interview(
            title: "Failed processing",
            duration: 5,
            segments: [segment],
            notes: "My notes",
            aiSummary: "A saved summary",
            aiInsights: [AIInsight(kind: .followUp, title: "Ask for the record", detail: "Request the record mentioned in the discussion.", segmentIDs: [segment.id])],
            processingError: "Speech recognition is unavailable. Try again later.",
            processingState: .failed
        )

        let restored = try JSONDecoder().decode(Interview.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.processingError, original.processingError)
        XCTAssertEqual(restored.aiInsights[0].segmentIDs, [segment.id])
        XCTAssertEqual(restored.notes, "My notes")
    }

    private var turns: [CloudTurn] {
        [
            CloudTurn(speaker: "Speaker A", startTime: 0, endTime: 2, text: "Tell me how the budget was decided."),
            CloudTurn(speaker: "Speaker B", startTime: 2, endTime: 5, text: "A committee proposed the allocation."),
            CloudTurn(speaker: "Speaker A", startTime: 6, endTime: 8, text: "Could you share the breakdown?"),
            CloudTurn(speaker: "Unassigned", startTime: 8, endTime: 9, text: "[inaudible]"),
            CloudTurn(speaker: "Speaker C", startTime: 9, endTime: 12, text: "The schedule is pending.")
        ]
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SubtextStructuredReview-\(UUID())")
    }
}
