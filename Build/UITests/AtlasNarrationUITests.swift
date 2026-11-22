import XCTest

final class AtlasNarrationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOfflineNarrationStylesCanChangeAndPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        openFlight(in: app)
        let indicator = item("simulator-narration", in: app)
        if indicator.label.contains("开启语音播报") { indicator.tap() }
        choose("AI 配音 · 机长广播", in: app)
        waitForLabel("机长广播", in: indicator)
        choose("AI 配音 · 航旅解说", in: app)
        waitForLabel("航旅解说", in: indicator)

        app.terminate()
        app.launch()
        openFlight(in: app)
        waitForLabel("航旅解说", in: indicator)
    }

    private func openFlight(in app: XCUIApplication) {
        app.openAtlasExploration()
        tap("exploration-route-PEK", in: app)
        XCTAssertTrue(item("simulator-narration", in: app).waitForExistence(timeout: 15))
    }

    private func choose(_ style: String, in app: XCUIApplication) {
        tap("simulator-options", in: app)
        tap("simulator-open-voice", in: app)
        tap("simulator-voice-style", in: app)
        let option = app.buttons[style].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
        let done = app.navigationBars["语音互动"].buttons["完成"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
    }

    private func item(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ id: String, in app: XCUIApplication) {
        let item = item(id, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.tap()
    }

    private func waitForLabel(_ phrase: String, in item: XCUIElement) {
        let hasLabel = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            item.exists && (item.label.contains(phrase) || (item.value as? String)?.contains(phrase) == true)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hasLabel], timeout: 10), .completed)
    }
}
