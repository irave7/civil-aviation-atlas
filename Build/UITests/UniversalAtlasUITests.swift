import UIKit
import XCTest

final class UniversalAtlasUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testUniversalAirportEntryAndDistributionControls() {
        let app = launchAtlas()
        #if MAINLAND_DISTRIBUTION && !MAINLAND_APPROVED_MAPS
        XCTAssertTrue(control("mainland-airport-browse", in: app).waitForExistence(timeout: 20))
        XCTAssertFalse(control("world-globe", in: app).exists)
        attachScreenshot(app.screenshot(), named: "大陆版机场浏览首页")
        #else
        XCTAssertTrue(control("world-globe", in: app).waitForExistence(timeout: 20))
        #endif

        tap("globe-featured-HKG", in: app, allowsCenterTap: true)
        #if MAINLAND_DISTRIBUTION
        XCTAssertTrue(control("airport-localized-title", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(control("airport-mode-model", in: app).exists)
        XCTAssertFalse(control("airport-mode-plan", in: app).exists)
        XCTAssertFalse(control("airport-mode-imagery", in: app).exists)
        XCTAssertFalse(control("model-viewport", in: app).exists)
        attachScreenshot(app.screenshot(), named: "大陆版香港国际机场资料")
        tap("airport-mode-routes", in: app)
        XCTAssertTrue(control("route-search-field", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(control("hkg-open-history", in: app).exists)
        XCTAssertFalse(control("airport-live-departures", in: app).exists)
        XCTAssertFalse(control("airport-live-arrivals", in: app).exists)
        #else
        XCTAssertTrue(control("model-viewport", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(control("airport-mode-model", in: app).exists)
        XCTAssertTrue(control("airport-mode-plan", in: app).exists)
        XCTAssertTrue(control("airport-mode-imagery", in: app).exists)
        attachScreenshot(app.screenshot(), named: "香港国际机场三维模型")
        #endif
    }

    func testUniversalAircraftControlsAndPrivacy() {
        let app = launchAtlas()
        openDirectory(in: app)
        tap("entry-privacy", in: app)
        let privacy = control("atlas-privacy", in: app)
        XCTAssertTrue(privacy.waitForExistence(timeout: 15))
        attachScreenshot(app.screenshot(), named: "隐私与数据")
        let clearFavorites = control("privacy-clear-favorites", in: app)
        for _ in 0..<4 where !clearFavorites.exists { privacy.swipeUp() }
        XCTAssertTrue(clearFavorites.exists)

        openDirectory(in: app)
        tap("entry-aircraft", in: app)
        tap("aircraft-a350-900", in: app)
        let viewport = control("model-viewport", in: app)
        XCTAssertTrue(viewport.waitForExistence(timeout: 20))
        XCTAssertTrue(control("aircraft-mode-model", in: app).exists)
        attachScreenshot(app.screenshot(), named: "A350-900 外观与模型展台")
        viewport.doubleTap()
        waitForMode("透视", in: app)
        viewport.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        waitForMode("剖视", in: app)
        viewport.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        waitForMode("外观", in: app)
        let originalViewport = viewport.frame
        tap("model-mode-拆分", in: app, allowsCenterTap: true)
        let separation = app.sliders["model-separation"].firstMatch
        XCTAssertTrue(separation.waitForExistence(timeout: 10))
        XCTAssertEqual(viewport.frame, originalViewport, "拆分控件出现时应保留整个 3D 操作区域")
        XCTAssertTrue(viewport.frame.insetBy(dx: -1, dy: -1).contains(separation.frame))
        XCTAssertTrue(control("model-split-zoom", in: app).exists)
        attachScreenshot(app.screenshot(), named: "A350-900 拆分与镜头缩放")

        tap("model-parts", in: app, allowsCenterTap: true)
        XCTAssertTrue(control("part-overview", in: app).waitForExistence(timeout: 12))
        if UIDevice.current.userInterfaceIdiom == .phone {
            tap("model-parts-sheet-done", in: app)
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height && viewport.exists && viewport.frame.width > viewport.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 15), .completed)
            XCTAssertTrue(control("model-split-zoom", in: app).exists)
            attachScreenshot(XCUIScreen.main.screenshot(), named: "iPhone 横屏客机拆分")
            XCUIDevice.shared.orientation = .portrait
        }
    }

    private func launchAtlas() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft
        XCTAssertTrue(control("atlas-sidebar-toggle", in: app).waitForExistence(timeout: 20))
        return app
    }

    private func openDirectory(in app: XCUIApplication) {
        let directory = control("entry-airports", in: app)
        if !directory.exists || !directory.isHittable {
            tap("atlas-sidebar-toggle", in: app)
        }
        XCTAssertTrue(directory.waitForExistence(timeout: 15))
    }

    private func control(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: id).firstMatch
        return button.exists ? button : app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ id: String, in app: XCUIApplication, allowsCenterTap: Bool = false) {
        let element = control(id, in: app)
        if allowsCenterTap {
            XCTAssertTrue(element.waitForExistence(timeout: 15), "找不到 \(id)")
            if !element.isHittable {
                // Glass controls over a map or native 3D canvas may lack an inferred accessibility hit point.
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return
            }
        }
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 15), .completed, "无法点按 \(id)")
        element.tap()
    }

    private func waitForMode(_ mode: String, in app: XCUIApplication) {
        let selectedMode = control("model-mode-\(mode)", in: app)
        let selection = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            selectedMode.exists && selectedMode.isSelected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selection], timeout: 10), .completed)
    }

    private func attachScreenshot(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
