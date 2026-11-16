import XCTest
#if canImport(SubtextAIValidation)
@testable import SubtextAIValidation
#else
@testable import Subtext
#endif

final class CloudReviewValidationTests: XCTestCase {
    func testSingleSpeakerResponseNeedsNoSecondSpeakerOrQuestionPair() throws {
        let object: [String: Any] = [
            "turns": [turn(start: 0, end: 3, text: "I am testing this recording."),
                      turn(start: 4, end: 7, text: "There is only one voice here."),
                      turn(start: 8, end: 10, text: "That voice is still speaking.")],
            "summary": "A single person tests a recording.",
            "insights": [],
            "questions": []
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let result = try CloudReviewService.parseResponse(XCTUnwrap(String(data: data, encoding: .utf8)), audioDuration: 12)
        XCTAssertEqual(result.turns.count, 3)
        XCTAssertEqual(Set(result.turns.map(\.speaker)), ["Speaker A"])
        XCTAssertEqual(result.insights, [])
        XCTAssertEqual(result.questions, [])
    }

    @MainActor
    func testIPhoneHostIncludesFirebaseSDKAndMatchingConfiguration() throws {
        #if os(iOS) && !SUBTEXT_PORTABLE_TEST_HOST
        let service = CloudReviewService()
        XCTAssertEqual(service.configurationStatus, .ready,
                       "The real iPhone app must include Firebase AI Logic and its matching GoogleService-Info.plist.")
        XCTAssertTrue(service.isAvailable)
        XCTAssertEqual(service.connectionStatus, .notChecked,
                       "Inspecting configuration must not request attestation or send interview content.")
        #else
        throw XCTSkip("The portable validation host deliberately does not include Firebase or app resources.")
        #endif
    }

    func testConfigurationFailuresDescribeTheActualMissingComponent() {
        XCTAssertEqual(CloudConfigurationStatus.sdkMissing.error, .firebaseSDKMissing)
        XCTAssertEqual(CloudConfigurationStatus.configurationMissing.error, .firebaseConfigurationMissing)
        XCTAssertEqual(CloudConfigurationStatus.configurationInvalid.error, .firebaseConfigurationInvalid)
        XCTAssertNil(CloudConfigurationStatus.ready.error)
        XCTAssertTrue(CloudReviewError.firebaseConfigurationMissing.localizedDescription.contains("configuration"))
        XCTAssertFalse(CloudReviewError.firebaseConfigurationMissing.localizedDescription.contains("Add the Firebase AI Logic SDK"))
        XCTAssertFalse(CloudReviewError.firebaseConfigurationInvalid.localizedDescription.contains("Add the Firebase AI Logic SDK"))
    }

    @MainActor
    func testUnavailableCloudDoesNotStartProcessing() async throws {
        let service = CloudReviewService()
        guard !service.isAvailable else { throw XCTSkip("Firebase is configured in this test host.") }
        let expected = try XCTUnwrap(service.configurationStatus.error)
        do {
            _ = try await service.analyzeAudio(url: URL(fileURLWithPath: "/nonexistent.m4a"))
            XCTFail("Unconfigured service must fail before reading or sending audio")
        } catch {
            XCTAssertEqual(error as? CloudReviewError, expected)
        }
        XCTAssertFalse(service.isProcessing)
    }

    @MainActor
    func testUnavailableConnectionCheckPersistsThePreciseConfigurationFailure() async throws {
        let service = CloudReviewService()
        guard !service.isAvailable else { throw XCTSkip("Firebase is configured in this test host.") }
        let expected = try XCTUnwrap(service.configurationStatus.error)
        do {
            _ = try await service.checkConnection()
            XCTFail("Unconfigured service must fail before a network request")
        } catch {
            XCTAssertEqual(error as? CloudReviewError, expected)
        }
        XCTAssertEqual(service.connectionStatus, .failed(expected))
        XCTAssertFalse(service.isProcessing)
        XCTAssertFalse(service.isCheckingConnection)
    }

    func testValidResponseTrimsTextAndPreservesNeutralSpeakerAssignments() throws {
        let payload = try response(
            turns: [turn(speaker: " Speaker A ", text: "  A statement to verify.\n"),
                    turn(speaker: "Unassigned", start: 5, end: 8, text: "Another voice.")],
            summary: "  Check every quotation against the recording.\n"
        )

        let result = try CloudReviewService.parseResponse(payload, audioDuration: 10)

        XCTAssertEqual(result.turns.count, 2)
        XCTAssertEqual(result.turns[0].speaker, "Speaker A")
        XCTAssertEqual(result.turns[0].text, "A statement to verify.")
        XCTAssertEqual(result.turns[1].speaker, "Unassigned")
        XCTAssertEqual(result.summary, "Check every quotation against the recording.")
    }

    func testOverlappingSpeechIsAllowedWhenStartsRemainChronological() throws {
        let payload = try response(turns: [turn(start: 0, end: 7), turn(speaker: "Speaker B", start: 3, end: 9)])
        let result = try CloudReviewService.parseResponse(payload, audioDuration: 10)
        XCTAssertEqual(result.turns.map(\.startTime), [0, 3])
    }

    func testRejectsNamedSpeakersAndLabelsOutsideTheNeutralRange() throws {
        for speaker in ["Jane Smith", "Speaker P", "Speaker 1", ""] {
            assertInvalid(try response(turns: [turn(speaker: speaker)]))
        }
    }

    func testRejectsInvalidTimeRangesAndOutOfOrderTurns() throws {
        for item in [turn(start: -1, end: 1), turn(start: 3, end: 3),
                     turn(start: 7, end: 5), turn(start: 0, end: 11)] {
            assertInvalid(try response(turns: [item]))
        }
        assertInvalid(try response(turns: [turn(start: 3, end: 6), turn(start: 2, end: 5)]))
    }

    func testRejectsInvalidAudioDurations() throws {
        let payload = try response(turns: [turn()])
        for duration in [0, -1, Double.infinity, Double.nan] {
            assertInvalid(payload, duration: duration)
        }
    }

    func testEmptyTurnsProduceNoSpeechInsteadOfAnInventedTranscript() throws {
        let payload = try response(turns: [], summary: "No speech was identified.")
        XCTAssertThrowsError(try CloudReviewService.parseResponse(payload, audioDuration: 10)) { error in
            switch error as? CloudReviewError {
            case .noSpeech?: break
            default: XCTFail("Expected noSpeech, received \(error)")
            }
        }
    }

    func testRejectsMissingOrBlankContentAndOversizedFields() throws {
        assertInvalid("{}")
        assertInvalid(try response(turns: [turn(text: " \n ")]))
        assertInvalid(try response(turns: [turn()], summary: "\n "))
        assertInvalid(try response(turns: [turn(text: String(repeating: "a", count: 20_001))]))
        assertInvalid(try response(turns: [turn()], summary: String(repeating: "a", count: 6_001)))
    }

    func testRejectsExcessiveTurnsAndResponseSize() throws {
        assertInvalid(try response(turns: Array(repeating: turn(), count: 2_001)))
        assertInvalid(String(repeating: " ", count: 2_000_001))
    }

    func testRejectsTruncatedJSONAndMarkdownWrappers() {
        assertInvalid("{\"turns\":[")
        assertInvalid("```json\n{\"turns\":[],\"summary\":\"No speech\"}\n```")
    }

    func testTransportAndBackendErrorsHaveActionableCategories() {
        let cases: [(NSError, CloudReviewError)] = [
            (NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost), .networkUnavailable),
            (NSError(domain: "HTTP", code: 429), .quotaExceeded),
            (NSError(domain: "HTTP", code: 403, userInfo: [NSLocalizedDescriptionKey: "SERVICE_DISABLED"]), .apiDisabled),
            (NSError(domain: "HTTP", code: 403), .permissionDenied),
            (NSError(domain: "HTTP", code: 404), .modelUnavailable),
            (NSError(domain: "HTTP", code: 503), .serviceUnavailable)
        ]
        for (error, expected) in cases { XCTAssertEqual(CloudReviewService.classify(error), expected) }
        XCTAssertEqual(CloudReviewService.classify(NSError(domain: "AppCheck", code: 403), appCheck: true), .appCheckRequired)
        XCTAssertEqual(CloudReviewService.classify(CloudReviewError.noSpeech), .noSpeech)
    }

    func testWrappedNetworkFailureRetainsNetworkCategoryAndDoesNotExposePrivateDetails() {
        let network = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        let wrapper = NSError(domain: "AppCheck", code: 1, userInfo: [NSUnderlyingErrorKey: network, NSLocalizedDescriptionKey: "private synthetic diagnostic detail"])
        let error = CloudReviewService.classify(wrapper, appCheck: true)
        XCTAssertEqual(error, .networkUnavailable)
        XCTAssertFalse(error.localizedDescription.contains("private synthetic diagnostic detail"))
    }

    private func assertInvalid(_ text: String, duration: Double = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try CloudReviewService.parseResponse(text, audioDuration: duration), file: file, line: line) { error in
            switch error as? CloudReviewError {
            case .invalidResponse?: break
            default: XCTFail("Expected invalidResponse, received \(error)", file: file, line: line)
            }
        }
    }

    private func response(turns: [[String: Any]], summary: String = "Review against original audio.") throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["turns": turns, "summary": summary])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func turn(speaker: String = "Speaker A", start: Double = 0, end: Double = 5, text: String = "A statement.") -> [String: Any] {
        ["speaker": speaker, "startTime": start, "endTime": end, "text": text]
    }
}
