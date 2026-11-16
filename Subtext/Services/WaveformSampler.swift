import AVFoundation
import Foundation

enum WaveformSamplingError: LocalizedError {
    case unreadableAudio

    var errorDescription: String? { "The waveform could not be read from this audio file." }
}

/// Reads a small PCM window from each time bin instead of decoding an entire long recording into memory.
enum WaveformSampler {
    nonisolated static func samples(url: URL, count: Int = 140) async throws -> [Float] {
        guard count > 0 else { return [] }
        let binCount = min(count, 512)
        let worker = Task.detached(priority: .utility) {
            try readSamples(url: url, count: binCount)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private nonisolated static func readSamples(url: URL, count: Int) throws -> [Float] {
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let totalFrames = file.length
        guard totalFrames > 0, file.processingFormat.channelCount > 0 else { throw WaveformSamplingError.unreadableAudio }
        let maxWindow: AVAudioFrameCount = 2_048
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: maxWindow) else {
            throw WaveformSamplingError.unreadableAudio
        }

        var values: [Float] = []
        values.reserveCapacity(count)
        for index in 0..<count {
            try Task.checkCancellation()
            let binStart = AVAudioFramePosition(Double(totalFrames) * Double(index) / Double(count))
            let binEnd = AVAudioFramePosition(Double(totalFrames) * Double(index + 1) / Double(count))
            let binLength = max(1, binEnd - binStart)
            let window = min(AVAudioFramePosition(maxWindow), binLength)
            let position = min(totalFrames - 1, binStart + max(0, (binLength - window) / 2))
            file.framePosition = position
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(window, totalFrames - position)))
            guard let channels = buffer.floatChannelData else { throw WaveformSamplingError.unreadableAudio }
            var peak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let amplitude = abs(channels[channel][frame])
                    if amplitude.isFinite { peak = max(peak, amplitude) }
                }
            }
            values.append(peak)
        }

        // Relative peak normalization preserves silence and makes soft speech legible.
        guard let highest = values.max(), highest > 0 else { return values }
        return values.map { min(1, max(0, sqrt($0 / highest))) }
    }
}
