import Foundation

/// Timed recognized text. These ranges do not identify the person speaking.
struct TranscribedTurn: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

struct SpeechChunkRange: Equatable, Sendable {
    let startTime: TimeInterval
    let duration: TimeInterval
    var endTime: TimeInterval { startTime + duration }
}

struct SpeechWordSegment: Sendable {
    let timestamp: TimeInterval
    let duration: TimeInterval
    let substringRange: NSRange
}

enum SpeechTranscriptDataError: LocalizedError, Equatable {
    case invalidDuration
    case invalidChunkDuration
    case invalidOffset
    case invalidSegmentMetadata
    case invalidTranscriptMetadata

    var errorDescription: String? {
        switch self {
        case .invalidDuration: "The recording has an invalid duration or exceeds the 24-hour local transcription limit."
        case .invalidChunkDuration: "The local transcription chunk duration must be between 1 and 50 seconds."
        case .invalidOffset: "The transcription chunk has an invalid position in the recording."
        case .invalidSegmentMetadata: "Speech recognition returned text with invalid word timing or text ranges. The original audio is unchanged."
        case .invalidTranscriptMetadata: "Speech recognition returned an invalid or out-of-order transcript. The original audio is unchanged."
        }
    }
}

/// Carries diagnostics without echoing arbitrary Speech error descriptions or userInfo values.
struct SpeechRecognitionFailure: LocalizedError, Sendable {
    let domain: String
    let code: Int
    let localeIdentifier: String
    let offset: TimeInterval
    let underlyingDomain: String?
    let underlyingCode: Int?

    var isNoSpeech: Bool { domain == "kAFAssistantErrorDomain" && code == 1110 }

    init(error: NSError, localeIdentifier: String, offset: TimeInterval) {
        domain = error.domain
        code = error.code
        self.localeIdentifier = localeIdentifier
        self.offset = offset.isFinite ? min(24 * 60 * 60, max(0, offset)) : 0
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        underlyingDomain = underlying?.domain
        underlyingCode = underlying?.code
    }

    var errorDescription: String? {
        let reason: String
        switch (domain, code) {
        case ("kLSRErrorDomain", 102):
            reason = "The Apple speech language assets are unavailable. Check the selected language and iPhone Dictation settings, then retry."
        case ("kLSRErrorDomain", 201):
            reason = "Speech recognition is disabled in iPhone settings. Check Dictation and Siri settings before trying again."
        case ("kLSRErrorDomain", 300):
            reason = "The Apple speech recognizer could not initialize. Try again or choose another supported language."
        case ("kLSRErrorDomain", 301):
            reason = "Speech recognition was cancelled."
        case ("kAFAssistantErrorDomain", 1100):
            reason = "The speech service is still handling an earlier request. Wait a moment, then retry."
        case ("kAFAssistantErrorDomain", 1101):
            reason = "The Apple speech service connection ended. Try again."
        case ("kAFAssistantErrorDomain", 1107):
            reason = "The Apple speech service was interrupted. Try again when the interruption has ended."
        case ("kAFAssistantErrorDomain", 1110):
            reason = "No speech was recognized in this part. Replay the audio, check the language, and try reducing overlapping sound."
        case ("kAFAssistantErrorDomain", 1700):
            reason = "Speech recognition is not authorized. Check Subtext's Speech Recognition access in iPhone Settings."
        default:
            reason = "Speech recognition could not process this part. Try a short sample with clear speech and the matching language."
        }
        let time = String(format: "%02d:%02d", Int(offset / 60), Int(offset.truncatingRemainder(dividingBy: 60)))
        var diagnostic = "\(Self.safeToken(domain)): \(code)"
        if let underlyingDomain, let underlyingCode {
            diagnostic += "; underlying \(Self.safeToken(underlyingDomain)): \(underlyingCode)"
        }
        return "\(reason) Language: \(Self.safeToken(localeIdentifier)). Part starting at \(time). The original audio is unchanged. (\(diagnostic))"
    }

    private static func safeToken(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let filtered = value.unicodeScalars.prefix(120).map { allowed.contains($0) ? String($0) : "_" }.joined()
        return filtered.isEmpty ? "unknown" : filtered
    }
}

/// Deterministic boundaries and text mapping shared by the file transcription pipeline and its tests.
enum SpeechTranscriptSupport {
    private static let maximumRecordingDuration: TimeInterval = 24 * 60 * 60
    private static let timingTolerance: TimeInterval = 0.25

    /// Region/script identify the spoken language. Calendar, numbering and hour-cycle
    /// preferences in Locale.current are formatting settings, not speech model names.
    /// Ignore BCP-47 extensions while retaining the user's language, script and region.
    static func recognitionLocaleIdentifier(_ identifier: String) -> String {
        let parts = Locale.identifier(.bcp47, from: identifier).lowercased().split(separator: "-")
        let languageParts = parts.prefix { $0.count != 1 }
        return languageParts.joined(separator: "-")
    }

    static func chunks(duration: TimeInterval, maximumDuration: TimeInterval = 45) throws -> [SpeechChunkRange] {
        guard duration.isFinite, duration > 0, duration <= maximumRecordingDuration else {
            throw SpeechTranscriptDataError.invalidDuration
        }
        guard maximumDuration.isFinite, (1...50).contains(maximumDuration) else {
            throw SpeechTranscriptDataError.invalidChunkDuration
        }
        let count = Int(ceil(duration / maximumDuration))
        return (0..<count).map { index in
            let start = Double(index) * maximumDuration
            return SpeechChunkRange(startTime: start, duration: min(maximumDuration, duration - start))
        }
    }

    /// `substringRange` is a UTF-16 range from the recognizer's full formatted string.
    /// Punctuation can sit outside a word's range, so each group extends through the following gap.
    static func turns(formattedString: String, segments: [SpeechWordSegment], offset: TimeInterval, chunkDuration: TimeInterval) throws -> [TranscribedTurn] {
        guard chunkDuration.isFinite, chunkDuration > 0, chunkDuration <= 50 else {
            throw SpeechTranscriptDataError.invalidChunkDuration
        }
        guard offset.isFinite, offset >= 0, offset + chunkDuration <= maximumRecordingDuration + timingTolerance else {
            throw SpeechTranscriptDataError.invalidOffset
        }
        if segments.isEmpty {
            guard formattedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SpeechTranscriptDataError.invalidSegmentMetadata
            }
            return []
        }

        let formatted = formattedString as NSString
        var previousEnd = 0
        var previousTimestamp: TimeInterval = -1
        for segment in segments {
            let range = segment.substringRange
            // Check subtraction before adding location and length to avoid overflowing a corrupt NSRange.
            guard range.location != NSNotFound, range.location >= previousEnd,
                  range.location <= formatted.length, range.length > 0,
                  range.length <= formatted.length - range.location,
                  Range(range, in: formattedString) != nil,
                  formatted.rangeOfComposedCharacterSequences(for: range) == range,
                  segment.timestamp.isFinite, segment.duration.isFinite,
                  segment.timestamp >= 0, segment.duration >= 0,
                  segment.timestamp >= previousTimestamp,
                  segment.timestamp < chunkDuration,
                  segment.timestamp + segment.duration <= chunkDuration + timingTolerance else {
                throw SpeechTranscriptDataError.invalidSegmentMetadata
            }
            previousEnd = range.location + range.length
            previousTimestamp = segment.timestamp
        }

        guard formattedString.rangeOfCharacter(from: .alphanumerics) != nil else { return [] }
        var result: [TranscribedTurn] = []
        var groupStart = 0
        var groupTextStart = 0
        var groupEndTime: TimeInterval = 0

        for index in segments.indices {
            let segment = segments[index]
            let next = index + 1 < segments.count ? segments[index + 1] : nil
            let textEnd = next?.substringRange.location ?? formatted.length
            groupEndTime = max(groupEndTime, segment.timestamp + segment.duration)
            let boundary = formatted.substring(with: NSRange(location: segment.substringRange.location, length: textEnd - segment.substringRange.location))
            let endsSentence = boundary.range(of: "[.!?…。！？][\\\"'’”»）)\\]\\}]*\\s*$", options: .regularExpression) != nil
            let gap = next.map { $0.timestamp - (segment.timestamp + segment.duration) } ?? 0
            let span = groupEndTime - segments[groupStart].timestamp
            guard next == nil || endsSentence || gap > 1.2 || span >= 15 else { continue }

            let text = formatted.substring(with: NSRange(location: groupTextStart, length: textEnd - groupTextStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let start = segments[groupStart].timestamp
            let end = min(chunkDuration, groupEndTime)
            guard !text.isEmpty, end > start else { throw SpeechTranscriptDataError.invalidSegmentMetadata }
            result.append(TranscribedTurn(startTime: offset + start, endTime: offset + end, text: text))
            groupStart = index + 1
            groupTextStart = textEnd
            groupEndTime = 0
        }
        return result
    }

    static func joinedTurns(_ chunks: [[TranscribedTurn]], audioDuration: TimeInterval) throws -> [TranscribedTurn] {
        guard audioDuration.isFinite, audioDuration > 0, audioDuration <= maximumRecordingDuration else {
            throw SpeechTranscriptDataError.invalidDuration
        }
        var result: [TranscribedTurn] = []
        var previousStart: TimeInterval = -1
        for chunk in chunks {
            for turn in chunk {
                guard turn.startTime.isFinite, turn.endTime.isFinite,
                      turn.startTime >= 0, turn.endTime > turn.startTime,
                      turn.startTime >= previousStart,
                      turn.endTime <= audioDuration + timingTolerance,
                      !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SpeechTranscriptDataError.invalidTranscriptMetadata
                }
                let end = min(audioDuration, turn.endTime)
                guard end > turn.startTime else { throw SpeechTranscriptDataError.invalidTranscriptMetadata }
                result.append(TranscribedTurn(startTime: turn.startTime, endTime: end, text: turn.text))
                previousStart = turn.startTime
            }
        }
        return result
    }

    /// A bounded warning for chunks that produced no recognized speech alongside successful chunks.
    static func noSpeechWarning(for ranges: [SpeechChunkRange]) throws -> String? {
        guard !ranges.isEmpty else { return nil }
        for range in ranges {
            guard range.startTime.isFinite, range.startTime >= 0 else {
                throw SpeechTranscriptDataError.invalidOffset
            }
            guard range.duration.isFinite, range.duration > 0, range.duration <= 50 else {
                throw SpeechTranscriptDataError.invalidChunkDuration
            }
            guard range.endTime <= maximumRecordingDuration else {
                throw SpeechTranscriptDataError.invalidOffset
            }
        }
        func timestamp(_ value: TimeInterval, roundUp: Bool = false) -> String {
            let seconds = Int(roundUp ? ceil(value) : floor(value))
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
        let displayed = ranges.prefix(3).map { "\(timestamp($0.startTime))–\(timestamp($0.endTime, roundUp: true))" }.joined(separator: ", ")
        let remaining = ranges.count - 3
        let suffix = remaining > 0 ? " and \(remaining) more range\(remaining == 1 ? "" : "s")" : ""
        let reference = ranges.count == 1 ? "this range" : "these ranges"
        return "This transcript contains recognized parts only and is incomplete around \(displayed)\(suffix). Replay and review \(reference) in the original audio. The original audio is unchanged."
    }
}
