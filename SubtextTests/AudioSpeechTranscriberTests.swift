#if canImport(Subtext) || canImport(SubtextSpeechValidation)
import Speech
import XCTest
#if canImport(SubtextSpeechValidation)
@testable import SubtextSpeechValidation
#else
@testable import Subtext
#endif

/// These tests deliberately avoid live speech recognition and permission prompts.
final class AudioSpeechTranscriberTests: XCTestCase {
    @MainActor
    func testRequestsPermitAppleServiceOnlyWhenExplicitlySelected() {
        let url = URL(fileURLWithPath: "/unused-synthetic-request.wav")
        let local = SpeechTranscriber.recognitionRequest(url: url, mode: .onDevice)
        let serviceAllowed = SpeechTranscriber.recognitionRequest(url: url, mode: .appleServiceAllowed)
        XCTAssertTrue(local.requiresOnDeviceRecognition)
        XCTAssertFalse(serviceAllowed.requiresOnDeviceRecognition)
        XCTAssertFalse(local.shouldReportPartialResults)
        XCTAssertFalse(serviceAllowed.shouldReportPartialResults)
        XCTAssertTrue(local.addsPunctuation)
        XCTAssertTrue(serviceAllowed.addsPunctuation)
    }

    func testMissingOnDeviceModelDoesNotBlockAnExplicitAppleServiceRequest() throws {
        XCTAssertThrowsError(try SpeechRecognitionMode.onDevice.validateAvailability(
            supportsOnDeviceRecognition: false, isAvailable: true
        )) { error in
            guard case .onDeviceUnavailable? = error as? SpeechTranscriptionError else {
                return XCTFail("Expected onDeviceUnavailable, got \(error)")
            }
        }
        XCTAssertNoThrow(try SpeechRecognitionMode.appleServiceAllowed.validateAvailability(
            supportsOnDeviceRecognition: false, isAvailable: true
        ))
        XCTAssertNoThrow(try SpeechRecognitionMode.appleServiceAllowed.validateAvailability(
            supportsOnDeviceRecognition: true, isAvailable: true
        ))
    }

    func testBothModesRequireAnAvailableRecognizer() {
        for mode: SpeechRecognitionMode in [.onDevice, .appleServiceAllowed] {
            XCTAssertThrowsError(try mode.validateAvailability(supportsOnDeviceRecognition: true, isAvailable: false)) { error in
                guard case .unavailable? = error as? SpeechTranscriptionError else {
                    return XCTFail("Expected unavailable, got \(error)")
                }
            }
        }
    }

    @MainActor
    func testExistingLocalProviderCannotSilentlyAcceptAnAppleServiceRequest() async throws {
        let provider: any SpeechTranscribing = MinimalWorkflowSpeech()
        let url = URL(fileURLWithPath: "/unused-synthetic-request.wav")
        let local = try await provider.transcribe(url: url, mode: .onDevice)
        XCTAssertTrue(local.isEmpty)
        do {
            _ = try await provider.transcribe(url: url, mode: .appleServiceAllowed)
            XCTFail("A local-only provider must explicitly reject service-capable requests")
        } catch {
            guard case .appleServiceUnsupported? = error as? SpeechTranscriptionError else {
                return XCTFail("Expected appleServiceUnsupported, got \(error)")
            }
        }
    }

    @MainActor
    func testAppleServiceModeRejectsMissingAudioWithoutRequestingAuthorization() async throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = SFSpeechRecognizer.authorizationStatus()
        let transcriber = SpeechTranscriber()
        do {
            _ = try await transcriber.transcribe(url: directory.appendingPathComponent("missing.wav"), mode: .appleServiceAllowed)
            XCTFail("A missing audio file must not enter Apple service recognition")
        } catch {
            guard case .missingAudio? = error as? SpeechTranscriptionError else {
                return XCTFail("Expected missingAudio, got \(error)")
            }
        }
        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
    }

    @MainActor
    func testCreatingAndCancellingAnIdleTranscriberDoesNotRequestAuthorization() {
        let before = SFSpeechRecognizer.authorizationStatus()
        let transcriber = SpeechTranscriber()

        transcriber.cancel()
        transcriber.cancel()

        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
    }

    @MainActor
    func testMissingAudioFailsBeforeRequestingSpeechAuthorization() async throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = SFSpeechRecognizer.authorizationStatus()
        let transcriber = SpeechTranscriber()

        do {
            _ = try await transcriber.transcribe(url: directory.appendingPathComponent("missing.wav"))
            XCTFail("A missing audio file must not enter speech recognition")
        } catch {
            guard case .missingAudio? = error as? SpeechTranscriptionError else {
                return XCTFail("Expected missingAudio, got \(error)")
            }
        }

        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
    }

    @MainActor
    func testAlreadyCancelledTaskWithExistingAudioDoesNotRequestAuthorization() async throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try SpeechAudioTestFixtures.writePCM(in: directory)
        let before = SFSpeechRecognizer.authorizationStatus()
        let transcriber = SpeechTranscriber()
        // The main actor cannot start this task until this test yields, so cancellation is deterministic.
        let task = Task { @MainActor in try await transcriber.transcribe(url: fixture) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled task must not enter speech recognition")
        } catch is CancellationError {
            // Expected before requestAuthorization is called.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
    }

    @MainActor
    func testIdleCancelDoesNotLeaveTheTranscriberBusy() async throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriber = SpeechTranscriber()
        let before = SFSpeechRecognizer.authorizationStatus()
        transcriber.cancel()

        do {
            _ = try await transcriber.transcribe(url: directory.appendingPathComponent("missing.wav"))
            XCTFail("Missing audio must fail")
        } catch {
            guard case .missingAudio? = error as? SpeechTranscriptionError else { return XCTFail("Expected missingAudio, got \(error)") }
        }

        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
    }

    @MainActor
    func testEmptyPCMIsRejectedBeforeSpeechAuthorization() async throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try SpeechAudioTestFixtures.writePCM(in: directory, duration: 0)
        let before = SFSpeechRecognizer.authorizationStatus()
        let transcriber = SpeechTranscriber()

        do {
            _ = try await transcriber.transcribe(url: fixture)
            XCTFail("Empty PCM must not enter recognition")
        } catch {
            guard case .emptyAudio? = error as? SpeechAudioPreparationError else { return XCTFail("Expected emptyAudio, got \(error)") }
        }
        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
    }

    @MainActor
    func testMalformedAudioIsRejectedBeforeSpeechAuthorization() async throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("invalid.wav")
        let data = Data("Not an audio file".utf8)
        try data.write(to: fixture)
        let before = SFSpeechRecognizer.authorizationStatus()
        let transcriber = SpeechTranscriber()

        do {
            _ = try await transcriber.transcribe(url: fixture)
            XCTFail("Invalid audio must not enter recognition")
        } catch {
            guard case .unreadableAudio? = error as? SpeechAudioPreparationError else { return XCTFail("Expected unreadableAudio, got \(error)") }
        }
        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
        XCTAssertEqual(try Data(contentsOf: fixture), data)
    }

    @MainActor
    func testDigitalSilenceDoesNotRequestSpeechAuthorization() async throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try SpeechAudioTestFixtures.writePCM(in: directory, amplitude: 0)
        let before = SFSpeechRecognizer.authorizationStatus()
        let transcriber = SpeechTranscriber()

        do {
            _ = try await transcriber.transcribe(url: fixture)
            XCTFail("Digital silence must produce an actionable empty result")
        } catch {
            guard case .emptyResult? = error as? SpeechTranscriptionError else { return XCTFail("Expected emptyResult, got \(error)") }
        }
        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
    }

    @MainActor
    func testProtocolDefaultsKeepExistingWorkflowDoublesCompatible() {
        let transcriber: any SpeechTranscribing = MinimalWorkflowSpeech()
        transcriber.localeIdentifier = "en-US"
        XCTAssertEqual(transcriber.localeIdentifier, Locale.current.identifier)
        XCTAssertEqual(transcriber.progress, 0)
        XCTAssertNil(transcriber.warningMessage)
        XCTAssertFalse(transcriber.isTranscribing)
    }

    @MainActor
    func testUnsupportedLanguageFailsBeforeAuthorizationRatherThanFallingBack() async throws {
        let directory = try SpeechAudioTestFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try SpeechAudioTestFixtures.writePCM(in: directory)
        let before = SFSpeechRecognizer.authorizationStatus()
        let transcriber = SpeechTranscriber(localeIdentifier: "zz-Invalid")
        do {
            _ = try await transcriber.transcribe(url: fixture)
            XCTFail("An unsupported language must not silently use the keyboard language")
        } catch {
            guard case .unsupportedLanguage? = error as? SpeechTranscriptionError else { return XCTFail("Expected unsupportedLanguage, got \(error)") }
        }
        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), before)
    }
}

@MainActor
private final class MinimalWorkflowSpeech: SpeechTranscribing {
    var isTranscribing: Bool { false }
    func transcribe(url: URL) async throws -> [TranscribedTurn] { [] }
    func cancel() { }
}
#endif
