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

    func testFavoriteWidebodyKeepsRunwayVisibleAtBothExteriorPinchLimits() {
        let app = launchSimulator(with: [
            "-AtlasFavoriteIDs.aircraft", "(a350-900)",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityMedium.rawValue
        ])
        XCUIDevice.shared.orientation = .portrait
        let beijing = app.buttons["exploration-route-PEK"].firstMatch
        let routes = app.scrollViews["flight-exploration"].firstMatch
        XCTAssertTrue(routes.waitForExistence(timeout: 15))
        for _ in 0..<4 where !beijing.isHittable { routes.swipeUp(velocity: .slow) }
        tap(beijing)
        tap(app.buttons["simulator-options"].firstMatch)
        tap(app.buttons["simulator-choose-aircraft"].firstMatch)
        tap(app.buttons["simulator-select-a350-900"].firstMatch)
        tap(app.segmentedControls["simulator-camera"].buttons["机外"].firstMatch)
        let exterior = app.descendants(matching: .any).matching(identifier: "simulator-exterior-view").firstMatch
        let zoom = app.buttons["simulator-exterior-zoom"].firstMatch
        let ground = app.descendants(matching: .any).matching(identifier: "simulator-ground-stage").firstMatch
        tap(app.buttons["exploration-simulator-start"].firstMatch)
        tap(app.buttons["simulator-rate"].firstMatch)
        let onRunway = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            ground.exists && ground.label == "起飞滑跑"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [onRunway], timeout: 85), .completed)
        tap(app.buttons["simulator-pause"].firstMatch)
        XCTAssertTrue(exterior.label.contains("A350-900") && exterior.label.contains("三维机场"))
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(exterior.frame))
        let canvas = app.descendants(matching: .any).matching(identifier: "simulator-exterior-canvas").firstMatch
        let source = app.descendants(matching: .any).matching(identifier: "simulator-airfield-source").firstMatch
        let telemetry = app.descendants(matching: .any).matching(identifier: "simulator-exterior-telemetry").firstMatch
        for element in [canvas, source, telemetry] { XCTAssertTrue(element.waitForExistence(timeout: 10)) }
        XCTAssertGreaterThan(canvas.frame.height, 75)
        XCTAssertLessThanOrEqual(telemetry.frame.maxY, canvas.frame.minY + 1)
        XCTAssertGreaterThanOrEqual(source.frame.minY, canvas.frame.maxY - 1)
        XCTAssertTrue(source.label.contains("OpenStreetMap"))

        for (caption, scale, velocity, target): (String, CGFloat, CGFloat, String) in [
            ("近景", 4, 3, "1.18"), ("远景", 0.20, -3, "0.72")
        ] {
            canvas.pinch(withScale: scale, velocity: velocity)
            let atLimit = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                zoom.value as? String == target
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [atLimit], timeout: 12), .completed)
            XCTAssertEqual(ground.label, "起飞滑跑")
            let image = XCTAttachment(screenshot: canvas.screenshot())
            image.name = "A350-900 · 跑道滑跑 · \(caption)"
            image.lifetime = .keepAlways
            add(image)
        }
        screenshot("宽体机滑跑 · 大字版完整界面")
    }

    func testRepresentativeAirportChapterOpensAirport() {
        let app = launchSimulator()
        app.selectExplorationCategory("机场")
        let chapter = app.buttons["flight-airport-chapter-SHA"].firstMatch
        let airport = app.buttons["flight-airport-open-SHA"].firstMatch
        if !airport.exists { tap(chapter) }
        XCTAssertTrue(airport.waitForExistence(timeout: 12))
        let content = app.scrollViews["exploration-airport-scroll"].firstMatch
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

    private func launchSimulator(with arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + arguments
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        app.launch()
        app.openAtlasExploration()
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
