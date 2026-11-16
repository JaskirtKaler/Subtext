import SwiftUI

/// Subtext's own sharing permission. This does not request tracking permission
/// and cannot register a Firebase App Check development token.
struct AIConsentView: View {
    var manualReviewNeedsRetry = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 42, weight: .light)).foregroundStyle(Theme.blue)
                        .accessibilityHidden(true)
                    Text("Choose how Subtext reviews recordings")
                        .font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Apple transcription comes first", systemImage: "iphone")
                            .font(.headline)
                        Text("New recordings are saved on this iPhone. When automatic transcription is enabled, Subtext first tries Apple’s on-device transcription in your selected language.")
                            .font(.subheadline)
                    }.editorialCard()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Optional cloud AI", systemImage: "sparkles").font(.headline)
                        Text("If you allow AI analysis, automatic transcription sends new recordings to Google through Firebase AI Logic after the Apple transcription attempt. Google analyzes the audio for a transcript, speaker suggestions, insights, Q&A, and follow-ups. It can also process the recording when Apple transcription is unavailable.")
                            .font(.subheadline)
                        Text("A transcript-only review sends saved text and timestamps to Google. Your notes, bookmarks, and assigned speaker names are not included in that text request. AI suggestions need checking against the original audio.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.editorialCard()
                    Text("This choice applies to future recordings and AI actions you request. Allowing it does not upload past interviews. You can turn it off in Settings & privacy. Recording and Apple transcription remain available when AI is off.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if manualReviewNeedsRetry {
                        Text("After allowing AI, choose your interview’s review action again to send that interview.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Cloud features also need a working connection. You can check the connection separately in Settings & privacy.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(22)
            }.background(Theme.canvas)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 12) {
                        if let saveError {
                            Label(saveError, systemImage: "exclamationmark.circle")
                                .font(.subheadline).foregroundStyle(.red)
                        }
                        Button { save(.allowed) } label: { Text("Allow AI analysis").frame(maxWidth: .infinity) }
                            .accessibilityIdentifier("aiConsent.allow")
                        Button { save(.denied) } label: { Text("Use Apple transcription only").frame(maxWidth: .infinity) }
                            .accessibilityIdentifier("aiConsent.appleOnly")
                    }.buttonStyle(.bordered).controlSize(.large)
                        .padding(.horizontal, 22).padding(.vertical, 14)
                        .frame(maxWidth: .infinity).background(Theme.canvas)
                }
                .navigationTitle("AI permission").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { save(.denied) }
                } }
        }
    }

    private func save(_ choice: AIConsentStatus) {
        guard model.setAIConsent(choice) else {
            saveError = model.errorMessage ?? "This choice could not be saved. Please try again."
            model.errorMessage = nil
            return
        }
        dismiss()
    }
}
