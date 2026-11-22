import XCTest

final class AtlasInteractionPerformanceUITests: XCTestCase {
    @MainActor
    func testLargeAirportDirectoryScrollHitches() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let directory = app.buttons["globe-airports"].firstMatch
        guard directory.waitForExistence(timeout: 20), !directory.frame.isEmpty else {
            XCTFail("机场目录入口未显示")
            return
        }
        directory.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let scope = app.segmentedControls["airport-directory-scope"].firstMatch
        let largeAirports = scope.buttons["全球大型机场"].firstMatch
        guard largeAirports.waitForExistence(timeout: 12) else {
            XCTFail("大型机场筛选未显示")
            return
        }
        largeAirports.tap()

        let result = app.staticTexts["airport-directory-result-count"].firstMatch
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            result.exists && result.label.contains("全球大型机场")
        }, object: nil)
        guard XCTWaiter.wait(for: [loaded], timeout: 12) == .completed else {
            XCTFail("大型机场列表未加载")
            return
        }

        // XCTest discards the first run as a warm-up.
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTHitchMetric(application: app), XCTClockMetric()], options: options) {
            app.swipeUp()
            app.swipeUp()
            app.swipeDown()
            app.swipeDown()
        }

        XCTAssertEqual(app.state, .runningForeground)
    }
}
