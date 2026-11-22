import UIKit
import XCTest

final class FlightExteriorCameraUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testExteriorAircraftAndTerrainRemainVisibleAfterRotation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        app.openAtlasExploration()
        tap(app.buttons["exploration-route-PEK"].firstMatch, description: "京沪航线")
        let views = app.segmentedControls["simulator-camera"].firstMatch
        tap(views.buttons["机外"].firstMatch, description: "机外视角")

        let exterior = item("simulator-exterior-view", in: app)
        let telemetry = item("simulator-exterior-telemetry", in: app)
        let terrain = item("simulator-terrain-map", in: app)
        XCTAssertTrue(telemetry.waitForExistence(timeout: 12))
        #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
        XCTAssertTrue(terrain.waitForExistence(timeout: 24), "机外视角应保持实景")
        #endif

        assertView(exterior: exterior, telemetry: telemetry, in: app)
        screenshot("机外跟拍 · 竖屏")

        XCUIDevice.shared.orientation = .landscapeLeft
        wait(for: "横屏") { app.frame.width > app.frame.height }
        assertView(exterior: exterior, telemetry: telemetry, in: app)
        screenshot("机外跟拍 · 横屏")

        tap(views.buttons["航图"].firstMatch, description: "航图")
        tap(views.buttons["机外"].firstMatch, description: "返回机外视角")
        assertView(exterior: exterior, telemetry: telemetry, in: app)
        XCUIDevice.shared.orientation = .portrait
    }

    private func assertView(exterior: XCUIElement, telemetry: XCUIElement, in app: XCUIApplication) {
        wait(for: "机外三维模型和飞行数据") {
            telemetry.exists && exterior.exists
                && exterior.label.contains("C919")
                && (exterior.value as? String) == "起落架放下"
        }
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(exterior.frame))
        XCTAssertTrue(exterior.frame.insetBy(dx: -1, dy: -1).contains(telemetry.frame))
    }

    private func item(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func wait(for description: String, when ready: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in ready() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, description)
    }

    private func tap(_ element: XCUIElement, description: String) {
        wait(for: "无法点按\(description)") { element.exists && element.isHittable && element.isEnabled }
        element.tap()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
