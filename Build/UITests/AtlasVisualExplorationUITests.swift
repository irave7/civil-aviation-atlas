import UIKit
import XCTest

final class AtlasVisualExplorationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testExplorationAndLiveryAtAdaptiveWidths() {
        let app = XCUIApplication()
        let phone = UIDevice.current.userInterfaceIdiom == .phone
        let first: UIDeviceOrientation = phone ? .portrait : .landscapeLeft
        let second: UIDeviceOrientation = phone ? .landscapeLeft : .portrait
        let device = phone ? "iPhone" : "iPad"

        for theme in ["light", "dark"] {
            XCUIDevice.shared.orientation = first
            app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                                   "-atlas.appearance", theme]
            app.launch()
            waitForOrientation(first, in: app)
            openBundledFlight(in: app, theme: theme)
            captureFlight("\(device)-\(theme)-\(name(of: first))", in: app)

            XCUIDevice.shared.orientation = second
            waitForOrientation(second, in: app)
            captureFlight("\(device)-\(theme)-\(name(of: second))", in: app)

            tap("simulator-options", in: app)
            tap("simulator-open-livery", in: app)
            captureLivery("\(device)-\(theme)-\(name(of: second))", in: app)

            XCUIDevice.shared.orientation = first
            waitForOrientation(first, in: app)
            captureLivery("\(device)-\(theme)-\(name(of: first))", in: app)
            app.terminate()
        }
    }

    private func openBundledFlight(in app: XCUIApplication, theme: String) {
        let entry = element("entry-exploration", in: app)
        if !entry.exists || !entry.isHittable { tap("atlas-sidebar-toggle", in: app) }
        XCTAssertTrue(entry.waitForExistence(timeout: 12))
        let appearance = element("atlas-appearance", in: app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 12))
        let title = theme == "light" ? "浅色" : "深色"
        XCTAssertTrue(appearance.label.contains(title) || (appearance.value as? String)?.contains(title) == true)
        entry.tap()
        app.selectExplorationCategory("航线")
        let route = element("exploration-route-PEK", in: app)
        reveal(route, in: app)
        route.tap()

        let views = app.segmentedControls["simulator-camera"]
        let exterior = views.buttons["机外"]
        XCTAssertTrue(exterior.waitForExistence(timeout: 15))
        exterior.tap()
    }

    private func captureFlight(_ suffix: String, in app: XCUIApplication) {
        let stage = element("simulator-exterior-view", in: app)
        let instruction = app.staticTexts["飞行简报"].firstMatch
        let control = element("simulator-exterior-camera", in: app)
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
        XCTAssertTrue(instruction.waitForExistence(timeout: 10))
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertTrue(stage.label.contains("C919"))
        assertHorizontalBounds(stage, in: app)
        assertHorizontalBounds(instruction, in: app)
        assertHorizontalBounds(control, in: app)
        if app.frame.width >= 740 {
            XCTAssertLessThan(stage.frame.midX, instruction.frame.midX, "宽屏应将飞行画面与简报并排")
        }
        attach("exploration-\(suffix)")
    }

    private func captureLivery(_ suffix: String, in app: XCUIApplication) {
        let editor = element("exploration-livery-sheet", in: app)
        let apply = element("exploration-livery-apply", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 12))
        XCTAssertTrue(apply.waitForExistence(timeout: 12))
        assertHorizontalBounds(apply, in: app)
        attach("livery-\(suffix)")
    }

    private func waitForOrientation(_ orientation: UIDeviceOrientation, in app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.frame
            return !frame.isEmpty && (frame.width > frame.height) == orientation.isLandscape
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 12), .completed, "设备窗口方向未更新")
    }

    private func assertHorizontalBounds(_ target: XCUIElement, in app: XCUIApplication) {
        let targetFrame = target.frame
        let frame = app.frame
        XCTAssertGreaterThan(targetFrame.width, 0)
        XCTAssertGreaterThanOrEqual(targetFrame.minX, frame.minX - 1, target.identifier)
        XCTAssertLessThanOrEqual(targetFrame.maxX, frame.maxX + 1, target.identifier)
    }

    private func name(of orientation: UIDeviceOrientation) -> String {
        orientation.isLandscape ? "landscape" : "portrait"
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: id).firstMatch
        return button.exists ? button : app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 12))
        target.tap()
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if target.exists && target.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(target.isHittable, "无法滚动到 \(target.identifier)")
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
