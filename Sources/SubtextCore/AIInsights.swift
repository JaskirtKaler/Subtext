import Foundation

public enum AIInsightKind: String, Codable, CaseIterable, Sendable {
    case keyPoint
    case openQuestion
    case followUp
    case needsContext

    public var displayName: String {
        switch self {
        case .keyPoint: "Key point"
        case .openQuestion: "Open question"
        case .followUp: "Follow-up"
        case .needsContext: "Needs context"
        }
    }
}

/// A saved AI suggestion linked to exact, editable transcript turns. The UUID
/// belongs to the app; a model never assigns the identity of saved material.
public struct AIInsight: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: AIInsightKind
    public var title: String
    public var detail: String
    public var segmentIDs: [UUID]

    public init(
        id: UUID = UUID(),
        kind: AIInsightKind,
        title: String,
        detail: String,
        segmentIDs: [UUID]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.segmentIDs = segmentIDs
    }
}

public struct CloudInsight: Codable, Equatable, Sendable {
    public let kind: AIInsightKind
    public let title: String
    public let detail: String
    public let evidenceTurnIndices: [Int]

    public init(kind: AIInsightKind, title: String, detail: String, evidenceTurnIndices: [Int]) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.evidenceTurnIndices = evidenceTurnIndices
    }
}

/// A possible spoken question and answer evidence. Review status is deliberately
/// absent from the model response: every new pair starts as needsReview.
public struct CloudQuestion: Codable, Equatable, Sendable {
    public let questionTurnIndex: Int
    public let answerTurnIndices: [Int]
    public let followUp: String

    public init(questionTurnIndex: Int, answerTurnIndices: [Int], followUp: String = "") {
        self.questionTurnIndex = questionTurnIndex
        self.answerTurnIndices = answerTurnIndices
        self.followUp = followUp
    }
}

/// Analysis of the current transcript. It contains no replacement turns or
/// timestamps, so applying it cannot alter a person's transcript corrections.
public struct CloudAnalysisResult: Codable, Equatable, Sendable {
    public let summary: String
    public let insights: [CloudInsight]
    public let questions: [CloudQuestion]

    public init(summary: String, insights: [CloudInsight] = [], questions: [CloudQuestion] = []) {
        self.summary = summary
        self.insights = insights
        self.questions = questions
    }
}
