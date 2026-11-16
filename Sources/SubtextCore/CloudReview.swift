import Foundation

public struct CloudTurn: Codable, Equatable, Sendable {
    public let speaker: String
    public let startTime: Double
    public let endTime: Double
    public let text: String

    public init(speaker: String, startTime: Double, endTime: Double, text: String) {
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public struct CloudReviewResult: Codable, Equatable, Sendable {
    public let turns: [CloudTurn]
    public let summary: String
    public let insights: [CloudInsight]?
    public let questions: [CloudQuestion]?

    public init(
        turns: [CloudTurn],
        summary: String,
        insights: [CloudInsight]? = nil,
        questions: [CloudQuestion]? = nil
    ) {
        self.turns = turns
        self.summary = summary
        self.insights = insights
        self.questions = questions
    }

    private enum CodingKeys: String, CodingKey { case turns, summary, insights, questions }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        turns = try values.decode([CloudTurn].self, forKey: .turns)
        summary = try values.decode(String.self, forKey: .summary)
        // Missing fields denote an old response. Explicit null is malformed,
        // so it cannot silently switch a current response to the fallback.
        insights = values.contains(.insights) ? try values.decode([CloudInsight].self, forKey: .insights) : nil
        questions = values.contains(.questions) ? try values.decode([CloudQuestion].self, forKey: .questions) : nil
    }
}

public enum ReviewApplicationError: Error, Equatable, Sendable, LocalizedError {
    case invalidResponse
    case noSpeech

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The AI draft contains invalid text, citations, speaker labels, or timestamps. Your original interview is unchanged."
        case .noSpeech:
            "The AI draft did not identify any speech. Your original interview is unchanged."
        }
    }
}

/// Applies a validated cloud draft to a value copy. The original recording and
/// user notes remain intact. Reprocessing creates new transcript/speaker IDs;
/// neutral labels are attribution suggestions, never inferred identities.
public enum ReviewApplication {
    public static func applying(_ result: CloudReviewResult, to session: Interview) throws -> Interview {
        guard session.duration.isFinite, session.duration > 0,
              result.turns.count <= 2_000 else {
            throw ReviewApplicationError.invalidResponse
        }
        let summary = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary.count <= 6_000 else {
            throw ReviewApplicationError.invalidResponse
        }
        guard !result.turns.isEmpty else { throw ReviewApplicationError.noSpeech }

        let neutralLabels = "ABCDEFGHIJKLMNO".map { "Speaker \($0)" }
        let labelIndices = Dictionary(uniqueKeysWithValues: neutralLabels.enumerated().map { ($0.element, $0.offset) })
        var previousStart = -1.0
        var normalizedTurns: [CloudTurn] = []

        for turn in result.turns {
            let label = turn.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard labelIndices[label] != nil || label == "Unassigned",
                  !text.isEmpty, text.count <= 20_000,
                  turn.startTime.isFinite, turn.endTime.isFinite,
                  turn.startTime >= 0, turn.startTime < turn.endTime,
                  turn.startTime >= previousStart,
                  turn.endTime <= session.duration else {
                throw ReviewApplicationError.invalidResponse
            }
            previousStart = turn.startTime
            normalizedTurns.append(CloudTurn(
                speaker: label,
                startTime: turn.startTime,
                endTime: turn.endTime,
                text: text
            ))
        }

        var speakers: [Speaker] = []
        var speakerIDs: [String: UUID] = [:]
        var segments: [TranscriptSegment] = []
        for turn in normalizedTurns {
            let speakerID: UUID?
            if let index = labelIndices[turn.speaker] {
                if let existing = speakerIDs[turn.speaker] {
                    speakerID = existing
                } else {
                    let speaker = Speaker(
                        name: turn.speaker,
                        color: SpeakerColor.allCases[index % SpeakerColor.allCases.count]
                    )
                    speakers.append(speaker)
                    speakerIDs[turn.speaker] = speaker.id
                    speakerID = speaker.id
                }
            } else {
                speakerID = nil
            }
            segments.append(TranscriptSegment(
                speakerID: speakerID,
                startTime: turn.startTime,
                endTime: turn.endTime,
                text: turn.text,
                needsReview: speakerID == nil || turn.text.localizedCaseInsensitiveContains("[inaudible]")
            ))
        }

        var reviewed = session
        reviewed.speakers = speakers
        reviewed.segments = segments
        reviewed.aiInsights = try makeInsights(result.insights ?? [], segments: segments)
        if let questions = result.questions {
            reviewed.questions = try makeQuestions(questions, segments: segments)
        } else {
            // Only old responses without structured Q&A use punctuation-based
            // drafting. A current model's explicit empty array stays empty.
            reviewed.questions = LocalReview.suggestQuestions(segments: segments)
        }
        reviewed.aiSummary = summary
        reviewed.processingError = nil
        reviewed.transcriptionWarning = nil
        reviewed.processingState = .ready
        return reviewed
    }

    /// Applies analysis to the exact transcript that was submitted. No turn,
    /// timestamp, speaker identity, quote, flag, or user note is replaced.
    /// AI pairs replace untouched local candidates while human Q&A review stays.
    public static func applying(_ result: CloudAnalysisResult, to session: Interview) throws -> Interview {
        try validateTranscript(session.segments, duration: session.duration)
        let summary = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, summary.count <= 6_000 else {
            throw ReviewApplicationError.invalidResponse
        }
        let insights = try makeInsights(result.insights, segments: session.segments, preserving: session.aiInsights)
        let suggestions = try makeQuestions(result.questions, segments: session.segments)

        var merged: [QuestionAnswer] = []
        var seenQuestions = Set<UUID>()
        let proposedQuestionIDs = Set(suggestions.map(\.questionSegmentID))
        for question in session.questions {
            guard seenQuestions.insert(question.questionSegmentID).inserted else { continue }
            let hasHumanReview = question.status != .needsReview
                || !question.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasHumanReview || proposedQuestionIDs.contains(question.questionSegmentID) {
                merged.append(question)
            }
        }
        for question in suggestions {
            if let index = merged.firstIndex(where: { $0.questionSegmentID == question.questionSegmentID }) {
                // The AI can suggest different evidence, but the reporter's
                // saved decision and written follow-up remain their own.
                merged[index].answerSegmentIDs = question.answerSegmentIDs
                if merged[index].followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    merged[index].followUp = question.followUp
                }
            } else {
                merged.append(question)
            }
        }
        let positions = Dictionary(uniqueKeysWithValues: session.segments.enumerated().map { ($0.element.id, $0.offset) })
        merged = merged.enumerated().sorted {
            let left = positions[$0.element.questionSegmentID] ?? Int.max
            let right = positions[$1.element.questionSegmentID] ?? Int.max
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)

        var reviewed = session
        reviewed.aiSummary = summary
        reviewed.aiInsights = insights
        reviewed.questions = merged
        reviewed.processingError = nil
        reviewed.processingState = .ready
        return reviewed
    }

    private static func validateTranscript(_ segments: [TranscriptSegment], duration: TimeInterval) throws {
        guard duration.isFinite, duration > 0, segments.count <= 2_000,
              Set(segments.map(\.id)).count == segments.count else {
            throw ReviewApplicationError.invalidResponse
        }
        guard !segments.isEmpty else { throw ReviewApplicationError.noSpeech }
        var previousStart = -1.0
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 20_000,
                  segment.startTime.isFinite, segment.endTime.isFinite,
                  segment.startTime >= 0, segment.startTime < segment.endTime,
                  segment.startTime >= previousStart, segment.endTime <= duration else {
                throw ReviewApplicationError.invalidResponse
            }
            previousStart = segment.startTime
        }
    }

    private static func makeInsights(
        _ inputs: [CloudInsight],
        segments: [TranscriptSegment],
        preserving existing: [AIInsight] = []
    ) throws -> [AIInsight] {
        guard inputs.count <= 30 else { throw ReviewApplicationError.invalidResponse }
        var insights: [AIInsight] = []
        for input in inputs {
            let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = input.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence = input.evidenceTurnIndices
            guard !title.isEmpty, title.count <= 160,
                  !detail.isEmpty, detail.count <= 2_000,
                  !evidence.isEmpty, evidence.count <= 20,
                  Set(evidence).count == evidence.count,
                  evidence.allSatisfy({ segments.indices.contains($0) }) else {
                throw ReviewApplicationError.invalidResponse
            }
            let segmentIDs = evidence.sorted().map { segments[$0].id }
            guard !insights.contains(where: {
                $0.kind == input.kind && $0.title == title && $0.detail == detail && $0.segmentIDs == segmentIDs
            }) else {
                throw ReviewApplicationError.invalidResponse
            }
            let prior = existing.first {
                $0.kind == input.kind && $0.title == title && $0.detail == detail && $0.segmentIDs == segmentIDs
            }
            insights.append(AIInsight(
                id: prior?.id ?? UUID(),
                kind: input.kind,
                title: title,
                detail: detail,
                segmentIDs: segmentIDs
            ))
        }
        return insights
    }

    private static func makeQuestions(_ inputs: [CloudQuestion], segments: [TranscriptSegment]) throws -> [QuestionAnswer] {
        guard inputs.count <= 500 else { throw ReviewApplicationError.invalidResponse }
        var questions: [QuestionAnswer] = []
        var seen = Set<Int>()
        for input in inputs.sorted(by: { $0.questionTurnIndex < $1.questionTurnIndex }) {
            let followUp = input.followUp.trimmingCharacters(in: .whitespacesAndNewlines)
            guard segments.indices.contains(input.questionTurnIndex),
                  seen.insert(input.questionTurnIndex).inserted,
                  input.answerTurnIndices.count <= 2_000,
                  Set(input.answerTurnIndices).count == input.answerTurnIndices.count,
                  input.answerTurnIndices.allSatisfy({
                      segments.indices.contains($0) && $0 > input.questionTurnIndex
                  }), followUp.count <= 2_000 else {
                throw ReviewApplicationError.invalidResponse
            }
            let questionID = segments[input.questionTurnIndex].id
            questions.append(QuestionAnswer(
                id: questionID,
                questionSegmentID: questionID,
                answerSegmentIDs: input.answerTurnIndices.sorted().map { segments[$0].id },
                status: .needsReview,
                followUp: followUp
            ))
        }
        return questions
    }
}
