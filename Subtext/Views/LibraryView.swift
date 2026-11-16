import SwiftUI
import UniformTypeIdentifiers
import SubtextCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var showSearch = false
    @State private var filter: LibraryFilter = .all
    @State private var sort: LibrarySort = .recent
    @State private var showSettings = false
    @State private var showImport = false
    @State private var showInsights = false
    @State private var pendingDelete: Interview?

    private var displayed: [Interview] {
        model.interviews.filter { session in
            (search.isEmpty || session.searchText.localizedCaseInsensitiveContains(search)) &&
            (filter == .all || (filter == .followUp ? session.hasFollowUps : session.segments.isEmpty))
        }.sorted {
            switch sort {
            case .recent: return $0.createdAt > $1.createdAt
            case .title: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            case .duration: return $0.duration > $1.duration
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if showSearch {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Titles, speakers, or transcript", text: $search)
                                .accessibilityIdentifier("library.search")
                            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Clear search") }
                        }.padding(.horizontal, 14).frame(minHeight: 48).background(Theme.inset, in: RoundedRectangle(cornerRadius: 13))
                    }
                    filters
                    HStack {
                        Text("Recent sessions").sectionCaption()
                        Spacer()
                        Menu {
                            Picker("Sort interviews", selection: $sort) { ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) } }
                        } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.caption.weight(.medium)).frame(minHeight: 44) }
                    }.padding(.bottom, -12)
                    if model.interviews.isEmpty {
                        VStack(spacing: 12) {
                            EmptyPanel(symbol: "waveform", title: "Your next story starts here", message: "Tap Record to capture an interview. Add a title and name the speakers whenever you’re ready.")
                            Button("Explore sample interviews") { model.loadSamples() }
                                .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("library.samples")
                        }.editorialCard().padding(.top, -6)
                    } else if displayed.isEmpty {
                        EmptyPanel(symbol: "magnifyingglass", title: "No matching interviews", message: "Try another search or choose All sessions.")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(displayed) { session in
                                Button { model.selectedInterviewID = session.id } label: { InterviewCard(session: session) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("interview.card.\(session.id.uuidString)")
                                    .contextMenu {
                                        Button("Open interview", systemImage: "doc.text") { model.selectedInterviewID = session.id }
                                        Button("Delete interview", systemImage: "trash", role: .destructive) { pendingDelete = session }
                                    }
                            }
                        }
                    }
                    if !model.interviews.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "iphone.and.arrow.forward").font(.title2).foregroundStyle(Theme.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("A little less setup. More listening.").font(.subheadline.weight(.semibold))
                                Text(model.aiConsentStatus == .allowed
                                     ? "Apple transcription runs first. With your AI permission, new recordings can then go to Google for speaker suggestions and AI review."
                                     : "Recordings stay on your iPhone. Cloud AI stays off until you give permission in Settings.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Theme.inset, in: RoundedRectangle(cornerRadius: 17))
                    }
                }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle("Subtext")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Image(systemName: "waveform").foregroundStyle(Theme.blue).font(.title3).accessibilityHidden(true) }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    IconButton(symbol: "magnifyingglass", label: "Search interviews") { withAnimation { showSearch.toggle(); if !showSearch { search = "" } } }
                        .accessibilityIdentifier("library.searchButton")
                    Menu {
                        Button("Import audio", systemImage: "square.and.arrow.down") { showImport = true }
                        Button("Settings & privacy", systemImage: "gearshape") { showSettings = true }
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Library actions")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationDestination(item: $model.selectedInterviewID) { id in WorkspaceView(interviewID: id) }
            .fullScreenCover(isPresented: $model.recordingPresented) { RecordingView().environment(model) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showInsights) { LibraryInsightsView() }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.audio]) { result in
                switch result { case .success(let url): Task { await model.importAudio(url) }; case .failure(let error): model.errorMessage = error.localizedDescription }
            }
            .confirmationDialog("Delete this interview and its original audio?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete interview", role: .destructive) { if let pendingDelete { model.delete(pendingDelete.id) }; pendingDelete = nil }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Interviews").font(.largeTitle.bold()).tracking(-0.8)
            Text("Be present. Keep every word.").font(.subheadline).foregroundStyle(.secondary)
        }.padding(.top, 10)
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { item in
                    Button { withAnimation(.easeInOut(duration: 0.18)) { filter = item } } label: {
                        HStack(spacing: 6) {
                            Text(item.rawValue)
                            if item == .all { Text("\(model.interviews.count)").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(.primary.opacity(0.12), in: Capsule()) }
                        }.font(.subheadline.weight(.medium)).padding(.horizontal, 15).frame(minHeight: 44)
                            .background(filter == item ? Color.primary : Theme.inset, in: Capsule())
                            .foregroundStyle(filter == item ? Theme.card : Color.primary)
                    }.buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                }
            }
        }
    }
    private var bottomBar: some View {
        HStack(alignment: .center) {
            VStack(spacing: 5) { Image(systemName: "folder").font(.title2); Text("Library").font(.caption.weight(.medium)) }.foregroundStyle(Theme.blue).frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityAddTraits(.isSelected)
            Button { Task { await model.startRecording() } } label: {
                VStack(spacing: 4) {
                    ZStack {
                        Circle().fill(Theme.card).frame(width: 64, height: 64)
                        Circle().stroke(Theme.red, lineWidth: 2).frame(width: 62, height: 62)
                        if model.startingRecording { ProgressView().tint(Theme.red) }
                        else { Circle().fill(Theme.red).frame(width: 23, height: 23) }
                    }
                    Text("Record").font(.caption.weight(.semibold)).foregroundStyle(Theme.red)
                }.frame(maxWidth: .infinity).padding(.top, -16)
            }.disabled(model.startingRecording || !model.canWrite).accessibilityLabel("Record interview").accessibilityIdentifier("library.record")
            Button { showInsights = true } label: {
                VStack(spacing: 5) { Image(systemName: "sparkle.magnifyingglass").font(.title2); Text("Insights").font(.caption.weight(.medium)) }.frame(maxWidth: .infinity).foregroundStyle(.secondary)
            }.accessibilityIdentifier("library.insights")
        }.padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 8).background(.regularMaterial)
    }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All", audioOnly = "Audio only", followUp = "Needs review"
    var id: String { rawValue }
}
private enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "Most recent", title = "Title", duration = "Longest first"
    var id: String { rawValue }
}

private struct InterviewCard: View {
    let session: Interview
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        if session.isDemo { Text("SAMPLE").font(.system(.caption2, design: .monospaced).weight(.bold)).foregroundStyle(Theme.blue) }
                        Text(session.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(session.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: session.isDemo ? "doc.text" : "play.fill").font(.body.weight(.semibold)).foregroundStyle(Theme.blue).frame(width: 44, height: 44).background(Theme.blue.opacity(0.10), in: Circle())
            }
            HStack(spacing: 10) {
                if !session.speakers.isEmpty {
                    HStack(spacing: -4) { ForEach(session.speakers.prefix(3)) { Circle().fill($0.color.tint).frame(width: 12, height: 12).overlay(Circle().stroke(Theme.card, lineWidth: 1.5)) } }
                    Text("\(session.speakers.count) speakers").font(.caption).lineLimit(1)
                    Divider().frame(height: 15)
                }
                WaveformView(isPlaceholder: session.isDemo).frame(maxWidth: 88).frame(height: 23)
                Spacer(minLength: 0)
                Text(TimeFormatting.duration(session.duration)).font(.system(.subheadline, design: .monospaced).weight(.semibold))
            }.padding(11).background(Theme.inset, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                Pill(title: statusTitle, color: session.processingState == .failed || session.transcriptionWarning != nil ? .orange : Theme.blue, icon: session.segments.isEmpty ? "waveform" : "text.alignleft")
                if !session.questions.isEmpty { Text("\(session.questions.count) Q&As").font(.caption).foregroundStyle(.secondary) }
                if session.hasFollowUps { Image(systemName: "flag.fill").font(.caption).foregroundStyle(.orange) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }.editorialCard().accessibilityElement(children: .combine)
    }
    private var statusTitle: String {
        if session.isDemo { return "Sample • no audio" }
        switch session.processingState {
        case .audioOnly: return "Audio saved"
        case .transcribing: return "Processing"
        case .ready: return session.transcriptionWarning == nil ? "Ready to review" : "Partial transcript"
        case .failed: return "Processing needs retry"
        }
    }
}
