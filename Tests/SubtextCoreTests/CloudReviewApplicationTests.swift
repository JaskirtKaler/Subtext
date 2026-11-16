import Foundation
import XCTest
@testable import SubtextCore

final class CloudReviewApplicationTests: XCTestCase {
    func testMonologueKeepsExactlyOneSpeakerAcrossTurnsAndPersistence() throws {
        let original = Interview(duration: 12, audioFilename: "monologue.m4a")
        let result = CloudReviewResult(turns: [
            CloudTurn(speaker: "Speaker A", startTime: 0, endTime: 3, text: "This is my recording."),
            CloudTurn(speaker: "Speaker A", startTime: 4, endTime: 7, text: "What am I testing?"),
            CloudTurn(speaker: "Speaker A", startTime: 8, endTime: 11, text: "Only my own voice is speaking.")
        ], summary: "One person describes a recording test.", insights: [], questions: [])

        let reviewed = try ReviewApplication.applying(result, to: original)
        XCTAssertEqual(reviewed.speakers.count, 1)
        let speaker = try XCTUnwrap(reviewed.speakers.first)
        XCTAssertEqual(speaker.name, "Speaker A")
        XCTAssertEqual(reviewed.segments.count, 3)
        XCTAssertTrue(reviewed.segments.allSatisfy { $0.speakerID == speaker.id })
        XCTAssertEqual(reviewed.questions, [])
        XCTAssertEqual(reviewed.processingState, .ready)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SubtextSingleSpeaker-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = InterviewRepository(directory: directory)
        try repository.save([reviewed])
        let loaded = try XCTUnwrap(repository.load().first)
        XCTAssertEqual(loaded.speakers, [speaker])
        XCTAssertTrue(loaded.segments.allSatisfy { $0.speakerID == speaker.id })
        XCTAssertEqual(loaded.audioFilename, original.audioFilename)
    }

    func testCloudDraftCanBeCorrectedReviewedSavedSearchedAndExported() throws {
        let bookmark = Bookmark(time: 6, note: "Return to the second question")
        let original = Interview(
            title: "Community project",
            createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            duration: 20,
            audioFilename: "original-recording.m4a",
            bookmarks: [bookmark],
            notes: "My reporting notes: confirm the opening date.",
            processingState: .transcribing
        )
        let result = CloudReviewResult(turns: [
            CloudTurn(speaker: "Speaker A", startTime: 0, endTime: 2, text: "How did the project start?"),
            CloudTurn(speaker: "Speaker B", startTime: 2, endTime: 5, text: "We met at a planting day."),
            CloudTurn(speaker: "Unassigned", startTime: 5, endTime: 6, text: "With our neighbours."),
            CloudTurn(speaker: "Speaker A", startTime: 6, endTime: 8, text: "What happens next?"),
            CloudTurn(speaker: "Speaker O", startTime: 8, endTime: 12, text: "A shared watering schedule."),
            CloudTurn(speaker: "Speaker B", startTime: 12, endTime: 16, text: "Everyone can choose a day.")
        ], summary: "  Speakers described a collective gardening project. Check the draft against the original audio.  ")

        var reviewed = try ReviewApplication.applying(result, to: original)

        XCTAssertEqual(reviewed.id, original.id)
        XCTAssertEqual(reviewed.title, original.title)
        XCTAssertEqual(reviewed.createdAt, original.createdAt)
        XCTAssertEqual(reviewed.duration, original.duration)
        XCTAssertEqual(reviewed.audioFilename, original.audioFilename)
        XCTAssertEqual(reviewed.bookmarks, [bookmark])
        XCTAssertEqual(reviewed.notes, original.notes)
        XCTAssertEqual(reviewed.isDemo, original.isDemo)
        XCTAssertEqual(reviewed.processingState, .ready)
        XCTAssertEqual(reviewed.aiSummary, result.summary.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(reviewed.speakers.map(\.name), ["Speaker A", "Speaker B", "Speaker O"])
        XCTAssertEqual(reviewed.speakers.map(\.color), [.blue, .purple, .green])
        XCTAssertTrue(reviewed.speakers.allSatisfy { $0.role.isEmpty })
        XCTAssertEqual(reviewed.segments[0].speakerID, reviewed.segments[3].speakerID)
        XCTAssertEqual(reviewed.segments[1].speakerID, reviewed.segments[5].speakerID)
        XCTAssertNil(reviewed.segments[2].speakerID)
        XCTAssertEqual(reviewed.questions.count, 2)
        XCTAssertEqual(reviewed.questions[0].answerSegmentIDs, [reviewed.segments[1].id, reviewed.segments[2].id])
        XCTAssertTrue(reviewed.questions.allSatisfy { $0.status == .needsReview })

        // A reporter corrects attribution without breaking the Q&A relationships.
        let correctedSpeakerID = try XCTUnwrap(reviewed.segments[1].speakerID)
        let speakerIndex = try XCTUnwrap(reviewed.speakers.firstIndex { $0.id == correctedSpeakerID })
        reviewed.speakers[speakerIndex].name = "Casey"
        reviewed.speakers[speakerIndex].role = "Garden coordinator"
        reviewed.segments[2].speakerID = correctedSpeakerID
        reviewed.segments[1].isQuote = true
        reviewed.segments[2].needsReview = true
        reviewed.questions[0].status = .partial
        reviewed.questions[0].followUp = "Confirm who attended the first planting day."
        reviewed.questions = LocalReview.suggestQuestions(segments: reviewed.segments, preserving: reviewed.questions)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SubtextCloudWorkflow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = InterviewRepository(directory: directory)
        try repository.save([reviewed])
        let loaded = try XCTUnwrap(repository.load().first)

        XCTAssertEqual(loaded, reviewed)
        XCTAssertEqual(loaded.speakerName(for: loaded.segments[2].speakerID), "Casey")
        XCTAssertTrue(loaded.segments[1].isQuote)
        XCTAssertTrue(loaded.segments[2].needsReview)
        XCTAssertEqual(loaded.questions[0].status, .partial)
        XCTAssertTrue(loaded.hasFollowUps)
        XCTAssertTrue(loaded.searchText.contains("collective gardening"))
        XCTAssertTrue(loaded.searchText.contains("Garden coordinator"))
        XCTAssertTrue(loaded.searchText.contains("Confirm who attended"))
        let exported = loaded.exportTranscript()
        XCTAssertTrue(exported.contains("[00:05] Casey\nWith our neighbours."))
        XCTAssertTrue(exported.contains("AI draft summary\n\(loaded.aiSummary)"))
        XCTAssertTrue(exported.contains("Notes\n\(original.notes)"))
        XCTAssertEqual(original.notes, "My reporting notes: confirm the opening date.")
        XCTAssertEqual(original.segments, [])
    }

    func testReprocessingReplacesDraftButPreservesRecordingAndUserMaterial() throws {
        let oldSpeaker = Speaker(name: "Corrected name")
        let oldSegment = TranscriptSegment(speakerID: oldSpeaker.id, text: "Old draft", isQuote: true, needsReview: true)
        let original = Interview(
            title: "Original title",
            duration: 12,
            audioFilename: "source.m4a",
            speakers: [oldSpeaker],
            segments: [oldSegment],
            bookmarks: [Bookmark(time: 3, note: "User bookmark")],
            questions: [QuestionAnswer(questionSegmentID: oldSegment.id, followUp: "Old follow-up")],
            notes: "Keep my notes",
            aiSummary: "Old summary",
            processingState: .failed
        )
        let result = CloudReviewResult(turns: [
            CloudTurn(speaker: "Speaker A", startTime: 1, endTime: 4, text: "A replacement draft.")
        ], summary: "A new summary.")

        let replaced = try ReviewApplication.applying(result, to: original)

        XCTAssertEqual(replaced.id, original.id)
        XCTAssertEqual(replaced.audioFilename, original.audioFilename)
        XCTAssertEqual(replaced.bookmarks, original.bookmarks)
        XCTAssertEqual(replaced.notes, "Keep my notes")
        XCTAssertEqual(replaced.aiSummary, "A new summary.")
        XCTAssertEqual(replaced.questions, [])
        XCTAssertEqual(replaced.speakers.first?.name, "Speaker A")
        XCTAssertNotEqual(replaced.speakers.first?.id, oldSpeaker.id)
        XCTAssertNotEqual(replaced.segments.first?.id, oldSegment.id)
        XCTAssertFalse(try XCTUnwrap(replaced.segments.first).isQuote)
        XCTAssertFalse(try XCTUnwrap(replaced.segments.first).needsReview)
        XCTAssertEqual(original.aiSummary, "Old summary")
    }

    func testInvalidCloudDraftsLeaveOriginalValueUnchanged() {
        let original = Interview(
            title: "Keep this interview",
            duration: 10,
            audioFilename: "original.m4a",
            segments: [TranscriptSegment(startTime: 0, endTime: 4, text: "Existing edited text")],
            notes: "Reporter notes",
            aiSummary: "Existing summary"
        )
        let snapshot = original
        let validTurn = CloudTurn(speaker: "Speaker A", startTime: 0, endTime: 2, text: "Hello.")
        let invalidDrafts = [
            CloudReviewResult(turns: [validTurn], summary: " \n"),
            CloudReviewResult(turns: [CloudTurn(speaker: "A named person", startTime: 0, endTime: 2, text: "Hello.")], summary: "Summary"),
            CloudReviewResult(turns: [CloudTurn(speaker: "Speaker P", startTime: 0, endTime: 2, text: "Hello.")], summary: "Summary"),
            CloudReviewResult(turns: [CloudTurn(speaker: "Speaker A", startTime: -1, endTime: 2, text: "Hello.")], summary: "Summary"),
            CloudReviewResult(turns: [CloudTurn(speaker: "Speaker A", startTime: 2, endTime: 2, text: "Hello.")], summary: "Summary"),
            CloudReviewResult(turns: [CloudTurn(speaker: "Speaker A", startTime: 0, endTime: 11, text: "Hello.")], summary: "Summary"),
            CloudReviewResult(turns: [CloudTurn(speaker: "Speaker A", startTime: .nan, endTime: 2, text: "Hello.")], summary: "Summary"),
            CloudReviewResult(turns: [CloudTurn(speaker: "Speaker A", startTime: 0, endTime: .infinity, text: "Hello.")], summary: "Summary"),
            CloudReviewResult(turns: [CloudTurn(speaker: "Speaker A", startTime: 0, endTime: 2, text: "\n\t")], summary: "Summary"),
            CloudReviewResult(turns: [
                CloudTurn(speaker: "Speaker A", startTime: 4, endTime: 8, text: "Later."),
                CloudTurn(speaker: "Speaker B", startTime: 3, endTime: 7, text: "Earlier.")
            ], summary: "Summary")
        ]

        for draft in invalidDrafts {
            XCTAssertThrowsError(try ReviewApplication.applying(draft, to: original)) { error in
                XCTAssertEqual(error as? ReviewApplicationError, .invalidResponse)
            }
            XCTAssertEqual(original, snapshot)
        }
        XCTAssertThrowsError(try ReviewApplication.applying(CloudReviewResult(turns: [], summary: "No speech identified."), to: original)) { error in
            XCTAssertEqual(error as? ReviewApplicationError, .noSpeech)
        }
        XCTAssertEqual(original, snapshot)
    }

    func testOverlappingSpeechRemainsChronologicalWithoutInventingAttribution() throws {
        let result = CloudReviewResult(turns: [
            CloudTurn(speaker: " Speaker B ", startTime: 1, endTime: 5, text: " First voice. "),
            CloudTurn(speaker: "Unassigned", startTime: 2, endTime: 4, text: "An overlapping voice.")
        ], summary: "Overlapping speech. Review attribution.")

        let applied = try ReviewApplication.applying(result, to: Interview(duration: 6))

        XCTAssertEqual(applied.speakers.map(\.name), ["Speaker B"])
        XCTAssertEqual(applied.speakers.map(\.color), [.purple])
        XCTAssertEqual(applied.segments[0].text, "First voice.")
        XCTAssertNil(applied.segments[1].speakerID)
    }

    func testLegacyInterviewWithoutSummaryLoadsAndMigratesWithoutChangingNotes() throws {
        let session = Interview(title: "Before AI summaries", duration: 8, notes: "Original user notes")
        let data = try JSONEncoder().encode([session])
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        objects[0].removeValue(forKey: "aiSummary")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SubtextLegacy-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent("interviews.json")
        try JSONSerialization.data(withJSONObject: objects).write(to: indexURL)

        let repository = InterviewRepository(directory: directory)
        let migrated = try XCTUnwrap(repository.load().first)

        XCTAssertEqual(migrated, session)
        XCTAssertEqual(migrated.aiSummary, "")
        XCTAssertEqual(migrated.notes, "Original user notes")
        try repository.save([migrated])
        let savedObjects = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [[String: Any]])
        XCTAssertEqual(savedObjects[0]["aiSummary"] as? String, "")
    }

    func testSummaryMigrationDoesNotHideMalformedValuesOrOtherMissingFields() throws {
        let session = Interview(title: "Strict decoding", notes: "Keep me")
        let data = try JSONEncoder().encode(session)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let invalidSummaries: [Any] = [42, NSNull()]
        for invalidSummary in invalidSummaries {
            var malformed = object
            malformed["aiSummary"] = invalidSummary
            let malformedData = try JSONSerialization.data(withJSONObject: malformed)
            XCTAssertThrowsError(try JSONDecoder().decode(Interview.self, from: malformedData))
        }
        var missingTitle = object
        missingTitle.removeValue(forKey: "title")
        missingTitle.removeValue(forKey: "aiSummary")
        XCTAssertThrowsError(try JSONDecoder().decode(Interview.self, from: JSONSerialization.data(withJSONObject: missingTitle)))
    }
}
