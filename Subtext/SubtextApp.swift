import SwiftUI
import SubtextCore

@main
struct SubtextApp: App {
    @State private var model = AppModel()
    @State private var showInitialAIConsent = false
    @State private var showAISettings = false
    @State private var hasCheckedInitialConsent = false
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(model)
                .tint(Theme.blue)
                .task {
                    presentInitialAIConsentIfReady()
                    await model.recoverRecording()
                }
                .onChange(of: model.recordingPresented) { _, _ in presentInitialAIConsentIfReady() }
                .onChange(of: model.startingRecording) { _, _ in presentInitialAIConsentIfReady() }
                .sheet(isPresented: $showInitialAIConsent, onDismiss: {
                    // Swiping the permission sheet away leaves sharing off and
                    // records the choice so recording is not repeatedly blocked.
                    if model.shouldRequestAIConsent { _ = model.setAIConsent(.denied) }
                }) { AIConsentView().environment(model) }
                .sheet(isPresented: $showAISettings) { SettingsView().environment(model) }
                .alert("Something needs your attention", isPresented: Binding(
                    get: { model.errorMessage != nil && !model.recordingPresented && !showInitialAIConsent && !showAISettings },
                    set: { if !$0 { model.errorMessage = nil } }
                )) {
                    Button("OK") { model.errorMessage = nil }
                    if let message = model.errorMessage,
                       message.localizedCaseInsensitiveContains("Firebase") || message.localizedCaseInsensitiveContains("AI access") {
                        Button("AI settings & setup") {
                            model.errorMessage = nil
                            Task { @MainActor in
                                await Task.yield()
                                showAISettings = true
                            }
                        }
                    }
                    if model.errorMessage?.localizedCaseInsensitiveContains("access") == true {
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }; model.errorMessage = nil }
                    }
                } message: { Text(model.errorMessage ?? "") }
        }
    }

    private func presentInitialAIConsentIfReady() {
        guard !hasCheckedInitialConsent, !model.recordingPresented,
              !model.startingRecording, !showAISettings else { return }
        let arguments = ProcessInfo.processInfo.arguments
        hasCheckedInitialConsent = true
        if (!arguments.contains("--uitesting") || arguments.contains("--show-ai-consent")), model.shouldRequestAIConsent {
            showInitialAIConsent = true
        }
    }
}
