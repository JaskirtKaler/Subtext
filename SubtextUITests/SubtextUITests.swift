import XCTest

@MainActor
final class SubtextUITests: XCTestCase {
    private var app: XCUIApplication!
    private let sampleID = "10000000-0000-0000-0000-000000000001"
    private let firstTurnID = "11100000-0000-0000-0000-000000000001"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset"]
        app.launch()
    }

    func testTitleChangePersistsAndCanBeFoundInLibrarySearch() {
        openSample()
        app.buttons["workspace.title"].tap()
        let editor = app.textViews["note.text"]
        replaceText(in: editor, with: "Public space follow-up")
        app.buttons["note.save"].tap()

        relaunchWithoutReset()
        searchLibrary(for: "Public space follow-up")
        let card = app.buttons["interview.card.\(sampleID)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["interview.card.20000000-0000-0000-0000-000000000002"].exists)
        card.tap()
        app.buttons["workspace.title"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "Public space follow-up")
    }

    func testRenamingSpeakerUpdatesTranscriptAndPersistsAcrossLaunches() {
        openSample()
        let speaker = app.buttons["segment.speaker.\(firstTurnID)"]
        reveal(speaker)
        speaker.tap()
        replaceText(in: app.textFields["speaker.name"], with: "Alex Morgan")
        app.buttons["speaker.save"].tap()
        XCTAssertTrue(speaker.waitForExistence(timeout: 3))
        XCTAssertEqual(speaker.label, "Edit speaker Alex Morgan")

        relaunchWithoutReset()
        searchLibrary(for: "Alex Morgan")
        openSample()
        reveal(speaker)
        XCTAssertEqual(speaker.label, "Edit speaker Alex Morgan")
        speaker.tap()
        XCTAssertEqual(app.textFields["speaker.name"].value as? String, "Alex Morgan")
    }

    func testEditingAndReassigningTranscriptTurnPersists() {
        openSample()
        let edit = app.buttons["segment.edit.\(firstTurnID)"]
        reveal(edit)
        edit.tap()
        let editor = app.textViews["segment.text"]
        replaceText(in: editor, with: "What should we ask the neighbourhood next?")

        let picker = app.descendants(matching: .any)["segment.speakerPicker"].firstMatch
        reveal(picker)
        picker.tap()
        let unassigned = app.buttons["Unassigned"].firstMatch
        XCTAssertTrue(unassigned.waitForExistence(timeout: 3))
        unassigned.tap()
        app.buttons["segment.save"].tap()

        relaunchWithoutReset()
        searchLibrary(for: "What should we ask the neighbourhood next?")
        openSample()
        let speaker = app.buttons["segment.speaker.\(firstTurnID)"]
        reveal(speaker)
        XCTAssertEqual(speaker.label, "Edit speaker Unknown speaker")
        reveal(edit)
        edit.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "What should we ask the neighbourhood next?")
    }

    func testDecliningFirstLaunchAIKeepsAppleDefaultAndPersists() {
        launchWithAIChoice(reset: true)
        let appleOnly = app.buttons["aiConsent.appleOnly"]
        XCTAssertTrue(appleOnly.waitForExistence(timeout: 5))
        appleOnly.tap()
        openPrivacySettings()
        XCTAssertEqual(app.switches["settings.cloudAI"].value as? String, "0")
        reveal(app.switches["settings.autoTranscribe"])
        XCTAssertEqual(app.switches["settings.autoTranscribe"].value as? String, "1")

        launchWithAIChoice(reset: false)
        XCTAssertTrue(app.buttons["interview.card.\(sampleID)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["aiConsent.allow"].exists)
        openPrivacySettings()
        XCTAssertEqual(app.switches["settings.cloudAI"].value as? String, "0")
    }

    func testAllowingThenRevokingAIConsentPersistsAcrossLaunches() {
        launchWithAIChoice(reset: true)
        let allow = app.buttons["aiConsent.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.tap()
        openPrivacySettings()
        let cloudAI = app.switches["settings.cloudAI"]
        XCTAssertEqual(cloudAI.value as? String, "1")
        cloudAI.tap()
        XCTAssertEqual(cloudAI.value as? String, "0")

        launchWithAIChoice(reset: false)
        XCTAssertTrue(app.buttons["interview.card.\(sampleID)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["aiConsent.allow"].exists)
        openPrivacySettings()
        XCTAssertEqual(app.switches["settings.cloudAI"].value as? String, "0")
    }

    func testEnablingAIInSettingsRequiresExplicitDisclosureChoice() {
        launchWithAIChoice(reset: true)
        let appleOnly = app.buttons["aiConsent.appleOnly"]
        XCTAssertTrue(appleOnly.waitForExistence(timeout: 5))
        appleOnly.tap()
        openPrivacySettings()
        let cloudAI = app.switches["settings.cloudAI"]
        XCTAssertEqual(cloudAI.value as? String, "0")
        cloudAI.tap()
        let allow = app.buttons["aiConsent.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 3))
        app.buttons["aiConsent.appleOnly"].tap()
        XCTAssertTrue(cloudAI.waitForExistence(timeout: 3))
        XCTAssertEqual(cloudAI.value as? String, "0")
        cloudAI.tap()
        XCTAssertTrue(allow.waitForExistence(timeout: 3))
        allow.tap()
        XCTAssertTrue(cloudAI.waitForExistence(timeout: 3))
        XCTAssertEqual(cloudAI.value as? String, "1")
    }

    private func launchWithAIChoice(reset: Bool) {
        app.terminate()
        app.launchArguments = ["--uitesting", "--show-ai-consent"] + (reset ? ["--reset"] : [])
        app.launch()
    }

    private func openPrivacySettings() {
        let actions = app.buttons["Library actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        app.buttons["Settings & privacy"].tap()
        reveal(app.switches["settings.cloudAI"])
    }

    private func openSample(file: StaticString = #filePath, line: UInt = #line) {
        let card = app.buttons["interview.card.\(sampleID)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), file: file, line: line)
        reveal(card)
        card.tap()
        XCTAssertTrue(app.buttons["workspace.title"].waitForExistence(timeout: 5), file: file, line: line)
    }

    private func searchLibrary(for query: String) {
        let button = app.buttons["library.searchButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let field = app.textFields["library.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(query)
    }

    private func relaunchWithoutReset() {
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    private func replaceText(in element: XCUIElement, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        element.tap()
        // A tap below a text view's content moves its insertion point to the end.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.95)).tap()
        let current = element.value as? String ?? ""
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected element to become visible: \(element)", file: file, line: line)
    }
}
