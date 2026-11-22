#if !MAINLAND_DISTRIBUTION
import UIKit
import XCTest

final class AtlasRegionalImageryUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testHanedaRegionalSourceAndAppleSwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let phone = UIDevice.current.userInterfaceIdiom == .phone
        let initial: UIDeviceOrientation = phone ? .portrait : .landscapeLeft
        let rotated: UIDeviceOrientation = phone ? .landscapeLeft : .portrait
        app.launch()
        rotate(to: initial, in: app)
        tap(control("globe-airports", in: app))
        let search = app.textFields["search-field"].firstMatch
        tap(search)
        search.typeText("HND\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 8))
        tap(control("airport-HND", in: app))
        tap(control("airport-mode-imagery", in: app))

        let source = control("airport-imagery-source", in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 12))
        let provider = "日本 · 国土地理院航空影像"
        XCTAssertEqual(source.value as? String, provider)

        tap(source)
        tap(app.buttons["Apple 卫星影像"].firstMatch)
        XCTAssertEqual(source.value as? String, "Apple 卫星影像")

        tap(source)
        tap(app.buttons[provider].firstMatch)

        // The service may be temporarily unreachable. Selection and attribution must still work.
        assertControls(provider: provider, orientation: initial, in: app)
        rotate(to: rotated, in: app)
        assertControls(provider: provider, orientation: rotated, in: app)
        XCUIDevice.shared.orientation = initial
    }

    private func assertControls(provider: String, orientation: UIDeviceOrientation, in app: XCUIApplication) {
        let source = control("airport-imagery-source", in: app)
        let credit = app.descendants(matching: .any)
            .matching(identifier: "airport-imagery-provider-credit").firstMatch
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let screen = app.frame.insetBy(dx: -1, dy: -1)
            return source.exists && source.value as? String == provider && credit.exists
                && credit.label.contains("国土地理院") && !source.frame.isEmpty && !credit.frame.isEmpty
                && screen.contains(source.frame) && screen.contains(credit.frame)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed, "影像选择和署名应完整显示")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "HND-国土地理院航空影像-\(orientation.isLandscape ? "横屏" : "竖屏")"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func rotate(to orientation: UIDeviceOrientation, in app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let screen = app.frame
            return !screen.isEmpty && (screen.width > screen.height) == orientation.isLandscape
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed, "设备未完成旋转")
    }

    private func control(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: id).firstMatch
        return button.exists ? button : app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "找不到 \(element.identifier)")
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}
#endif
