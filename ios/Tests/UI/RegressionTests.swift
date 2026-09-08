import XCTest

private extension XCUIElement {
    var disclosureValue: String { value as? String ?? "" }
}

@MainActor final class RegressionTests: XCTestCase {
    private func makeApp(fixtures: Bool = false, wikipediaOnly: Bool = false, activityFixture: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.ethanrimes.thimvale")
        app.launchEnvironment["THIMVALE_TEST_SESSION"] = UUID().uuidString
        if activityFixture { app.launchEnvironment["THIMVALE_UI_ACTIVITY_FIXTURE"] = "1" }
        if wikipediaOnly { app.launchEnvironment["THIMVALE_UI_WIKI_ONLY"] = "1" }
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

    func testImportedLocalFileSearchAndCitationAfterRelaunch() throws {
        let app = try makeApp(fixtures: true, wikipediaOnly: true)
        // The fixture copies a real Markdown file into the app's local Exports
        // folder, then imports its URL with the same service as the Files picker.
        app.terminate(); app.launch()
        app.selectMainTab("Knowledge")
        let search = app.textFields["knowledgeSearch"]
        reveal(search, in: app)
        search.tap(); search.typeText("Which channel does the emergency radio use?\n")
        let result = app.buttons.containing(.staticText, identifier: "Field notes.md").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        reveal(result, in: app); result.tap()
        XCTAssertTrue(app.navigationBars["Evidence"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'channel seven'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Exports/Field notes.md'")).firstMatch.exists)
        capture(app, "Imported local Markdown source after relaunch")
        app.buttons["Done"].tap()
        app.selectMainTab("Chat")
        XCTAssertTrue(app.buttons["modelPicker"].exists)
    }

    func testManualWikipediaBrowsingWithoutAModel() throws {
        let app = try makeApp(fixtures: true, wikipediaOnly: true)
        XCTAssertFalse(app.staticTexts["modelMemoryState"].exists)
        app.selectMainTab("Knowledge")
        let read = app.buttons["readWikipedia"]
        reveal(read, in: app); read.tap()
        let pack = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'wikiPack_'")).firstMatch
        XCTAssertTrue(pack.waitForExistence(timeout: 10)); pack.tap()
        XCTAssertTrue(app.staticTexts["Articles A–Z"].waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("bowline\n")
        let bowline = app.buttons["wikiArticle_Bowline"]
        XCTAssertTrue(bowline.waitForExistence(timeout: 10)); bowline.tap()
        XCTAssertTrue(app.navigationBars["Bowline"].waitForExistence(timeout: 10))
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        XCTAssertTrue(web.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'loop'")).firstMatch.waitForExistence(timeout: 10))
        capture(app, "Wikipedia offline article reader")
        let linked = web.links["sheet bend"].firstMatch
        XCTAssertTrue(linked.exists)
        for _ in 0..<4 { if linked.isHittable { break }; web.swipeUp() }
        linked.tap()
        XCTAssertTrue(app.navigationBars["Sheet bend"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Bowline"].tap()
        XCTAssertTrue(app.navigationBars["Bowline"].waitForExistence(timeout: 5))
        app.buttons["Source & license"].tap()
        XCTAssertTrue(app.buttons["Open in browser"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons["Articles"].tap()
        XCTAssertTrue(bowline.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "bowline")
    }

    func testManualWikipediaEmptyState() throws {
        let app = try makeApp()
        app.selectMainTab("Knowledge")
        let read = app.buttons["readWikipedia"]
        reveal(read, in: app); read.tap()
        XCTAssertTrue(app.staticTexts["No downloaded Wikipedia"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Download Wikipedia packs"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(read.exists)
    }

    func testUpdateAndReviewSettingsNeedNoNotificationPermissionAtLaunch() throws {
        let app = try makeApp()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.selectMainTab("Knowledge")
        let updates = app.buttons["wikipediaUpdates"]
        reveal(updates, in: app); updates.tap()
        XCTAssertTrue(app.staticTexts["No packs to update"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Check for updates"].isEnabled)
        app.buttons["Done"].tap()
        app.selectMainTab("Chat"); app.buttons["Settings"].tap()
        let reviews = app.switches["I've already reviewed this app"]
        reveal(reviews, in: app)
        reviews.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(reviews.value as? String, "1")
        XCTAssertFalse(app.buttons["Write an App Store review"].exists)
        app.buttons["Done"].tap()
        app.terminate(); app.launch(); app.buttons["Settings"].tap()
        reveal(reviews, in: app)
        XCTAssertEqual(reviews.value as? String, "1")
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
        // A short answer can finish while the approval sheet is disappearing.
        // Do not require a transient streaming view to remain visible afterward.
        // testLiveTokensStopAndBackgroundModelRelease covers live UI streaming
        // with a deliberately long request; native tests verify token callbacks.
        let live = app.staticTexts["liveModelOutput"]
        let responseVisible = NSPredicate { _, _ in
            live.exists || (app.buttons["New conversation"].isEnabled && app.buttons["messageSources"].exists)
        }
        let visible = XCTNSPredicateExpectation(predicate: responseVisible, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 120), .completed)
        XCTAssertFalse(app.staticTexts["eventOutput"].exists, "Raw output stays collapsed; the reply streams in the conversation")
        capture(app, "Work model response and tool activity")
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
        XCTAssertTrue(app.buttons["messageSources"].exists)
        XCTAssertFalse(app.buttons["citation_1"].exists, "Full source list starts collapsed")
        XCTAssertTrue(app.buttons["New conversation"].waitForExistence(timeout: 5))
        let finished = NSPredicate(format: "enabled == true")
        expectation(for: finished, evaluatedWith: app.buttons["New conversation"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse(answer.label.contains("couldn't complete"))
        XCTAssertTrue(answer.label.lowercased().contains("loop"), answer.label)
        if let citationRange = answer.label.range(of: "\\[[1-9][0-9]*\\]", options: .regularExpression) {
            let citedNumber = String(answer.label[citationRange].dropFirst().dropLast())
            let inline = app.links["[" + citedNumber + "]"].firstMatch
            XCTAssertTrue(inline.exists, "Citation should be a link inside the reply")
            reveal(inline, in: app); inline.tap()
            XCTAssertTrue(app.navigationBars["Evidence"].waitForExistence(timeout: 5))
            app.buttons["Done"].tap()
        } else {
            // Small models can omit citation numbers. The UI must disclose that;
            // it must not invent a citation or present retrieval as verification.
            XCTAssertTrue(app.staticTexts["missingInlineCitations"].exists, answer.label)
        }
        XCTAssertFalse(answer.label.contains("search_knowledge("), answer.label)
        XCTAssertTrue(app.buttons["toolEvent_search_knowledge"].firstMatch.exists)
        let tool = app.buttons["toolEvent_search_knowledge"].firstMatch
        reveal(tool, in: app)
        XCTAssertTrue((tool.value as? String)?.contains("collapsed") == true)
        tool.tap()
        XCTAssertTrue(tool.wait(for: \.disclosureValue, toEqual: "Completed, expanded", timeout: 5))
        XCTAssertTrue(app.staticTexts["eventOutput"].firstMatch.waitForExistence(timeout: 5))
        reveal(tool, in: app)
        tool.tap()
        XCTAssertTrue(tool.wait(for: \.disclosureValue, toEqual: "Completed, collapsed", timeout: 5))
        XCTAssertTrue(app.staticTexts["eventOutput"].firstMatch.waitForNonExistence(timeout: 5))
        capture(app, "Work answer with evidence")
        let sources = app.buttons["messageSources"]
        reveal(sources, in: app); sources.tap()
        XCTAssertTrue(app.buttons["citation_1"].waitForExistence(timeout: 5))
        reveal(app.buttons["citation_1"], in: app); app.buttons["citation_1"].tap()
        XCTAssertTrue(app.navigationBars["Evidence"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    func testToolDisclosureSurvivesRepeatedTapsAndTranscriptScrolling() throws {
        let app = try makeApp(activityFixture: true)
        let tool = app.buttons["toolEvent_search_knowledge"]
        reveal(tool, in: app)
        for _ in 0..<3 {
            tool.tap()
            XCTAssertTrue(tool.wait(for: \.disclosureValue, toEqual: "Completed, expanded", timeout: 5))
            XCTAssertTrue(app.staticTexts["eventOutput"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["eventOutput"].label.contains("Presentation fixture"))
            reveal(tool, in: app); tool.tap()
            XCTAssertTrue(tool.wait(for: \.disclosureValue, toEqual: "Completed, collapsed", timeout: 5))
            XCTAssertTrue(app.staticTexts["eventOutput"].waitForNonExistence(timeout: 5))
        }
        tool.tap()
        XCTAssertTrue(tool.wait(for: \.disclosureValue, toEqual: "Completed, expanded", timeout: 5))
        for _ in 0..<6 { scrollTranscript(app, upward: true) }
        XCTAssertFalse(tool.isHittable)
        for _ in 0..<6 { scrollTranscript(app, upward: false) }
        reveal(tool, in: app)
        XCTAssertTrue(tool.wait(for: \.disclosureValue, toEqual: "Completed, expanded", timeout: 5))
        tool.tap()
        XCTAssertTrue(tool.wait(for: \.disclosureValue, toEqual: "Completed, collapsed", timeout: 5))
        XCTAssertTrue(app.staticTexts["eventOutput"].waitForNonExistence(timeout: 5))
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
            // XCTest can report a partly obscured row as hittable even when
            // its center is behind the fixed chat composer. Bring the whole
            // control into the visible conversation before tapping it.
            let composer = app.textFields["messageInput"]
            let transcript = app.scrollViews["chatTranscript"]
            let clearOfComposer = !element.exists || !composer.exists || element.frame.maxY < composer.frame.minY - 24
            let clearOfHeader = !element.exists || !transcript.exists || element.frame.minY > transcript.frame.minY + 4
            if element.exists && element.isHittable && clearOfComposer && clearOfHeader { return }
            let upward = !element.exists || element.frame.midY >= app.frame.midY
            if transcript.exists { scrollTranscript(app, upward: upward) }
            else if upward { app.swipeUp() }
            else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, "Could not reach \(element)")
    }
    private func scrollTranscript(_ app: XCUIApplication, upward: Bool) {
        let top = app.scrollViews["chatTranscript"].frame.minY + 30
        let bottom = app.textFields["messageInput"].frame.minY - 45
        // Use the outer gutter, not a tool's independently scrolling output.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let high = origin.withOffset(CGVector(dx: 10, dy: top))
        let low = origin.withOffset(CGVector(dx: 10, dy: bottom))
        (upward ? low : high).press(forDuration: 0.05, thenDragTo: upward ? high : low)
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
