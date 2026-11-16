import SwiftUI
import SubtextCore

struct WorkspaceView: View {
    let interviewID: UUID
    @Environment(AppModel.self) private var model
    @State private var player = AudioPlayer()
    @State private var waveform: [Float] = []
    @State private var tab: WorkspaceTab = .transcript
    @State private var transcriptSearch = ""
    @State private var speakerFilter = "all"
    @State private var followPlayback = true
    @State private var samplePosition: Double = 0
    @State private var selectedTurnID: UUID?
    @State private var editingTitle = false
    @State private var editingSpeaker: Speaker?
    @State private var editingSegment: TranscriptSegment?
    @State private var editingQuestion: QuestionAnswer?
    @State private var editingBookmark: Bookmark?
    @State private var editingNotes = false
    @State private var showCloudConsent = false
    @State private var showTranscribeConsent = false
    @State private var showAppleServiceConsent = false
    @State private var showTranscriptReviewConsent = false
    @State private var showAIReviewOptions = false
    @State private var showSettings = false
    @State private var showAIConsent = false
    @State private var showDelete = false
    @Environment(\.dismiss) private var dismiss

    private var session: Interview? { model.interview(interviewID) }
    private var busy: Bool { model.isProcessing(interviewID) }
    private var processingElsewhere: Bool { model.isProcessing && !busy }
    private var position: Double { session?.isDemo == true ? samplePosition : player.currentTime }
    private var activeSegmentID: UUID? { session?.segments.last(where: { $0.startTime <= position })?.id }

    var body: some View {
        if let session {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heading(session)
                        audioTimeline(session)
                        Picker("Workspace tab", selection: $tab) {
                            ForEach(WorkspaceTab.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("workspace.tab")
                        if busy {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(processingMessage).font(.subheadline)
                                Spacer()
                                Button("Cancel") { model.cancelProcessing(for: interviewID) }.font(.caption).accessibilityIdentifier("workspace.cancelProcessing")
                            }.editorialCard()
                        }
                        if processingElsewhere {
                            Label("Another interview is processing. You can keep reviewing this one.", systemImage: "waveform")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.queuedTranscriptionIDs.contains(interviewID) {
                            HStack {
                                Label("Waiting to create a local transcript", systemImage: "clock")
                                Spacer()
                                Button("Cancel") { model.cancelQueuedTranscription(interviewID) }
                            }.font(.caption).editorialCard()
                        }
                        if let message = session.processingError, !busy { processingFailure(message, session: session) }
                        if showAIReviewOptions, !busy { aiReviewOptions(session) }
                        if let warning = session.transcriptionWarning, !busy {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Partial transcript", systemImage: "exclamationmark.bubble").font(.subheadline.weight(.semibold))
                                Text(warning).font(.caption)
                                Button("Use original audio for cloud transcription & AI review") { requestCloudReview() }
                                    .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                                Button("Transcribe with Apple service") { showAppleServiceConsent = true }
                                    .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                                cloudConnectionActions
                            }.editorialCard()
                        }
                        Group {
                            switch tab {
                            case .transcript: transcriptContent(session)
                            case .questions: questionsContent(session)
                            case .insights: insightsContent(session)
                            }
                        }.disabled(busy)
                    }.padding(18).padding(.bottom, 14)
                }
                .background(Theme.canvas)
                .onChange(of: activeSegmentID) { _, newValue in
                    if followPlayback, player.isPlaying, tab == .transcript, let newValue {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(newValue, anchor: .center) }
                    }
                }
                .onChange(of: selectedTurnID) { _, id in
                    if let id { Task { @MainActor in
                        // Allow the segmented content to lay out before revealing its turn.
                        await Task.yield()
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                        selectedTurnID = nil
                    } }
                }
            }
            .navigationTitle("Interview workspace").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { actions(session) } }
            .safeAreaInset(edge: .bottom, spacing: 0) { playbackControls(session) }
            .task(id: session.audioFilename) { await loadAudio(session) }
            .onAppear { offerAIReviewIfNeeded() }
            .onChange(of: model.pendingAIReviewIDs) { _, _ in offerAIReviewIfNeeded() }
            .onChange(of: model.isProcessing) { _, _ in offerAIReviewIfNeeded() }
            .onDisappear { player.stop() }
            .sheet(isPresented: $editingTitle) {
                NoteEditor(title: "Interview title", initialText: session.title) { text in
                    model.update(interviewID) { $0.title = text.isEmpty ? Interview.defaultTitle(date: $0.createdAt) : text }
                }
            }
            .sheet(item: $editingSpeaker) { speaker in
                SpeakerEditor(speaker: speaker) { edited in
                    model.update(interviewID) { if let index = $0.speakers.firstIndex(where: { $0.id == edited.id }) { $0.speakers[index] = edited } else { $0.speakers.append(edited) } }
                }
            }
            .sheet(item: $editingSegment) { segment in
                SegmentEditor(segment: segment, speakers: session.speakers, duration: session.duration) { edited in
                    model.update(interviewID) { current in
                        current.upsertSegment(edited)
                    }
                }
            }
            .sheet(item: $editingQuestion) { question in
                NoteEditor(title: "Suggested follow-up", initialText: question.followUp) { text in
                    model.update(interviewID) { current in
                        if let index = current.questions.firstIndex(where: { $0.id == question.id }) { current.questions[index].followUp = text }
                    }
                }
            }
            .sheet(item: $editingBookmark) { bookmark in
                NoteEditor(title: "Bookmark note", initialText: bookmark.note) { text in
                    model.update(interviewID) { current in if let index = current.bookmarks.firstIndex(where: { $0.id == bookmark.id }) { current.bookmarks[index].note = text } }
                }
            }
            .sheet(isPresented: $editingNotes) {
                NoteEditor(title: "Interview notes", initialText: session.notes) { text in model.update(interviewID) { $0.notes = text } }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAIConsent, onDismiss: {
                if model.shouldRequestAIConsent { _ = model.setAIConsent(.denied) }
            }) { AIConsentView(manualReviewNeedsRetry: true) }
            .confirmationDialog("Send this interview to Google for AI review?", isPresented: $showCloudConsent, titleVisibility: .visible) {
                Button("Send audio & create AI draft") { Task { await model.analyzeWithCloud(interviewID) } }
            } message: {
                Text("The original audio will be uploaded to Google through Firebase AI Logic for a transcript, speaker suggestions, insights, Q&A, and follow-ups. This replaces the saved transcript, speaker labels, transcript-linked quotes/flags, Q&A, and AI summary. Your own notes and bookmarks are kept. Check all suggested text, speaker turns, and timestamps against the audio. Your original recording stays on your iPhone.")
            }
            .confirmationDialog("Create AI insights and Q&A?", isPresented: $showTranscriptReviewConsent, titleVisibility: .visible) {
                Button("Send transcript & create AI review") { Task { await model.reviewTranscriptWithCloud(interviewID) } }
                    .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
            } message: {
                Text("Send the saved transcript and its timestamps to Google through Firebase AI Logic to draft a summary, evidence-linked insights, Q&A, and follow-ups. No interview audio is sent. Transcript corrections, speaker names, notes, and bookmarks are kept. Automatic speaker detection requires Cloud transcript, speakers & AI review from Interview actions. AI suggestions may be wrong; check them against the original recording." + (session.transcriptionWarning == nil ? "" : " This transcript has missing sections, so AI review can only cover the available text."))
            }
            .confirmationDialog("Create an on-device transcript?", isPresented: $showTranscribeConsent, titleVisibility: .visible) {
                Button("Transcribe on this iPhone") { Task { await model.transcribe(interviewID) } }
            } message: { Text("This replaces the transcript and its AI review using Apple’s on-device speech recognition in the selected language, when supported. Speaker turns remain unassigned. Your original audio, notes, and bookmarks are kept.") }
            .confirmationDialog("Allow Apple service transcription?", isPresented: $showAppleServiceConsent, titleVisibility: .visible) {
                Button("Allow Apple service for this recording") {
                    Task { await model.transcribe(interviewID, mode: .appleServiceAllowed) }
                }
            } message: {
                Text("Apple may receive this recording to recognize speech in the selected language, or process it locally when available. This permission applies to this request only. It replaces the saved transcript, speaker assignments, transcript-linked quotes/flags, Q&A, and AI review. Apple transcription does not identify speakers. Your original audio, notes, and bookmarks are kept.")
            }
            .confirmationDialog("Delete this interview and its original audio?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete interview", role: .destructive) { player.stop(); model.delete(interviewID); if model.interview(interviewID) == nil { dismiss() } }
            }
        } else { ContentUnavailableView("Interview unavailable", systemImage: "doc.questionmark", description: Text("This interview may have been deleted.")) }
    }

    private func heading(_ session: Interview) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { editingTitle = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(session.title).font(.title2.bold()).multilineTextAlignment(.leading).foregroundStyle(.primary)
                    Image(systemName: "pencil").font(.caption).foregroundStyle(Theme.blue)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel("Edit interview title").accessibilityIdentifier("workspace.title")
            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            if session.isDemo {
                Label("Sample interview · fictional text, no audio attached", systemImage: "doc.text").font(.caption).foregroundStyle(Theme.blue)
            }
        }
    }

    private func audioTimeline(_ session: Interview) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label(session.isDemo ? "Sample timeline" : "Original audio", systemImage: "waveform").font(.caption.weight(.semibold)).foregroundStyle(Theme.blue)
                Spacer()
                Text("\(TimeFormatting.timestamp(position)) / \(TimeFormatting.duration(session.duration))").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            WaveformView(levels: waveform, progress: session.duration > 0 ? position / session.duration : 0, isPlaceholder: session.isDemo)
                .frame(height: 48)
            Slider(value: Binding(get: { min(max(0, position), max(1, session.duration)) }, set: { seek($0, in: session) }), in: 0...max(1, session.duration))
                .disabled(!session.isDemo && !player.hasAudio).accessibilityLabel("Audio position").accessibilityValue(TimeFormatting.timestamp(position))
            if let message = player.errorMessage {
                Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
            } else if !player.hasAudio && !session.isDemo {
                Text("Audio is unavailable. Saved text is still editable.").font(.caption).foregroundStyle(.secondary)
            }
        }.editorialCard(padding: 14)
    }

    private func playbackControls(_ session: Interview) -> some View {
        HStack(spacing: 5) {
            Menu {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { rate in
                    Button("\(rate.formatted())×") { player.setRate(rate) }
                }
            } label: { Text("\(player.rate.formatted())×").font(.system(.caption, design: .monospaced).weight(.medium)).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Playback speed").disabled(!player.hasAudio)
            Spacer(minLength: 0)
            IconButton(symbol: "gobackward.15", label: "Back 15 seconds") { player.skip(-15) }.disabled(!player.hasAudio)
            Button {
                do { try player.playPause() } catch { model.errorMessage = error.localizedDescription }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3.weight(.bold)).foregroundStyle(.white).frame(width: 54, height: 54).background(player.hasAudio ? Theme.blue : Color.secondary.opacity(0.45), in: Circle())
            }.disabled(!player.hasAudio).accessibilityLabel(player.isPlaying ? "Pause audio" : "Play audio").accessibilityIdentifier("workspace.play")
            IconButton(symbol: "goforward.30", label: "Forward 30 seconds") { player.skip(30) }.disabled(!player.hasAudio)
            Spacer(minLength: 0)
            IconButton(symbol: "bookmark.badge.plus", label: "Bookmark current moment") {
                model.update(interviewID) { $0.bookmarks.append(Bookmark(time: position, note: "Bookmark \($0.bookmarks.count + 1)")) }
            }.disabled(busy).accessibilityIdentifier("workspace.bookmark")
        }.padding(.horizontal, 18).padding(.vertical, 9).background(.regularMaterial)
    }

    @ViewBuilder private func transcriptContent(_ session: Interview) -> some View {
        if session.segments.isEmpty {
            VStack(spacing: 16) {
                EmptyPanel(symbol: "text.alignleft", title: "Every interview starts with listening", message: "Your audio is saved. Create a transcript, or add your own notes and speaker turns.")
                if session.audioFilename != nil {
                    Button { showTranscribeConsent = true } label: { Label("Transcribe on this iPhone", systemImage: "text.bubble") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                    Button { showAppleServiceConsent = true } label: { Label("Transcribe with Apple service", systemImage: "network") }
                        .buttonStyle(.bordered).controlSize(.large).disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                        .accessibilityIdentifier("workspace.appleServiceTranscription")
                    Button { requestCloudReview() } label: { Label("AI transcript & speaker suggestions", systemImage: "sparkles") }.buttonStyle(.bordered).controlSize(.large).disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                    if !model.cloudReview.isAvailable { Text(model.cloudReview.configurationStatus.message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    cloudConnectionActions
                }
                Button { addTurn() } label: { Label("Add a transcript turn", systemImage: "plus") }.frame(minHeight: 44).accessibilityIdentifier("workspace.addTurn")
            }.editorialCard()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search transcript", text: $transcriptSearch).accessibilityIdentifier("workspace.search")
                    if !transcriptSearch.isEmpty { Button { transcriptSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Clear transcript search") }
                }.padding(.horizontal, 12).frame(minHeight: 46).background(Theme.inset, in: RoundedRectangle(cornerRadius: 12))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { followPlayback.toggle() } label: { Pill(title: followPlayback ? "Follow on" : "Follow off", icon: "eye") }.frame(minHeight: 44)
                        Menu {
                            Picker("Speaker", selection: $speakerFilter) {
                                Text("All speakers").tag("all")
                                Text("Unassigned").tag("unassigned")
                                ForEach(session.speakers) { Text($0.name).tag($0.id.uuidString) }
                            }
                            Button("Add speaker", systemImage: "person.badge.plus") { addSpeaker(session) }
                        } label: { Pill(title: filterName(session), icon: "line.3.horizontal.decrease") }.frame(minHeight: 44)
                        Button { addTurn() } label: { Pill(title: "Add turn", icon: "plus") }.frame(minHeight: 44).accessibilityIdentifier("workspace.addTurn")
                    }
                }
                Text("Transcript and speaker labels are drafts. Check important passages against the audio.").font(.caption).foregroundStyle(.secondary)
                let turns = session.segments.filter {
                    (transcriptSearch.isEmpty || $0.text.localizedCaseInsensitiveContains(transcriptSearch)) &&
                    (speakerFilter == "all" || (speakerFilter == "unassigned" ? $0.speakerID == nil : $0.speakerID?.uuidString == speakerFilter))
                }
                if turns.isEmpty { EmptyPanel(symbol: "magnifyingglass", title: "No matching turns", message: "Try another phrase or speaker filter.") }
                ForEach(turns) { segment in
                    TranscriptCard(segment: segment, session: session, active: player.isPlaying && activeSegmentID == segment.id,
                        jump: { seek(segment.startTime, in: session) },
                        rename: { if let speaker = session.speakers.first(where: { $0.id == segment.speakerID }) { editingSpeaker = speaker } else { editingSegment = segment } },
                        edit: { editingSegment = segment },
                        quote: { toggleSegment(segment.id, keyPath: \.isQuote) },
                        flag: { toggleSegment(segment.id, keyPath: \.needsReview) })
                        .id(segment.id)
                }
            }
        }
    }

    @ViewBuilder private func questionsContent(_ session: Interview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(session.questions.count) question\(session.questions.count == 1 ? "" : "s")").font(.headline)
                Spacer()
                Menu {
                    Button("AI Q&A review", systemImage: "sparkles") { requestTranscriptReview() }.disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                    Button("Find questions locally", systemImage: "text.magnifyingglass") { findQuestionsLocally() }
                } label: { Label("Review", systemImage: "sparkles").font(.caption).frame(minHeight: 44) }.disabled(session.segments.isEmpty)
            }
            Text("AI review links questions to possible answers and suggests follow-ups. Pairings are drafts, not verified answers. Set the status after listening.").font(.caption).foregroundStyle(.secondary)
            if session.questions.isEmpty {
                EmptyPanel(symbol: "bubble.left.and.bubble.right", title: session.aiSummary.isEmpty ? "Follow the conversation" : "No Q&A pairs suggested", message: session.aiSummary.isEmpty ? "Create a transcript, then choose AI Q&A review for suggested answers and follow-ups. Local question finding is also available without sending text." : "The review did not find clear question-and-answer pairs. A recording can still have useful insights without an interview structure; refresh the review or add your own follow-up notes.")
            }
            ForEach(session.questions) { question in
                if let turn = session.segments.first(where: { $0.id == question.questionSegmentID }) {
                    QuestionCard(question: question, turn: turn, session: session,
                        jump: { seek($0, in: session) }, editFollowUp: { editingQuestion = question },
                        changeStatus: { status in model.update(interviewID) { current in if let index = current.questions.firstIndex(where: { $0.id == question.id }) { current.questions[index].status = status } } })
                }
            }
        }
    }

    @ViewBuilder private func insightsContent(_ session: Interview) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("AI perspective").font(.title3.bold())
                Text("What stands out, what needs more context, and what to ask next. These are suggestions anchored to your source, not external fact checks.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    if session.segments.isEmpty { requestCloudReview() } else { requestTranscriptReview() }
                } label: { Label(session.aiSummary.isEmpty ? "Create AI review" : "Refresh AI review", systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                    .accessibilityIdentifier("workspace.createAIReview")
                if !model.cloudReview.isAvailable { Text(model.cloudReview.configurationStatus.message).font(.caption).foregroundStyle(.secondary) }
                cloudConnectionActions
            }.editorialCard()
            ForEach(session.aiInsights) { insight in
                AIInsightCard(insight: insight, session: session) { jumpToEvidence($0, in: session) }
            }
            if !session.aiSummary.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("AI summary · draft", systemImage: "sparkles").font(.headline)
                    Text(session.aiSummary).font(.subheadline).textSelection(.enabled)
                    Text("Check this draft and its speaker assignments against the original audio.").font(.caption).foregroundStyle(.secondary)
                }.editorialCard()
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label("Interview notes", systemImage: "square.and.pencil").font(.headline); Spacer(); Button("Edit") { editingNotes = true }.frame(minHeight: 44) }
                Text(session.notes.isEmpty ? "Your observations, context, and next steps belong here." : session.notes).font(.subheadline).foregroundStyle(session.notes.isEmpty ? .secondary : .primary).textSelection(.enabled)
            }.editorialCard()
            VStack(alignment: .leading, spacing: 12) {
                Text("Speakers").sectionCaption()
                if session.speakers.isEmpty {
                    Text("Apple transcription leaves speakers unassigned. Review the original audio with cloud AI to suggest speaker turns.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if session.audioFilename != nil {
                    Button { requestCloudReview() } label: { Label("Detect speakers from audio", systemImage: "person.2.wave.2") }
                        .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                        .accessibilityIdentifier("workspace.detectSpeakers")
                }
                ForEach(session.speakers) { speaker in
                    Button { editingSpeaker = speaker } label: {
                        HStack(spacing: 10) {
                            Circle().fill(speaker.color.tint).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 3) { Text(speaker.name).foregroundStyle(.primary); if !speaker.role.isEmpty { Text(speaker.role).font(.caption).foregroundStyle(.secondary) } }
                            Spacer(); Image(systemName: "pencil").font(.caption)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("speaker.row.\(speaker.id.uuidString)")
                }
                Button { addSpeaker(session) } label: { Label("Add speaker", systemImage: "person.badge.plus") }.frame(minHeight: 44)
            }.editorialCard()
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved quotes & review flags").sectionCaption()
                let saved = session.segments.filter { $0.isQuote || $0.needsReview }
                if saved.isEmpty { Text("Save a quote or flag a turn from the transcript.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(saved) { turn in
                    Button { tab = .transcript; transcriptSearch = ""; speakerFilter = "all"; followPlayback = false; selectedTurnID = turn.id; seek(turn.startTime, in: session) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("\(TimeFormatting.timestamp(turn.startTime)) · \(session.speakerName(for: turn.speakerID))", systemImage: turn.isQuote ? "quote.opening" : "flag").font(.caption).foregroundStyle(Theme.blue)
                            Text(turn.text).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.padding(.vertical, 5)
                }
            }.editorialCard()
            VStack(alignment: .leading, spacing: 12) {
                Text("Bookmarks · \(session.bookmarks.count)").sectionCaption()
                if session.bookmarks.isEmpty { Text("Tap the bookmark button during recording or playback to save a moment.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(session.bookmarks) { bookmark in
                    HStack(alignment: .top) {
                        Button { seek(bookmark.time, in: session) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(TimeFormatting.timestamp(bookmark.time)).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.blue)
                                Text(bookmark.note.isEmpty ? "Untitled bookmark" : bookmark.note).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        IconButton(symbol: "pencil", label: "Edit bookmark") { editingBookmark = bookmark }
                    }.contextMenu { Button("Delete bookmark", systemImage: "trash", role: .destructive) { model.update(interviewID) { $0.bookmarks.removeAll { $0.id == bookmark.id } } } }
                }
            }.editorialCard()
        }
    }

    private func actions(_ session: Interview) -> some View {
        Menu {
            Button("Rename interview", systemImage: "pencil") { editingTitle = true }
            if !session.segments.isEmpty {
                Button("AI insights & Q&A from transcript", systemImage: "sparkles") { requestTranscriptReview() }
                    .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
            }
            ShareLink(item: model.exportText(session)) { Label("Share transcript & notes", systemImage: "square.and.arrow.up") }
            if let url = model.audioURL(for: session) {
                ShareLink(item: url) { Label("Share original audio", systemImage: "waveform") }
                Button("Transcribe on this iPhone", systemImage: "text.bubble") { showTranscribeConsent = true }.disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                Button("Transcribe with Apple service", systemImage: "network") { showAppleServiceConsent = true }.disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                Button("Cloud transcript, speakers & AI review", systemImage: "sparkles") { requestCloudReview() }.disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
            }
            Button("Settings & AI connection", systemImage: "gearshape") { showSettings = true }
            Button("Delete interview", systemImage: "trash", role: .destructive) { showDelete = true }.disabled(busy)
        } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Interview actions")
    }
    private var processingMessage: String {
        switch model.processingKind {
        case .localTranscription: return "Transcribing on this iPhone… \(Int(model.transcriber.progress * 100))%"
        case .appleServiceTranscription: return "Transcribing with Apple service… \(Int(model.transcriber.progress * 100))%"
        case .transcriptReview: return "Creating AI insights and Q&A…"
        case .cloudReview: return "Creating transcript, speakers, and AI review…"
        case nil: return "Processing…"
        }
    }
    private func offerAIReviewIfNeeded() {
        guard model.pendingAIReviewIDs.contains(interviewID), !model.isProcessing,
              !showCloudConsent, !showTranscribeConsent, !showAppleServiceConsent,
              model.aiConsentStatus == .allowed, model.cloudReview.isAvailable else { return }
        model.dismissAIReviewOffer(interviewID)
        showAIReviewOptions = true
    }
    private func processingFailure(_ message: String, session: Interview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Processing needs attention", systemImage: "exclamationmark.triangle").font(.subheadline.weight(.semibold))
            Text(message).font(.caption).textSelection(.enabled)
            if !session.segments.isEmpty {
                Button("Create AI review from saved transcript") { requestTranscriptReview() }
                    .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
            }
            if session.audioFilename != nil {
                Button("Retry on-device transcription") { showTranscribeConsent = true }.disabled(model.isProcessing)
                Button("Transcribe with Apple service") { showAppleServiceConsent = true }.disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                Button("Cloud transcription & AI review") { requestCloudReview() }
                    .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
            }
            cloudConnectionActions
        }.foregroundStyle(.primary).editorialCard()
    }
    private func requestCloudReview() {
        guard model.aiConsentStatus == .allowed else { showAIConsent = true; return }
        if model.cloudReview.isAvailable { showCloudConsent = true }
        else { showSettings = true }
    }
    private func requestTranscriptReview() {
        guard model.aiConsentStatus == .allowed else { showAIConsent = true; return }
        if model.cloudReview.isAvailable { showTranscriptReviewConsent = true }
        else { showSettings = true }
    }
    private var cloudConnectionActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.aiConsentStatus != .allowed {
                Button("Allow AI analysis") { showAIConsent = true }
                    .accessibilityIdentifier("workspace.allowAI")
                Text("AI sharing is off. Apple transcription remains available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Settings & AI connection") { showSettings = true }
                .accessibilityIdentifier("workspace.aiSettings")
            if model.cloudReview.isAvailable {
                Button(model.cloudReview.isCheckingConnection ? "Checking AI connection…" : "Check AI connection") {
                    Task { _ = try? await model.cloudReview.checkConnection() }
                }.disabled(model.cloudReview.isCheckingConnection || model.isProcessing)
                    .accessibilityIdentifier("workspace.checkAI")
                if case .notChecked = model.cloudReview.connectionStatus { }
                else { Text(model.cloudReview.connectionStatus.message).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func aiReviewOptions(_ session: Interview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your transcript is ready", systemImage: "checkmark.bubble").font(.headline)
            Text("Choose what to review next. Transcript review creates insights and Q&A; reviewing the audio also suggests speaker turns. You’ll confirm what is sent before either review begins.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Transcript insights & Q&A") { showAIReviewOptions = false; requestTranscriptReview() }
                .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                .accessibilityIdentifier("workspace.offerTextReview")
            if session.audioFilename != nil {
                Button("Speakers, transcript & AI review") { showAIReviewOptions = false; requestCloudReview() }
                    .disabled(model.isProcessing || model.cloudReview.isCheckingConnection)
                    .accessibilityIdentifier("workspace.offerAudioReview")
            }
            Button("Later") { showAIReviewOptions = false }
        }.editorialCard()
    }
    private func jumpToEvidence(_ turn: TranscriptSegment, in session: Interview) {
        tab = .transcript; transcriptSearch = ""; speakerFilter = "all"; followPlayback = false
        selectedTurnID = turn.id; seek(turn.startTime, in: session)
    }
    private func findQuestionsLocally() {
        model.update(interviewID) { current in
            let suggested = LocalReview.suggestQuestions(segments: current.segments, preserving: current.questions)
            for question in suggested where !current.questions.contains(where: { $0.questionSegmentID == question.questionSegmentID }) { current.questions.append(question) }
            let order = Dictionary(uniqueKeysWithValues: current.segments.enumerated().map { ($0.element.id, $0.offset) })
            current.questions.sort { (order[$0.questionSegmentID] ?? Int.max) < (order[$1.questionSegmentID] ?? Int.max) }
        }
    }

    private func loadAudio(_ session: Interview) async {
        guard let url = model.audioURL(for: session) else { return }
        do {
            try player.load(url: url)
        } catch { return }
        // Waveform decoding is optional; a preview error must not stop playable audio.
        if let sampled = try? await WaveformSampler.samples(url: url) { waveform = sampled }
    }
    private func seek(_ time: Double, in session: Interview) {
        if session.isDemo { samplePosition = max(0, min(session.duration, time)) }
        else { player.seek(to: time) }
    }
    private func toggleSegment(_ id: UUID, keyPath: WritableKeyPath<TranscriptSegment, Bool>) {
        model.update(interviewID) { current in if let index = current.segments.firstIndex(where: { $0.id == id }) { current.segments[index][keyPath: keyPath].toggle() } }
    }
    private func addTurn() { editingSegment = TranscriptSegment(startTime: position, endTime: min((session?.duration ?? 0), position + 10)) }
    private func addSpeaker(_ session: Interview) {
        let speaker = Speaker(name: session.speakers.count < 15 ? "Speaker \(String(UnicodeScalar(65 + session.speakers.count)!))" : "New speaker", color: SpeakerColor.allCases[session.speakers.count % SpeakerColor.allCases.count])
        editingSpeaker = speaker
    }
    private func filterName(_ session: Interview) -> String {
        if speakerFilter == "all" { return "All speakers" }
        if speakerFilter == "unassigned" { return "Unassigned" }
        return session.speakers.first(where: { $0.id.uuidString == speakerFilter })?.name ?? "All speakers"
    }
}

private enum WorkspaceTab: String, CaseIterable, Identifiable {
    case questions = "Q&A", transcript = "Transcript", insights = "Insights"
    var id: String { rawValue }
    var symbol: String { switch self { case .questions: "bubble.left.and.bubble.right"; case .transcript: "text.alignleft"; case .insights: "sparkles" } }
}
