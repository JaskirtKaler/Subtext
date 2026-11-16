import XCTest
@testable import SubtextCore

final class TranscriptOrderTests: XCTestCase {
    func testEditingAndAddingTurnsKeepsChronologicalOrderAndStableIdentity() {
        let speaker = Speaker(name: "Speaker A")
        var early = TranscriptSegment(speakerID: speaker.id, startTime: 2, endTime: 4, text: "First")
        let later = TranscriptSegment(startTime: 8, endTime: 12, text: "Second")
        var session = Interview(segments: [early, later])
        early.startTime = 14
        early.endTime = 18
        session.upsertSegment(early)
        XCTAssertEqual(session.segments.map(\.id), [later.id, early.id])
        XCTAssertEqual(session.segments.last?.speakerID, speaker.id)
        let inserted = TranscriptSegment(startTime: 1, endTime: 2, text: "Inserted")
        session.upsertSegment(inserted)
        XCTAssertEqual(session.segments.map(\.startTime), [1, 8, 14])
        XCTAssertEqual(Set(session.segments.map(\.id)).count, 3)
    }
}
