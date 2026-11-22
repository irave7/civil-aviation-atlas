import UIKit
import XCTest

final class AtlasTouchGuideUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTouchGuideOpensFromDirectoryAndModel() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft

        tapDirectoryEntry("entry-gesture-guide", in: app)
        assertGuide(in: app)
        screenshot("目录触控教程")

        tapDirectoryEntry("entry-aircraft", in: app)
        tap(app.buttons["aircraft-a350-900"].firstMatch)
        let viewport = element("model-viewport", in: app)
        XCTAssertTrue(viewport.waitForExistence(timeout: 20))
        tap(app.buttons["model-gesture-help"].firstMatch)
        assertGuide(in: app)
        screenshot("模型内触控教程")

        tap(app.buttons["model-gesture-help-done"].firstMatch)
        XCTAssertTrue(element("gesture-guide", in: app).waitForNonExistence(timeout: 10))
        XCTAssertTrue(viewport.exists)
    }

    private func tapDirectoryEntry(_ id: String, in app: XCUIApplication) {
        let entry = app.buttons[id].firstMatch
        if !entry.exists { tap(app.buttons["atlas-sidebar-toggle"].firstMatch) }
        XCTAssertTrue(entry.waitForExistence(timeout: 12))
        if !entry.isHittable { app.swipeUp() }
        tap(entry)
    }

    private func assertGuide(in app: XCUIApplication) {
        XCTAssertTrue(element("gesture-guide", in: app).waitForExistence(timeout: 12))
        for (id, label) in [("gesture-guide-zoom", "双指缩放"), ("gesture-guide-split", "三指拆分与合并")] {
            let heading = app.staticTexts[id].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 8))
            XCTAssertEqual(heading.label, label)
            XCTAssertGreaterThan(heading.frame.width, 0)
            XCTAssertGreaterThanOrEqual(heading.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(heading.frame.maxX, app.frame.maxX)
        }
    }

    private func tap(_ target: XCUIElement) {
        XCTAssertTrue(target.waitForExistence(timeout: 12), "找不到 \(target.identifier)")
        if target.isHittable { target.tap() }
        else { target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
