import UIKit
import XCTest

final class FlightSimulatorCockpitUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCockpitVoiceAndExteriorKeepPreflightInputs() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-atlas.exploration.voice.v1", "guide"]
        app.launch()
        let onPad = UIDevice.current.userInterfaceIdiom == .pad
        XCUIDevice.shared.orientation = onPad ? .landscapeLeft : .portrait
        let entry = app.buttons["entry-flight-simulator"].firstMatch
        if !entry.exists || !entry.isHittable { tap(app.buttons["atlas-sidebar-toggle"].firstMatch) }
        tap(entry)
        tap(app.buttons["exploration-route-PEK"].firstMatch)

        let voice = app.buttons["simulator-narration"].firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout: 15))
        XCTAssertTrue(voice.label.contains("关闭语音播报"))
        let played = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            voice.label.contains("最近播报 航前准备") || (voice.value as? String)?.contains("最近播报 航前准备") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [played], timeout: 12), .completed, "默认语音应实际启动播放")
        tap(voice)
        XCTAssertTrue(voice.label.contains("开启语音播报"))
        tap(voice)
        XCTAssertTrue(voice.label.contains("关闭语音播报"))

        let views = app.segmentedControls["simulator-camera"].firstMatch
        tap(views.buttons["驾驶舱"].firstMatch)
        let cockpit = item("simulator-cockpit-view", in: app)
        XCTAssertTrue(cockpit.waitForExistence(timeout: 12))
        XCTAssertTrue(cockpit.label.contains("C919"))
        #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
        let terrain = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            cockpit.value as? String == "实景地形" && self.item("simulator-terrain-map", in: app).exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [terrain], timeout: 24), .completed, "驾驶舱应显示渲染完成的机场影像")
        #endif

        let controls = app.scrollViews["simulator-control-scroll"].firstMatch
        let takeoff = app.segmentedControls["cockpit-flaps"].buttons["起飞"].firstMatch
        reveal(takeoff, in: controls)
        tap(takeoff)
        XCTAssertTrue(takeoff.isSelected)
        let brake = app.buttons["cockpit-brake"].firstMatch
        reveal(brake, in: controls)
        tap(brake)
        XCTAssertEqual(brake.value as? String, "解除")
        screenshot("C919 驾驶舱 · 襟翼和驻车刹车")

        tap(views.buttons["机外"].firstMatch)
        let exterior = item("simulator-exterior-view", in: app)
        XCTAssertTrue(exterior.waitForExistence(timeout: 20))
        XCTAssertTrue(exterior.label.contains("C919"))
        let renderedAircraft = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            exterior.value as? String == "起落架放下"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [renderedAircraft], timeout: 15), .completed)
        #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
        XCTAssertTrue(item("simulator-terrain-map", in: app).waitForExistence(timeout: 24))
        #endif
        screenshot("C919 机外视角")
        tap(views.buttons["驾驶舱"].firstMatch)
        XCTAssertTrue(cockpit.waitForExistence(timeout: 12))
        XCUIDevice.shared.orientation = onPad ? .portrait : .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.frame
            return frame.width > 0 && (onPad ? frame.height > frame.width : frame.width > frame.height)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 12), .completed)
        for element in [cockpit, views] {
            XCTAssertTrue(element.waitForExistence(timeout: 12))
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(element.frame), "视角控件应留在窗口内")
        }
        screenshot("C919 驾驶舱 · 旋转后")
        reveal(takeoff, in: controls)
        XCTAssertTrue(takeoff.isSelected)
        reveal(brake, in: controls)
        XCTAssertEqual(brake.value as? String, "解除")

        tap(app.buttons["exploration-simulator-start"].firstMatch)
        XCTAssertTrue(item("simulator-phase", in: app).waitForExistence(timeout: 15))
        tap(views.buttons["航图"].firstMatch)
        #if MAINLAND_DISTRIBUTION && !MAINLAND_APPROVED_MAPS
        XCTAssertTrue(item("simulator-progress-track", in: app).waitForExistence(timeout: 12))
        #else
        XCTAssertTrue(item("simulator-globe", in: app).waitForExistence(timeout: 12))
        XCTAssertTrue(item("simulator-ground-stage", in: app).waitForExistence(timeout: 12))
        #endif
    }

    func testCabinAnnouncerCanPreviewAnotherAirline() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        let entry = app.buttons["entry-flight-simulator"].firstMatch
        if !entry.exists || !entry.isHittable { tap(app.buttons["atlas-sidebar-toggle"].firstMatch) }
        tap(entry)
        tap(app.buttons["exploration-route-PEK"].firstMatch)
        tap(app.buttons["simulator-options"].firstMatch)
        tap(item("simulator-cabin-announcements", in: app))
        let option = app.buttons["simulator-cabin-lufthansa"].firstMatch
        let list = app.collectionViews.firstMatch
        reveal(option, in: list)
        tap(option)
        let preview = app.buttons["simulator-cabin-preview"].firstMatch
        for _ in 0..<8 where !preview.exists || !preview.isHittable { list.swipeDown(velocity: .slow) }
        tap(preview)
        let played = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            preview.label.contains("已播放汉莎航空")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [played], timeout: 10), .completed, "国际航司广播应实际启动播放")
        screenshot("航司广播 · 原创模拟台词")
    }

    private func item(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func tap(_ target: XCUIElement) {
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists && target.isHittable && target.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 15), .completed, "无法点按 \(target.identifier)")
        target.tap()
    }

    private func reveal(_ target: XCUIElement, in scroll: XCUIElement) {
        for _ in 0..<14 {
            let viewport = scroll.frame
            let frame = target.exists ? target.frame : .null
            if !frame.isEmpty && target.isHittable && viewport.insetBy(dx: -1, dy: -1).contains(frame) { return }
            let above = !frame.isEmpty && frame.midY < viewport.midY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: above ? 0.36 : 0.70))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: above ? 0.67 : 0.39))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    private func screenshot(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
