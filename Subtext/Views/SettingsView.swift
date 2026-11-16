import SwiftUI
import SubtextCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var debugTokenCopied = false
    @State private var showAIConsent = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Subtext", systemImage: "waveform").font(.title2.weight(.bold))
                    Text("Make room for the conversation.").foregroundStyle(.secondary)
                }
                Section("Recording & privacy") {
                    Label("Original audio is stored on this iPhone", systemImage: "iphone")
                    Text("You can record without an account or internet. Audio stays in the app’s local storage and may be included in your iPhone’s device backup. Export important interviews before deleting the app.")
                    Text("On-device transcription can start after Finish or when you request it, and requires Apple’s language support. It does not identify different speakers.")
                    Text("Apple transcription with online processing is a separate choice for devices without a local speech model. You confirm each request before allowing Apple to process the recording online. It also does not identify different speakers.")
                    Text("Cloud AI sends audio or transcript text to Google through Firebase AI Logic when you allow AI analysis. Your sharing permission is separate from the Firebase connection. AI output needs checking against the original audio.")
                }
                Section("AI permission") {
                    Toggle("Allow cloud AI analysis", isOn: Binding(
                        get: { model.aiConsentStatus == .allowed },
                        set: { enabled in
                            if enabled { showAIConsent = true }
                            else { _ = model.setAIConsent(.denied) }
                        }
                    )).accessibilityIdentifier("settings.cloudAI")
                    Text(model.aiConsentStatus == .allowed
                         ? "Allowed. When automatic transcription is enabled, new recordings use Apple transcription first, followed by Google audio analysis for a transcript, speakers, insights, and Q&A. Turning this off cancels current AI work and prevents future interview analysis; audio already sent cannot be recalled."
                         : "Off. Recording and Apple transcription stay available. Allowing AI shares new recording audio, or transcript text you choose to review, with Google. Past interviews are not uploaded when you enable it.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Review AI sharing permission") { showAIConsent = true }
                }
                Section("After recording") {
                    Toggle("Create a local transcript after Finish", isOn: Binding(
                        get: { model.automaticallyTranscribeNewRecordings }, set: { model.setAutomaticallyTranscribe($0) }
                    )).accessibilityIdentifier("settings.autoTranscribe")
                    Picker("Speech language", selection: Binding(
                        get: { model.transcriber.localeIdentifier }, set: { model.setSpeechLocale($0) }
                    )) {
                        ForEach(SpeechTranscriber.supportedLocales, id: \.identifier) { locale in
                            Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier).tag(locale.identifier)
                        }
                    }.disabled(model.isProcessing).accessibilityIdentifier("settings.speechLanguage")
                    Text("When enabled, new recordings are saved first, then transcribed locally in this language. If cloud AI permission is on, audio analysis follows the Apple attempt; otherwise processing stays on this iPhone. Turning automatic transcription off saves audio without starting either review.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("AI connection") {
                    LabeledContent("Your AI sharing permission", value: model.aiConsentStatus == .allowed ? "Allowed" : "Off")
                    LabeledContent("Firebase AI Logic", value: model.cloudReview.configurationStatus.title)
                    Text(model.cloudReview.configurationStatus.message).font(.footnote).foregroundStyle(.secondary)
                    if model.cloudReview.isAvailable {
                        Button {
                            Task { _ = try? await model.cloudReview.checkConnection() }
                        } label: {
                            HStack {
                                Label("Check AI connection", systemImage: "network")
                                if model.cloudReview.isCheckingConnection { Spacer(); ProgressView() }
                            }
                        }.disabled(model.cloudReview.isCheckingConnection || model.isProcessing)
                            .accessibilityIdentifier("settings.checkAI")
                        Text(model.cloudReview.connectionStatus.title).font(.subheadline.weight(.semibold))
                        Text(model.cloudReview.connectionStatus.message).font(.footnote).foregroundStyle(.secondary)
                        Text("The check sends a short fixed test prompt. Your interviews and audio are not sent.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                #if DEBUG
                Section("Firebase development setup") {
                    Button("Copy Firebase debug token") {
                        do {
                            let token = try model.cloudReview.debugTokenForRegistration()
                            UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: token]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                            debugTokenCopied = true
                        } catch { model.errorMessage = error.localizedDescription }
                    }.disabled(!model.cloudReview.isAvailable || model.isProcessing)
                        .accessibilityIdentifier("settings.copyFirebaseDebugToken")
                    Text(debugTokenCopied ? "Copied for 2 minutes. Register it in your Firebase app’s App Check → Manage debug tokens, then retry Check AI connection." : "If App Check rejects this simulator build, copy its private debug token and register it in Firebase App Check. The app copies the token without displaying its value.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Open Firebase App Check", destination: URL(string: "https://console.firebase.google.com/project/_/appcheck/apps/?useAutoProject=true")!)
                }
                Section("Integration test recording") {
                    Button {
                        Task { await addSyntheticTestRecording() }
                    } label: { Label("Add AI test recording", systemImage: "waveform.badge.plus") }
                        .disabled(model.isProcessing)
                        .accessibilityIdentifier("settings.addTestRecording")
                    Text("Adds a 19-second fictional interview with two synthetic voices. You can test playback, bookmarks, and cloud review without recording anyone. Nothing uploads automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                #endif
                Section {
                    Button("Open iPhone permission settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    Button("Add sample interviews") { model.loadSamples(); dismiss() }
                }
                Section {
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))")
                        .accessibilityIdentifier("settings.buildVersion")
                    Text("iPhone · AI uploads follow your sharing permission. No analytics.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings & privacy").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $showAIConsent, onDismiss: {
                    if model.shouldRequestAIConsent { _ = model.setAIConsent(.denied) }
                }) { AIConsentView() }
        }
    }
    #if DEBUG
    @MainActor private func addSyntheticTestRecording() async {
        guard let url = Bundle.main.url(forResource: "IntegrationSample", withExtension: "wav") else {
            model.errorMessage = "The synthetic test recording is missing from this build."
            return
        }
        let previousIDs = Set(model.interviews.map(\.id))
        await model.importAudio(url)
        guard let id = model.selectedInterviewID, !previousIDs.contains(id) else { return }
        model.update(id) {
            $0.title = "AI test interview — synthetic audio"
            $0.notes = "Fictional test interview generated with two synthetic voices. Expected topics: Tuesday at 6 PM at the public library; volunteer planting on Saturday at 9 AM. No real interview participants."
        }
        dismiss()
    }
    #endif
}

struct LibraryInsightsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("The moments worth revisiting.").font(.title2.bold())
                    Text("AI perspectives, saved quotes, and review flags from your interviews. AI content is a draft; sample content is labeled.").font(.subheadline).foregroundStyle(.secondary)
                    let sessions = model.interviews.filter { !$0.aiSummary.isEmpty || !$0.aiInsights.isEmpty || $0.segments.contains { $0.isQuote || $0.needsReview } }
                    if sessions.isEmpty { EmptyPanel(symbol: "sparkle.magnifyingglass", title: "Collect the useful moments", message: "Create an AI review from an interview, or save quotes and review flags. Those perspectives and moments appear here.") }
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(session.title).font(.headline)
                            if session.isDemo { Pill(title: "Sample interview", icon: "doc.text") }
                            if !session.aiSummary.isEmpty { Text(session.aiSummary).font(.subheadline).textSelection(.enabled) }
                            ForEach(session.aiInsights.prefix(3)) { insight in
                                VStack(alignment: .leading, spacing: 5) {
                                    Pill(title: insight.kind.displayName, icon: "sparkles")
                                    Text(insight.title).font(.subheadline.weight(.semibold))
                                    Text(insight.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Button("Open interview & source audio") { model.selectedInterviewID = session.id; dismiss() }.frame(minHeight: 44)
                            ForEach(session.segments.filter { $0.isQuote || $0.needsReview }) { turn in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack { Text(TimeFormatting.timestamp(turn.startTime)).monospacedDigit(); Text(session.speakerName(for: turn.speakerID)); Spacer(); Image(systemName: turn.isQuote ? "quote.opening" : "flag") }.font(.caption).foregroundStyle(Theme.blue)
                                    Text(turn.text).font(.subheadline).textSelection(.enabled)
                                }.padding(.vertical, 6)
                            }
                        }.editorialCard()
                    }
                }.padding(18)
            }.background(Theme.canvas).navigationTitle("Insights").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
