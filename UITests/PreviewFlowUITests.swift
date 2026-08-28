import XCTest

/// Drives the whole PoC flow in the simulator using the DEBUG "Thử nhanh"
/// shortcut and captures a screenshot at every step. Run by the `UI preview`
/// workflow; skipped by the normal test action.
final class PreviewFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN"]
        app.launch()
    }

    func testWalkthrough() {
        snap("01-home")

        // Open menu → quick-try with the bundled synthetic package.
        app.buttons["Mở"].firstMatch.tap()
        let quickTry = app.buttons["Thử nhanh (dữ liệu mẫu)"]
        XCTAssertTrue(quickTry.waitForExistence(timeout: 5), "quick-try shortcut missing")
        quickTry.tap()

        // Catalog ready.
        let ready = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'hỗ trợ clip'")
        ).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "catalog never became ready")
        snap("02-catalog")

        // Draw an AOI by tapping the map (top area; control panel is at the bottom).
        let window = app.windows.firstMatch
        for offset in [CGVector(dx: 0.30, dy: 0.28), CGVector(dx: 0.68, dy: 0.30),
                       CGVector(dx: 0.66, dy: 0.55), CGVector(dx: 0.32, dy: 0.52)] {
            window.coordinate(withNormalizedOffset: offset).tap()
        }
        snap("03-aoi-drawn")

        // Run the clip.
        let clip = app.buttons.containing(
            NSPredicate(format: "label BEGINSWITH 'Trích xuất'")
        ).firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout: 5), "clip button missing")
        clip.tap()

        // Results sheet.
        let results = app.navigationBars["Kết quả trích xuất"]
        XCTAssertTrue(results.waitForExistence(timeout: 60), "results never appeared")
        snap("04-results")

        // Open the first written layer's map preview.
        let firstLayer = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'sample_'")
        ).firstMatch
        if firstLayer.waitForExistence(timeout: 5) {
            firstLayer.tap()
            snap("05-layer-preview")
        }
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
