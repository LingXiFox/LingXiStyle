import XCTest

/// 1.8.1 tutorial entry points: first launch, skip, step navigation, and the Home / Settings shortcuts.
/// The Live Photo default chosen inside the tutorial is verified again after reopening the sheet, so the
/// preference is exercised through the real UI instead of only through LingXiKitTests.
final class TutorialUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(firstRun: Bool, app: XCUIApplication) {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if firstRun {
            app.launchArguments += ["-LingXiStyle.hasSeenTutorial", "NO"]
        }
        app.launch()
    }

    private func advanceToLivePhotoStep(in app: XCUIApplication) {
        for _ in 0..<4 {
            app.buttons["tutorial.primary"].tap()
        }
        XCTAssertTrue(app.staticTexts["tutorial.step.livePhoto.title"].waitForExistence(timeout: 5),
                      "four next taps must reach the Live Photo step")
    }

    private func waitForSelected(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.images["Selected"].waitForExistence(timeout: timeout),
                      "the tapped mode must show its selected checkmark")
    }

    func testFirstRunShowsTutorialAndSkipLeadsHome() throws {
        let app = XCUIApplication()
        launch(firstRun: true, app: app)

        let tutorial = app.descendants(matching: .any)["tutorial.root"]
        XCTAssertTrue(tutorial.waitForExistence(timeout: 20), "the first launch must open the tutorial")

        let skip = app.buttons["tutorial.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "the first run must offer a skip action")
        XCTAssertTrue(app.buttons["tutorial.primary"].exists, "the tutorial needs one primary action")
        skip.tap()

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10),
                      "skipping the tutorial must land on home")
        XCTAssertTrue(app.buttons["home.selectPhotos"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tutorial.root"].exists,
                       "the tutorial must close when skipped")
    }

    func testTutorialDoesNotOpenAgainAfterSkip() throws {
        let app = XCUIApplication()
        launch(firstRun: true, app: app)
        let tutorial = app.descendants(matching: .any)["tutorial.root"]
        XCTAssertTrue(tutorial.waitForExistence(timeout: 20))
        app.buttons["tutorial.skip"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10))

        app.terminate()
        launch(firstRun: false, app: app)

        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 20),
                      "home must appear without the tutorial sheet")
        XCTAssertFalse(tutorial.waitForExistence(timeout: 3),
                       "the tutorial must not open automatically once it was seen")
    }

    func testTutorialOpensFromHomeAndSettings() throws {
        let app = XCUIApplication()
        launch(firstRun: false, app: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 20))

        let tutorial = app.descendants(matching: .any)["tutorial.root"]
        let homeTutorial = app.buttons["home.tutorial"]
        XCTAssertTrue(homeTutorial.waitForExistence(timeout: 5), "home must link to the tutorial")
        homeTutorial.tap()
        XCTAssertTrue(tutorial.waitForExistence(timeout: 10), "home tutorial entry did not open the sheet")
        app.buttons["tutorial.done"].tap()
        XCTAssertTrue(app.buttons["home.selectPhotos"].waitForExistence(timeout: 10))

        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let settingsTutorial = app.buttons["settings.tutorial"]
        XCTAssertTrue(settingsTutorial.waitForExistence(timeout: 5), "settings must link to the tutorial")
        settingsTutorial.tap()
        XCTAssertTrue(tutorial.waitForExistence(timeout: 10), "settings tutorial entry did not open the sheet")
        app.buttons["tutorial.done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10),
                      "closing the tutorial must return to settings")
    }

    func testTutorialConfiguresLivePhotoDefaultAndKeepsIt() throws {
        let app = XCUIApplication()
        launch(firstRun: true, app: app)
        let tutorial = app.descendants(matching: .any)["tutorial.root"]
        XCTAssertTrue(tutorial.waitForExistence(timeout: 20))

        XCTAssertTrue(app.staticTexts["tutorial.step.layers.title"].waitForExistence(timeout: 5))
        advanceToLivePhotoStep(in: app)

        let stillMode = app.buttons["livePhoto.mode.stillOnly"]
        let fullMode = app.buttons["livePhoto.mode.full"]
        XCTAssertTrue(stillMode.waitForExistence(timeout: 5), "the Live Photo step must offer both modes")
        XCTAssertTrue(fullMode.exists)
        stillMode.tap()
        waitForSelected(stillMode)
        fullMode.tap()
        waitForSelected(fullMode)
        app.buttons["tutorial.done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10))

        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.buttons["settings.tutorial"].tap()
        XCTAssertTrue(tutorial.waitForExistence(timeout: 10))
        advanceToLivePhotoStep(in: app)
        let persisted = app.buttons["livePhoto.mode.full"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 5))
        waitForSelected(persisted)
    }
}
