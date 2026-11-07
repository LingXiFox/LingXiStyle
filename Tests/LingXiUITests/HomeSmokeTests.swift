import XCTest

/// Launches the real app on a simulator and checks the home, settings and Pro entry points.
/// HEIC inspection, conversion, PhotoKit save and quota persistence are covered by
/// LingXiIntegrationTests, which calls the production ConversionService directly.
final class HomeSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeSettingsAndProEntryPoints() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let home = app.descendants(matching: .any)["home.root"]
        XCTAssertTrue(home.waitForExistence(timeout: 20), "home did not appear")
        XCTAssertTrue(app.buttons["home.selectPhotos"].exists, "select photos button missing")
        XCTAssertTrue(app.buttons["home.importFiles"].exists, "file import button missing")
        XCTAssertTrue(app.buttons["home.settings"].exists, "settings button missing")
        XCTAssertTrue(app.buttons["home.quota"].exists, "quota badge missing")

        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "settings sheet missing")

        let proRow = app.buttons["settings.proRow"]
        XCTAssertTrue(proRow.waitForExistence(timeout: 5), "Pro row missing")
        proRow.tap()
        XCTAssertTrue(app.staticTexts["Texel Pro"].waitForExistence(timeout: 10), "Pro page missing")

        let close = app.buttons["pro.close"]
        if close.waitForExistence(timeout: 5) { close.tap() }
        let done = app.buttons["settings.done"]
        if done.waitForExistence(timeout: 5) { done.tap() }

        XCTAssertTrue(app.buttons["home.selectPhotos"].waitForExistence(timeout: 5), "home did not return")
    }
}
