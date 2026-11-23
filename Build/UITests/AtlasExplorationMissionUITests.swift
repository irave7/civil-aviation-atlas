import UIKit
import XCTest

final class AtlasExplorationMissionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCompletesAirportAndAircraftObservationsAndKeepsProgress() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        app.openAtlasExploration(category: "机场")

        selectDomesticAirportRegion(in: app)
        let airport = app.buttons["flight-airport-chapter-SHA"].firstMatch
        XCTAssertTrue(airport.waitForExistence(timeout: 15))
        if airport.value as? String != "已完成" {
            let wrong = app.buttons["exploration-answer-airport-SHA-0"].firstMatch
            if !wrong.exists { tap(airport) }
            let scroll = app.scrollViews["exploration-airport-scroll"].firstMatch
            reveal(wrong, in: scroll)
            tap(wrong)
            let tryAgain = app.staticTexts["exploration-retry-airport-SHA"].firstMatch
            reveal(tryAgain, in: scroll)
            XCTAssertTrue(tryAgain.exists)
            let answer = app.buttons["exploration-answer-airport-SHA-1"].firstMatch
            reveal(answer, in: scroll)
            tap(answer)
        }
        verifyCompleted(airport)
        let airportGuide = app.buttons["flight-airport-listen-SHA"].firstMatch
        if !airportGuide.exists { tap(airport) }
        reveal(airportGuide, in: app.scrollViews["exploration-airport-scroll"].firstMatch)
        screenshot("机场探索 · 上海虹桥任务")

        app.selectExplorationCategory("机型")
        let aircraft = app.buttons["exploration-aircraft-mission-c919"].firstMatch
        XCTAssertTrue(aircraft.waitForExistence(timeout: 15))
        if aircraft.value as? String != "已完成" {
            let answer = app.buttons["exploration-answer-aircraft-c919-1"].firstMatch
            if !answer.exists { tap(aircraft) }
            reveal(answer, in: app.scrollViews["exploration-aircraft-scroll"].firstMatch)
            tap(answer)
        }
        verifyCompleted(aircraft)
        let aircraftGuide = app.buttons["exploration-aircraft-listen-c919"].firstMatch
        if !aircraftGuide.exists { tap(aircraft) }
        reveal(aircraftGuide, in: app.scrollViews["exploration-aircraft-scroll"].firstMatch)
        screenshot("机型探索 · C919 任务")

        let model = app.buttons["exploration-aircraft-open-c919"].firstMatch
        if !model.exists { tap(aircraft) }
        reveal(model, in: app.scrollViews["exploration-aircraft-scroll"].firstMatch)
        tap(model)
        XCTAssertTrue(app.buttons["aircraft-mode-model"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "model-viewport").firstMatch.waitForExistence(timeout: 20))

        app.terminate()
        app.launch()
        app.openAtlasExploration(category: "机型")
        verifyCompleted(app.buttons["exploration-aircraft-mission-c919"].firstMatch)
        app.selectExplorationCategory("机场")
        selectDomesticAirportRegion(in: app)
        verifyCompleted(app.buttons["flight-airport-chapter-SHA"].firstMatch)
        app.selectExplorationCategory("航线")
        XCTAssertTrue(app.segmentedControls["exploration-route-mode"].firstMatch.waitForExistence(timeout: 15))
    }

    func testRouteDiscoveryKeepsControlsVisibleAcrossWidths() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-atlas.appearance", "dark"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.openAtlasExploration(category: "航线")
        let style = app.buttons["exploration-voice-style"].firstMatch
        tap(style)
        tap(app.buttons["AI 配音 · 航程向导"].firstMatch)
        XCTAssertEqual(style.value as? String, "航程向导")
        let modes = app.segmentedControls["exploration-route-mode"].firstMatch
        tap(modes.buttons["自由航线"].firstMatch)
        let departure = app.buttons["exploration-origin"].firstMatch
        XCTAssertTrue(departure.waitForExistence(timeout: 15))
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(departure.frame))
        screenshot("自由航线 · 横屏")

        XCUIDevice.shared.orientation = .portrait
        tap(modes.buttons["航线关卡"].firstMatch)
        let route = app.buttons["flight-challenge-SHA-PEK"].firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 15))
        reveal(route, in: app.scrollViews["flight-exploration"].firstMatch)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(route.frame))
        let guide = app.buttons["flight-challenge-listen-SHA-PEK"].firstMatch
        reveal(guide, in: app.scrollViews["flight-exploration"].firstMatch)
        tap(guide)
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (guide.value as? String) == "正在播放"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 12), .completed)
        screenshot("代表航线 · 竖屏")
        tap(route)
        XCTAssertTrue(app.descendants(matching: .any)["flight-challenge-briefing"].firstMatch.waitForExistence(timeout: 15))
    }

    private func selectDomesticAirportRegion(in app: XCUIApplication) {
        let regions = app.segmentedControls["exploration-airport-region"].firstMatch
        XCTAssertTrue(regions.waitForExistence(timeout: 15))
        let segment = regions.buttons["中国大陆"].firstMatch
        if segment.exists && segment.isSelected { return }
        if segment.exists && segment.isHittable {
            segment.tap()
        } else {
            regions.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        }
    }

    private func verifyCompleted(_ element: XCUIElement) {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.value as? String == "已完成"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 15), .completed)
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        for _ in 0..<12 {
            if element.exists && element.isHittable && scroll.frame.insetBy(dx: -1, dy: -1).contains(element.frame) {
                return
            }
            let above = element.exists && element.frame.midY < scroll.frame.midY
            if above { scroll.swipeDown(velocity: .slow) }
            else { scroll.swipeUp(velocity: .slow) }
        }
    }

    private func tap(_ element: XCUIElement) {
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable && element.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 15), .completed)
        element.tap()
    }

    private func screenshot(_ title: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
