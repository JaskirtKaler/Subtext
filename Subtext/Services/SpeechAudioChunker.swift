import AVFoundation
import Foundation

struct SpeechAudioInfo: Sendable {
    let duration: TimeInterval
    let sampleRate: Double
    let frameCount: AVAudioFramePosition
    let channelCount: AVAudioChannelCount
}

struct PreparedSpeechChunk: Sendable {
    let url: URL
    let startTime: TimeInterval
    let duration: TimeInterval
    let peak: Float
    let rootMeanSquare: Float

    /// Rejects digital silence without discarding ordinary quiet speech.
    var containsAudibleSamples: Bool { peak > 0.0001 && rootMeanSquare > 0.00001 }
}

enum SpeechAudioPreparationError: LocalizedError {
    case missingAudio
    case emptyAudio
    case invalidFormat
    case invalidChunk
    case invalidSamples
    case unreadableAudio(String)

    var errorDescription: String? {
        switch self {
        case .missingAudio: "The audio file could not be found."
        case .emptyAudio: "This recording contains no readable audio. The original file has been kept."
        case .invalidFormat: "This audio format could not be prepared for local transcription. The original file has been kept."
        case .invalidChunk: "The audio timing could not be prepared for local transcription. The original file has been kept."
        case .invalidSamples: "This audio contains invalid sample data. The original file has been kept."
        case .unreadableAudio(let detail): "The audio file could not be read for transcription. \(detail) The original file has been kept."
        }
    }
}

/// Produces one short, mono 16 kHz PCM file at a time. Never edits the original recording.
enum SpeechAudioChunker {
    nonisolated static func inspect(url: URL) throws -> SpeechAudioInfo {
        try Task.checkCancellation()
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { throw SpeechAudioPreparationError.missingAudio }
        do {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            return try info(for: file)
        } catch let error as SpeechAudioPreparationError {
            throw error
        } catch {
            throw SpeechAudioPreparationError.unreadableAudio(error.localizedDescription)
        }
    }

    nonisolated static func prepare(url: URL, range: SpeechChunkRange, directory: URL) throws -> PreparedSpeechChunk {
        try Task.checkCancellation()
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { throw SpeechAudioPreparationError.missingAudio }
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) }
        catch { throw SpeechAudioPreparationError.unreadableAudio(error.localizedDescription) }
        let audio = try info(for: input)
        guard range.startTime.isFinite, range.duration.isFinite, range.startTime >= 0,
              range.duration > 0, range.duration <= 50,
              range.endTime <= audio.duration + 0.01 else { throw SpeechAudioPreparationError.invalidChunk }

        let startFrame = AVAudioFramePosition((range.startTime * audio.sampleRate).rounded())
        let requestedFrames = AVAudioFramePosition((range.duration * audio.sampleRate).rounded())
        guard startFrame < input.length, requestedFrames > 0 else { throw SpeechAudioPreparationError.invalidChunk }
        var framesRemaining = min(input.length - startFrame, requestedFrames)
        let sourceDuration = Double(framesRemaining) / audio.sampleRate
        input.framePosition = startFrame

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 4_096),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
            throw SpeechAudioPreparationError.invalidFormat
        }
        converter.primeMethod = .none
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("speech-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: outputURL) } }
        var output: AVAudioFile? = try AVAudioFile(forWriting: outputURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let targetFrames = AVAudioFramePosition((sourceDuration * format.sampleRate).rounded())
        guard targetFrames > 0 else { throw SpeechAudioPreparationError.emptyAudio }
        var writtenFrames: AVAudioFramePosition = 0
        var sumSquares: Double = 0
        var peak: Float = 0
        var emptyIterations = 0

        while true {
            try Task.checkCancellation()
            var conversionError: NSError?
            var inputError: Error?
            outputBuffer.frameLength = 0
            let status = converter.convert(to: outputBuffer, error: &conversionError) { requestedPackets, inputStatus in
                if Task.isCancelled {
                    inputError = CancellationError()
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                guard framesRemaining > 0 else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    let requested = max(1, min(inputBuffer.frameCapacity, requestedPackets))
                    let count = AVAudioFrameCount(min(AVAudioFramePosition(requested), framesRemaining))
                    try input.read(into: inputBuffer, frameCount: count)
                    framesRemaining -= AVAudioFramePosition(inputBuffer.frameLength)
                    guard inputBuffer.frameLength > 0 else {
                        framesRemaining = 0
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    inputStatus.pointee = .haveData
                    return inputBuffer
                } catch {
                    inputError = error
                    inputStatus.pointee = .endOfStream
                    return nil
                }
            }
            if let inputError { throw inputError }
            if let conversionError { throw SpeechAudioPreparationError.unreadableAudio(conversionError.localizedDescription) }
            guard status != .error else { throw SpeechAudioPreparationError.invalidFormat }

            // A sample-rate converter can append a short filter tail. Keep each chunk on the
            // original source interval so padding cannot introduce overlaps or time drift.
            outputBuffer.frameLength = min(outputBuffer.frameLength, AVAudioFrameCount(targetFrames - writtenFrames))

            if outputBuffer.frameLength > 0 {
                guard let samples = outputBuffer.floatChannelData?[0] else { throw SpeechAudioPreparationError.invalidFormat }
                for index in 0..<Int(outputBuffer.frameLength) {
                    guard samples[index].isFinite else { throw SpeechAudioPreparationError.invalidSamples }
                    let value = min(1, max(-1, samples[index]))
                    samples[index] = value
                    peak = max(peak, abs(value))
                    sumSquares += Double(value) * Double(value)
                }
                try output?.write(from: outputBuffer)
                writtenFrames += AVAudioFramePosition(outputBuffer.frameLength)
                emptyIterations = 0
            } else {
                emptyIterations += 1
            }
            if writtenFrames == targetFrames || status == .endOfStream { break }
            guard emptyIterations < 8 else { throw SpeechAudioPreparationError.invalidFormat }
        }

        // Close the PCM file before the recognition request opens it.
        output = nil
        let duration = Double(writtenFrames) / format.sampleRate
        guard writtenFrames > 0, duration.isFinite, abs(duration - sourceDuration) <= 0.05 else {
            throw SpeechAudioPreparationError.emptyAudio
        }
        try Task.checkCancellation()
        completed = true
        return PreparedSpeechChunk(url: outputURL,
                                   startTime: Double(startFrame) / audio.sampleRate,
                                   duration: duration,
                                   peak: peak,
                                   rootMeanSquare: Float(sqrt(sumSquares / Double(writtenFrames))))
    }

    private nonisolated static func info(for file: AVAudioFile) throws -> SpeechAudioInfo {
        let format = file.processingFormat
        guard format.sampleRate.isFinite, (8_000...384_000).contains(format.sampleRate),
              (1...32).contains(format.channelCount) else { throw SpeechAudioPreparationError.invalidFormat }
        guard file.length > 0 else { throw SpeechAudioPreparationError.emptyAudio }
        let duration = Double(file.length) / format.sampleRate
        guard duration.isFinite, duration > 0, duration <= 24 * 60 * 60 else { throw SpeechAudioPreparationError.invalidFormat }
        return SpeechAudioInfo(duration: duration, sampleRate: format.sampleRate, frameCount: file.length, channelCount: format.channelCount)
    }
}
