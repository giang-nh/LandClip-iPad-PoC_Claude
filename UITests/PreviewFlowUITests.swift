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
        // First launch asks for a user name.
        let nameField = app.textFields.firstMatch
        if nameField.waitForExistence(timeout: 5) {
            nameField.tap()
            nameField.typeText("Người kiểm thử")
            app.buttons["Lưu"].tap()
        }

        snap("01-home")

        // Open menu → quick-try with the bundled synthetic package.
        app.buttons["Mở"].firstMatch.tap()
        let quickTry = app.buttons["Thử nhanh (dữ liệu mẫu)"]
        XCTAssertTrue(quickTry.waitForExistence(timeout: 5), "quick-try shortcut missing")
        quickTry.tap()

        // Catalog ready (the layer-selection button only shows once catalogued).
        let ready = app.buttons["Chọn layer"]
        XCTAssertTrue(ready.waitForExistence(timeout: 45), "catalog never became ready")
        snap("02-catalog")

        // Layer selection sheet.
        ready.tap()
        if app.navigationBars.element(boundBy: 0).waitForExistence(timeout: 3) {
            snap("03-layer-selection")
            app.buttons["Xong"].firstMatch.tap()
        }

        // Run the clip (demo AOI is already loaded, so this is enabled).
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
