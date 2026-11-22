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
