#if canImport(Subtext) || canImport(SubtextAudioValidation)
import AVFoundation
import XCTest
#if canImport(SubtextAudioValidation)
@testable import SubtextAudioValidation
#else
@testable import Subtext
#endif

final class AudioRecorderRecoveryTests: XCTestCase {
    @MainActor
    func testNoRecoveryMarkerReturnsNoRecording() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(try AudioRecorder.recoveryMetadata(in: directory))
        XCTAssertNil(try AudioRecorder.recoverableRecording(in: directory))
        try AudioRecorder.clearRecoveryMetadata(in: directory)
    }

    @MainActor
    func testRecoveryMetadataPreservesFilenameAndStartDate() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try writeMarker(filename: "interrupted.wav", startedAt: startedAt, in: directory)

        let metadata = try XCTUnwrap(AudioRecorder.recoveryMetadata(in: directory))

        XCTAssertEqual(metadata.filename, "interrupted.wav")
        XCTAssertEqual(metadata.startedAt, startedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker(in: directory).path))
    }

    @MainActor
    func testReadablePCMRecoveryLeavesAudioAndMarkerUntilExplicitClear() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try AudioTestFixtures.writePCM(in: directory, filename: "interrupted.wav", duration: 1.25)
        try writeMarker(filename: fixture.lastPathComponent, in: directory)
        let originalAudio = try Data(contentsOf: fixture)
        let originalMarker = try Data(contentsOf: marker(in: directory))

        let recovered = try XCTUnwrap(AudioRecorder.recoverableRecording(in: directory))

        XCTAssertEqual(recovered.filename, fixture.lastPathComponent)
        XCTAssertEqual(recovered.duration, 1.25, accuracy: 0.01)
        XCTAssertEqual(try Data(contentsOf: fixture), originalAudio)
        XCTAssertEqual(try Data(contentsOf: marker(in: directory)), originalMarker)
        try AudioRecorder.clearRecoveryMetadata(in: directory)
        try AudioRecorder.clearRecoveryMetadata(in: directory)
        XCTAssertNil(try AudioRecorder.recoveryMetadata(in: directory))
        XCTAssertEqual(try Data(contentsOf: fixture), originalAudio)
    }

    @MainActor
    func testRecoveryRejectsTraversalAndAbsolutePathsWithoutChangingFiles() throws {
        let root = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordings = root.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let outside = try AudioTestFixtures.writePCM(in: root, filename: "outside.wav")
        let originalAudio = try Data(contentsOf: outside)

        for filename in ["", "../outside.wav", outside.path, "nested/outside.wav"] {
            try writeMarker(filename: filename, in: recordings)
            let originalMarker = try Data(contentsOf: marker(in: recordings))
            assertUnreadableRecovery(in: recordings)
            XCTAssertEqual(try Data(contentsOf: marker(in: recordings)), originalMarker)
            XCTAssertEqual(try Data(contentsOf: outside), originalAudio)
        }
    }

    @MainActor
    func testMalformedMetadataIsRetainedForInspection() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let malformed = Data("{\"filename\":\"interrupted.wav\"".utf8)
        try malformed.write(to: marker(in: directory))

        XCTAssertThrowsError(try AudioRecorder.recoveryMetadata(in: directory))
        XCTAssertThrowsError(try AudioRecorder.recoverableRecording(in: directory))
        XCTAssertEqual(try Data(contentsOf: marker(in: directory)), malformed)
    }

    @MainActor
    func testMissingAudioRecoveryRetainsMarker() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeMarker(filename: "missing.wav", in: directory)
        let original = try Data(contentsOf: marker(in: directory))

        assertUnreadableRecovery(in: directory)

        XCTAssertEqual(try Data(contentsOf: marker(in: directory)), original)
    }

    @MainActor
    func testEmptyAndInvalidAudioAreRetainedAfterRecoveryFailure() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for data in [Data(), Data("unfinalized audio fixture".utf8)] {
            let fixture = directory.appendingPathComponent("interrupted.m4a")
            try data.write(to: fixture)
            try writeMarker(filename: fixture.lastPathComponent, in: directory)

            assertUnreadableRecovery(in: directory)

            XCTAssertEqual(try Data(contentsOf: fixture), data)
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker(in: directory).path))
        }
    }

    @MainActor
    func testKeepFileAndCloseWithoutActiveCaptureIsSafeAndKeepsRecoveryData() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try AudioTestFixtures.writePCM(in: directory)
        try writeMarker(filename: fixture.lastPathComponent, in: directory)
        let originalAudio = try Data(contentsOf: fixture)
        let originalMarker = try Data(contentsOf: marker(in: directory))
        let permissionBefore = AVAudioApplication.shared.recordPermission
        let recorder = AudioRecorder(directory: directory)

        XCTAssertNil(recorder.keepFileAndClose())
        XCTAssertNil(recorder.keepFileAndClose())

        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(recorder.isPaused)
        XCTAssertNil(recorder.activeFilename)
        XCTAssertEqual(recorder.elapsed, 0)
        XCTAssertEqual(try Data(contentsOf: fixture), originalAudio)
        XCTAssertEqual(try Data(contentsOf: marker(in: directory)), originalMarker)
        XCTAssertEqual(AVAudioApplication.shared.recordPermission, permissionBefore)
    }

    @MainActor
    func testIdlePauseResumeAndFinishDoNotRequestMicrophonePermission() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let permissionBefore = AVAudioApplication.shared.recordPermission
        let recorder = AudioRecorder(directory: directory)

        recorder.pause()
        try recorder.resume()
        XCTAssertEqual(recorder.addBookmarkTime(), 0)
        XCTAssertThrowsError(try recorder.finish()) { error in
            guard case .noRecording? = error as? AudioRecordingError else { return XCTFail("Expected noRecording, got \(error)") }
        }

        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(recorder.isPaused)
        XCTAssertEqual(AVAudioApplication.shared.recordPermission, permissionBefore)
        XCTAssertNil(try AudioRecorder.recoveryMetadata(in: directory))
    }

    private func marker(in directory: URL) -> URL { directory.appendingPathComponent("ActiveRecording.json") }

    private func writeMarker(filename: String, startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000), in directory: URL) throws {
        try JSONEncoder().encode(ActiveRecordingMetadata(filename: filename, startedAt: startedAt)).write(to: marker(in: directory), options: .atomic)
    }

    @MainActor
    private func assertUnreadableRecovery(in directory: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try AudioRecorder.recoverableRecording(in: directory), file: file, line: line) { error in
            guard case .unreadableRecording? = error as? AudioRecordingError else {
                return XCTFail("Expected unreadableRecording, got \(error)", file: file, line: line)
            }
        }
    }
}
#endif
