#if canImport(SubtextSpeechValidation) || canImport(Subtext)
import AVFoundation
import Foundation
import XCTest
#if canImport(SubtextSpeechValidation)
@testable import SubtextSpeechValidation
#else
@testable import Subtext
#endif

enum SpeechAudioTestFixtures {
    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SubtextSpeechTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writePCM(in directory: URL, filename: String = "speech.wav", duration: TimeInterval = 1, sampleRate: Double = 44_100, channels: AVAudioChannelCount = 1, amplitude: Float = 0.2) throws -> URL {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096))
        let data = try XCTUnwrap(buffer.floatChannelData)
        let url = directory.appendingPathComponent(filename)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let totalFrames = AVAudioFramePosition(duration * sampleRate)
        var written: AVAudioFramePosition = 0
        while written < totalFrames {
            let count = AVAudioFrameCount(min(4_096, totalFrames - written))
            buffer.frameLength = count
            for channel in 0..<Int(channels) {
                for index in 0..<Int(count) {
                    data[channel][index] = amplitude * Float(sin(Double(written + AVAudioFramePosition(index)) * 2 * Double.pi * 440 / sampleRate))
                }
            }
            try file.write(from: buffer)
            written += AVAudioFramePosition(count)
        }
        return url
    }
}

final class AudioSpeechChunkerTests: XCTestCase {
    func testInspectReadsRealPCMMetadata() throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try SpeechAudioTestFixtures.writePCM(in: directory, duration: 1.25, sampleRate: 48_000, channels: 2)

        let info = try SpeechAudioChunker.inspect(url: source)

        XCTAssertEqual(info.duration, 1.25, accuracy: 0.0001)
        XCTAssertEqual(info.frameCount, 60_000)
        XCTAssertEqual(info.sampleRate, 48_000)
        XCTAssertEqual(info.channelCount, 2)
    }

    func testPreparingStereoPCMDownmixesAndResamplesWithoutChangingOriginal() throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try SpeechAudioTestFixtures.writePCM(in: directory, duration: 1.25, sampleRate: 48_000, channels: 2)
        let original = try Data(contentsOf: source)
        let outputDirectory = directory.appendingPathComponent("prepared")

        let prepared = try SpeechAudioChunker.prepare(url: source, range: SpeechChunkRange(startTime: 0.25, duration: 0.75), directory: outputDirectory)
        let decoded = try AVAudioFile(forReading: prepared.url)

        XCTAssertNotEqual(prepared.url, source)
        XCTAssertEqual(decoded.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(decoded.fileFormat.channelCount, 1)
        XCTAssertEqual(decoded.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int, 16)
        XCTAssertEqual(prepared.startTime, 0.25, accuracy: 0.0001)
        XCTAssertEqual(prepared.duration, 0.75, accuracy: 0.002)
        XCTAssertTrue(prepared.containsAudibleSamples)
        XCTAssertTrue(prepared.peak.isFinite)
        XCTAssertTrue(prepared.rootMeanSquare.isFinite)
        XCTAssertGreaterThan(prepared.peak, 0)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testLongAudioUsesAdjacentBoundedChunksAndKeepsAbsoluteOffsets() throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try SpeechAudioTestFixtures.writePCM(in: directory, duration: 46, sampleRate: 8_000)
        let original = try Data(contentsOf: source)
        let info = try SpeechAudioChunker.inspect(url: source)
        let ranges = try SpeechTranscriptSupport.chunks(duration: info.duration)
        XCTAssertEqual(ranges.count, 2)
        let prepared = try ranges.map {
            try SpeechAudioChunker.prepare(url: source, range: $0, directory: directory.appendingPathComponent("chunks"))
        }

        XCTAssertEqual(prepared[0].duration, 45, accuracy: 0.002)
        XCTAssertEqual(prepared[1].startTime, 45, accuracy: 0.0001)
        XCTAssertEqual(prepared[1].duration, 1, accuracy: 0.002)
        for chunk in prepared {
            XCTAssertLessThanOrEqual(chunk.duration, 45.01)
            let bytes = try FileManager.default.attributesOfItem(atPath: chunk.url.path)[.size] as? NSNumber
            XCTAssertLessThan(try XCTUnwrap(bytes).intValue, 1_500_000)
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testDigitalSilencePreparesButDoesNotClaimAudibleSamples() throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try SpeechAudioTestFixtures.writePCM(in: directory, amplitude: 0)

        let prepared = try SpeechAudioChunker.prepare(url: source, range: SpeechChunkRange(startTime: 0, duration: 1), directory: directory.appendingPathComponent("chunks"))

        XCTAssertFalse(prepared.containsAudibleSamples)
        XCTAssertEqual(prepared.peak, 0)
        XCTAssertEqual(prepared.rootMeanSquare, 0)
        XCTAssertEqual(prepared.duration, 1, accuracy: 0.002)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testEmptyPCMIsRejectedWithoutRemovingIt() throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try SpeechAudioTestFixtures.writePCM(in: directory, duration: 0)

        XCTAssertThrowsError(try SpeechAudioChunker.inspect(url: source)) { error in
            guard case .emptyAudio? = error as? SpeechAudioPreparationError else { return XCTFail("Expected emptyAudio, got \(error)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMissingInvalidAndRemoteURLsAreRejectedLocally() throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = directory.appendingPathComponent("invalid.wav")
        let original = Data("Not audio".utf8)
        try original.write(to: invalid)

        XCTAssertThrowsError(try SpeechAudioChunker.inspect(url: directory.appendingPathComponent("missing.wav")))
        XCTAssertThrowsError(try SpeechAudioChunker.inspect(url: invalid))
        XCTAssertThrowsError(try SpeechAudioChunker.inspect(url: URL(string: "https://example.invalid/audio.wav")!))
        XCTAssertEqual(try Data(contentsOf: invalid), original)
    }

    func testInvalidChunkRangesFailBeforeCreatingTemporaryAudio() throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try SpeechAudioTestFixtures.writePCM(in: directory)
        let output = directory.appendingPathComponent("chunks")
        for range in [SpeechChunkRange(startTime: -1, duration: 1),
                      SpeechChunkRange(startTime: 0, duration: 0),
                      SpeechChunkRange(startTime: 0, duration: 51),
                      SpeechChunkRange(startTime: .nan, duration: 1),
                      SpeechChunkRange(startTime: .greatestFiniteMagnitude, duration: 1),
                      SpeechChunkRange(startTime: 2, duration: 1)] {
            XCTAssertThrowsError(try SpeechAudioChunker.prepare(url: source, range: range, directory: output))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testPreCancelledPreparationProducesNoChunkAndPreservesSource() async throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try SpeechAudioTestFixtures.writePCM(in: directory)
        let output = directory.appendingPathComponent("chunks")
        let gate = SpeechPreparationTestGate()
        let task = Task {
            await gate.wait()
            return try SpeechAudioChunker.prepare(url: source, range: SpeechChunkRange(startTime: 0, duration: 1), directory: output)
        }
        task.cancel()
        await gate.open()
        do {
            _ = try await task.value
            XCTFail("Cancelled preparation must not create a chunk")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
}

private actor SpeechPreparationTestGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
#endif
