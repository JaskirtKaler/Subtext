import SwiftUI
import SubtextCore

struct RecordingView: View {
    @Environment(AppModel.self) private var model
    @State private var editingBookmark: Bookmark?
    @State private var actionError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        HStack(spacing: 7) {
                            Circle().fill(model.recorder.isPaused ? .orange : Theme.red).frame(width: 7, height: 7)
                            Text(model.recorder.isPaused ? "PAUSED" : "RECORDING").font(.caption.weight(.bold)).tracking(1.8)
                        }.foregroundStyle(model.recorder.isPaused ? .orange : Theme.red)
                        Text(TimeFormatting.timestamp(model.recorder.elapsed, includeHours: true))
                            .font(.system(size: 54, weight: .light, design: .monospaced))
                            .minimumScaleFactor(0.5).lineLimit(1).contentTransition(.numericText())
                            .accessibilityIdentifier("recorder.timer")
                        Text("Interview · \(Date().formatted(date: .abbreviated, time: .omitted))").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 20).padding(.bottom, 4)
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 10) {
                            Image(systemName: "mic.fill").foregroundStyle(Theme.blue)
                            Text(model.recorder.inputName.isEmpty ? "iPhone microphone" : model.recorder.inputName).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Pill(title: "LOCAL", color: Theme.blue)
                        }
                        WaveformView(levels: model.recorder.levels, color: model.recorder.isPaused ? .secondary : Theme.red)
                            .frame(height: 150).padding(14).background(Theme.inset, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("Input level").font(.caption.weight(.semibold)); Spacer(); Text(model.recorder.isPaused ? "Paused" : "Live microphone").font(.caption).foregroundStyle(.secondary) }
                            ProgressView(value: Double(model.recorder.levels.last ?? 0)).tint(Theme.blue).accessibilityLabel("Microphone input level")
                            HStack { Text("Quiet"); Spacer(); Text("Loud") }.font(.caption2).foregroundStyle(.secondary)
                        }
                    }.editorialCard()
                    if let error = model.recorder.errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange)
                            if model.recorder.isPaused {
                                Button("Keep file & close") { model.keepFailedRecording() }.frame(minHeight: 44)
                            }
                        }.editorialCard()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Session bookmarks").sectionCaption(); Spacer(); Text("\(model.pendingBookmarks.count) added").font(.caption).foregroundStyle(Theme.blue) }
                        if model.pendingBookmarks.isEmpty {
                            Text("Mark a moment without interrupting the conversation. Add details now or later.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).editorialCard()
                        }
                        ForEach(model.pendingBookmarks) { bookmark in
                            Button { editingBookmark = bookmark } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bookmark").foregroundStyle(Theme.blue).frame(width: 40, height: 40).background(Theme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(TimeFormatting.timestamp(bookmark.time)).font(.system(.caption, design: .monospaced).bold()).foregroundStyle(Theme.blue)
                                        Text(bookmark.note).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                                }.editorialCard()
                            }.buttonStyle(.plain)
                        }
                    }
                    Label("Your original audio is being written to this iPhone. Review and transcription are available after you finish.", systemImage: "iphone")
                        .font(.caption).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.inset, in: RoundedRectangle(cornerRadius: 16))
                }.padding(18).padding(.bottom, 16)
            }.background(Theme.canvas)
                .navigationTitle("Live session").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Image(systemName: "waveform").foregroundStyle(Theme.red) } }
                .safeAreaInset(edge: .bottom) { controls }
                .sheet(item: $editingBookmark) { bookmark in
                    NoteEditor(title: "Bookmark", initialText: bookmark.note) { model.editRecordingBookmark(bookmark.id, note: $0) }
                }
                .alert("Recording needs attention", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                    Button("OK") { actionError = nil }
                } message: { Text(actionError ?? "") }
        }.interactiveDismissDisabled()
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 18) {
            Button {
                do { if model.recorder.isPaused { try model.recorder.resume() } else { model.recorder.pause() } }
                catch { actionError = error.localizedDescription }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: model.recorder.isPaused ? "play.fill" : "pause.fill").font(.title2).frame(width: 60, height: 60).background(Theme.inset, in: Circle())
                    Text(model.recorder.isPaused ? "Resume" : "Pause").font(.caption)
                }.frame(maxWidth: .infinity)
            }.foregroundStyle(.primary).accessibilityIdentifier("recorder.pause")
            Button { model.finishRecording() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "stop.fill").font(.title).foregroundStyle(.white).frame(width: 82, height: 82).background(Theme.red, in: Circle())
                    Text("Finish").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.red)
                }.frame(maxWidth: .infinity)
            }.accessibilityIdentifier("recorder.finish")
            Button { model.addRecordingBookmark() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark.badge.plus").font(.title2).frame(width: 60, height: 60).background(Theme.inset, in: Circle())
                    Text("Bookmark").font(.caption)
                }.frame(maxWidth: .infinity)
            }.accessibilityIdentifier("recorder.bookmark")
        }.padding(.horizontal, 18).padding(.vertical, 14).background(.regularMaterial)
    }
}

struct NoteEditor: View {
    let title: String
    let initialText: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form { Section(title) { TextEditor(text: $text).frame(minHeight: 160).accessibilityIdentifier("note.text") } }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(text.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }.accessibilityIdentifier("note.save") }
                }.onAppear { text = initialText }
        }.presentationDetents([.medium, .large])
    }
}
