import XCTest

extension XCUIApplication {
    func openAtlasExploration(category: String = "航线") {
        let entry = buttons["entry-exploration"].firstMatch
        if !entry.exists || !entry.isHittable {
            let sidebar = buttons["atlas-sidebar-toggle"].firstMatch
            XCTAssertTrue(sidebar.waitForExistence(timeout: 12))
            sidebar.tap()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 12))
        entry.tap()
        selectExplorationCategory(category)
    }

    func selectExplorationCategory(_ category: String) {
        let picker = descendants(matching: .any).matching(identifier: "atlas-exploration-category").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        let button = picker.buttons[category].firstMatch
        if button.exists && button.isSelected { return }
        if button.exists && button.isHittable {
            button.tap()
        } else if let index = ["机场", "机型", "航线"].firstIndex(of: category) {
            picker.coordinate(withNormalizedOffset: CGVector(dx: (Double(index) + 0.5) / 3, dy: 0.5)).tap()
        } else {
            XCTFail("找不到探索分类 \(category)")
        }
    }
}
