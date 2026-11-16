#if canImport(Subtext) || canImport(SubtextAudioValidation)
import AVFoundation
import XCTest
#if canImport(SubtextAudioValidation)
@testable import SubtextAudioValidation
#else
@testable import Subtext
#endif

final class AudioPlayerTests: XCTestCase {
    @MainActor
    func testLoadingPCMReadsDurationWithoutStartingPlayback() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try AudioTestFixtures.writePCM(in: directory, duration: 1.25)
        let player = AudioPlayer()
        defer { player.stop() }

        try player.load(url: fixture)

        XCTAssertTrue(player.hasAudio)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.duration, 1.25, accuracy: 0.01)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.rate, 1)
        XCTAssertNil(player.errorMessage)
    }

    @MainActor
    func testSeekingAndSkippingStayWithinAudioBoundsAndIgnoreNonfiniteValues() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let player = AudioPlayer()
        defer { player.stop() }
        try player.load(url: AudioTestFixtures.writePCM(in: directory, duration: 2))

        player.seek(to: -20)
        XCTAssertEqual(player.currentTime, 0)
        player.seek(to: 200)
        XCTAssertEqual(player.currentTime, player.duration)
        player.skip(-0.25)
        XCTAssertEqual(player.currentTime, player.duration - 0.25, accuracy: 0.01)
        player.skip(200)
        XCTAssertEqual(player.currentTime, player.duration)
        player.skip(-200)
        XCTAssertEqual(player.currentTime, 0)

        player.seek(to: 0.75)
        for invalid in [Double.nan, .infinity, -.infinity] {
            player.seek(to: invalid)
            player.skip(invalid)
            XCTAssertEqual(player.currentTime, 0.75, accuracy: 0.01)
        }
        XCTAssertFalse(player.isPlaying)
    }

    @MainActor
    func testPlaybackRateClampsAndPersistsWhenAnotherFileLoads() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let player = AudioPlayer()
        defer { player.stop() }
        player.setRate(1.5)
        try player.load(url: AudioTestFixtures.writePCM(in: directory, filename: "first.wav"))
        XCTAssertEqual(player.rate, 1.5)
        try player.load(url: AudioTestFixtures.writePCM(in: directory, filename: "second.wav", duration: 0.5))
        XCTAssertEqual(player.rate, 1.5)

        player.setRate(9)
        XCTAssertEqual(player.rate, 2)
        player.setRate(-1)
        XCTAssertEqual(player.rate, 0.5)
        for invalid in [Float.nan, .infinity, -.infinity] {
            player.setRate(invalid)
            XCTAssertEqual(player.rate, 0.5)
        }
    }

    @MainActor
    func testStopResetsPositionAndKeepsLoadedAudioReady() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let player = AudioPlayer()
        try player.load(url: AudioTestFixtures.writePCM(in: directory))
        player.seek(to: 0.5)

        player.stop()
        player.stop()

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertTrue(player.hasAudio)
        XCTAssertEqual(player.duration, 1, accuracy: 0.01)
    }

    @MainActor
    func testInvalidOrMissingSelectionClearsPreviouslyLoadedAudio() throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try AudioTestFixtures.writePCM(in: directory)
        let invalid = directory.appendingPathComponent("invalid.m4a")
        try Data("This is not an audio file.".utf8).write(to: invalid)
        let missing = directory.appendingPathComponent("missing.wav")
        let player = AudioPlayer()
        defer { player.stop() }

        for unreadable in [invalid, missing] {
            try player.load(url: fixture)
            player.seek(to: 0.5)
            XCTAssertThrowsError(try player.load(url: unreadable))
            XCTAssertFalse(player.hasAudio)
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(player.duration, 0)
            XCTAssertEqual(player.currentTime, 0)
            XCTAssertNotNil(player.errorMessage)
            XCTAssertThrowsError(try player.playPause()) { error in
                guard case .noAudio? = error as? AudioPlaybackError else {
                    return XCTFail("Expected noAudio after failed selection, got \(error)")
                }
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalid.path))
    }

    @MainActor
    func testPlayWithoutAudioReportsFailureAndKeepsIdleState() {
        let player = AudioPlayer()
        XCTAssertThrowsError(try player.playPause()) { error in
            guard case .noAudio? = error as? AudioPlaybackError else { return XCTFail("Expected noAudio, got \(error)") }
        }
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.hasAudio)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertNotNil(player.errorMessage)
    }

    @MainActor
    func testRealPCMPlaybackAdvancesThenPauseAndStopHoldTheClock() async throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let player = AudioPlayer()
        defer { player.stop() }
        try player.load(url: AudioTestFixtures.writePCM(in: directory, duration: 2, amplitude: 0.03))
        try player.playPause()
        XCTAssertTrue(player.isPlaying)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertGreaterThan(player.currentTime, 0)
        XCTAssertLessThan(player.currentTime, player.duration)

        try player.playPause()
        let pausedAt = player.currentTime
        XCTAssertFalse(player.isPlaying)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(player.currentTime, pausedAt, accuracy: 0.02)
        player.stop()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertTrue(player.hasAudio)
    }

    @MainActor
    func testRealPCMPlaybackCompletionCanRestartFromBeginning() async throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let player = AudioPlayer()
        defer { player.stop() }
        try player.load(url: AudioTestFixtures.writePCM(in: directory, duration: 0.15, amplitude: 0.03))
        try player.playPause()
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, player.duration, accuracy: 0.01)
        try player.playPause()
        XCTAssertTrue(player.isPlaying)
        XCTAssertLessThan(player.currentTime, player.duration)
    }

    /// Exercises the delivered notification path, not an actual phone-call interruption.
    @MainActor
    func testDeliveredInterruptionNotificationPausesPlayback() async throws {
        let directory = try AudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let player = AudioPlayer()
        defer { player.stop() }
        try player.load(url: AudioTestFixtures.writePCM(in: directory, duration: 2, amplitude: 0.03))
        try player.playPause()

        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.errorMessage)
        XCTAssertTrue(player.hasAudio)
    }
}
#endif
