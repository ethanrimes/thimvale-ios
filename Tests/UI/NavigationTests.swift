import XCTest

final class NavigationTests: XCTestCase {
    @MainActor func testPrimaryNavigationAndModelFiltering() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["appWordmark"].label, "thimvale")
        XCTAssertFalse(app.staticTexts["pocketmind"].exists)
        XCTAssertTrue(app.textFields["messageInput"].exists)
        capture(app, name: "Chat")
        app.tabBars.buttons["Models"].tap()
        XCTAssertTrue(app.textFields["modelSearch"].waitForExistence(timeout: 5))
        capture(app, name: "Models")
        app.textFields["modelSearch"].tap()
        app.textFields["modelSearch"].typeText("Granite\n")
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Granite 4 Micro").firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Permissions"].tap()
        XCTAssertTrue(app.segmentedControls["permission_search_knowledge"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["permission_list_files"].exists)
        capture(app, name: "Permissions")
        app.tabBars.buttons["Knowledge"].tap()
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
        let app = XCUIApplication(bundleIdentifier: "com.ethanrimes.pocketmind")
        app.launchEnvironment["THIMVALE_TEST_SESSION"] = UUID().uuidString
        return app
    }
}
