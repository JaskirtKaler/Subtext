import Foundation

/// Fixed, fictional examples for exploring review tools. These sessions contain
/// sample text only; they never point to a recording or simulate real playback.
public enum DemoData {
    public static let interviews: [Interview] = [publicSpace, localNews, communityGarden]

    private static let publicSpace: Interview = {
        let a = Speaker(id: id("11000000-0000-0000-0000-000000000001"), name: "Speaker A", role: "Interviewer", color: .blue)
        let b = Speaker(id: id("11000000-0000-0000-0000-000000000002"), name: "Speaker B", role: "Interview guest", color: .purple)
        let segments = [
            segment("11100000-0000-0000-0000-000000000001", a.id, 0, 9, "When you picture a successful public space, what do you see?"),
            segment("11100000-0000-0000-0000-000000000002", b.id, 10, 31, "A place where people have a reason to stay. A bench in the shade, room for a conversation, and a route that works for someone pushing a stroller."),
            segment("11100000-0000-0000-0000-000000000003", b.id, 32, 49, "The small details tell you whether a place is welcoming. We start by watching how people already use it, then ask what is missing.", quote: true),
            segment("11100000-0000-0000-0000-000000000004", a.id, 52, 62, "How did those observations change the first proposal?"),
            segment("11100000-0000-0000-0000-000000000005", b.id, 64, 86, "We moved the seating closer to the walking route and kept an open area for informal games. The first drawing looked tidy, but it did not leave enough room for everyday use."),
            segment("11100000-0000-0000-0000-000000000006", a.id, 91, 100, "Who has not been heard from yet?"),
            segment("11100000-0000-0000-0000-000000000007", b.id, 102, 125, "We still need to speak with people who use the space early in the morning and later in the evening. A meeting at lunchtime will never give us the whole picture.", review: true),
            segment("11100000-0000-0000-0000-000000000008", a.id, 129, 138, "What would you want to learn before making the next decision?"),
            segment("11100000-0000-0000-0000-000000000009", b.id, 140, 162, "Whether the changes make it easier for different groups to share the space. We can try temporary seating first, listen, and adjust before anything permanent is built.")
        ]
        return Interview(
            id: id("10000000-0000-0000-0000-000000000001"),
            title: "The future of public space",
            createdAt: Date(timeIntervalSince1970: 1_794_477_600),
            duration: 162,
            speakers: [a, b],
            segments: segments,
            bookmarks: [
                Bookmark(id: id("11200000-0000-0000-0000-000000000001"), time: 32, note: "A useful description of what makes a place welcoming."),
                Bookmark(id: id("11200000-0000-0000-0000-000000000002"), time: 102, note: "Ask about outreach outside meeting hours.")
            ],
            questions: [
                question(segments[0], answers: [segments[1], segments[2]], status: .answered),
                question(segments[3], answers: [segments[4]], status: .answered),
                question(segments[5], answers: [segments[6]], status: .partial, followUp: "Which groups will you contact, and when?"),
                question(segments[7], answers: [segments[8]], followUp: "What would count as a successful temporary trial?")
            ],
            notes: "Fictional sample transcript for exploring Subtext. No audio is attached. Review labels are examples, not verified findings.\n\nStory angle: how small design decisions shape who feels welcome.",
            processingState: .ready,
            isDemo: true
        )
    }()

    private static let localNews: Interview = {
        let a = Speaker(id: id("21000000-0000-0000-0000-000000000001"), name: "Speaker A", role: "Interviewer", color: .blue)
        let b = Speaker(id: id("21000000-0000-0000-0000-000000000002"), name: "Speaker B", role: "Interview guest", color: .green)
        let segments = [
            segment("21100000-0000-0000-0000-000000000001", a.id, 0, 8, "What makes a local story worth following?"),
            segment("21100000-0000-0000-0000-000000000002", b.id, 10, 31, "A question that matters in someone's daily life. Sometimes it starts with a bus stop, a notice in a window, or a reader asking why something changed."),
            segment("21100000-0000-0000-0000-000000000003", a.id, 35, 44, "How do you decide which questions to investigate first?"),
            segment("21100000-0000-0000-0000-000000000004", b.id, 46, 68, "We look at the impact, what we can establish, and who is affected. We also ask whether we have heard from the people closest to the issue."),
            segment("21100000-0000-0000-0000-000000000005", b.id, 69, 83, "A good follow-up begins with noticing what the first answer left open.", quote: true),
            segment("21100000-0000-0000-0000-000000000006", a.id, 87, 97, "What would help readers take part in that process?"),
            segment("21100000-0000-0000-0000-000000000007", b.id, 99, 122, "A clear way to send questions, and an explanation of what we are working on. We should also tell people when we do not yet have an answer."),
            segment("21100000-0000-0000-0000-000000000008", a.id, 127, 138, "Is there an example we could look at together?"),
            segment("21100000-0000-0000-0000-000000000009", b.id, 140, 157, "I can bring a reader question and the notes from our first conversation. We would need permission before sharing anything that identifies a source.", review: true)
        ]
        return Interview(
            id: id("20000000-0000-0000-0000-000000000002"),
            title: "Listening to the neighbourhood",
            createdAt: Date(timeIntervalSince1970: 1_794_391_200),
            duration: 157,
            speakers: [a, b],
            segments: segments,
            bookmarks: [Bookmark(id: id("21200000-0000-0000-0000-000000000001"), time: 69, note: "Potential quote about follow-up questions.")],
            questions: [
                question(segments[0], answers: [segments[1]], status: .answered),
                question(segments[2], answers: [segments[3], segments[4]], status: .answered),
                question(segments[5], answers: [segments[6]], status: .partial, followUp: "How will readers know what happened to their question?"),
                question(segments[7], answers: [segments[8]], followUp: "Arrange a follow-up and confirm what can be shared.")
            ],
            notes: "Fictional sample transcript. No audio is attached. Speaker labels and Q&A review states are illustrative.\n\nFollow up on the reader feedback process.",
            processingState: .ready,
            isDemo: true
        )
    }()

    private static let communityGarden: Interview = {
        let a = Speaker(id: id("31000000-0000-0000-0000-000000000001"), name: "Speaker A", role: "Interviewer", color: .blue)
        let b = Speaker(id: id("31000000-0000-0000-0000-000000000002"), name: "Speaker B", role: "Interview guest", color: .orange)
        let segments = [
            segment("31100000-0000-0000-0000-000000000001", a.id, 0, 8, "How did the garden project begin?"),
            segment("31100000-0000-0000-0000-000000000002", b.id, 10, 33, "A few neighbours wanted somewhere to grow food and spend time outside. We started with a shared planting day and asked everyone what they would like to try."),
            segment("31100000-0000-0000-0000-000000000003", a.id, 37, 46, "What has surprised you most?"),
            segment("31100000-0000-0000-0000-000000000004", b.id, 48, 66, "People bring different knowledge. Someone knows about soil, someone can repair a gate, and someone else makes sure a new volunteer feels included.", quote: true),
            segment("31100000-0000-0000-0000-000000000005", a.id, 70, 79, "What is the biggest challenge for the next season?"),
            segment("31100000-0000-0000-0000-000000000006", b.id, 81, 103, "Sharing the work consistently. We want a simple schedule so that watering and opening the gate do not always fall to the same people.", review: true),
            segment("31100000-0000-0000-0000-000000000007", a.id, 107, 117, "How can a new neighbour get involved?"),
            segment("31100000-0000-0000-0000-000000000008", b.id, 119, 140, "Come to an open session, ask questions, and start with a small task. You do not need to arrive with tools or experience.")
        ]
        return Interview(
            id: id("30000000-0000-0000-0000-000000000003"),
            title: "Growing something together",
            createdAt: Date(timeIntervalSince1970: 1_794_218_400),
            duration: 140,
            speakers: [a, b],
            segments: segments,
            bookmarks: [Bookmark(id: id("31200000-0000-0000-0000-000000000001"), time: 48, note: "Different ways to contribute.")],
            questions: [
                question(segments[0], answers: [segments[1]], status: .answered),
                question(segments[2], answers: [segments[3]], status: .answered),
                question(segments[4], answers: [segments[5]], status: .partial, followUp: "Who will coordinate the shared schedule?"),
                question(segments[6], answers: [segments[7]], status: .answered)
            ],
            notes: "Fictional sample transcript for exploring bookmarks, quotes, and follow-ups. No audio is attached.",
            processingState: .ready,
            isDemo: true
        )
    }()

    private static func id(_ value: String) -> UUID {
        // All values are source-controlled UUID literals.
        UUID(uuidString: value)!
    }

    private static func segment(
        _ value: String,
        _ speakerID: UUID,
        _ start: TimeInterval,
        _ end: TimeInterval,
        _ text: String,
        quote: Bool = false,
        review: Bool = false
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: id(value),
            speakerID: speakerID,
            startTime: start,
            endTime: end,
            text: text,
            isQuote: quote,
            needsReview: review
        )
    }

    private static func question(
        _ segment: TranscriptSegment,
        answers: [TranscriptSegment],
        status: AnswerStatus = .needsReview,
        followUp: String = ""
    ) -> QuestionAnswer {
        QuestionAnswer(
            id: segment.id,
            questionSegmentID: segment.id,
            answerSegmentIDs: answers.map(\.id),
            status: status,
            followUp: followUp
        )
    }
}
