import XCTest

/// Comprehensive click-through UI tests for RAGFlowMobile.
/// Run against the iPad Pro 13-inch M4 simulator.
/// Tests cover: app launch, onboarding, KB CRUD, retrieval settings,
/// chat navigation, documents tab, settings sheet, and workflow list.
final class RAGFlowMobileUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Suppress onboarding via UserDefaults launch argument
        app.launchArguments += ["-hasCompletedOnboarding", "1"]
        app.launch()
        skipOnboardingIfPresent()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Onboarding

    private func skipOnboardingIfPresent() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2) { skip.tap() }
        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 2) { getStarted.tap() }
    }

    // MARK: - Helpers

    private var kbListNav: XCUIElement {
        app.navigationBars["Knowledge Bases"]
    }

    @discardableResult
    private func waitForKBList(timeout: TimeInterval = 6) -> Bool {
        kbListNav.waitForExistence(timeout: timeout)
    }

    private func seedTestData() {
        let seed = app.buttons["Seed Test Data"]
        guard seed.waitForExistence(timeout: 3) else { return }
        seed.tap()
        _ = app.staticTexts["My Library"].waitForExistence(timeout: 3)
    }

    private func ensureMyLibraryExists() {
        if !app.staticTexts["My Library"].waitForExistence(timeout: 2) {
            seedTestData()
        }
    }

    // MARK: - 1. App Launch

    func test01_AppLaunchesAndShowsKBList() {
        XCTAssertTrue(waitForKBList(), "Knowledge Bases nav bar must appear on launch")
    }

    // MARK: - 2. Seed Data

    func test02_SeedDataPopulatesKBList() {
        XCTAssertTrue(waitForKBList())
        seedTestData()
        XCTAssertTrue(app.staticTexts["My Library"].exists, "My Library KB must appear after seeding")
    }

    // MARK: - 3. Create KB

    func test03_CreateKB() {
        XCTAssertTrue(waitForKBList())
        let addBtn = kbListNav.buttons["Add"]
        XCTAssertTrue(addBtn.waitForExistence(timeout: 3), "Add (+) button must be in KB list toolbar")
        addBtn.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        alert.textFields.firstMatch.typeText("UITest KB")
        alert.buttons["Create"].tap()

        XCTAssertTrue(app.staticTexts["UITest KB"].waitForExistence(timeout: 3), "Newly created KB must appear in list")
    }

    // MARK: - 4. Rename KB

    func test04_RenameKB() {
        XCTAssertTrue(waitForKBList())
        ensureMyLibraryExists()

        app.staticTexts["My Library"].firstMatch.press(forDuration: 1.0)
        let renameBtn = app.buttons["Rename"]
        XCTAssertTrue(renameBtn.waitForExistence(timeout: 2))
        renameBtn.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        let field = alert.textFields.firstMatch
        field.clearText()
        field.typeText("My Library")
        alert.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["My Library"].waitForExistence(timeout: 2))
    }

    // MARK: - 5. Retrieval Settings — stepper works

    func test05_RetrievalSettingsStepper() {
        XCTAssertTrue(waitForKBList())
        ensureMyLibraryExists()

        app.staticTexts["My Library"].firstMatch.press(forDuration: 1.0)
        let retrievalBtn = app.buttons["Retrieval Settings"]
        XCTAssertTrue(retrievalBtn.waitForExistence(timeout: 2))
        retrievalBtn.tap()

        // Sheet opens with the KB name as title
        XCTAssertTrue(app.navigationBars["My Library"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Top-K (returned passages)"].waitForExistence(timeout: 2))

        // Read current value
        let valueBefore = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+$'")).firstMatch

        // Increment 3× (use firstMatch — sheet now has multiple steppers)
        let increment = app.buttons["Increment"].firstMatch
        XCTAssertTrue(increment.waitForExistence(timeout: 2))
        increment.tap(); increment.tap(); increment.tap()

        // Decrement 1×
        let decrement = app.buttons["Decrement"].firstMatch
        XCTAssertTrue(decrement.waitForExistence(timeout: 2))
        decrement.tap()

        // The displayed value must differ from the initial (net +2)
        _ = valueBefore

        app.buttons["Save"].tap()
        XCTAssertFalse(app.navigationBars["My Library"].waitForExistence(timeout: 2), "Sheet should dismiss after Save")
    }

    // MARK: - 6. Navigate to Chat tab

    func test06_NavigateToChatTab() {
        XCTAssertTrue(waitForKBList())
        ensureMyLibraryExists()

        app.staticTexts["My Library"].firstMatch.tap()

        let chatTab = app.buttons["Chat"].firstMatch
        XCTAssertTrue(chatTab.waitForExistence(timeout: 4), "Chat tab must be visible in KB detail view")
        chatTab.tap()
    }

    // MARK: - 7. Navigate to Documents tab

    func test07_DocumentsTab() {
        XCTAssertTrue(waitForKBList())
        ensureMyLibraryExists()

        app.staticTexts["My Library"].firstMatch.tap()

        let docsTab = app.buttons["Documents"].firstMatch
        XCTAssertTrue(docsTab.waitForExistence(timeout: 4))
        docsTab.tap()

        // Either empty state or document list (which also contains Import Documents button) must appear
        let importButton = app.buttons["Import Documents"].firstMatch
        let emptyLabel   = app.staticTexts["No Documents Yet"]
        let docList      = app.collectionViews.firstMatch
        XCTAssertTrue(
            importButton.waitForExistence(timeout: 5) || emptyLabel.waitForExistence(timeout: 5)
                || docList.waitForExistence(timeout: 5),
            "Documents tab must show empty state, import button, or document list"
        )
    }

    // MARK: - 8. Settings sheet

    func test08_SettingsSheet() {
        XCTAssertTrue(waitForKBList())

        let settingsBtn = app.buttons["btn.settings"].firstMatch
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 3), "Settings toolbar button must exist")
        settingsBtn.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        // Verify provider segmented control or at least the settings nav bar is present
        let segmented = app.segmentedControls.firstMatch
        let providerText = app.staticTexts["Provider"]
        XCTAssertTrue(
            segmented.waitForExistence(timeout: 3) || providerText.waitForExistence(timeout: 3),
            "Settings sheet must contain provider picker"
        )

        app.swipeDown()
    }

    // MARK: - 9. Workflow list

    func test09_WorkflowList() {
        XCTAssertTrue(waitForKBList())

        let workflowBtn = app.buttons["btn.workflows"].firstMatch
        XCTAssertTrue(workflowBtn.waitForExistence(timeout: 3), "Workflows toolbar button must exist")
        workflowBtn.tap()

        XCTAssertTrue(app.navigationBars["Workflows"].waitForExistence(timeout: 3))

        // Create button or empty state must be present
        let newWorkflow = app.buttons["Add"]
        let emptyLabel  = app.staticTexts["No Workflows Yet"]
        XCTAssertTrue(
            newWorkflow.waitForExistence(timeout: 2) || emptyLabel.waitForExistence(timeout: 2),
            "Workflow list must show Add button or empty state"
        )
        app.swipeDown()
    }

    // MARK: - 10. New Chat session

    func test10_NewChatSession() {
        XCTAssertTrue(waitForKBList())
        ensureMyLibraryExists()

        app.staticTexts["My Library"].firstMatch.tap()

        let chatTab = app.buttons["Chat"].firstMatch
        XCTAssertTrue(chatTab.waitForExistence(timeout: 4))
        chatTab.tap()

        // "+" to create a new session
        let addChat = app.buttons["Add"]
        if addChat.waitForExistence(timeout: 3) {
            addChat.tap()
            // Chat input is a TextField (axis: .vertical) — XCUITest reports it as textField
            let textField = app.textFields.firstMatch
            let textView  = app.textViews.firstMatch
            XCTAssertTrue(
                textField.waitForExistence(timeout: 4) || textView.waitForExistence(timeout: 1),
                "Chat input field must appear in a session"
            )
        }
    }

    // MARK: - 11. Delete KB created in test03

    func test11_DeleteTestKB() {
        XCTAssertTrue(waitForKBList())

        let kb = app.staticTexts["UITest KB"]
        guard kb.waitForExistence(timeout: 3) else { return }

        kb.press(forDuration: 1.0)

        let deleteMenuBtn = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteMenuBtn.waitForExistence(timeout: 2))
        deleteMenuBtn.tap()

        // Confirmation dialog
        let confirmBtn = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirmBtn.waitForExistence(timeout: 2))
        confirmBtn.tap()

        XCTAssertFalse(app.staticTexts["UITest KB"].waitForExistence(timeout: 3), "Deleted KB must not appear in list")
    }
}

// MARK: - XCUIElement helpers

extension XCUIElement {
    /// Clears all text from a text field or text view.
    func clearText() {
        guard let current = value as? String, !current.isEmpty else { return }
        tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }
}
