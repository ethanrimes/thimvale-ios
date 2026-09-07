import XCTest

final class NavigationTests: XCTestCase {
    @MainActor func testExpandedCatalogSearchAndHigherMemoryFilter() {
        let app = makeApp(); app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 15))
        app.selectMainTab("Models")
        let size = app.segmentedControls["modelSizeFilter"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.buttons["Higher RAM"].tap()
        XCTAssertTrue(app.staticTexts["higherRAMGuidance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["model_qwen35-9"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["model_qwen35-08"].exists)
        capture(app, name: "Higher RAM model library")
        size.buttons["All sizes"].tap()
        app.textFields["modelSearch"].tap()
        app.textFields["modelSearch"].typeText("Nanbeige\n")
        XCTAssertTrue(app.buttons["model_nanbeige42-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["model_qwen35-9"].exists)
        capture(app, name: "Nanbeige model search")
    }

    @MainActor func testFourBillionModelsFilterAndSearch() {
        let app = makeApp(); app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 15))
        app.selectMainTab("Models")
        let size = app.segmentedControls["modelSizeFilter"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.buttons["4B class"].tap()
        XCTAssertTrue(app.buttons["model_qwen35-4"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["model_qwen35-08"].exists)
        capture(app, name: "4B model library")
        app.buttons["Gemma"].tap()
        XCTAssertTrue(app.buttons["model_gemma3-4"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["model_gemma3-1"].exists)
        app.textFields["modelSearch"].tap()
        app.textFields["modelSearch"].typeText("4b\n")
        XCTAssertTrue(app.buttons["model_gemma3-4"].waitForExistence(timeout: 5))
    }

    @MainActor func testPrimaryNavigationAndModelFiltering() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["appWordmark"].label, "thimvale")
        XCTAssertFalse(app.staticTexts["pocketmind"].exists)
        XCTAssertTrue(app.textFields["messageInput"].exists)
        capture(app, name: "Chat")
        app.selectMainTab("Models")
        XCTAssertTrue(app.textFields["modelSearch"].waitForExistence(timeout: 5))
        capture(app, name: "Models")
        app.textFields["modelSearch"].tap()
        app.textFields["modelSearch"].typeText("Granite\n")
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Granite 4 Micro").firstMatch.waitForExistence(timeout: 5))
        app.selectMainTab("Permissions")
        XCTAssertTrue(app.segmentedControls["permission_search_knowledge"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["permission_list_files"].exists)
        capture(app, name: "Permissions")
        app.selectMainTab("Knowledge")
        XCTAssertTrue(app.buttons["exploreWikipedia"].waitForExistence(timeout: 5))
        capture(app, name: "Knowledge")
    }
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    @MainActor func testWorkModeDoesNotRequireNetworkOrModelToConfigure() {
        let app = makeApp(); app.launch()
        XCTAssertTrue(app.segmentedControls["modePicker"].waitForExistence(timeout: 10))
        app.segmentedControls["modePicker"].buttons["Work"].tap()
        XCTAssertTrue(app.staticTexts["Work with your files."].waitForExistence(timeout: 5))
        app.segmentedControls["modePicker"].buttons["Chat"].tap()
    }
    @MainActor private func makeApp() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.ethanrimes.thimvale")
        app.launchEnvironment["THIMVALE_TEST_SESSION"] = UUID().uuidString
        return app
    }
}

extension XCUIApplication {
    @MainActor func selectMainTab(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let phoneTab = tabBars.buttons[title]
        if phoneTab.exists {
            phoneTab.tap()
            return
        }
        // iPadOS exposes its floating tab items without a TabBar ancestor.
        // Match the observed icon identifier to avoid Chat's mode segment and
        // duplicated text/button descendants inside the same tab item.
        let icons = ["Chat": "bubble.left.and.bubble.right", "Models": "square.stack.3d.up",
                     "Knowledge": "books.vertical", "Permissions": "hand.raised"]
        guard let identifier = icons[title] else {
            XCTFail("Unknown main tab: \(title)", file: file, line: line)
            return
        }
        let tabletTab = descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(tabletTab.waitForExistence(timeout: 5), file: file, line: line)
        tabletTab.tap()
    }
}
