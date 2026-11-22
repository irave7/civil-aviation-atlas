#if !MAINLAND_DISTRIBUTION
import UIKit
import XCTest

final class AtlasMapInteractionsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testGlobeAirportCategoriesDefaultToTransportAndToggleIndependently() {
        let app = launchAtlas()
        let categories = control("globe-airport-categories", in: app)
        waitForValue("运输机场", on: categories)

        toggleCategory("globe-show-heliports", label: "直升机场", menu: categories, in: app)
        waitForValue("运输机场、直升机场", on: categories)
        toggleCategory("globe-show-other-airports", label: "其他机场", menu: categories, in: app)
        waitForValue("运输机场、直升机场、其他机场", on: categories)
        toggleCategory("globe-show-heliports", label: "直升机场", menu: categories, in: app)
        waitForValue("运输机场、其他机场", on: categories)
    }

    func testAirportPlanTwistsAndBothResetsRestoreNorth() {
        let app = launchAtlas()
        tap(control("globe-featured-HKG", in: app), in: app)
        tap(control("airport-mode-plan", in: app), in: app)
        let canvas = control("airport-plan-canvas", in: app)
        let north = control("airport-plan-north", in: app)
        waitForValue("正北朝上", on: north)

        canvas.rotate(.pi / 3, withVelocity: 1.5)
        waitForRotation(on: north)
        tap(north, in: app)
        waitForValue("正北朝上", on: north)

        canvas.rotate(-.pi / 3, withVelocity: -1.5)
        waitForRotation(on: north)
        canvas.pinch(withScale: 1.5, velocity: 1.2)
        waitForPlanZoom(on: canvas, greaterThan: 110)
        tap(control("airport-plan-reset", in: app), in: app)
        waitForValue("正北朝上", on: north)
        XCTAssertTrue((canvas.value as? String)?.contains("缩放 100%") == true)
    }

    private func launchAtlas() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft
        XCTAssertTrue(control("world-globe", in: app).waitForExistence(timeout: 20))
        return app
    }

    private func toggleCategory(_ id: String, label: String, menu: XCUIElement, in app: XCUIApplication) {
        let identified = control(id, in: app)
        let titled = app.buttons[label].firstMatch
        if !canTap(identified, in: app) && !canTap(titled, in: app) {
            tap(menu, in: app)
        }
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.canTap(identified, in: app) || self.canTap(titled, in: app)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed, "未显示 \(label) 开关")
        tap(canTap(identified, in: app) ? identified : titled, in: app)
    }

    private func canTap(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && (element.isHittable || centerInApp(of: element, app: app) != nil)
    }

    private func centerInApp(of element: XCUIElement, app: XCUIApplication) -> CGPoint? {
        let frame = element.frame
        let window = app.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard frame.width >= 10, frame.height >= 10, window.contains(center) else { return nil }
        return CGPoint(x: center.x - window.minX, y: center.y - window.minY)
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.canTap(element, in: app)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 15), .completed, "无法点按 \(element.identifier)")
        if element.isHittable {
            element.tap()
        } else if let point = centerInApp(of: element, app: app) {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x, dy: point.y))
                .tap()
        } else {
            XCTFail("控件未落在应用窗口内 \(element.identifier)")
        }
    }

    private func control(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: id).firstMatch
        return button.exists ? button : app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitForValue(_ value: String, on element: XCUIElement) {
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.value as? String == value
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 10), .completed, "预期显示 \(value)")
    }

    private func waitForRotation(on compass: XCUIElement) {
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            compass.exists && (compass.value as? String)?.hasPrefix("正北朝向") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed, "双指旋转后未更新朝向")
    }

    private func waitForPlanZoom(on canvas: XCUIElement, greaterThan minimum: Int) {
        let enlarged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard canvas.exists, let state = canvas.value as? String,
                  let zoom = state.components(separatedBy: "、").first(where: { $0.hasPrefix("缩放 ") }),
                  let percent = Int(zoom.dropFirst(3).dropLast()) else { return false }
            return percent > minimum
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enlarged], timeout: 10), .completed, "双指缩放后未放大平面图")
    }
}
#endif
