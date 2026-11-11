import XCTest

/// Native iPad surface: the app must run as a regular-width app, not an iPhone
/// compatibility window, and show the queue rail beside the active page.
final class IPadLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRegularWidthShowsQueueRailBesideDetail() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad,
                          "iPad-only layout check")

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-LingXiStyle.hasSeenTutorial", "YES"]
        app.launch()

        let rail = app.descendants(matching: .any)["workspace.rail"]
        XCTAssertTrue(rail.waitForExistence(timeout: 20),
                      "regular width must show the queue rail")
        XCTAssertTrue(app.buttons["home.selectPhotos"].waitForExistence(timeout: 10),
                      "the detail pane must show the active page")
        XCTAssertTrue(app.buttons["home.settings"].exists)
    }
}
