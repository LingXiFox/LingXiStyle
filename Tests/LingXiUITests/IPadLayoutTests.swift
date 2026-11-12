import XCTest
import UIKit

/// Verifies the iPad home keeps the native two-column layout after a rotation.
/// The test leaves the device in landscape so a simulator screenshot can capture the result.
final class IPadLayoutTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeSurvivesLandscapeRotation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad layout test")
        }

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-LingXiStyle.hasSeenTutorial", "YES"]
        app.launch()

        let home = app.descendants(matching: .any)["home.root"]
        XCTAssertTrue(home.waitForExistence(timeout: 20), "home did not appear")
        XCTAssertTrue(app.buttons["home.selectPhotos"].exists, "picker entry missing in portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertTrue(app.buttons["home.selectPhotos"].waitForExistence(timeout: 10),
                      "picker entry missing after rotation")
        XCTAssertTrue(app.buttons["home.settings"].exists, "settings entry missing after rotation")
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.width, window.frame.height,
                             "window stayed portrait after rotation")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ipad-landscape-home"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
