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
        XCTAssertTrue(telemetry.waitForExistence(timeout: 12))
        wait(for: "机外三维机场") { exterior.label.contains("三维机场") }

        assertView(exterior: exterior, telemetry: telemetry, in: app)
        screenshot("机外跟拍 · 竖屏")

        XCUIDevice.shared.orientation = .landscapeLeft
        wait(for: "横屏") { app.frame.width > app.frame.height }
        assertView(exterior: exterior, telemetry: telemetry, in: app)
        screenshot("机外跟拍 · 横屏")
        let expand = app.buttons["simulator-expand-stage"]
        tap(expand, description: "全屏展示")
        wait(for: "全屏飞行") { expand.label == "显示飞行面板" && !app.buttons["exploration-simulator-start"].exists }
        assertView(exterior: exterior, telemetry: telemetry, in: app)
        screenshot("三维机场 · 横屏全景")
        tap(expand, description: "恢复飞行面板")
        wait(for: "恢复航程面板") { app.buttons["exploration-simulator-start"].exists }

        tap(views.buttons["航图"].firstMatch, description: "航图")
        tap(views.buttons["机外"].firstMatch, description: "返回机外视角")
        assertView(exterior: exterior, telemetry: telemetry, in: app)
        XCUIDevice.shared.orientation = .portrait
    }

    func testAirfieldFollowsFlightFromDepartureToArrival() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        app.openAtlasExploration()
        tap(app.buttons["exploration-route-PEK"].firstMatch, description: "京沪航线")
        let views = app.segmentedControls["simulator-camera"].firstMatch
        tap(views.buttons["机外"].firstMatch, description: "机外视角")
        tap(app.buttons["exploration-simulator-start"], description: "开始飞行")

        let exterior = item("simulator-exterior-view", in: app)
        let phase = item("simulator-phase", in: app)
        let ground = item("simulator-ground-stage", in: app)
        let rate = app.buttons["simulator-rate"].firstMatch
        tap(rate, description: "模拟倍速")
        wait(for: "进入起飞滑跑", timeout: 60) {
            ground.exists && ground.label.contains("起飞滑跑") && exterior.label.contains("三维机场")
        }
        screenshot("起飞滑跑 · 上海虹桥机场三维跑道")
        wait(for: "离开本场进入巡航", timeout: 90) {
            phase.exists && phase.label.contains("巡航") && !exterior.label.contains("三维机场")
        }
        screenshot("巡航 · 从本场三维空间过渡至航线")
        wait(for: "着陆后进入目的地三维机场", timeout: 120) {
            exterior.label.contains("三维机场") && (ground.exists || app.staticTexts["飞行记录"].exists)
        }
        screenshot("抵达北京首都 · 目的地三维机场")
        XCTAssertTrue(app.staticTexts["飞行记录"].firstMatch.waitForExistence(timeout: 90))
    }

    func testTakeoffZoomLimitsOnMapAndExterior() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.openAtlasExploration()
        tap(app.buttons["exploration-route-PEK"].firstMatch, description: "京沪航线")
        let views = app.segmentedControls["simulator-camera"].firstMatch
        let ground = item("simulator-ground-stage", in: app)
        let phase = item("simulator-phase", in: app)
        let pause = app.buttons["simulator-pause"]
        tap(app.buttons["exploration-simulator-start"], description: "开始飞行")
        tap(app.buttons["simulator-rate"], description: "模拟倍速")
        wait(for: "进入跑道实际滑跑", timeout: 80) { ground.exists && ground.label == "起飞滑跑" }
        tap(pause, description: "暂停滑跑")
        #if !MAINLAND_DISTRIBUTION || MAINLAND_APPROVED_MAPS
        let globe = item("simulator-globe", in: app)
        let miniature = item("simulator-map-aircraft-3d", in: app)
        wait(for: "航图飞机可见") { miniature.exists && globe.frame.intersects(miniature.frame) }
        for _ in 0..<2 { globe.pinch(withScale: 3.5, velocity: 3) }
        let closeMapWidth = miniature.frame.width
        XCTAssertLessThanOrEqual(closeMapWidth, globe.frame.width * 0.40 + 1)
        screenshot("起飞滑跑 · 航图近景")
        for _ in 0..<3 { globe.pinch(withScale: 0.25, velocity: -3) }
        wait(for: "地球缩小时保留可读的飞机") {
            miniature.exists && miniature.frame.width >= 36 && miniature.frame.width < closeMapWidth - 1
        }
        screenshot("起飞滑跑 · 航图远景")
        #endif
        tap(views.buttons["机外"], description: "机外跟拍")
        let exterior = item("simulator-exterior-view", in: app)
        let zoom = app.buttons["simulator-exterior-zoom"]
        wait(for: "同一场景中的三维机场与飞机") { exterior.label.contains("三维机场") && exterior.value as? String == "起落架放下" }
        exterior.pinch(withScale: 4, velocity: 3)
        wait(for: "机外近端边界") { zoom.value as? String == "1.18" }
        screenshot("起飞滑跑 · 跑道机外最近视距")
        exterior.pinch(withScale: 0.20, velocity: -3)
        wait(for: "机外远端边界") { zoom.value as? String == "0.72" }
        screenshot("起飞滑跑 · 跑道机外最远视距")
        tap(app.buttons["simulator-rate"], description: "恢复正常速度观察离地")
        tap(pause, description: "继续起飞")
        wait(for: "进入离地阶段", timeout: 60) { phase.exists && phase.label.contains("离地与爬升") }
        tap(pause, description: "暂停初始爬升")
        XCUIDevice.shared.orientation = .landscapeLeft
        wait(for: "旋转维持机外视距") { app.frame.width > app.frame.height && zoom.value as? String == "0.72" }
        screenshot("初始爬升 · 横屏机外最远视距")
        exterior.pinch(withScale: 3.2, velocity: 2)
        exterior.pinch(withScale: 3.2, velocity: 2)
        wait(for: "横屏离地近端边界") { zoom.value as? String == "1.18" }
        screenshot("初始爬升 · 横屏机外最近视距")
        XCTAssertTrue(zoom.exists && zoom.isEnabled)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(zoom.frame))
        XCTAssertGreaterThanOrEqual(zoom.frame.height, 44)
        let diagnostic = XCTAttachment(string: "按钮 \(zoom.frame)，自动命中 \(zoom.isHittable)，应用 \(app.frame)\n\(app.debugDescription)")
        diagnostic.name = "横屏倍率按钮命中"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        zoom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        wait(for: "标准取景") { zoom.value as? String == "1.00" }
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

    private func wait(for description: String, timeout: TimeInterval = 15, when ready: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in ready() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, description)
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
