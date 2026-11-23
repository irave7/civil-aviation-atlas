import UIKit
import XCTest

final class FlightVoiceInteractionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFlightVoiceCanReplayPauseAndAnswerContextualQuestions() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "-atlas.exploration.voice.v1", "guide", "-atlas.simulator.narration.v1", "YES"]
        app.launch()
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        app.openAtlasExploration()

        let route = app.buttons["exploration-route-PEK"].firstMatch
        let content = app.scrollViews["flight-exploration"].firstMatch
        bringIntoView(route, in: content)
        tap(route)
        let speaker = app.buttons["simulator-narration"].firstMatch
        let hasInitialBroadcast = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            speaker.exists && (speaker.label.contains("最近播报 航前准备") ||
                              (speaker.value as? String)?.contains("最近播报 航前准备") == true)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hasInitialBroadcast], timeout: 14), .completed)

        tap(app.buttons["simulator-options"].firstMatch)
        tap(app.descendants(matching: .any).matching(identifier: "simulator-open-voice").firstMatch)
        let scroll = app.scrollViews["simulator-voice-scroll"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 12))
        let replay = app.buttons["simulator-voice-replay"].firstMatch
        bringIntoView(replay, in: scroll)
        tap(replay)
        let pause = app.buttons["simulator-voice-pause"].firstMatch
        tap(pause)
        let voiceStatus = app.staticTexts["simulator-voice-status"].firstMatch
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            voiceStatus.exists && voiceStatus.label == "语音已暂停"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 8), .completed)
        tap(pause)

        let position = app.buttons["simulator-voice-question-progress"].firstMatch
        bringIntoView(position, in: scroll)
        tap(position)
        let summary = app.staticTexts["simulator-voice-summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        XCTAssertTrue(summary.label.contains("上海虹桥"))
        XCTAssertTrue(summary.label.contains("北京首都"))

        let instruments = app.buttons["simulator-voice-question-instruments"].firstMatch
        bringIntoView(instruments, in: scroll)
        tap(instruments)
        XCTAssertTrue(summary.label.contains("当前地速"))
        XCTAssertTrue(replay.isEnabled)
    }

    func testPlayAndStopARecordedGuideInEachChapter() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        app.openAtlasExploration(category: "机场")
        let selector = app.buttons["exploration-voice-style"].firstMatch
        if selector.value as? String != "航程向导" {
            tap(selector)
            tap(app.buttons["AI 配音 · 航程向导"].firstMatch)
        }
        let domestic = app.segmentedControls["exploration-airport-region"].buttons["中国大陆"]
        if domestic.exists && !domestic.isSelected { tap(domestic) }
        let airport = app.buttons["flight-airport-listen-SHA"].firstMatch
        if !airport.exists { tap(app.buttons["flight-airport-chapter-SHA"].firstMatch) }
        checkRecording(airport, in: app.scrollViews["exploration-airport-scroll"].firstMatch)
        tap(selector)
        tap(app.buttons["AI 配音 · 航旅解说"].firstMatch)
        XCTAssertEqual(selector.value as? String, "航旅解说")
        checkRecording(airport, in: app.scrollViews["exploration-airport-scroll"].firstMatch)

        app.selectExplorationCategory("机型")
        let aircraft = app.buttons["exploration-aircraft-listen-c919"].firstMatch
        if !aircraft.exists { tap(app.buttons["exploration-aircraft-mission-c919"].firstMatch) }
        checkRecording(aircraft, in: app.scrollViews["exploration-aircraft-scroll"].firstMatch)

        app.selectExplorationCategory("航线")
        let challenges = app.segmentedControls["exploration-route-mode"].buttons["航线关卡"]
        if !challenges.isSelected { tap(challenges) }
        checkRecording(app.buttons["flight-challenge-listen-SHA-PEK"].firstMatch,
                       in: app.scrollViews["flight-exploration"].firstMatch)
    }

    private func checkRecording(_ button: XCUIElement, in scroll: XCUIElement) {
        bringIntoView(button, in: scroll)
        XCTAssertEqual(button.label, "听 AI 导览")
        tap(button)
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            button.label == "停止播放" && button.value as? String == "正在播放"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 6), .completed)
        let caption = scroll.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "exploration-transcript-")).firstMatch
        XCTAssertTrue(caption.exists)
        tap(button)
        XCTAssertEqual(button.label, "听 AI 导览")
    }

    private func bringIntoView(_ target: XCUIElement, in scroll: XCUIElement) {
        for _ in 0..<6 {
            if target.exists && target.isHittable { return }
            if scroll.exists { scroll.swipeUp(velocity: .slow) }
        }
    }

    private func tap(_ target: XCUIElement) {
        let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists && target.isHittable && target.isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 12), .completed)
        target.tap()
    }
}
