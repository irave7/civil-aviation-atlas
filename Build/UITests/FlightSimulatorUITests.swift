import UIKit
import XCTest

final class FlightSimulatorUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAidedShanghaiToBeijingKeepsTrackVisibleThroughDebrief() {
        let app = openShanghaiToBeijing(challenge: true)

        #if MAINLAND_DISTRIBUTION && !MAINLAND_APPROVED_MAPS
        let track = control("simulator-progress-track", in: app)
        #else
        let track = control("simulator-globe", in: app)
        #endif
        let briefing = app.staticTexts["飞行简报"].firstMatch
        assertViewport(track, separateFrom: briefing, in: app)
        #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
        assertMiniature(in: track, app: app, gear: "起落架放下")
        #endif
        screenshot("上海虹桥至北京首都：飞行简报与航线图")

        let start = control("exploration-simulator-start", in: app)
        let panel = app.scrollViews["simulator-control-scroll"].firstMatch
        tap(start)

        let phase = control("simulator-phase", in: app)
        wait(for: phase, label: "起飞滑跑")
        assertViewport(track, separateFrom: phase, in: app)
        #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
        waitForValue("跟随飞机", in: control("simulator-globe-viewpoint", in: app))
        #endif
        let rate = control("simulator-rate", in: app)
        tap(rate)
        wait(for: rate, label: "2×")

        let assist = control("simulator-assist", in: app)
        tap(assist, scrolling: panel, at: CGVector(dx: 0.95, dy: 0.5))
        let assistEnabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard assist.exists else { return false }
            let value = (assist.value as? String) ?? (assist.value as? NSNumber)?.stringValue
            return value == "1"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [assistEnabled], timeout: 10), .completed, "辅助驾驶开关应打开")
        wait(for: phase, label: "巡航", timeout: 90)
        assertViewport(track, separateFrom: phase, in: app)
        #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
        assertMiniature(in: track, app: app, gear: "起落架收起")
        #endif
        screenshot("上海虹桥至北京首都：巡航与持久在线地图")

        let debrief = app.staticTexts["飞行记录"].firstMatch
        XCTAssertTrue(debrief.waitForExistence(timeout: 120), "辅助驾驶应完成着陆并显示飞行记录")
        assertViewport(track, separateFrom: debrief, in: app)
        let goArounds = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "复飞次数")).firstMatch
        XCTAssertTrue(goArounds.exists)
        let result = control("flight-challenge-result", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 12))
        XCTAssertTrue(result.label.contains("航线关卡已完成"))
        screenshot("上海虹桥至北京首都：着陆后飞行记录")
    }

    #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
    func testGlobeCameraChoicesKeepBriefingVisible() {
        let app = openShanghaiToBeijing()
        let phone = UIDevice.current.userInterfaceIdiom == .phone
        if phone {
            verifyCameraChoices(in: app, orientation: "竖屏")
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 15), .completed, "应切换到横屏")
        }
        defer { if phone { XCUIDevice.shared.orientation = .portrait } }
        verifyCameraChoices(in: app, orientation: "横屏")

        let track = control("simulator-globe", in: app)
        let start = track.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 0.68))
        let end = track.coordinate(withNormalizedOffset: CGVector(dx: 0.43, dy: 0.60))
        start.press(forDuration: 0.05, thenDragTo: end)
        waitForValue("自由浏览", in: control("simulator-globe-viewpoint", in: app))
        assertViewport(track, separateFrom: app.staticTexts["飞行简报"].firstMatch, in: app)
        screenshot("航线模拟 · 横屏 · 自由浏览")
    }

    private func verifyCameraChoices(in app: XCUIApplication, orientation: String) {
        let track = control("simulator-globe", in: app)
        let briefing = app.staticTexts["飞行简报"].firstMatch
        let viewpoint = control("simulator-globe-viewpoint", in: app)
        let title = app.staticTexts["航线地图"].firstMatch
        assertViewport(track, separateFrom: briefing, in: app)
        let viewportSize = track.frame.size
        let miniatureWidth = assertMiniature(in: track, app: app).width

        for (id, name) in [("global", "全球视角"), ("follow", "跟随飞机"), ("overview", "航线总览")] {
            tap(viewpoint)
            tap(control("simulator-globe-\(id)", in: app))
            waitForValue(name, in: viewpoint)
            assertViewport(track, separateFrom: briefing, in: app)
            XCTAssertEqual(track.frame.width, viewportSize.width, accuracy: 1)
            XCTAssertEqual(track.frame.height, viewportSize.height, accuracy: 1)
            XCTAssertEqual(assertMiniature(in: track, app: app).width, miniatureWidth, accuracy: 1)
            XCTAssertTrue(title.exists)
            XCTAssertTrue(app.frame.contains(title.frame))
            XCTAssertTrue(app.frame.contains(viewpoint.frame))
            XCTAssertFalse(title.frame.intersects(viewpoint.frame), "地图标题与视角按钮应各自可读")
            screenshot("航线模拟 · \(orientation) · \(name)")
        }
    }

    private func waitForValue(_ value: String, in target: XCUIElement) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists && (target.value as? String)?.contains(value) == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed, "应显示\(value)")
    }

    @discardableResult
    private func assertMiniature(in map: XCUIElement, app: XCUIApplication, gear: String? = nil) -> CGRect {
        let aircraft = control("simulator-map-aircraft-3d", in: app)
        XCTAssertTrue(aircraft.waitForExistence(timeout: 20), "应显示实际渲染的三维客机")
        XCTAssertTrue(aircraft.label.contains("C919"), "该航线的三维模型应为 C919")
        if let gear { waitForValue(gear, in: aircraft) }
        let inFrame = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard aircraft.exists, map.exists else { return false }
            let frame = aircraft.frame
            return frame.width > 0 && frame.height > 0 && map.frame.insetBy(dx: -1, dy: -1).contains(frame)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [inFrame], timeout: 12), .completed, "三维客机应完整留在地图内")
        let frame = aircraft.frame
        XCTAssertGreaterThanOrEqual(frame.width, 80)
        XCTAssertLessThanOrEqual(frame.width, 155)
        return frame
    }
    #endif

    private func openShanghaiToBeijing(challenge: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        let theme = UIDevice.current.userInterfaceIdiom == .phone ? "light" : "dark"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-atlas.appearance", theme]
        app.launch()
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .landscapeLeft

        let entry = control("entry-flight-simulator", in: app)
        if !entry.exists { tap(control("atlas-sidebar-toggle", in: app)) }
        tap(entry, scrolling: app.scrollViews.firstMatch)
        if challenge {
            let selector = app.segmentedControls["exploration-route-mode"].firstMatch
            tap(selector.buttons["航线关卡"].firstMatch)
            tap(control("flight-challenge-SHA-PEK", in: app), scrolling: app.scrollViews.firstMatch)
            XCTAssertTrue(control("flight-challenge-briefing", in: app).waitForExistence(timeout: 15))
        } else {
            wait(for: control("exploration-origin", in: app), label: "SHA", timeout: 20)
            tap(control("exploration-route-PEK", in: app), scrolling: app.scrollViews.firstMatch)
        }
        return app
    }

    private func control(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[id].firstMatch
        if button.exists { return button }
        let toggle = app.switches[id].firstMatch
        if toggle.exists { return toggle }
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ target: XCUIElement, scrolling scroll: XCUIElement? = nil, at point: CGVector? = nil) {
        if let scroll {
            for _ in 0..<7 {
                if target.exists && target.isHittable { break }
                if scroll.exists { scroll.swipeUp(velocity: .slow) }
            }
        }
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists && target.isHittable && target.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 15), .completed, "未找到可点按的控件")
        if let point {
            target.coordinate(withNormalizedOffset: point).tap()
        } else {
            target.tap()
        }
    }

    private func wait(for target: XCUIElement, label: String, timeout: TimeInterval = 15) {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists && target.label.contains(label)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: timeout), .completed, "未显示 \(label)")
    }

    private func assertViewport(_ viewport: XCUIElement, separateFrom heading: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(viewport.waitForExistence(timeout: 20))
        XCTAssertTrue(heading.waitForExistence(timeout: 15))
        let map = viewport.frame
        let controls = heading.frame
        XCTAssertGreaterThan(map.width, 100)
        XCTAssertGreaterThan(map.height, 65)
        XCTAssertTrue(app.frame.contains(map.insetBy(dx: 1, dy: 1)), "航线图应保留在屏幕内")
        XCTAssertTrue(map.maxY <= controls.minY + 1 || map.maxX <= controls.minX + 1,
                      "航线图应在控制台上方或左侧")
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
