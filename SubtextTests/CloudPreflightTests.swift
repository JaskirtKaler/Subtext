#if canImport(SubtextAIValidation) || canImport(Subtext)
import XCTest
#if canImport(SubtextAIValidation)
@testable import SubtextAIValidation
#else
@testable import Subtext
#endif

/// Exercises callback lifecycle without configuring Firebase or making requests.
final class CloudPreflightTests: XCTestCase {
    @MainActor
    func testSynchronousCallbackCompletesAndRepeatedCallbacksAreIgnored() async throws {
        let waiter = CloudPreflightWaiter()
        try await waiter.wait(timeout: .seconds(1)) { complete in
            complete(.success(()))
            complete(.success(()))
        }
        // Allow a repeated callback to run after the caller has returned.
        await Task.yield()
    }

    @MainActor
    func testCallbackFailurePreservesItsTypedError() async throws {
        do {
            try await CloudPreflightWaiter().wait { complete in
                complete(.failure(CloudReviewError.appCheckRequired))
            }
            XCTFail("An App Check failure must reach the caller")
        } catch {
            XCTAssertEqual(error as? CloudReviewError, .appCheckRequired)
        }
    }

    @MainActor
    func testCancellationReturnsWithoutSDKCallbackAndIgnoresLateCallback() async throws {
        let waiter = CloudPreflightWaiter()
        let probe = PreflightCallbackProbe()
        let task = Task { @MainActor in
            try await waiter.wait(timeout: .seconds(1)) { probe.callback = $0 }
        }
        await waitForCallback(in: probe)
        task.cancel()
        do {
            try await task.value
            XCTFail("Cancellation must release the preflight caller")
        } catch is CancellationError {
            // SDK callback has deliberately not fired.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
        probe.callback?(.success(()))
        probe.callback?(.failure(CloudReviewError.appCheckRequired))
        await Task.yield()
    }

    @MainActor
    func testAlreadyCancelledTaskDoesNotStartSDKOperation() async throws {
        let probe = PreflightCallbackProbe()
        let task = Task { @MainActor in
            try await CloudPreflightWaiter().wait { probe.callback = $0 }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("A cancelled task must fail before starting the SDK operation")
        } catch is CancellationError { }
        XCTAssertNil(probe.callback)
    }

    @MainActor
    func testTimeoutReturnsWithoutSDKCallbackAndIgnoresLateCallback() async throws {
        let waiter = CloudPreflightWaiter()
        let probe = PreflightCallbackProbe()
        do {
            try await waiter.wait(timeout: .milliseconds(10)) { probe.callback = $0 }
            XCTFail("A missing SDK callback must reach the deadline")
        } catch {
            XCTAssertEqual(error as? CloudReviewError, .connectionTimedOut)
        }
        XCTAssertNotNil(probe.callback)
        probe.callback?(.success(()))
        probe.callback?(.failure(CloudReviewError.appCheckRequired))
        await Task.yield()
    }

    @MainActor
    private func waitForCallback(in probe: PreflightCallbackProbe) async {
        for _ in 0..<1_000 {
            if probe.callback != nil { return }
            await Task.yield()
        }
        XCTFail("Preflight did not start its callback operation")
    }
}

@MainActor
private final class PreflightCallbackProbe {
    var callback: (@Sendable (Result<Void, Error>) -> Void)?
}
#endif
