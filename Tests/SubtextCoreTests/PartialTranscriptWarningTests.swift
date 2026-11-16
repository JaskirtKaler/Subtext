import Foundation
import XCTest
@testable import SubtextCore

final class PartialTranscriptWarningTests: XCTestCase {
    func testPartialTranscriptWarningSurvivesCorrectionsAnalysisAndPersistence() throws {
        let speaker = Speaker(name: "Corrected speaker")
        let segment = TranscriptSegment(speakerID: speaker.id, startTime: 0, endTime: 3, text: "Recognized text.")
        let warning = "Partial transcript: no speech was recognized from 00:45 to 01:30. Review the original audio."
        var session = Interview(
            duration: 120,
            audioFilename: "original.m4a",
            speakers: [speaker],
            segments: [segment],
            notes: "My notes",
            processingError: "An old processing failure",
            transcriptionWarning: warning,
            processingState: .ready
        )
        var corrected = segment
        corrected.text = "Corrected recognized text."
        corrected.isQuote = true
        session.upsertSegment(corrected)
        let analysis = CloudAnalysisResult(
            summary: "An analysis of the available transcript.",
            insights: [CloudInsight(kind: .needsContext, title: "Check the missing interval", detail: "Review the original audio before drawing conclusions.", evidenceTurnIndices: [0])]
        )

        let analyzed = try ReviewApplication.applying(analysis, to: session)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SubtextWarning-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = InterviewRepository(directory: directory)
        try repository.save([analyzed])
        let restored = try XCTUnwrap(repository.load().first)

        XCTAssertEqual(restored.transcriptionWarning, warning)
        XCTAssertEqual(restored.segments, session.segments)
        XCTAssertEqual(restored.speakers, session.speakers)
        XCTAssertTrue(restored.segments[0].isQuote)
        XCTAssertNil(restored.processingError)
        XCTAssertEqual(restored.notes, "My notes")
        XCTAssertTrue(restored.searchText.contains("00:45 to 01:30"))
        XCTAssertTrue(restored.exportTranscript().contains("Transcription warning: \(warning)"))
    }

    func testWholeAudioReplacementClearsPartialWarningAndFlagsUncertainTurns() throws {
        let original = Interview(duration: 12, audioFilename: "original.m4a", notes: "Keep my notes", transcriptionWarning: "An earlier partial transcript had a gap.")
        let result = CloudReviewResult(
            turns: [
                CloudTurn(speaker: "Speaker A", startTime: 0, endTime: 2, text: "[INAUDIBLE]"),
                CloudTurn(speaker: "Unassigned", startTime: 2, endTime: 5, text: "An uncertain speaker."),
                CloudTurn(speaker: "Speaker B", startTime: 5, endTime: 9, text: "A clearly attributed draft turn.")
            ],
            summary: "A new draft of the whole audio. Review it against the recording.",
            insights: [],
            questions: []
        )

        let replaced = try ReviewApplication.applying(result, to: original)

        XCTAssertNil(replaced.transcriptionWarning)
        XCTAssertEqual(replaced.segments.map(\.needsReview), [true, true, false])
        XCTAssertNil(replaced.segments[1].speakerID)
        XCTAssertTrue(replaced.hasFollowUps)
        XCTAssertEqual(replaced.audioFilename, original.audioFilename)
        XCTAssertEqual(replaced.notes, original.notes)
        XCTAssertNotNil(original.transcriptionWarning)
    }

    func testLegacyMissingWarningDefaultsNilWhileWrongTypeRemainsCorruption() throws {
        let session = Interview(title: "Legacy", processingError: "A separate failure", transcriptionWarning: "A saved warning")
        let data = try JSONEncoder().encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "transcriptionWarning")

        let migrated = try JSONDecoder().decode(Interview.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertNil(migrated.transcriptionWarning)
        XCTAssertEqual(migrated.processingError, "A separate failure")
        object["transcriptionWarning"] = 1110
        XCTAssertThrowsError(try JSONDecoder().decode(Interview.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}
