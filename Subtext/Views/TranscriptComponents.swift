import SwiftUI
import SubtextCore

struct TranscriptCard: View {
    let segment: TranscriptSegment
    let session: Interview
    let active: Bool
    let jump: () -> Void
    let rename: () -> Void
    let edit: () -> Void
    let quote: () -> Void
    let flag: () -> Void
    private var color: Color { session.speakers.first(where: { $0.id == segment.speakerID })?.color.tint ?? .secondary }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Button(action: rename) {
                    HStack(spacing: 7) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        Text(session.speakerName(for: segment.speakerID)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    }.frame(minHeight: 44)
                }.accessibilityLabel("Edit speaker \(session.speakerName(for: segment.speakerID))")
                    .accessibilityIdentifier("segment.speaker.\(segment.id.uuidString)")
                Spacer(minLength: 3)
                Button(action: jump) {
                    Text(TimeFormatting.timestamp(segment.startTime)).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.blue).frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Jump to \(TimeFormatting.timestamp(segment.startTime))")
            }
            Text(segment.text).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if segment.isQuote || segment.needsReview {
                ViewThatFits(in: .horizontal) {
                    HStack { if segment.isQuote { Pill(title: "Saved quote", icon: "quote.opening") }; if segment.needsReview { Pill(title: "Needs review", color: .orange, icon: "flag") } }
                    VStack(alignment: .leading) { if segment.isQuote { Pill(title: "Saved quote", icon: "quote.opening") }; if segment.needsReview { Pill(title: "Needs review", color: .orange, icon: "flag") } }
                }
            }
            HStack(spacing: 4) {
                Button(action: quote) { Label(segment.isQuote ? "Saved" : "Quote", systemImage: segment.isQuote ? "quote.bubble.fill" : "quote.bubble").font(.caption).frame(minHeight: 44) }.accessibilityLabel(segment.isQuote ? "Unsave quote" : "Save quote")
                Spacer(minLength: 4)
                IconButton(symbol: segment.needsReview ? "flag.fill" : "flag", label: segment.needsReview ? "Clear review flag" : "Flag for review", color: segment.needsReview ? .orange : Theme.blue, action: flag)
                IconButton(symbol: "pencil", label: "Edit transcript turn", action: edit).accessibilityIdentifier("segment.edit.\(segment.id.uuidString)")
            }.padding(.bottom, -8)
        }.padding(16).padding(.leading, 7)
            .background(active ? color.opacity(0.07) : Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 16).padding(.leading, 8) }
            .contextMenu {
                Button("Edit text or reassign speaker", systemImage: "pencil", action: edit)
                Button(segment.isQuote ? "Unsave quote" : "Save quote", systemImage: "quote.bubble", action: quote)
                Button(segment.needsReview ? "Clear review flag" : "Flag for review", systemImage: "flag", action: flag)
            }
    }
}

struct QuestionCard: View {
    let question: QuestionAnswer
    let turn: TranscriptSegment
    let session: Interview
    let jump: (Double) -> Void
    let editFollowUp: () -> Void
    let changeStatus: (AnswerStatus) -> Void
    @State private var expanded = true
    private var answerTurns: [TranscriptSegment] { question.answerSegmentIDs.compactMap { id in session.segments.first { $0.id == id } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(session.speakerName(for: turn.speakerID)).font(.caption.weight(.semibold)).foregroundStyle(Theme.blue)
                Spacer()
                Button { jump(turn.startTime) } label: { Label(TimeFormatting.timestamp(turn.startTime), systemImage: "play.circle").font(.system(.caption, design: .monospaced)).frame(minHeight: 44) }
            }
            Text(turn.text).font(.body.weight(.medium)).lineSpacing(4).textSelection(.enabled)
            Divider()
            ForEach(answerTurns) { answer in
                VStack(alignment: .leading, spacing: 8) {
                    Button { jump(answer.startTime) } label: {
                        HStack(spacing: 6) { Circle().fill(session.speakers.first(where: { $0.id == answer.speakerID })?.color.tint ?? .secondary).frame(width: 7, height: 7); Text(session.speakerName(for: answer.speakerID)); Text("· \(TimeFormatting.timestamp(answer.startTime))").foregroundStyle(.secondary) }.font(.caption).frame(minHeight: 44)
                    }
                    Text(answer.text).font(.subheadline).lineSpacing(4).textSelection(.enabled)
                }
            }
            if answerTurns.isEmpty { Text("No following answer turn found. Listen to the audio and review this question.").font(.subheadline).foregroundStyle(.secondary) }
            Menu {
                ForEach(AnswerStatus.allCases, id: \.rawValue) { status in Button(status.title) { changeStatus(status) } }
            } label: { Pill(title: question.status.title, color: question.status == .answered ? .green : .orange, icon: "checklist").frame(minHeight: 44) }.accessibilityLabel("Answer status: \(question.status.title)")
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(question.followUp.isEmpty ? "Add a question you want to revisit." : question.followUp).font(.subheadline).italic().foregroundStyle(.primary).textSelection(.enabled)
                    HStack {
                        Button("Edit follow-up", action: editFollowUp).font(.caption).frame(minHeight: 44)
                        Spacer()
                        if !question.followUp.isEmpty { ShareLink(item: question.followUp) { Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Share follow-up") }
                    }
                }.padding(.top, 8)
            } label: { Label("Suggested follow-up", systemImage: "lightbulb").font(.caption.weight(.semibold)) }
                .padding(12).background(Theme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }.editorialCard()
    }
}

extension AnswerStatus {
    var title: String {
        switch self { case .answered: "Answered · reviewed"; case .partial: "Partial · reviewed"; case .needsReview: "Needs review" }
    }
}

struct SpeakerEditor: View {
    let speaker: Speaker
    let save: (Speaker) -> Void
    @State private var name = ""
    @State private var role = ""
    @State private var color: SpeakerColor = .blue
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Speaker name", text: $name).textContentType(.name).accessibilityIdentifier("speaker.name")
                    TextField("Role or context (optional)", text: $role).accessibilityIdentifier("speaker.role")
                } header: { Text("Name this speaker") } footer: { Text("Updates every reference to this speaker in this interview. To correct a wrongly assigned turn, edit that turn in the transcript.") }
                Section("Speaker color") {
                    Picker("Color", selection: $color) {
                        ForEach(SpeakerColor.allCases, id: \.rawValue) { value in Label(value.rawValue.capitalized, systemImage: "circle.fill").foregroundStyle(value.tint).tag(value) }
                    }.pickerStyle(.inline).labelsHidden()
                }
            }.navigationTitle("Rename speaker").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { var updated = speaker; updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines); updated.role = role.trimmingCharacters(in: .whitespacesAndNewlines); updated.color = color; save(updated); dismiss() }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("speaker.save")
                    }
                }
                .onAppear { name = speaker.name; role = speaker.role; color = speaker.color }
        }.presentationDetents([.medium, .large])
    }
}

struct SegmentEditor: View {
    let segment: TranscriptSegment
    let speakers: [Speaker]
    let duration: Double
    let save: (TranscriptSegment) -> Void
    @State private var text = ""
    @State private var speakerID: UUID?
    @State private var start = 0.0
    @State private var end = 0.0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Transcript text") { TextEditor(text: $text).frame(minHeight: 150).accessibilityIdentifier("segment.text") }
                Section {
                    Picker("Assigned speaker", selection: $speakerID) {
                        Text("Unassigned").tag(nil as UUID?)
                        ForEach(speakers) { Text($0.name).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("segment.speakerPicker")
                } footer: { Text("Changing this assignment affects only this turn. Add speakers from the Insights tab.") }
                Section("Audio timing (seconds)") {
                    LabeledContent("Start") { TextField("Start", value: $start, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("segment.start") }
                    LabeledContent("End") { TextField("End", value: $end, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    if !validTiming { Text("Use a start and end within the recording, with the end after the start.").font(.caption).foregroundStyle(.orange) }
                }
            }.navigationTitle("Edit transcript turn").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { var updated = segment; updated.text = text.trimmingCharacters(in: .whitespacesAndNewlines); updated.speakerID = speakerID; updated.startTime = start; updated.endTime = end; save(updated); dismiss() }
                            .disabled(!validTiming || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("segment.save")
                    }
                }.onAppear { text = segment.text; speakerID = segment.speakerID; start = segment.startTime; end = segment.endTime }
        }
    }
    private var validTiming: Bool { start.isFinite && end.isFinite && start >= 0 && end > start && end <= duration }
}

struct AIInsightCard: View {
    let insight: AIInsight
    let session: Interview
    let jump: (TranscriptSegment) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Pill(title: insight.kind.displayName, icon: "sparkles")
            Text(insight.title).font(.headline)
            Text(insight.detail).font(.subheadline).lineSpacing(3).textSelection(.enabled)
            Text("Source passages").sectionCaption()
            ForEach(insight.segmentIDs, id: \.self) { id in
                if let turn = session.segments.first(where: { $0.id == id }) {
                    Button { jump(turn) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("\(TimeFormatting.timestamp(turn.startTime)) · \(session.speakerName(for: turn.speakerID))", systemImage: "play.circle").font(.caption)
                            Text(turn.text).font(.caption).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
            }
        }.editorialCard()
    }
}
