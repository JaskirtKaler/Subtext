#if os(iOS) && canImport(Subtext)
import AVFoundation
import Foundation
import XCTest
import SubtextCore
@testable import Subtext
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// Explicitly uploads only the bundled fictional recording to the real provider.
/// This test never substitutes model output or reads the normal interview library.
/// Enable SUBTEXT_RUN_LIVE_AI_TESTS=1 in the Test scheme environment after setting
/// up the running test host's Firebase App Check debug token and model access.
final class LiveAIIntegrationTests: XCTestCase {
    @MainActor
    func testRealAudioSpeakersInsightsQuestionsAndTranscriptReview() async throws {
        guard ProcessInfo.processInfo.environment["SUBTEXT_RUN_LIVE_AI_TESTS"] == "1" else {
            throw XCTSkip("Real-provider test is opt-in: set SUBTEXT_RUN_LIVE_AI_TESTS=1 with a registered App Check test-host token and model access. No AI request was made.")
        }

        #if canImport(FirebaseCore)
        // The SDK may otherwise print its private debug-token setup message.
        let logging = FirebaseConfiguration.shared
        let previousLogLevel = logging.loggerLevel()
        logging.setLoggerLevel(.min)
        defer { logging.setLoggerLevel(previousLogLevel) }
        #else
        XCTFail("Real-provider test host must expose FirebaseCore before making requests.")
        return
        #endif

        let service = CloudReviewService()
        guard service.isAvailable else {
            XCTFail("Live provider is not configured (\(service.configurationStatus.error?.rawValue ?? "unknown_configuration")).")
            return
        }
        guard let fixture = Bundle.main.url(forResource: "IntegrationSample", withExtension: "wav") else {
            XCTFail("The hosted app is missing the fictional integration recording.")
            return
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SubtextLiveAI-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var stage = "fixture_preparation"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let originalBytes = try Data(contentsOf: fixture)
            let audio = directory.appendingPathComponent("fictional-interview.wav")
            try originalBytes.write(to: audio, options: .atomic)
            let duration = try await AVURLAsset(url: audio).load(.duration).seconds
            var original = Interview(
                title: "Fictional live integration test",
                duration: duration,
                audioFilename: audio.lastPathComponent,
                bookmarks: [Bookmark(time: 1, note: "Reporter bookmark")],
                notes: "Synthetic integration test editorial note."
            )

            stage = "audio_review"
            let audioResult = try await service.analyzeAudio(url: audio)
            guard !audioResult.turns.isEmpty else {
                XCTFail("Live audio review returned zero transcript turns.")
                return
            }
            let neutralSpeakers = Set(audioResult.turns.map(\.speaker).filter { $0 != "Unassigned" })
            guard neutralSpeakers.count >= 2 else {
                XCTFail("The two-voice fictional recording needs at least two neutral speaker groups; fewer were returned.")
                return
            }
            XCTAssertFalse(audioResult.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Live audio review needs a summary.")
            guard let audioInsights = audioResult.insights, !audioInsights.isEmpty,
                  let audioQuestions = audioResult.questions, !audioQuestions.isEmpty else {
                XCTFail("Live audio review needs evidence-linked insights and Q&A for the fictional interview.")
                return
            }
            assertValidEvidence(insights: audioInsights, questions: audioQuestions, turnCount: audioResult.turns.count)
            var reviewed = try ReviewApplication.applying(audioResult, to: original)
            XCTAssertTrue(reviewed.notes == original.notes, "Audio review must preserve editorial notes.")
            XCTAssertTrue(reviewed.bookmarks == original.bookmarks, "Audio review must preserve bookmarks.")
            XCTAssertTrue(reviewed.audioFilename == original.audioFilename, "Audio review must preserve the original recording reference.")

            // Apply manual edits to real model output; no expected transcript is
            // inserted into either the request or the result.
            reviewed.segments[0].text += " [reporter reviewed wording]"
            reviewed.segments[0].isQuote = true
            reviewed.segments[0].needsReview = true
            reviewed.speakers[0].name = "Reporter-assigned speaker name"
            reviewed.questions[0].status = .partial
            reviewed.questions[0].followUp = "Reporter-written follow-up to preserve."
            let humanQuestion = reviewed.questions[0]
            original = reviewed

            stage = "transcript_review"
            let analysis = try await service.reviewTranscript(reviewed)
            guard !analysis.insights.isEmpty, !analysis.questions.isEmpty else {
                XCTFail("Live transcript review needs cited insights and Q&A for the supplied interview.")
                return
            }
            XCTAssertFalse(analysis.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Live transcript review needs a summary.")
            assertValidEvidence(insights: analysis.insights, questions: analysis.questions, turnCount: reviewed.segments.count)
            let updated = try ReviewApplication.applying(analysis, to: reviewed)
            XCTAssertTrue(updated.segments == original.segments, "Transcript review must preserve manual text, quote, and review-flag edits.")
            XCTAssertTrue(updated.speakers == original.speakers, "Transcript review must preserve manual speaker names and identities.")
            XCTAssertTrue(updated.notes == original.notes && updated.bookmarks == original.bookmarks, "Transcript review must preserve notes and bookmarks.")
            let preservedQuestion = updated.questions.first { $0.questionSegmentID == humanQuestion.questionSegmentID }
            XCTAssertTrue(preservedQuestion?.status == humanQuestion.status, "Transcript review must preserve the reporter's Q&A decision.")
            XCTAssertTrue(preservedQuestion?.followUp == humanQuestion.followUp, "Transcript review must preserve the reporter's follow-up.")
            let sourceIDs = Set(updated.segments.map(\.id))
            XCTAssertTrue(updated.aiInsights.allSatisfy { !$0.segmentIDs.isEmpty && Set($0.segmentIDs).isSubset(of: sourceIDs) }, "Saved insight evidence must resolve to actual transcript turns.")

            stage = "persistence"
            let repository = InterviewRepository(directory: directory)
            try repository.save([updated])
            let restored = try repository.load()
            XCTAssertTrue(restored.count == 1 && restored.first == updated, "The complete live review and manual edits must survive a repository round-trip.")
            XCTAssertTrue(try Data(contentsOf: audio) == originalBytes, "The original recording bytes must remain intact after both real-provider requests.")
        } catch let error as CloudReviewError {
            XCTFail("Live provider failed at \(stage) (\(error.rawValue)).")
        } catch is CancellationError {
            XCTFail("Live provider check was cancelled at \(stage).")
        } catch {
            // SDK/filesystem NSError descriptions may include private values.
            XCTFail("Live integration failed at \(stage); raw details withheld.")
        }
    }

    private func assertValidEvidence(insights: [CloudInsight], questions: [CloudQuestion], turnCount: Int, file: StaticString = #filePath, line: UInt = #line) {
        let validIndices = 0..<turnCount
        XCTAssertTrue(insights.allSatisfy { !$0.evidenceTurnIndices.isEmpty && $0.evidenceTurnIndices.allSatisfy(validIndices.contains) }, "Every live insight must cite an actual source turn.", file: file, line: line)
        XCTAssertTrue(questions.allSatisfy { question in
            validIndices.contains(question.questionTurnIndex) && question.answerTurnIndices.allSatisfy { validIndices.contains($0) && $0 > question.questionTurnIndex }
        }, "Every live Q&A reference must resolve to a question and later answer turn.", file: file, line: line)
        XCTAssertTrue(questions.contains { !$0.answerTurnIndices.isEmpty }, "The fictional interview needs at least one question with a cited answer.", file: file, line: line)
    }
}
#endif
