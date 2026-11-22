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
        tap("exploration-voice", in: app)
        for option in ["captain", "guide", "story", "system"] {
            XCTAssertTrue(button("exploration-voice-\(option)", in: app).waitForExistence(timeout: 8))
        }
        tap("exploration-voice-captain", in: app)

        let indicator = app.descendants(matching: .any).matching(identifier: "exploration-active-voice").firstMatch
        XCTAssertFalse(indicator.exists, "进入时保持静音")
        tap("exploration-narration", in: app)
        waitForLabel("机长广播", in: indicator)
        tap("exploration-voice", in: app)
        tap("exploration-voice-story", in: app)
        waitForLabel("航旅解说", in: indicator)
        tap("exploration-narration", in: app)
        XCTAssertFalse(indicator.exists)

        app.terminate()
        app.launch()
        openFlight(in: app)
        waitForLabel("航旅解说", in: button("exploration-voice", in: app))
        XCTAssertFalse(indicator.exists)
    }

    private func openFlight(in app: XCUIApplication) {
        if !button("entry-exploration", in: app).exists {
            tap("atlas-sidebar-toggle", in: app)
        }
        tap("entry-exploration", in: app)
        tap("exploration-route-PEK", in: app)
        XCTAssertTrue(button("exploration-narration", in: app).waitForExistence(timeout: 15))
    }

    private func button(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    private func tap(_ id: String, in app: XCUIApplication) {
        let item = button(id, in: app)
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
