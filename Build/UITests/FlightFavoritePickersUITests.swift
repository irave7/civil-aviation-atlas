import UIKit
import XCTest

final class FlightFavoritePickersUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFlightStartsFromSavedAirportWithSavedAircraft() {
        let app = launchSimulator(with: [
            "-AtlasFavoriteIDs.airport", "(FOC, LHR)", "-AtlasFavoriteIDs.aircraft", "(a350-900)"
        ])
        let departure = app.buttons["exploration-origin"].firstMatch
        tap(departure)
        let savedAirports = app.staticTexts["收藏的出发机场"].firstMatch
        XCTAssertTrue(savedAirports.waitForExistence(timeout: 15))
        let fuzhou = app.buttons["exploration-origin-FOC"].firstMatch
        let shanghai = app.buttons["exploration-origin-SHA"].firstMatch
        XCTAssertTrue(fuzhou.waitForExistence(timeout: 10))
        XCTAssertTrue(shanghai.waitForExistence(timeout: 10))
        XCTAssertLessThan(fuzhou.frame.midY, shanghai.frame.midY)
        XCTAssertEqual(app.buttons.matching(identifier: "exploration-origin-FOC").count, 1)
        XCTAssertFalse(app.buttons["exploration-origin-LHR"].exists)
        screenshot("收藏机场列表")

        let search = app.searchFields.firstMatch
        tap(search)
        search.typeText("FOC")
        XCTAssertFalse(shanghai.exists)
        XCTAssertTrue(savedAirports.exists)
        XCTAssertEqual(app.buttons.matching(identifier: "exploration-origin-FOC").count, 1)
        tap(fuzhou)
        XCTAssertTrue(departure.label.contains("FOC"))

        tap(app.buttons["exploration-route-PEK"].firstMatch)
        tap(app.buttons["simulator-options"].firstMatch)
        tap(app.buttons["simulator-choose-aircraft"].firstMatch)
        XCTAssertTrue(app.staticTexts["收藏的机型"].firstMatch.waitForExistence(timeout: 12))
        let favoriteAircraft = app.buttons["simulator-select-a350-900"].firstMatch
        XCTAssertEqual(app.buttons.matching(identifier: "simulator-select-a350-900").count, 1)
        screenshot("收藏机型列表")
        tap(favoriteAircraft)
        let camera = app.segmentedControls["simulator-camera"].firstMatch
        tap(camera.buttons["驾驶舱"].firstMatch)
        let cockpit = app.descendants(matching: .any).matching(identifier: "simulator-cockpit-view").firstMatch
        XCTAssertTrue(cockpit.waitForExistence(timeout: 12))
        XCTAssertTrue(cockpit.label.contains("A350-900"))

        screenshot("收藏机场 FOC 与收藏机型 A350-900")
    }

    func testRepresentativeAirportChapterOpensAirport() {
        let app = launchSimulator()
        tapSecondSegment("exploration-route-mode", label: "航线关卡", in: app)
        tapSecondSegment("flight-chapter", label: "代表机场", in: app)
        let chapter = app.buttons["flight-airport-chapter-SHA"].firstMatch
        tap(chapter)
        XCTAssertEqual(chapter.value as? String, "已展开")

        let airport = app.buttons["flight-airport-open-SHA"].firstMatch
        let content = app.scrollViews["flight-exploration"].firstMatch
        for _ in 0..<5 where !airport.isHittable { content.swipeUp(velocity: .slow) }
        screenshot("上海虹桥机场篇章")
        tap(airport)
        #if MAINLAND_DISTRIBUTION
        let title = app.staticTexts["airport-localized-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 12))
        XCTAssertTrue(title.label.contains("上海虹桥"))
        #else
        let model = app.descendants(matching: .any).matching(identifier: "model-viewport").firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "上海虹桥")).firstMatch.exists)
        #endif
    }

    private func tapSecondSegment(_ identifier: String, label: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 15), "找不到 \(identifier)")
        let button = picker.buttons[label].firstMatch
        if button.exists && button.isHittable {
            button.tap()
        } else {
            picker.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        }
    }

    private func launchSimulator(with arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + arguments
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        app.launch()
        let entry = app.buttons["entry-flight-simulator"].firstMatch
        if !entry.exists || !entry.isHittable { tap(app.buttons["atlas-sidebar-toggle"].firstMatch) }
        tap(entry)
        return app
    }

    private func tap(_ element: XCUIElement) {
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable && element.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 15), .completed, "无法点按 \(element.identifier)")
        element.tap()
    }

    private func screenshot(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
