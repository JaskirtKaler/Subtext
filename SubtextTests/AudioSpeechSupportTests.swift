#if canImport(SubtextSpeechValidation) || canImport(Subtext)
import Foundation
import XCTest
#if canImport(SubtextSpeechValidation)
@testable import SubtextSpeechValidation
#else
@testable import Subtext
#endif

final class AudioSpeechSupportTests: XCTestCase {
    func testRecognitionLocaleIgnoresUserFormattingExtensions() {
        XCTAssertEqual(SpeechTranscriptSupport.recognitionLocaleIdentifier("en_US"), "en-us")
        XCTAssertEqual(SpeechTranscriptSupport.recognitionLocaleIdentifier("en-US-u-hc-h12"), "en-us")
        XCTAssertEqual(SpeechTranscriptSupport.recognitionLocaleIdentifier("en_US@calendar=gregorian;numbers=latn"), "en-us")
        XCTAssertEqual(SpeechTranscriptSupport.recognitionLocaleIdentifier("en-US-x-private"), "en-us")
    }

    func testRecognitionLocalePreservesSelectedScriptAndRegion() {
        XCTAssertEqual(SpeechTranscriptSupport.recognitionLocaleIdentifier("zh-Hant-TW-u-nu-hanidec"), "zh-hant-tw")
        XCTAssertEqual(SpeechTranscriptSupport.recognitionLocaleIdentifier("sr-Latn-RS"), "sr-latn-rs")
        XCTAssertNotEqual(SpeechTranscriptSupport.recognitionLocaleIdentifier("en-US"), SpeechTranscriptSupport.recognitionLocaleIdentifier("en-GB"))
    }

    func testChunkPlanIsContiguousBoundedAndPreservesRemainder() throws {
        let ranges = try SpeechTranscriptSupport.chunks(duration: 100)
        XCTAssertEqual(ranges, [SpeechChunkRange(startTime: 0, duration: 45), SpeechChunkRange(startTime: 45, duration: 45), SpeechChunkRange(startTime: 90, duration: 10)])
        XCTAssertEqual(ranges.last?.endTime, 100)
        XCTAssertTrue(ranges.allSatisfy { $0.duration > 0 && $0.duration <= 45 })
    }

    func testExactChunkBoundariesDoNotCreateEmptyRequests() throws {
        XCTAssertEqual(try SpeechTranscriptSupport.chunks(duration: 45).map(\.duration), [45])
        XCTAssertEqual(try SpeechTranscriptSupport.chunks(duration: 90).map(\.duration), [45, 45])
        XCTAssertEqual(try SpeechTranscriptSupport.chunks(duration: 0.01).map(\.duration), [0.01])
    }

    func testInvalidDurationsAndChunkSizesAreRejected() {
        for duration in [0, -1, Double.nan, .infinity, 86_400.1] {
            XCTAssertThrowsError(try SpeechTranscriptSupport.chunks(duration: duration))
        }
        for chunk in [0, 0.5, 50.1, Double.nan, .infinity] {
            XCTAssertThrowsError(try SpeechTranscriptSupport.chunks(duration: 60, maximumDuration: chunk))
        }
    }

    func testQuestionMarksOutsideWordRangesArePreservedAndSplitQuestions() throws {
        let text = "When? Next."
        let turns = try SpeechTranscriptSupport.turns(formattedString: text, segments: [word("When", in: text, at: 0.2, duration: 0.6), word("Next", in: text, at: 1.2, duration: 0.7)], offset: 45, chunkDuration: 3)

        XCTAssertEqual(turns.map(\.text), ["When?", "Next."])
        XCTAssertEqual(turns.map(\.startTime), [45.2, 46.2])
        XCTAssertEqual(turns[0].endTime, 45.8, accuracy: 0.0001)
        XCTAssertEqual(turns[1].endTime, 46.9, accuracy: 0.0001)
    }

    func testUnicodeUTF16RangesPreserveQuotesAndNonLatinPunctuation() throws {
        let text = "“你好？” Café ☕️, please."
        let segments = [word("你好", in: text, at: 0.1, duration: 0.6), word("Café", in: text, at: 1.0, duration: 0.4), word("☕️", in: text, at: 1.5, duration: 0.3), word("please", in: text, at: 2, duration: 0.5)]
        let turns = try SpeechTranscriptSupport.turns(formattedString: text, segments: segments, offset: 0, chunkDuration: 3)

        XCTAssertEqual(turns.map(\.text), ["“你好？”", "Café ☕️, please."])
    }

    func testLongGroupAndSilentGapSplitWithoutLosingText() throws {
        let text = "First long phrase then one pause"
        let segments = [word("First", in: text, at: 0, duration: 0.5), word("long", in: text, at: 1, duration: 13.5), word("phrase", in: text, at: 14.8, duration: 0.7), word("then", in: text, at: 16, duration: 0.3), word("one", in: text, at: 16.5, duration: 0.1), word("pause", in: text, at: 19, duration: 0.7)]
        let turns = try SpeechTranscriptSupport.turns(formattedString: text, segments: segments, offset: 0, chunkDuration: 21)
        XCTAssertEqual(turns.map(\.text), ["First long phrase", "then one", "pause"])
    }

    func testSmallRecognizerRoundingOvershootIsClampedToAudioBoundary() throws {
        let text = "Done."
        let turns = try SpeechTranscriptSupport.turns(formattedString: text, segments: [word("Done", in: text, at: 1.5, duration: 0.6)], offset: 45, chunkDuration: 2)
        XCTAssertEqual(turns[0].endTime, 47)
    }

    func testEmptyTextAndSegmentsReturnNoInventedTranscript() throws {
        XCTAssertTrue(try SpeechTranscriptSupport.turns(formattedString: " \n", segments: [], offset: 0, chunkDuration: 1).isEmpty)
        XCTAssertThrowsError(try SpeechTranscriptSupport.turns(formattedString: "Missing timing", segments: [], offset: 0, chunkDuration: 1))
    }

    func testInvalidWordRangesAndTimingAreRejected() throws {
        let invalid = [
            SpeechWordSegment(timestamp: 0, duration: 1, substringRange: NSRange(location: NSNotFound, length: 1)),
            SpeechWordSegment(timestamp: 0, duration: 1, substringRange: NSRange(location: 3, length: Int.max)),
            SpeechWordSegment(timestamp: -1, duration: 1, substringRange: NSRange(location: 0, length: 4)),
            SpeechWordSegment(timestamp: .nan, duration: 1, substringRange: NSRange(location: 0, length: 4)),
            SpeechWordSegment(timestamp: 0, duration: -.infinity, substringRange: NSRange(location: 0, length: 4)),
            SpeechWordSegment(timestamp: 0, duration: 8, substringRange: NSRange(location: 0, length: 4)),
            SpeechWordSegment(timestamp: 3, duration: 0, substringRange: NSRange(location: 0, length: 4))
        ]
        for segment in invalid {
            XCTAssertThrowsError(try SpeechTranscriptSupport.turns(formattedString: "Word", segments: [segment], offset: 0, chunkDuration: 3))
        }
        XCTAssertThrowsError(try SpeechTranscriptSupport.turns(formattedString: "Hi 😀", segments: [SpeechWordSegment(timestamp: 0, duration: 0.5, substringRange: NSRange(location: 4, length: 1))], offset: 0, chunkDuration: 1))
    }

    func testOutOfOrderOrOverlappingWordRangesAreRejected() {
        let text = "One two"
        XCTAssertThrowsError(try SpeechTranscriptSupport.turns(formattedString: text, segments: [word("One", in: text, at: 1, duration: 0.4), word("two", in: text, at: 0, duration: 0.4)], offset: 0, chunkDuration: 2))
        XCTAssertThrowsError(try SpeechTranscriptSupport.turns(formattedString: text, segments: [word("One", in: text, at: 0, duration: 0.4), word("One", in: text, at: 1, duration: 0.4)], offset: 0, chunkDuration: 2))
    }

    func testInvalidOffsetsAndChunkDurationsAreRejected() {
        for offset in [-1, Double.nan, .infinity, 86_400] {
            XCTAssertThrowsError(try SpeechTranscriptSupport.turns(formattedString: "", segments: [], offset: offset, chunkDuration: 1))
        }
        for duration in [0, -1, 51, Double.nan, .infinity] {
            XCTAssertThrowsError(try SpeechTranscriptSupport.turns(formattedString: "", segments: [], offset: 0, chunkDuration: duration))
        }
    }

    func testJoiningAbsoluteChunkTimesPreservesQuestionAndChronology() throws {
        let first = [TranscribedTurn(startTime: 0.2, endTime: 2, text: "When is the meeting?")]
        let second = [TranscribedTurn(startTime: 46, endTime: 49, text: "Tuesday at six.")]
        let joined = try SpeechTranscriptSupport.joinedTurns([first, [], second], audioDuration: 50)
        XCTAssertEqual(joined.map(\.startTime), [0.2, 46])
        XCTAssertEqual(joined.map(\.text), ["When is the meeting?", "Tuesday at six."])
    }

    func testJoiningRejectsInvalidOrOutOfOrderTranscriptMetadata() {
        let valid = TranscribedTurn(startTime: 2, endTime: 3, text: "Valid.")
        let invalid = [
            TranscribedTurn(startTime: -1, endTime: 2, text: "Invalid"),
            TranscribedTurn(startTime: .nan, endTime: 2, text: "Invalid"),
            TranscribedTurn(startTime: 1, endTime: .infinity, text: "Invalid"),
            TranscribedTurn(startTime: 1, endTime: 1, text: "Invalid"),
            TranscribedTurn(startTime: 1, endTime: 10, text: "Invalid"),
            TranscribedTurn(startTime: 1, endTime: 2, text: " \n")
        ]
        for turn in invalid { XCTAssertThrowsError(try SpeechTranscriptSupport.joinedTurns([[turn]], audioDuration: 5)) }
        XCTAssertThrowsError(try SpeechTranscriptSupport.joinedTurns([[valid], [TranscribedTurn(startTime: 1, endTime: 2, text: "Earlier")]], audioDuration: 5))
    }

    func testSpeechFailureMappingRequiresBothKnownDomainAndCode() {
        let missingAssets = SpeechRecognitionFailure(error: NSError(domain: "kLSRErrorDomain", code: 102), localeIdentifier: "en-US", offset: 45)
        XCTAssertTrue(missingAssets.localizedDescription.contains("language assets are unavailable"))
        let sameCodeOtherDomain = SpeechRecognitionFailure(error: NSError(domain: "SomeOtherDomain", code: 102), localeIdentifier: "en-US", offset: 45)
        XCTAssertFalse(sameCodeOtherDomain.localizedDescription.contains("language assets are unavailable"))
        XCTAssertTrue(sameCodeOtherDomain.localizedDescription.contains("SomeOtherDomain: 102"))
    }

    func testNoSpeechIsRecognizedOnlyForExactDomainAndCode() {
        XCTAssertTrue(failure(domain: "kAFAssistantErrorDomain", code: 1110).isNoSpeech)
        XCTAssertFalse(failure(domain: "kLSRErrorDomain", code: 1110).isNoSpeech)
        XCTAssertFalse(failure(domain: "kAFAssistantErrorDomain", code: 1101).isNoSpeech)
        XCTAssertTrue(failure(domain: "kAFAssistantErrorDomain", code: 1110).localizedDescription.contains("No speech was recognized"))
    }

    func testServiceConnectionErrorDoesNotClaimLanguageModelIsMissing() {
        let failure = failure(domain: "kAFAssistantErrorDomain", code: 1101)
        XCTAssertTrue(failure.localizedDescription.contains("service connection ended"))
        XCTAssertFalse(failure.localizedDescription.contains("language assets"))
    }

    func testSpeechFailureIncludesSafeDiagnosticsWithoutEchoingErrorText() {
        let underlying = NSError(domain: "Underlying.Domain", code: -42, userInfo: [NSLocalizedDescriptionKey: "private underlying words"])
        let error = NSError(domain: "kAFAssistantErrorDomain", code: 203, userInfo: [NSLocalizedDescriptionKey: "private recognized words", NSUnderlyingErrorKey: underlying, "transcript": "private transcript"])
        let failure = SpeechRecognitionFailure(error: error, localeIdentifier: "en-GB", offset: 90)

        XCTAssertEqual(failure.domain, "kAFAssistantErrorDomain")
        XCTAssertEqual(failure.code, 203)
        XCTAssertEqual(failure.underlyingDomain, "Underlying.Domain")
        XCTAssertEqual(failure.underlyingCode, -42)
        XCTAssertTrue(failure.localizedDescription.contains("en-GB"))
        XCTAssertTrue(failure.localizedDescription.contains("01:30"))
        XCTAssertTrue(failure.localizedDescription.contains("underlying Underlying.Domain: -42"))
        XCTAssertFalse(failure.localizedDescription.contains("private"))
    }

    func testSpeechFailureHandlesUntrustedDiagnosticTokensAndExtremeOffsets() {
        let failure = SpeechRecognitionFailure(error: NSError(domain: "bad\ndomain💬", code: 99), localeIdentifier: "en-US\ntext", offset: Double.greatestFiniteMagnitude)
        XCTAssertFalse(failure.localizedDescription.contains("\n"))
        XCTAssertTrue(failure.localizedDescription.contains("bad_domain_"))
        XCTAssertTrue(failure.localizedDescription.contains("1440:00"))
    }

    func testNoSpeechWarningIsAbsentForCompleteTranscriptAndExplainsSingleMissingRange() throws {
        XCTAssertNil(try SpeechTranscriptSupport.noSpeechWarning(for: []))
        let warning = try XCTUnwrap(SpeechTranscriptSupport.noSpeechWarning(for: [SpeechChunkRange(startTime: 45, duration: 45)]))
        XCTAssertTrue(warning.contains("00:45–01:30"))
        XCTAssertTrue(warning.contains("recognized parts only"))
        XCTAssertTrue(warning.contains("incomplete"))
        XCTAssertTrue(warning.contains("review this range"))
        XCTAssertTrue(warning.contains("original audio is unchanged"))
    }

    func testNoSpeechWarningListsOnlyThreeRangesAndCountsRemainingRanges() throws {
        let ranges = (0..<5).map { SpeechChunkRange(startTime: Double($0) * 45, duration: 45) }
        let warning = try XCTUnwrap(SpeechTranscriptSupport.noSpeechWarning(for: ranges))
        XCTAssertTrue(warning.contains("00:00–00:45, 00:45–01:30, 01:30–02:15 and 2 more ranges"))
        XCTAssertFalse(warning.contains("02:15–03:00"))
        XCTAssertTrue(warning.contains("review these ranges"))
        let four = try XCTUnwrap(SpeechTranscriptSupport.noSpeechWarning(for: Array(ranges.prefix(4))))
        XCTAssertTrue(four.contains("and 1 more range."))
    }

    func testNoSpeechWarningRejectsInvalidRangesEvenAfterDisplayLimit() {
        let valid = (0..<3).map { SpeechChunkRange(startTime: Double($0) * 45, duration: 45) }
        let invalid = [
            SpeechChunkRange(startTime: .nan, duration: 45),
            SpeechChunkRange(startTime: -.infinity, duration: 45),
            SpeechChunkRange(startTime: -1, duration: 45),
            SpeechChunkRange(startTime: 0, duration: 0),
            SpeechChunkRange(startTime: 0, duration: .infinity),
            SpeechChunkRange(startTime: 0, duration: 51),
            SpeechChunkRange(startTime: 86_390, duration: 45)
        ]
        for range in invalid {
            XCTAssertThrowsError(try SpeechTranscriptSupport.noSpeechWarning(for: valid + [range]))
        }
    }

    private func failure(domain: String, code: Int) -> SpeechRecognitionFailure {
        SpeechRecognitionFailure(error: NSError(domain: domain, code: code), localeIdentifier: "en-US", offset: 0)
    }

    private func word(_ word: String, in text: String, at timestamp: TimeInterval, duration: TimeInterval) -> SpeechWordSegment {
        SpeechWordSegment(timestamp: timestamp, duration: duration, substringRange: (text as NSString).range(of: word))
    }
}
#endif
