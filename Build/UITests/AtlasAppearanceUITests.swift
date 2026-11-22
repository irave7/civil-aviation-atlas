import UIKit
import XCTest

final class AtlasAppearanceUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLightAndDarkAppearanceKeepAirportEntryAvailableAndPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let phone = UIDevice.current.userInterfaceIdiom == .phone
        XCUIDevice.shared.orientation = phone ? .portrait : .landscapeLeft

        select("light", title: "浅色 · 青瓷航空图鉴", on: app, phone: phone)
        closeDirectory(in: app, phone: phone)
        assertHome(in: app)
        assertGlobeRail(isTrailing: false, in: app, phone: phone)
        screenshot("浅色首页 · 青瓷航空图鉴")
        tap(element("globe-featured-HKG", in: app), preferFrame: true)
        assertAirport(in: app)
        #if !MAINLAND_DISTRIBUTION
        if !phone {
            tap(element("model-parts", in: app), preferFrame: true)
            XCTAssertTrue(element("model-inspector", in: app).waitForExistence(timeout: 12))
        }
        #endif
        screenshot("浅色机场 · 香港国际机场")

        select("dark", title: "深色 · 深海飞行仪表", on: app, phone: phone)
        closeDirectory(in: app, phone: phone)
        assertAirport(in: app)
        screenshot("深色机场 · 香港国际机场")

        app.terminate()
        app.launch()
        assertHome(in: app)
        assertGlobeRail(isTrailing: true, in: app, phone: phone)
        screenshot("深色首页 · 深海飞行仪表")
        openDirectory(in: app)
        waitForChoice("深色 · 深海飞行仪表", in: app)
        select("system", title: "跟随系统", on: app, phone: phone)
    }

    private func select(_ option: String, title: String, on app: XCUIApplication, phone: Bool) {
        openDirectory(in: app)
        tap(element("atlas-appearance", in: app), preferFrame: !phone)
        tap(element("atlas-appearance-\(option)", in: app))
        if !phone && !element("atlas-appearance", in: app).exists { openDirectory(in: app) }
        waitForChoice(title, in: app)
    }

    private func openDirectory(in app: XCUIApplication) {
        let menu = element("atlas-appearance", in: app)
        if !menu.exists || !app.frame.intersects(menu.frame) {
            tap(element("atlas-sidebar-toggle", in: app))
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 12))
    }

    private func closeDirectory(in app: XCUIApplication, phone: Bool) {
        let control = element(phone ? "atlas-directory-done" : "atlas-sidebar-toggle", in: app)
        if !phone && !element("atlas-appearance", in: app).exists { return }
        if control.exists { tap(control) }
    }

    private func waitForChoice(_ title: String, in app: XCUIApplication) {
        let menu = element("atlas-appearance", in: app)
        let choice = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            menu.exists && (menu.label.contains(title) || (menu.value as? String)?.contains(title) == true)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [choice], timeout: 12), .completed, "外观应为 \(title)")
    }

    private func assertHome(in app: XCUIApplication) {
        #if MAINLAND_DISTRIBUTION
        XCTAssertTrue(element("mainland-airport-browse", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(element("world-globe", in: app).exists)
        #else
        XCTAssertTrue(element("world-globe", in: app).waitForExistence(timeout: 15))
        #endif
    }

    private func assertGlobeRail(isTrailing: Bool, in app: XCUIApplication, phone: Bool) {
        #if !MAINLAND_DISTRIBUTION
        if !phone {
            let rail = element("globe-featured-rail", in: app)
            let map = element("world-globe", in: app)
            XCTAssertTrue(rail.waitForExistence(timeout: 10))
            XCTAssertEqual(rail.frame.midX > map.frame.midX, isTrailing)
        }
        #endif
    }

    private func assertAirport(in app: XCUIApplication) {
        #if MAINLAND_DISTRIBUTION
        XCTAssertTrue(element("airport-localized-title", in: app).waitForExistence(timeout: 20))
        XCTAssertFalse(element("airport-mode-model", in: app).exists)
        #else
        XCTAssertTrue(element("model-viewport", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(element("airport-mode-plan", in: app).exists)
        XCTAssertTrue(element("airport-mode-imagery", in: app).exists)
        #endif
        XCTAssertTrue(element("airport-mode-routes", in: app).exists)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: id).firstMatch
        return button.exists ? button : app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ element: XCUIElement, preferFrame: Bool = false) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "找不到 \(element.identifier)")
        if preferFrame && !element.frame.isEmpty {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            element.tap()
        }
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
