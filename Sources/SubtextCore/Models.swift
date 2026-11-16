import Foundation

public enum ProcessingState: String, Codable, CaseIterable, Sendable {
    case audioOnly
    case transcribing
    case ready
    case failed
}

public enum SpeakerColor: String, Codable, CaseIterable, Sendable {
    case blue
    case purple
    case green
    case orange
}

public enum AnswerStatus: String, Codable, CaseIterable, Sendable {
    case answered
    case partial
    case needsReview
}

public struct Speaker: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var role: String
    public var color: SpeakerColor

    public init(
        id: UUID = UUID(),
        name: String = "Speaker A",
        role: String = "",
        color: SpeakerColor = .blue
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.color = color
    }
}

public struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var speakerID: UUID?
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String
    public var isQuote: Bool
    public var needsReview: Bool

    public init(
        id: UUID = UUID(),
        speakerID: UUID? = nil,
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 0,
        text: String = "",
        isQuote: Bool = false,
        needsReview: Bool = false
    ) {
        self.id = id
        self.speakerID = speakerID
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.isQuote = isQuote
        self.needsReview = needsReview
    }
}

public struct Bookmark: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var time: TimeInterval
    public var note: String

    public init(id: UUID = UUID(), time: TimeInterval = 0, note: String = "") {
        self.id = id
        self.time = time
        self.note = note
    }
}

public struct QuestionAnswer: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var questionSegmentID: UUID
    public var answerSegmentIDs: [UUID]
    public var status: AnswerStatus
    public var followUp: String

    public init(
        id: UUID = UUID(),
        questionSegmentID: UUID,
        answerSegmentIDs: [UUID] = [],
        status: AnswerStatus = .needsReview,
        followUp: String = ""
    ) {
        self.id = id
        self.questionSegmentID = questionSegmentID
        self.answerSegmentIDs = answerSegmentIDs
        self.status = status
        self.followUp = followUp
    }
}

public struct Interview: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var duration: TimeInterval
    public var audioFilename: String?
    public var speakers: [Speaker]
    public var segments: [TranscriptSegment]
    public var bookmarks: [Bookmark]
    public var questions: [QuestionAnswer]
    public var notes: String
    public var aiSummary: String
    public var aiInsights: [AIInsight]
    public var processingError: String?
    public var transcriptionWarning: String?
    public var processingState: ProcessingState
    public var isDemo: Bool

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFilename: String? = nil,
        speakers: [Speaker] = [],
        segments: [TranscriptSegment] = [],
        bookmarks: [Bookmark] = [],
        questions: [QuestionAnswer] = [],
        notes: String = "",
        aiSummary: String = "",
        aiInsights: [AIInsight] = [],
        processingError: String? = nil,
        transcriptionWarning: String? = nil,
        processingState: ProcessingState = .audioOnly,
        isDemo: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.audioFilename = audioFilename
        self.speakers = speakers
        self.segments = segments
        self.bookmarks = bookmarks
        self.questions = questions
        self.notes = notes
        self.aiSummary = aiSummary
        self.aiInsights = aiInsights
        self.processingError = processingError
        self.transcriptionWarning = transcriptionWarning
        self.processingState = processingState
        self.isDemo = isDemo
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, duration, audioFilename, speakers, segments
        case bookmarks, questions, notes, aiSummary, aiInsights, processingError, transcriptionWarning, processingState, isDemo
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        audioFilename = try values.decodeIfPresent(String.self, forKey: .audioFilename)
        speakers = try values.decode([Speaker].self, forKey: .speakers)
        segments = try values.decode([TranscriptSegment].self, forKey: .segments)
        bookmarks = try values.decode([Bookmark].self, forKey: .bookmarks)
        questions = try values.decode([QuestionAnswer].self, forKey: .questions)
        notes = try values.decode(String.self, forKey: .notes)
        // Added AI fields default only when absent from an older index. Present
        // malformed values, or corruption of existing fields, still fail.
        aiSummary = values.contains(.aiSummary)
            ? try values.decode(String.self, forKey: .aiSummary)
            : ""
        aiInsights = values.contains(.aiInsights)
            ? try values.decode([AIInsight].self, forKey: .aiInsights)
            : []
        processingError = try values.decodeIfPresent(String.self, forKey: .processingError)
        transcriptionWarning = try values.decodeIfPresent(String.self, forKey: .transcriptionWarning)
        processingState = try values.decode(ProcessingState.self, forKey: .processingState)
        isDemo = try values.decode(Bool.self, forKey: .isDemo)
    }

    /// Inserts or edits one turn, preserving chronological playback order.
    public mutating func upsertSegment(_ segment: TranscriptSegment) {
        if let index = segments.firstIndex(where: { $0.id == segment.id }) { segments[index] = segment }
        else { segments.append(segment) }
        segments.sort { $0.startTime < $1.startTime }
    }

    /// Resolves the current display name by stable identity, so renaming a
    /// speaker updates every segment without rewriting transcript text.
    public func speakerName(for speakerID: UUID?) -> String {
        guard let speakerID,
              let speaker = speakers.first(where: { $0.id == speakerID }) else {
            return "Unknown speaker"
        }
        let name = speaker.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unknown speaker" : name
    }

    /// Text used by local search. No audio, network service, or transcription
    /// is needed to search the material the user has already saved.
    public var searchText: String {
        ([title, notes, aiSummary, transcriptionWarning ?? ""]
            + speakers.flatMap { [$0.name, $0.role] }
            + segments.map(\.text)
            + bookmarks.map(\.note)
            + questions.map(\.followUp)
            + aiInsights.flatMap { [$0.title, $0.detail] })
            .joined(separator: "\n")
    }

    /// Whether flagged text, an unresolved answer, or a written follow-up
    /// remains for the session's review filter.
    public var hasFollowUps: Bool {
        segments.contains(where: \.needsReview) || questions.contains {
            $0.status != .answered
                || !$0.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public static func defaultTitle(date: Date = Date()) -> String {
        "Interview · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    /// A readable text export using the current speaker names and saved text.
    public func exportTranscript() -> String {
        var lines = [title, createdAt.formatted(date: .abbreviated, time: .shortened)]
        if isDemo {
            lines.append("Sample interview · no audio attached")
        }
        if let transcriptionWarning,
           !transcriptionWarning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Transcription warning: \(transcriptionWarning)")
        }
        lines.append("")

        if segments.isEmpty {
            lines.append("No transcript has been added.")
        } else {
            for segment in segments {
                lines.append("[\(TimeFormatting.timestamp(segment.startTime))] \(speakerName(for: segment.speakerID))")
                lines.append(segment.text)
                lines.append("")
            }
        }

        if !aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("AI draft summary")
            lines.append(aiSummary)
            lines.append("")
        }
        if !aiInsights.isEmpty {
            lines.append("AI draft insights · review against the original audio")
            for insight in aiInsights {
                lines.append("\(insight.kind.displayName): \(insight.title)")
                lines.append(insight.detail)
                for segmentID in insight.segmentIDs {
                    guard let segment = segments.first(where: { $0.id == segmentID }) else { continue }
                    lines.append("Evidence [\(TimeFormatting.timestamp(segment.startTime))] \(speakerName(for: segment.speakerID)): \(segment.text)")
                }
                lines.append("")
            }
        }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Notes")
            lines.append(notes)
        }
        return lines.joined(separator: "\n")
    }
}
