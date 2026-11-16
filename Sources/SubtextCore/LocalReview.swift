import Foundation

/// A deterministic, local drafting aid. A question mark identifies a possible
/// question; following nonempty segments are grouped until the next question.
/// New groups require a person's review. A repeated scan preserves saved
/// identities, review decisions, and follow-ups for matching question segments.
public enum LocalReview {
    public static func suggestQuestions(
        segments: [TranscriptSegment],
        preserving existing: [QuestionAnswer] = []
    ) -> [QuestionAnswer] {
        var previousByQuestion: [UUID: QuestionAnswer] = [:]
        for question in existing where previousByQuestion[question.questionSegmentID] == nil {
            previousByQuestion[question.questionSegmentID] = question
        }
        var suggestions: [QuestionAnswer] = []

        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if text.hasSuffix("?") {
                var question = previousByQuestion[segment.id] ?? QuestionAnswer(
                    id: segment.id,
                    questionSegmentID: segment.id,
                    status: .needsReview
                )
                question.answerSegmentIDs = []
                suggestions.append(question)
            } else if !suggestions.isEmpty {
                suggestions[suggestions.count - 1].answerSegmentIDs.append(segment.id)
            }
        }

        return suggestions
    }
}
