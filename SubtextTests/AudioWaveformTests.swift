#if canImport(Subtext) || canImport(SubtextAudioValidation)
import AVFoundation
import Foundation
import XCTest
#if canImport(SubtextAudioValidation)
@testable import SubtextAudioValidation
#else
@testable import Subtext
#endif

/// Small, real PCM fixtures shared by the audio service tests. No microphone permission is needed.
enum AudioTestFixtures {
    enum FixtureError: Error {
        case invalidParameters
        case unavailablePCMBuffer
    }

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubtextAudioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func writePCM(in directory: URL, filename: String = "tone.wav", duration: TimeInterval = 1, amplitude: Float = 0.3) throws -> URL {
        guard duration.isFinite, duration >= 0, duration <= 3_600,
              amplitude.isFinite, abs(amplitude) <= 1 else { throw FixtureError.invalidParameters }
        let sampleRate: Double = 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096),
              let samples = buffer.floatChannelData?[0] else { throw FixtureError.unavailablePCMBuffer }
        let url = directory.appendingPathComponent(filename)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFramePosition(duration * sampleRate)
        var written: AVAudioFramePosition = 0
        while written < frameCount {
            let length = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), frameCount - written))
            buffer.frameLength = length
            for index in 0..<Int(length) {
                samples[index] = amplitude * Float(sin(Double(written + AVAudioFramePosition(index)) * 2 * Double.pi * 440 / sampleRate))
            }
            try file.write(from: buffer)
            written += AVAudioFramePosition(length)
        }
        return url
    }
}

final class AudioWaveformTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try AudioTestFixtures.makeDirectory()
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    func testToneProducesDefaultCountAndNormalizedFiniteAmplitudes() async throws {
        let url = try AudioTestFixtures.writePCM(in: directory)
        let values = try await WaveformSampler.samples(url: url)

        XCTAssertEqual(values.count, 140)
        XCTAssertTrue(values.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertEqual(try XCTUnwrap(values.max()), 1, accuracy: 0.0001)
        XCTAssertTrue(values.allSatisfy { $0 > 0.95 }, "A sustained 440 Hz tone should be present throughout the file.")
    }

    func testSilenceRemainsZeroInsteadOfProducingAnArtificialWaveform() async throws {
        let url = try AudioTestFixtures.writePCM(in: directory, filename: "silence.wav", amplitude: 0)
        let values = try await WaveformSampler.samples(url: url)

        XCTAssertEqual(values.count, 140)
        XCTAssertTrue(values.allSatisfy { $0 == 0 })
    }

    func testPositiveRequestedCountsAreHonoredWithinLimit() async throws {
        let url = try AudioTestFixtures.writePCM(in: directory)
        for count in [1, 7, 140, 512] {
            let values = try await WaveformSampler.samples(url: url, count: count)
            XCTAssertEqual(values.count, count)
            XCTAssertTrue(values.allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
    }

    func testCountsAboveLimitAreCappedWithoutAllocatingRequestedSize() async throws {
        let url = try AudioTestFixtures.writePCM(in: directory)
        for count in [513, Int.max] {
            let values = try await WaveformSampler.samples(url: url, count: count)
            XCTAssertEqual(values.count, 512)
        }
    }

    func testNonPositiveCountsReturnEmptyWithoutOpeningAFile() async throws {
        let missingURL = directory.appendingPathComponent("missing.wav")
        for count in [0, -1, Int.min] {
            let values = try await WaveformSampler.samples(url: missingURL, count: count)
            XCTAssertTrue(values.isEmpty)
        }
    }

    func testMissingFileThrows() async throws {
        do {
            _ = try await WaveformSampler.samples(url: directory.appendingPathComponent("missing.wav"))
            XCTFail("A missing audio file must not produce a waveform.")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testInvalidFileThrows() async throws {
        let url = directory.appendingPathComponent("invalid.wav")
        try Data("This is not an audio file.".utf8).write(to: url)
        do {
            _ = try await WaveformSampler.samples(url: url)
            XCTFail("Non-audio data must not produce a waveform.")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testEmptyPCMFileThrows() async throws {
        let url = try AudioTestFixtures.writePCM(in: directory, filename: "empty.wav", duration: 0)
        do {
            _ = try await WaveformSampler.samples(url: url)
            XCTFail("An empty recording must not produce a waveform.")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testCancellationPropagatesToSamplingWorker() async throws {
        let url = try AudioTestFixtures.writePCM(in: directory, duration: 3)
        let gate = WaveformTestGate()
        let task = Task {
            await gate.wait()
            return try await WaveformSampler.samples(url: url, count: 512)
        }
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("Cancellation must propagate instead of returning a waveform.")
        } catch is CancellationError {
            // Expected: the detached sampling worker observes the caller's cancellation.
        } catch {
            XCTFail("Expected CancellationError, got \(error).")
        }
    }
}

private actor WaveformTestGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}
#endif
