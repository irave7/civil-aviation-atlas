import UIKit
import XCTest

final class AtlasFlightFlowUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testGuidedRoutePausesAndResumes() {
        let app = launchAtlas()
        openShanghaiToBeijing(in: app)
        tap("exploration-simulator-start", in: app)
        wait(for: control("simulator-phase", in: app), labelContaining: "起飞滑跑")
        let playback = control("simulator-pause", in: app)
        tap("simulator-pause", in: app)
        wait(for: playback, labelContaining: "继续")
        XCTAssertFalse(control("exploration-simulator-arrival-airport", in: app).exists)
        tap("simulator-pause", in: app)
        wait(for: playback, labelContaining: "暂停")
        attachScreenshot(app, named: "上海至北京的导览飞行")
    }

    func testInteractiveRouteWaitsForAction() {
        let app = launchAtlas()
        openShanghaiToBeijing(in: app)
        let mode = app.segmentedControls["simulator-pilot-style"].firstMatch
        tap(mode.buttons["手动操纵"].firstMatch, named: "手动操纵", in: app, scrolls: true)
        tap("exploration-simulator-start", in: app)
        wait(for: control("simulator-phase", in: app), labelContaining: "起飞滑跑")
        let throttle = app.sliders["simulator-throttle"].firstMatch
        reveal(throttle, in: app)
        XCTAssertTrue(throttle.isHittable && throttle.isEnabled)
        throttle.adjust(toNormalizedSliderPosition: 0.4)
        let accelerated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard throttle.exists, let value = throttle.value as? String,
                  let percent = Int(value.prefix(while: \.isNumber)) else { return false }
            return percent > 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [accelerated], timeout: 10), .completed)
        attachScreenshot(app, named: "上海至北京手动操纵推力")
    }

    func testCustomLiveryAppliesAndRestoresAirlinePaint() {
        let app = launchAtlas()
        openShanghaiToBeijing(in: app)
        let camera = app.segmentedControls["simulator-camera"].firstMatch
        tap(camera.buttons["机外"].firstMatch, named: "机外", in: app)
        tap("simulator-options", in: app)
        tap("simulator-open-livery", in: app)
        let editor = control("exploration-livery-sheet", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 12))
        let pattern = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", "exploration-livery-pattern-ribbon", "波浪飘带"))
            .firstMatch
        tap(pattern, named: "波浪飘带", in: app, scrolls: true)
        tap("exploration-livery-apply", in: app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 12))
        let exterior = control("simulator-exterior-view", in: app)
        wait(for: exterior, labelContaining: "我的涂装")
        attachScreenshot(app, named: "上海至北京自定义涂装")

        tap("simulator-options", in: app)
        tap("simulator-open-livery", in: app)
        let restore = control("exploration-livery-restore", in: app)
        reveal(restore, in: app)
        wait(for: restore, labelContaining: "恢复航司涂装")
        tap("exploration-livery-restore", in: app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 12))
        wait(for: exterior, labelContaining: "中国东方航空标准涂装")
    }

    #if !MAINLAND_DISTRIBUTION
    func testWorldwideExplorationShowsSourceAndA350() {
        let app = launchAtlas()
        app.openAtlasExploration()
        let scope = app.segmentedControls.matching(identifier: "exploration-scope").firstMatch
        let worldwide = scope.buttons["全球"]
        XCTAssertTrue(worldwide.waitForExistence(timeout: 15))
        worldwide.tap()
        wait(for: control("exploration-origin", in: app), labelContaining: "PVG")
        let routeRow = control("exploration-route-SIN", in: app)
        XCTAssertTrue(routeRow.waitForExistence(timeout: 15))
        let rowFrame = routeRow.frame
        let appFrame = app.frame
        let center = CGPoint(x: rowFrame.midX, y: rowFrame.midY)
        XCTAssertTrue(rowFrame.width > 0 && rowFrame.height > 0 && appFrame.contains(center))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: center.x - appFrame.minX, dy: center.y - appFrame.minY)).tap()
        let camera = app.segmentedControls["simulator-camera"].firstMatch
        tap(camera.buttons["机外"].firstMatch, named: "机外", in: app)
        wait(for: control("simulator-exterior-view", in: app), labelContaining: "A350-900")
        tap("simulator-options", in: app)
        tap("simulator-open-weather", in: app)
        XCTAssertTrue(control("exploration-reality-panel", in: app).waitForExistence(timeout: 15))
        tap("exploration-reality-fetch", in: app)
        XCTAssertTrue(label(containing: "NOAA 航空气象中心", in: app).waitForExistence(timeout: 20))
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot(app, named: "上海浦东至新加坡的实际天气与航班观测")
    }
    #endif

    func testNativeFlightBoardAndNumberedRouteDetails() {
        let app = launchAtlas()
        openSingapore(in: app)
        tap("airport-mode-routes", in: app)
        tap("airport-flight-details", in: app)
        XCTAssertTrue(control("flight-details-board", in: app).waitForExistence(timeout: 12))
        tap("flight-published-SQ23", in: app, scrolls: true)
        assertFlightFacts(in: app)
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot(app, named: "原生航班班表资料")
        app.terminate()

        app.launch()
        openSingapore(in: app)
        tap("airport-mode-routes", in: app)
        let search = control("route-search-field", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("SQ23\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8))
        tap("route-SQ23", in: app, scrolls: true)
        XCTAssertTrue(control("route-detail", in: app).waitForExistence(timeout: 12))
        tap("route-flight-details", in: app)
        XCTAssertTrue(control("flight-details-board", in: app).waitForExistence(timeout: 12))
        assertFlightFacts(in: app)
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func openSingapore(in app: XCUIApplication) {
        tap("globe-airports", in: app)
        let search = app.textFields.matching(identifier: "search-field").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 12))
        search.tap()
        search.typeText("SIN\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8))
        tap("airport-SIN", in: app, scrolls: true)
    }

    private func assertFlightFacts(in app: XCUIApplication) {
        XCTAssertTrue(control("flight-published-facts", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(label(containing: "新加坡航空", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(label(containing: "A350-900", in: app).exists)
        XCTAssertTrue(label(containing: "班表时刻", in: app).exists)
        XCTAssertTrue(label(containing: "22:05", in: app).exists)
    }

    private func openShanghaiToBeijing(in app: XCUIApplication) {
        app.openAtlasExploration()
        wait(for: control("exploration-origin", in: app), labelContaining: "SHA")
        tap("exploration-route-PEK", in: app, scrolls: true)
    }

    private func launchAtlas() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft
        XCTAssertTrue(control("atlas-sidebar-toggle", in: app).waitForExistence(timeout: 20))
        return app
    }

    private func control(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: id).firstMatch
        return button.exists ? button : app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func label(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text))
            .firstMatch
    }

    private func tap(_ id: String, in app: XCUIApplication, scrolls: Bool = false) {
        tap(control(id, in: app), named: id, in: app, scrolls: scrolls)
    }

    private func tap(_ element: XCUIElement, named name: String, in app: XCUIApplication, scrolls: Bool = false) {
        if scrolls { reveal(element, in: app) }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable && element.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed, "无法点按 \(name)")
        element.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func wait(for element: XCUIElement, labelContaining value: String, timeout: TimeInterval = 12) {
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.label.contains(value)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: timeout), .completed, "未找到 \(value)")
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
