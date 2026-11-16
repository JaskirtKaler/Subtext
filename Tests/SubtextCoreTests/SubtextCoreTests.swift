import Foundation
import XCTest
@testable import SubtextCore

final class SubtextCoreTests: XCTestCase {
    func testRepositoryRoundTripPreservesInterviewRelationships() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let speaker = Speaker(name: "Speaker A", role: "Host", color: .purple)
        let question = TranscriptSegment(speakerID: speaker.id, startTime: 4, endTime: 8, text: "What changed?")
        let answer = TranscriptSegment(startTime: 9, endTime: 15, text: "The workflow became simpler.", isQuote: true, needsReview: true)
        let interview = Interview(
            title: "Research session",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 96,
            audioFilename: "recording.m4a",
            speakers: [speaker],
            segments: [question, answer],
            bookmarks: [Bookmark(time: 9, note: "Follow up here")],
            questions: [QuestionAnswer(questionSegmentID: question.id, answerSegmentIDs: [answer.id], status: .partial, followUp: "Ask for an example")],
            notes: "Useful session notes",
            processingState: .ready
        )
        let repository = InterviewRepository(directory: directory)

        try repository.save([interview])

        XCTAssertEqual(try repository.load(), [interview])
        XCTAssertEqual(try repository.load().first?.questions.first?.answerSegmentIDs, [answer.id])
    }

    func testMissingRepositoryStartsEmpty() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(try InterviewRepository(directory: directory).load(), [])
    }

    func testCorruptRepositoryThrowsWithoutErasingFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent("interviews.json")
        let corruptData = Data("{this is not valid JSON".utf8)
        try corruptData.write(to: indexURL)

        XCTAssertThrowsError(try InterviewRepository(directory: directory).load())
        XCTAssertEqual(try Data(contentsOf: indexURL), corruptData)
    }

    func testAudioURLRemainsInsideRepositoryDirectory() {
        let directory = temporaryDirectory()
        let url = InterviewRepository(directory: directory).audioURL(filename: "../../outside/recording.m4a")

        XCTAssertEqual(url.lastPathComponent, "recording.m4a")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
    }

    func testRenamingSpeakerUpdatesExistingSegmentLookup() {
        let speaker = Speaker(name: "Speaker A")
        let segment = TranscriptSegment(speakerID: speaker.id, text: "A stable relationship.")
        var interview = Interview(speakers: [speaker], segments: [segment])

        interview.speakers[0].name = "Researcher"

        XCTAssertEqual(interview.speakerName(for: interview.segments[0].speakerID), "Researcher")
        XCTAssertEqual(interview.segments[0].speakerID, speaker.id)
        XCTAssertEqual(interview.speakerName(for: nil), "Unknown speaker")
        XCTAssertEqual(interview.speakerName(for: UUID()), "Unknown speaker")
    }

    func testSuggestedQuestionsKeepAnswersWithTheCorrectQuestion() {
        let opening = TranscriptSegment(text: "Thank you for joining.")
        let firstQuestion = TranscriptSegment(startTime: 3, text: "What is working? ")
        let firstAnswer = TranscriptSegment(startTime: 5, text: "Sharing notes is easy.")
        let secondAnswer = TranscriptSegment(startTime: 9, text: "Search also helps.")
        let secondQuestion = TranscriptSegment(startTime: 14, text: "What would you improve?")
        let thirdAnswer = TranscriptSegment(startTime: 17, text: "I would add a review step.")
        let unansweredQuestion = TranscriptSegment(startTime: 20, text: "Anything else?")

        let questions = LocalReview.suggestQuestions(segments: [opening, firstQuestion, firstAnswer, secondAnswer, secondQuestion, thirdAnswer, unansweredQuestion])

        XCTAssertEqual(questions.map(\.questionSegmentID), [firstQuestion.id, secondQuestion.id, unansweredQuestion.id])
        XCTAssertEqual(questions.map(\.answerSegmentIDs), [[firstAnswer.id, secondAnswer.id], [thirdAnswer.id], []])
        XCTAssertTrue(questions.allSatisfy { $0.status == .needsReview })
    }

    func testQuestionSuggestionsHaveStableIdentityAcrossRepeatedReview() {
        let question = TranscriptSegment(text: "What changed?")
        let answer = TranscriptSegment(text: "We simplified the workflow.")
        let segments = [question, answer]

        let firstReview = LocalReview.suggestQuestions(segments: segments)
        let secondReview = LocalReview.suggestQuestions(segments: segments)

        XCTAssertEqual(firstReview, secondReview)
        XCTAssertEqual(firstReview.first?.id, question.id)
    }

    func testRefreshingQuestionsPreservesReviewEditsAndUpdatesTranscriptGrouping() {
        let retainedQuestion = TranscriptSegment(text: "What improved?")
        let originalAnswer = TranscriptSegment(text: "Sharing notes is easier.")
        let removedQuestion = TranscriptSegment(text: "What should we ask next?")
        let customQuestionID = UUID()
        let existing = [
            QuestionAnswer(id: customQuestionID, questionSegmentID: retainedQuestion.id, answerSegmentIDs: [originalAnswer.id], status: .answered, followUp: "Ask for a specific example."),
            QuestionAnswer(questionSegmentID: removedQuestion.id, status: .partial, followUp: "This question was removed.")
        ]
        let addedAnswer = TranscriptSegment(text: "It also reduces duplicated work.")
        let newQuestion = TranscriptSegment(text: "What remains difficult?")
        let newAnswer = TranscriptSegment(text: "Finding the right session.")

        let refreshed = LocalReview.suggestQuestions(
            segments: [retainedQuestion, originalAnswer, addedAnswer, newQuestion, newAnswer],
            preserving: existing
        )

        XCTAssertEqual(refreshed.map(\.questionSegmentID), [retainedQuestion.id, newQuestion.id])
        XCTAssertEqual(refreshed[0].id, customQuestionID)
        XCTAssertEqual(refreshed[0].status, .answered)
        XCTAssertEqual(refreshed[0].followUp, "Ask for a specific example.")
        XCTAssertEqual(refreshed[0].answerSegmentIDs, [originalAnswer.id, addedAnswer.id])
        XCTAssertEqual(refreshed[1].status, .needsReview)
        XCTAssertEqual(refreshed[1].followUp, "")
        XCTAssertEqual(refreshed[1].answerSegmentIDs, [newAnswer.id])
    }

    func testQuestionEditedIntoStatementNoLongerAppearsInReview() {
        var question = TranscriptSegment(text: "Was the workflow useful?")
        let existing = LocalReview.suggestQuestions(segments: [question])
        question.text = "The workflow was useful."

        let refreshed = LocalReview.suggestQuestions(segments: [question], preserving: existing)

        XCTAssertTrue(refreshed.isEmpty)
    }

    func testFollowUpsIgnoreWhitespaceOnlyDrafts() {
        var interview = Interview(questions: [QuestionAnswer(questionSegmentID: UUID(), status: .answered, followUp: " \n\t ")])

        XCTAssertFalse(interview.hasFollowUps)

        interview.questions[0].followUp = " \nAsk for a concrete example. \t"

        XCTAssertTrue(interview.hasFollowUps)
    }

    func testFollowUpFilterClearsAsTranscriptAndQuestionsAreResolved() {
        var interview = Interview(
            segments: [TranscriptSegment(text: "Confirm this transcript.", needsReview: true)],
            questions: [QuestionAnswer(questionSegmentID: UUID(), status: .needsReview)]
        )

        XCTAssertTrue(interview.hasFollowUps)

        interview.segments[0].needsReview = false
        XCTAssertTrue(interview.hasFollowUps)

        interview.questions[0].status = .partial
        XCTAssertTrue(interview.hasFollowUps)

        interview.questions[0].status = .answered
        XCTAssertFalse(interview.hasFollowUps)

        interview.segments[0].needsReview = true
        XCTAssertTrue(interview.hasFollowUps)
    }

    func testTranscriptExportUsesRenamedSpeakerAndLabelsSampleWithoutAudio() {
        let speaker = Speaker(name: "Speaker A")
        let segment = TranscriptSegment(speakerID: speaker.id, startTime: 65, text: "A useful observation.")
        var interview = Interview(title: "Sample study", speakers: [speaker], segments: [segment], notes: "Review this insight.", isDemo: true)
        interview.speakers[0].name = "Researcher"

        let export = interview.exportTranscript()

        XCTAssertTrue(export.contains("[01:05] Researcher"))
        XCTAssertTrue(export.contains(segment.text))
        XCTAssertTrue(export.contains("Sample interview · no audio attached"))
        XCTAssertTrue(export.contains(interview.notes))
        XCTAssertFalse(export.contains("Speaker A"))
    }

    func testTimestampFormattingClampsInvalidInputAndUsesHoursWhenNeeded() {
        XCTAssertEqual(TimeFormatting.timestamp(-8), "00:00")
        XCTAssertEqual(TimeFormatting.timestamp(.nan), "00:00")
        XCTAssertEqual(TimeFormatting.timestamp(.infinity), "00:00")
        XCTAssertEqual(TimeFormatting.timestamp(59.99), "00:59")
        XCTAssertEqual(TimeFormatting.timestamp(65), "01:05")
        XCTAssertEqual(TimeFormatting.timestamp(65, includeHours: true), "0:01:05")
        XCTAssertEqual(TimeFormatting.timestamp(3_661), "1:01:01")
    }

    func testSearchIncludesTitlePeopleTranscriptAndNotes() {
        let interview = Interview(
            title: "Design study",
            speakers: [Speaker(name: "Researcher")],
            segments: [TranscriptSegment(text: "A memorable observation")],
            notes: "Clarify the timeline"
        )
        let searchText = interview.searchText.lowercased()

        for term in ["design study", "researcher", "memorable observation", "clarify the timeline"] {
            XCTAssertTrue(searchText.contains(term), "Missing searchable content: \(term)")
        }
    }

    func testDemoInterviewsHaveNoRealAudioReference() {
        let interviews = DemoData.interviews

        XCTAssertGreaterThanOrEqual(interviews.count, 3)
        XCTAssertTrue(interviews.allSatisfy(\.isDemo))
        XCTAssertTrue(interviews.allSatisfy { $0.audioFilename == nil })
        XCTAssertTrue(interviews.allSatisfy { !$0.segments.isEmpty })
        XCTAssertEqual(Set(interviews.map(\.id)).count, interviews.count)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SubtextCoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
