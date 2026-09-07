import XCTest

@MainActor final class RegressionTests: XCTestCase {
    private func makeApp(fixtures: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.ethanrimes.thimvale")
        app.launchEnvironment["THIMVALE_TEST_SESSION"] = UUID().uuidString
        if fixtures {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Vendor/smoke-model.gguf").path),
                  FileManager.default.fileExists(atPath: root.appendingPathComponent("Vendor/smoke-wikipedia.zim").path) else {
                throw XCTSkip("Run scripts/fetch-test-assets.sh for the real model and Wikipedia UI tests.")
            }
            app.launchEnvironment["THIMVALE_UI_FIXTURES"] = root.path
        }
        app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.state, .runningForeground)
        return app
    }

    func testMissingModelPreservesDraft() throws {
        let app = try makeApp()
        let input = app.textFields["messageInput"]
        input.tap(); input.typeText("Explain how a bowline works.")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.alerts["Library update"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.textFields["modelSearch"].exists)
        app.selectMainTab("Chat")
        XCTAssertEqual(input.value as? String, "Explain how a bowline works.")
    }

    func testColdLaunchAndBackgroundReturn() throws {
        let app = try makeApp()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'No script URL'")).firstMatch.exists)
    }

    func testKnowledgeSearchDismissesKeyboard() throws {
        let app = try makeApp()
        app.selectMainTab("Knowledge")
        let search = app.textFields["knowledgeSearch"]
        reveal(search, in: app)
        search.tap(); search.typeText("bowline\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No matching passages. Try a specific term or import more sources."].waitForExistence(timeout: 5))
        app.selectMainTab("Chat")
        XCTAssertTrue(app.buttons["modelPicker"].exists)
    }

    func testIndependentPermissionsSurviveRelaunch() throws {
        let app = try makeApp()
        app.selectMainTab("Permissions")
        let read = app.segmentedControls["permission_read_file"]
        reveal(read, in: app); read.buttons["Off"].tap()
        let write = app.segmentedControls["permission_write_file"]
        reveal(write, in: app); write.buttons["Allow"].tap()
        app.terminate(); app.launch()
        app.selectMainTab("Permissions")
        reveal(read, in: app); XCTAssertTrue(read.buttons["Off"].isSelected)
        reveal(write, in: app); XCTAssertTrue(write.buttons["Allow"].isSelected)
        let web = app.segmentedControls["permission_web_search"]
        reveal(web, in: app); XCTAssertTrue(web.buttons["Off"].isSelected)
    }

    func testSettingsSaveAndAcknowledgments() throws {
        let app = try makeApp()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let cellular = app.switches["Allow cellular downloads"]
        // SwiftUI exposes the whole Form row as a switch; tap its trailing control.
        cellular.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(cellular.value as? String, "1")
        capture(app, "Cellular setting after toggle")
        let save = app.buttons["Save keys"]
        reveal(save, in: app); save.tap()
        XCTAssertTrue(app.buttons["Keys saved"].exists)
        let credits = app.buttons["Open-source acknowledgments"]
        reveal(credits, in: app); credits.tap()
        XCTAssertTrue(app.navigationBars["Acknowledgments"].waitForExistence(timeout: 5))
        app.navigationBars["Acknowledgments"].buttons["Settings"].tap()
        app.buttons["Done"].tap()
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        XCTAssertEqual(app.switches["Allow cellular downloads"].value as? String, "1")
        app.buttons["Done"].tap()
    }

    func testImportPickersCancelWithoutError() throws {
        let app = try makeApp()
        app.selectMainTab("Models")
        app.buttons["Import GGUF model"].tap()
        dismissFiles(app)
        app.selectMainTab("Knowledge")
        app.buttons["Add files"].tap(); dismissFiles(app)
        app.buttons["Add folder"].tap(); dismissFiles(app)
        let archive = app.buttons["Import an existing ZIM archive"]
        reveal(archive, in: app); archive.tap(); dismissFiles(app)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["exploreWikipedia"].exists)
    }

    func testInvalidRepositoryCanBeDismissedAndRetried() throws {
        let app = try makeApp()
        app.selectMainTab("Models")
        app.segmentedControls.buttons["Downloaded"].tap()
        app.buttons["Open a Hugging Face repository"].tap()
        app.alerts.textFields.firstMatch.typeText("invalid")
        app.alerts.buttons["Open"].tap()
        XCTAssertTrue(app.staticTexts["Enter a repository in owner/model format."].waitForExistence(timeout: 10))
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["Enter a repository in owner/model format."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.selectMainTab("Chat")
        XCTAssertTrue(app.buttons["modelPicker"].exists)
    }

    func testRealChatHistoryAndRestart() throws {
        let app = try makeApp(fixtures: true)
        XCTAssertTrue(app.staticTexts["modelMemoryState"].wait(for: \.label, toEqual: "In memory", timeout: 30))
        let input = app.textFields["messageInput"]
        input.tap(); input.typeText("What is two plus two? Answer with the number.")
        app.buttons["sendMessage"].tap()
        let answer = app.staticTexts["assistantMessage"]
        XCTAssertTrue(answer.waitForExistence(timeout: 90))
        XCTAssertTrue(app.buttons["New conversation"].wait(for: \.isEnabled, toEqual: true, timeout: 90))
        XCTAssertTrue(answer.label.contains("4") || answer.label.lowercased().contains("four"), answer.label)
        app.buttons["New conversation"].tap()
        XCTAssertTrue(app.staticTexts["Start a conversation."].exists)
        XCTAssertEqual(app.staticTexts["modelMemoryState"].label, "In memory")
        app.buttons["Conversation history"].tap()
        app.buttons.containing(.staticText, identifier: "What is two plus two? Answer with the number.").firstMatch.tap()
        XCTAssertTrue(answer.label.contains("4") || answer.label.lowercased().contains("four"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["modelMemoryState"].wait(for: \.label, toEqual: "Unloaded · loads when you send", timeout: 15))
        app.buttons["Conversation history"].tap()
        app.buttons.containing(.staticText, identifier: "What is two plus two? Answer with the number.").firstMatch.tap()
        XCTAssertTrue(answer.label.contains("4") || answer.label.lowercased().contains("four"))
        capture(app, "Real local chat")
    }

    func testLiveTokensStopAndBackgroundModelRelease() throws {
        let app = try makeApp(fixtures: true)
        XCTAssertTrue(app.staticTexts["modelMemoryState"].wait(for: \.label, toEqual: "In memory", timeout: 30))
        let input = app.textFields["messageInput"]
        input.tap(); input.typeText("Write a long story about a sailor exploring an island. Include many details.")
        app.buttons["sendMessage"].tap()
        let live = app.staticTexts["liveModelOutput"]
        XCTAssertTrue(live.waitForExistence(timeout: 60))
        XCTAssertFalse(app.buttons["New conversation"].isEnabled, "Output must be visible before generation finishes")
        XCTAssertFalse(live.label.isEmpty)
        capture(app, "Live streamed local model output")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.buttons["New conversation"].wait(for: \.isEnabled, toEqual: true, timeout: 20))
        XCTAssertEqual(app.staticTexts["modelMemoryState"].label, "In memory")
        XCUIDevice.shared.press(.home)
        let home = XCTAttachment(screenshot: XCUIApplication(bundleIdentifier: "com.apple.springboard").screenshot())
        home.name = "Installed Thimvale icon"; home.lifetime = .keepAlways; add(home)
        app.activate()
        XCTAssertTrue(app.staticTexts["modelMemoryState"].wait(for: \.label, toEqual: "Unloaded · loads when you send", timeout: 10))
        app.buttons["New conversation"].tap()
        input.tap(); input.typeText("What is two plus two? Answer with the number.")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["assistantMessage"].waitForExistence(timeout: 90))
        XCTAssertTrue(app.buttons["New conversation"].wait(for: \.isEnabled, toEqual: true, timeout: 90))
        XCTAssertEqual(app.staticTexts["modelMemoryState"].label, "In memory")
    }

    func testOfflineSearchAndCitationInspector() throws {
        let app = try makeApp(fixtures: true)
        app.selectMainTab("Knowledge")
        let search = app.textFields["knowledgeSearch"]
        reveal(search, in: app)
        search.tap(); search.typeText("bowline\n")
        let result = app.buttons.containing(.staticText, identifier: "Bowline").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        reveal(result, in: app); result.tap()
        XCTAssertTrue(app.navigationBars["Evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bowline"].exists)
        capture(app, "Offline Wikipedia source")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.textFields["knowledgeSearch"].exists)
    }

    func testWorkKnowledgeApprovalAndDenial() throws {
        let app = try makeApp(fixtures: true)
        app.selectMainTab("Permissions")
        app.segmentedControls["permission_search_knowledge"].buttons["Ask"].tap()
        app.selectMainTab("Chat")
        app.segmentedControls["modePicker"].buttons["Work"].tap()
        let input = app.textFields["messageInput"]
        input.tap(); input.typeText("What is a bowline?")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.buttons["denyTool"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["What is a bowline?"].exists)
        app.buttons["denyTool"].tap()
        let answer = app.staticTexts["assistantMessage"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        XCTAssertTrue(answer.label.contains("declined"))
        XCTAssertFalse(app.buttons["citation_1"].exists)

        app.buttons["New conversation"].tap()
        app.segmentedControls["modePicker"].buttons["Work"].tap()
        input.tap(); input.typeText("What is a bowline? Answer briefly using the sources.")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.buttons["allowTool"].waitForExistence(timeout: 10))
        app.buttons["allowTool"].tap()
        // The dismissed sheet remains in the accessibility tree during animation.
        // Do not mistake its old Deny button for a newly requested tool.
        XCTAssertTrue(app.buttons["allowTool"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["liveModelOutput"].waitForExistence(timeout: 120))
        XCTAssertFalse(app.buttons["New conversation"].isEnabled)
        capture(app, "Live Work model output and tool activity")
        // Hosted simulator runners can be much slower than a local Mac. This is
        // still a bounded wait for real inference, not a sleep or fixture answer.
        let deadline = Date().addingTimeInterval(240)
        while !app.buttons["New conversation"].isEnabled && Date() < deadline {
            // Allow once is not blanket access; refuse any extra action the model proposes.
            if app.buttons["denyTool"].exists && app.buttons["denyTool"].isHittable {
                app.buttons["denyTool"].tap()
                XCTAssertTrue(app.buttons["denyTool"].waitForNonExistence(timeout: 10))
            }
            if app.buttons["New conversation"].wait(for: \.isEnabled, toEqual: true, timeout: 2) { break }
        }
        XCTAssertTrue(app.buttons["citation_1"].exists)
        XCTAssertTrue(app.buttons["New conversation"].waitForExistence(timeout: 5))
        let finished = NSPredicate(format: "enabled == true")
        expectation(for: finished, evaluatedWith: app.buttons["New conversation"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse(answer.label.contains("couldn't complete"))
        XCTAssertTrue(answer.label.lowercased().contains("loop"), answer.label)
        if let citationRange = answer.label.range(of: "\\[[1-9][0-9]*\\]", options: .regularExpression) {
            let citedNumber = String(answer.label[citationRange].dropFirst().dropLast())
            XCTAssertTrue(app.buttons["citation_" + citedNumber].exists)
        } else {
            // Small models can omit citation numbers. The UI must disclose that;
            // it must not invent a citation or present retrieval as verification.
            XCTAssertTrue(app.staticTexts["missingInlineCitations"].exists, answer.label)
        }
        XCTAssertFalse(answer.label.contains("search_knowledge("), answer.label)
        XCTAssertTrue(app.buttons["toolEvent_search_knowledge"].firstMatch.exists)
        capture(app, "Work answer with evidence")
        reveal(app.buttons["citation_1"], in: app); app.buttons["citation_1"].tap()
        XCTAssertTrue(app.navigationBars["Evidence"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    func testDownloadedModelSelectionAndDeletion() throws {
        let app = try makeApp(fixtures: true)
        app.selectMainTab("Models")
        app.segmentedControls.buttons["Downloaded"].tap()
        app.buttons.containing(.staticText, identifier: "smoke-model").firstMatch.tap()
        XCTAssertTrue(app.buttons["Use this model"].waitForExistence(timeout: 5))
        app.buttons["Use this model"].tap()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 5))
        app.buttons["modelPicker"].tap()
        app.buttons.containing(.staticText, identifier: "smoke-model").firstMatch.tap()
        app.buttons["Delete downloaded model"].tap()
        XCTAssertTrue(app.buttons["Delete model"].waitForExistence(timeout: 5))
        app.buttons["Delete model"].tap()
        XCTAssertTrue(app.staticTexts["No models found"].waitForExistence(timeout: 5))
        app.selectMainTab("Chat")
        XCTAssertTrue(app.buttons["modelPicker"].label.contains("Pick a model"))
    }

    func testLiveModelDetailsAndWikipediaCatalog() throws {
        guard ProcessInfo.processInfo.environment["THIMVALE_NETWORK_TESTS"] == "1" else { throw XCTSkip("Network tests disabled") }
        let app = try makeApp()
        app.selectMainTab("Models")
        let search = app.textFields["modelSearch"]
        search.tap(); search.typeText("230M\n")
        app.buttons.containing(.staticText, identifier: "Liquid LFM 2.5").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Download size"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Download ·'")).firstMatch.exists)
        app.buttons["Done"].tap()
        app.selectMainTab("Knowledge")
        app.buttons["exploreWikipedia"].tap()
        XCTAssertTrue(app.staticTexts["English Wikipedia"].firstMatch.waitForExistence(timeout: 40))
        XCTAssertFalse(app.buttons["Try again"].exists)
        capture(app, "Live Wikipedia download catalog")
        app.buttons["Done"].tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Could not reach \(element)")
    }
    private func dismissFiles(_ app: XCUIApplication) {
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 30)); cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
