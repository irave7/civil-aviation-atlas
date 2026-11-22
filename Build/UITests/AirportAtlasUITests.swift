import XCTest

final class AirportAtlasUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDirectoryTitles() {
        let app = launchAtlas()
        tap("entry-airports", in: app)
        XCTAssertTrue(label(containing: "民航图鉴", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["机场图鉴"].firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(app, named: "机场目录标题")
        tap("entry-aircraft", in: app)
        XCTAssertTrue(app.staticTexts["客机图鉴"].firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(app, named: "客机目录标题")
    }

    func testGlobeOpensAirportModelDirectlyAndPinsLongestRoute() {
        let app = launchAtlas()
        XCTAssertFalse(element("entry-airports", in: app).isHittable)
        attachScreenshot(app, named: "全宽地球启动页")
        tap("globe-featured-HKG", in: app)
        XCTAssertTrue(waitForTappable(element("model-viewport", in: app), timeout: 20))
        XCTAssertFalse(element("entry-airports", in: app).isHittable)
        XCTAssertFalse(element("part-overview", in: app).isHittable)
        XCTAssertTrue(label(containing: "13,053 km", in: app).waitForExistence(timeout: 12))
        attachScreenshot(app, named: "香港机场全宽三维与置顶最远航线")
        tap("airport-longest-route", in: app)
        XCTAssertTrue(element("route-detail", in: app).waitForExistence(timeout: 12))
        XCTAssertTrue(label(containing: "实飞记录", in: app).exists)
        tap("route-detail-close", in: app)
        tap("return-to-globe", in: app)
        XCTAssertTrue(element("world-globe", in: app).waitForExistence(timeout: 12))
    }

    func testAirportSearchModelAndRoute() {
        let app = launchAtlas()
        tap("entry-globe", in: app)
        XCTAssertTrue(element("world-globe", in: app).waitForExistence(timeout: 15))
        attachScreenshot(app, named: "机场地球")
        tap("entry-airports", in: app)
        attachScreenshot(app, named: "机场目录")

        let identifiedSearchField = app.textFields.matching(identifier: "search-field").firstMatch
        let searchField = identifiedSearchField.exists ? identifiedSearchField : app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 12), "Missing airport search field")
        searchField.tap()
        searchField.typeText("HKG")
        tap("airport-HKG", in: app)

        tap("airport-mode-overview", in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "香港國際機場")).firstMatch.exists ||
                      app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "香港国际机场")).firstMatch.exists,
                      "Missing Hong Kong International Airport overview")
        tap("airport-mode-model", in: app)
        tap("model-mode-外观", in: app)
        attachScreenshot(app, named: "香港国际机场外部模型")
        selectPart("part-hkg-terminal", in: app)
        tap("model-mode-内部", in: app)
        attachScreenshot(app, named: "香港国际机场内部模型")
        selectPart("part-hkg-checkin", in: app)
        XCTAssertTrue(label(containing: "值机大堂", in: app).waitForExistence(timeout: 10))
        attachScreenshot(app, named: "香港国际机场值机大堂")
        tap("model-measure", in: app)
        XCTAssertTrue(element("model-distance", in: app).label.contains("起点"))
        tapModelSurface(offsetX: -28, in: app)
        XCTAssertTrue(element("model-distance", in: app).label.contains("终点"))
        tapModelSurface(offsetX: 28, in: app)
        XCTAssertTrue(element("model-distance", in: app).label.contains("模型直线距离"))
        attachScreenshot(app, named: "香港国际机场值机大堂测距")
        tap("model-reset", in: app)
        selectPart("part-hkg-runways", in: app)
        selectPart("part-hkg-runway-07L-25R", in: app)
        XCTAssertTrue(label(containing: "跑道几何长度", in: app).waitForExistence(timeout: 10))
        attachScreenshot(app, named: "香港国际机场北跑道")
        tap("model-reset", in: app)

        tap("airport-mode-imagery", in: app)
        attachScreenshot(app, named: "香港国际机场实景地图")
        tap("airport-imagery-photos", in: app)
        tap("airport-photo-HKGPhotoExterior", in: app)
        XCTAssertTrue(label(containing: "一号客运大楼外观", in: app).waitForExistence(timeout: 10))
        attachScreenshot(app, named: "香港国际机场外观实景照片")
        tap("完成", in: app)
        tap("完成", in: app)

        tap("airport-mode-routes", in: app)
        findRoute("route-SQ875", in: app).tap()
        XCTAssertTrue(label(containing: "机场间大圆距离", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "566", "km")).firstMatch.exists)
        attachScreenshot(app, named: "香港国际机场航线")
        tap("route-aircraft-a350-900", in: app)
        XCTAssertTrue(element("aircraft-mode-model", in: app).waitForExistence(timeout: 12))
    }

    func testAircraftExhibitsAndLinkedRoutes() {
        let app = launchAtlas()
        tap("entry-aircraft", in: app)
        attachScreenshot(app, named: "客机目录")
        tap("aircraft-a350-900", in: app)
        tap("aircraft-mode-model", in: app)

        tap("model-mode-外观", in: app)
        attachScreenshot(app, named: "A350-900 外观")
        tap("model-mode-内部", in: app)
        attachScreenshot(app, named: "A350-900 客舱")
        tap("model-mode-透视", in: app)
        attachScreenshot(app, named: "A350-900 透视")
        tap("model-mode-剖视", in: app)
        attachScreenshot(app, named: "A350-900 剖视")
        tap("model-mode-拆分", in: app)
        attachScreenshot(app, named: "A350-900 拆分")
        tap("model-reset", in: app)
        selectPart("part-engine-right", in: app)
        tap("model-mode-剖视", in: app)
        attachScreenshot(app, named: "A350-900 右侧发动机剖视")
        tap("model-reset", in: app)
        tap("aircraft-configuration", in: app)
        attachScreenshot(app, named: "A350-900 航司与客舱选择")
        tap("configuration-cx-long", in: app)
        XCTAssertTrue(label(containing: "国泰航空", in: app).waitForExistence(timeout: 12))
        attachScreenshot(app, named: "A350-900 国泰航空配置")
        tap("aircraft-mode-routes", in: app)

        XCTAssertTrue(findRoute("route-SQ875", in: app).exists, "Missing A350-900 service SQ875")
    }

    func testAircraftCatalogSearchAndNarrowbodySection() {
        let app = launchAtlas()
        let searchField = searchAircraft("737", in: app)
        let boeing737 = element("aircraft-b737-800", in: app)
        XCTAssertTrue(boeing737.waitForExistence(timeout: 10))
        XCTAssertTrue(boeing737.label.contains("波音 737-800"))
        XCTAssertTrue(boeing737.label.contains("Boeing 737-800"))
        XCTAssertTrue(element("aircraft-b737-max8", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("aircraft-a350-900", in: app).exists)
        tap("双通道", in: app)
        XCTAssertFalse(element("aircraft-b737-800", in: app).exists)
        XCTAssertFalse(element("aircraft-b737-max8", in: app).exists)
        tap("单通道", in: app)
        XCTAssertTrue(element("aircraft-b737-800", in: app).waitForExistence(timeout: 10))
        attachScreenshot(app, named: "737-800 与 737 MAX 8 目录搜索")

        searchField.tap()
        searchField.typeText(" MAX")
        XCTAssertFalse(element("aircraft-b737-800", in: app).exists)
        tap("aircraft-b737-max8", in: app)
        tap("model-mode-剖视", in: app)
        attachScreenshot(app, named: "737 MAX 8 全机剖视")
        selectPart("part-engine-right", in: app)
        tap("model-mode-剖视", in: app)
        XCTAssertTrue(element("part-engine-right-fan", in: app).waitForExistence(timeout: 10))
        attachScreenshot(app, named: "737 MAX 8 右发动机剖视")
    }

    func testA380QuadEngineAndUpperDeck() {
        let app = launchAtlas()
        searchAircraft("A380", in: app)
        tap("aircraft-a380-800", in: app)
        tap("model-mode-外观", in: app)

        let engineIDs = ["part-engine-right", "part-engine-right-outboard", "part-engine-left", "part-engine-left-outboard"]
        for identifier in engineIDs {
            XCTAssertTrue(element(identifier, in: app).waitForExistence(timeout: 10))
        }
        attachScreenshot(app, named: "A380 四发动机外观")
        for (index, identifier) in engineIDs.prefix(2).enumerated() {
            selectPart(identifier, in: app)
            tap("model-mode-剖视", in: app)
            attachScreenshot(app, named: "A380 翼下发动机剖视 \(index + 1)")
            tap("model-reset", in: app)
        }

        selectPart("part-fuselage", in: app)
        tap("model-mode-内部", in: app)
        selectPart("part-cabin-upper", in: app)
        attachScreenshot(app, named: "A380 上层客舱")
    }

    func testExpandedAircraftCatalogAndMultiTouch() throws {
        let app = launchAtlas()
        searchAircraft("787-10", in: app)
        tap("aircraft-b787-10", in: app)
        tap("aircraft-mode-data", in: app)
        XCTAssertTrue(label(containing: "机身长", in: app).waitForExistence(timeout: 12))
        tap("aircraft-mode-routes", in: app)
        XCTAssertTrue(findRoute("route-SQ618", in: app).exists)

        searchAircraft("A350-1000", in: app)
        tap("aircraft-a350-1000", in: app)
        XCTAssertTrue(element("aircraft-mode-model", in: app).waitForExistence(timeout: 12))
        try verifyViewportPinches(in: app)
        let viewport = element("model-viewport", in: app)
        let cameraZoom = app.sliders["model-split-zoom"]
        XCTAssertTrue(cameraZoom.waitForExistence(timeout: 10))
        cameraZoom.adjust(toNormalizedSliderPosition: 0)
        XCTAssertLessThan(try zoomPercent(viewport), 25)
        cameraZoom.adjust(toNormalizedSliderPosition: 0.33)
        tap("model-split-pinch-mode", in: app)
        let separation = app.sliders["model-separation"].normalizedSliderPosition
        let baseline = try zoomPercent(viewport)
        viewport.pinch(withScale: 1.6, velocity: 1.0)
        XCTAssertGreaterThan(try zoomPercent(viewport), baseline)
        XCTAssertEqual(app.sliders["model-separation"].normalizedSliderPosition, separation)
        attachScreenshot(app, named: "A350-1000 双指拆分")
    }

    func testAirportMultiTouchPlanAndSatellite() throws {
        let app = launchAtlas()
        tap("sidebar-airport-SFO", in: app)
        selectPart("part-site-terminals", in: app)
        XCTAssertTrue(label(containing: "航站楼", in: app).waitForExistence(timeout: 12))
        tap("model-reset", in: app)
        try verifyViewportPinches(in: app)
        attachScreenshot(app, named: "SFO 空港 3D 拆分")

        tap("airport-mode-plan", in: app)
        XCTAssertTrue(element("airport-plan-canvas", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["滑行道"].exists)
        XCTAssertTrue(app.buttons["航站楼"].exists)
        attachScreenshot(app, named: "SFO 离线机场平面图")
        tap("airport-mode-model", in: app)
        XCTAssertTrue(element("model-viewport", in: app).waitForExistence(timeout: 12))

        tap("airport-mode-imagery", in: app)
        let pitch = element("airport-imagery-pitch", in: app)
        XCTAssertTrue(pitch.waitForExistence(timeout: 12))
        tap("airport-imagery-pitch", in: app)
        XCTAssertEqual(pitch.value as? String, "倾斜")
        tap("airport-imagery-recenter", in: app)
        attachScreenshot(app, named: "SFO 卫星实景")
    }

    func testAirportWithoutDocumentedRunwayShowsTerrainAndImagery() {
        let app = launchAtlas()
        tap("entry-airports", in: app)
        let search = app.textFields.matching(identifier: "search-field").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 12))
        search.tap()
        search.typeText("AUL")
        tap("airport-AUL", in: app)

        XCTAssertTrue(element("model-viewport", in: app).waitForExistence(timeout: 15))
        selectPart("part-site-terrain", in: app)
        XCTAssertTrue(label(containing: "场址地形", in: app).waitForExistence(timeout: 12))
        XCTAssertFalse(element("airport-mode-plan", in: app).exists)
        attachScreenshot(app, named: "AUL 机场场址地形")
        tap("model-reset", in: app)
        tap("model-mode-拆分", in: app)
        XCTAssertTrue(element("model-separation", in: app).waitForExistence(timeout: 10))

        tap("airport-mode-imagery", in: app)
        XCTAssertTrue(label(containing: "卫星影像 · AUL", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("airport-imagery-pitch", in: app).exists)
    }

    func testAirportCatalogIncludesLargeAndLicensedDomesticSites() {
        let app = launchAtlas()
        tap("entry-airports", in: app)
        tap("全球大型机场", in: app)
        let search = app.textFields.matching(identifier: "search-field").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 12))
        search.tap()
        search.typeText("LFPB")
        XCTAssertTrue(element("airport-LBG", in: app).waitForExistence(timeout: 10))

        tap("中国民用机场", in: app)
        XCTAssertFalse(element("airport-LBG", in: app).exists)
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "JRJ")
        tap("airport-JRJ", in: app)
        XCTAssertTrue(element("model-viewport", in: app).waitForExistence(timeout: 15))
        tap("airport-mode-overview", in: app)
        XCTAssertTrue(label(containing: "运输机场", in: app).waitForExistence(timeout: 10))
        attachScreenshot(app, named: "赣州瑞金机场分类与资料")
    }

    func testRouteSearchAndExpandedDetail() {
        let app = launchAtlas()
        tap("sidebar-airport-HKG", in: app)
        tap("airport-mode-routes", in: app)
        let search = app.textFields.matching(identifier: "route-search-field").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 12))
        search.tap()
        search.typeText("樟宜 空客A350 SQ875\n")
        tap("route-SQ875", in: app)

        let detail = element("route-detail", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 12))
        XCTAssertGreaterThan(detail.frame.width, 600)
        XCTAssertTrue(element("route-map", in: app).exists)
        XCTAssertTrue(element("route-aircraft-a350-900", in: app).exists)
        XCTAssertTrue(label(containing: "机场间大圆距离", in: app).exists)
        XCTAssertTrue(label(containing: "空中客车 A350-900", in: app).exists)
        XCTAssertTrue(label(containing: "新加坡樟宜机场", in: app).exists)
        attachScreenshot(app, named: "航线搜索与加宽详情")
        tap("route-detail-close", in: app)
    }

    func testAirportChineseNameAndEnglishReference() {
        let app = launchAtlas()
        tap("entry-airports", in: app)
        let search = app.textFields.matching(identifier: "search-field").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 12))
        search.tap()
        search.typeText("勒布尔热")
        tap("airport-LBG", in: app)
        tap("airport-mode-overview", in: app)
        let localized = element("airport-localized-title", in: app)
        XCTAssertTrue(localized.waitForExistence(timeout: 12))
        XCTAssertTrue(localized.label.contains("勒布尔热"))
        XCTAssertTrue(element("airport-original-title", in: app).label.contains("Le Bourget"))
        attachScreenshot(app, named: "巴黎勒布尔热机场中文名称")
    }

    func testAircraftLiverySwitchPreservesCabinConfiguration() {
        let app = launchAtlas()
        searchAircraft("波音777-300ER", in: app)
        tap("aircraft-b777-300er", in: app)
        XCTAssertTrue(element("model-viewport", in: app).waitForExistence(timeout: 15))

        let livery = element("aircraft-livery", in: app)
        let picker = element("livery-results", in: app)
        tap("aircraft-livery", in: app)
        tap("livery-air-china", in: app)
        XCTAssertTrue((livery.value as? String)?.contains("中国国际航空") == true)
        XCTAssertTrue(picker.waitForNonExistence(timeout: 8))
        XCTAssertTrue(waitForTappable(element("model-viewport", in: app), timeout: 10))
        attachScreenshot(app, named: "波音 777-300ER 中国国际航空涂装")

        tap("aircraft-livery", in: app)
        tap("livery-singapore-airlines", in: app)
        XCTAssertTrue((livery.value as? String)?.contains("新加坡航空") == true)
        tap("aircraft-configuration", in: app)
        tap("configuration-sq-264", in: app)
        XCTAssertTrue((livery.value as? String)?.contains("新加坡航空") == true)

        tap("aircraft-livery", in: app)
        let special = element("livery-ana-star-wars-bb8", in: app)
        for _ in 0..<5 where !special.isHittable { picker.swipeUp() }
        tap("livery-ana-star-wars-bb8", in: app)
        XCTAssertEqual(livery.value as? String, "星球大战 BB-8 号")
        XCTAssertTrue(picker.waitForNonExistence(timeout: 8))
        XCTAssertTrue(waitForTappable(element("model-viewport", in: app), timeout: 10))
        attachScreenshot(app, named: "波音 777-300ER 星球大战 BB-8 特殊涂装")
    }

    func testFavoritesHomeCanSaveOpenAndRemoveAfterRelaunch() {
        let app = launchAtlas()
        let bookmarks = [
            (shortcut: "sidebar-airport-HKG", row: "favorites-airport-HKG", control: "favorite-airport-HKG"),
            (shortcut: "sidebar-aircraft-a350-900", row: "favorites-aircraft-a350-900", control: "favorite-aircraft-a350-900")
        ]
        tap("entry-favorites", in: app)
        XCTAssertTrue(element("favorites-home", in: app).waitForExistence(timeout: 12))

        for bookmark in bookmarks {
            tap(bookmark.shortcut, in: app)
            let control = element(bookmark.control, in: app)
            XCTAssertTrue(waitForTappable(control, timeout: 12))
            if control.value as? String == "已收藏" { control.tap() }
            XCTAssertEqual(control.value as? String, "未收藏")
            control.tap()
            XCTAssertEqual(control.value as? String, "已收藏")
        }

        app.terminate()
        let reopened = launchAtlas()
        tap("entry-favorites", in: reopened)
        XCTAssertTrue(element("favorites-home", in: reopened).waitForExistence(timeout: 12))
        for bookmark in bookmarks {
            XCTAssertTrue(waitForTappable(element(bookmark.row, in: reopened), timeout: 12), "Saved entry \(bookmark.row) did not persist")
        }
        attachScreenshot(reopened, named: "机场与客机收藏首页")

        for bookmark in bookmarks {
            tap(bookmark.row, in: reopened)
            let control = element(bookmark.control, in: reopened)
            XCTAssertTrue(waitForTappable(control, timeout: 12))
            XCTAssertEqual(control.value as? String, "已收藏")
            control.tap()
            XCTAssertEqual(control.value as? String, "未收藏")
            tap("entry-favorites", in: reopened)
            XCTAssertTrue(element("favorites-home", in: reopened).waitForExistence(timeout: 12))
            XCTAssertFalse(element(bookmark.row, in: reopened).exists)
        }

        reopened.terminate()
        let cleared = launchAtlas()
        tap("entry-favorites", in: cleared)
        XCTAssertTrue(element("favorites-home", in: cleared).waitForExistence(timeout: 12))
        for bookmark in bookmarks {
            XCTAssertFalse(element(bookmark.row, in: cleared).exists)
        }
    }

    func testDomesticAirportHangarsAreIndividual3DParts() {
        let app = launchAtlas()
        tap("entry-airports", in: app)
        let search = app.textFields.matching(identifier: "search-field").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 12))
        search.tap()
        search.typeText("HAK")
        tap("airport-HAK", in: app)
        selectPart("part-site-hangars", in: app)
        let viewport = element("model-viewport", in: app)
        XCTAssertTrue(waitForTappable(viewport, timeout: 20))
        tap("model-mode-拆分", in: app)
        let separation = app.sliders.matching(identifier: "model-separation").firstMatch
        XCTAssertTrue(separation.waitForExistence(timeout: 12))
        let initial = separation.normalizedSliderPosition
        viewport.pinch(withScale: 1.55, velocity: 1.0)
        XCTAssertGreaterThan(separation.normalizedSliderPosition, initial)
        attachScreenshot(app, named: "海口美兰机库 3D 拆分")

        tap("airport-mode-plan", in: app)
        XCTAssertTrue(app.buttons["机库与附属建筑"].waitForExistence(timeout: 10))
    }

    func testRunwayOnlyAirportCanSeparateMarkings() {
        let app = launchAtlas()
        tap("entry-airports", in: app)
        let search = app.textFields.matching(identifier: "search-field").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 12))
        search.tap()
        search.typeText("FOG")
        tap("airport-FOG", in: app)
        tap("airport-mode-plan", in: app)
        XCTAssertTrue(element("airport-plan-canvas", in: app).waitForExistence(timeout: 12))
        tap("airport-mode-model", in: app)
        selectPart("part-FOG-0-runway-15-33", in: app)
        tap("model-mode-拆分", in: app)
        XCTAssertTrue(element("part-FOG-0-runway-15-33-markings", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("model-separation", in: app).exists)
    }

    private func verifyViewportPinches(in app: XCUIApplication) throws {
        let viewport = element("model-viewport", in: app)
        XCTAssertTrue(waitForTappable(viewport, timeout: 20))
        let originalZoom = try zoomPercent(viewport)
        viewport.pinch(withScale: 1.65, velocity: 1.1)
        let enlargedZoom = try zoomPercent(viewport)
        XCTAssertGreaterThan(enlargedZoom, originalZoom)
        viewport.pinch(withScale: 0.79, velocity: -0.55)
        XCTAssertLessThan(try zoomPercent(viewport), enlargedZoom)

        if element("model-measure", in: app).exists {
            tap("model-measure", in: app)
            viewport.pinch(withScale: 1.36, velocity: 0.65)
            XCTAssertTrue(element("model-distance", in: app).label.contains("起点"))
            tap("model-reset", in: app)
        }

        tap("model-mode-拆分", in: app)
        let slider = app.sliders.matching(identifier: "model-separation").firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 12))
        let fixedZoom = try zoomPercent(viewport)
        let baselineSeparation = slider.normalizedSliderPosition
        viewport.pinch(withScale: 1.6, velocity: 1.1)
        let openSeparation = slider.normalizedSliderPosition
        XCTAssertGreaterThan(openSeparation, baselineSeparation)
        XCTAssertEqual(try zoomPercent(viewport), fixedZoom)
        viewport.pinch(withScale: 0.79, velocity: -0.55)
        XCTAssertLessThan(slider.normalizedSliderPosition, openSeparation)
        XCTAssertEqual(try zoomPercent(viewport), fixedZoom)
        viewport.pinch(withScale: 1.45, velocity: 0.9)
    }

    private func zoomPercent(_ viewport: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(viewport.value as? String)
        return try XCTUnwrap(Int(value.filter(\.isNumber)), "Unexpected model zoom value \(value)")
    }

    @discardableResult
    private func searchAircraft(_ query: String, in app: XCUIApplication) -> XCUIElement {
        tap("entry-aircraft", in: app)
        let field = app.textFields.matching(identifier: "aircraft-search-field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Missing aircraft catalogue search")
        field.tap()
        field.typeText(query)
        return field
    }

    private func launchAtlas() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .landscapeLeft
        #endif
        XCTAssertTrue(element("world-globe", in: app).waitForExistence(timeout: 20), "地球没有在启动时打开")
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        return button.exists ? button : app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let control = element(identifier, in: app)
        if identifier.hasPrefix("entry-") || identifier.hasPrefix("sidebar-") {
            if !control.isHittable {
                let directory = element("atlas-sidebar-toggle", in: app)
                XCTAssertTrue(waitForTappable(directory, timeout: 12))
                directory.tap()
            }
        }
        XCTAssertTrue(waitForTappable(control, timeout: 12), "Control \(identifier) never became tappable")
        control.tap()
    }

    private func waitForTappable(_ control: XCUIElement, timeout: TimeInterval) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in control.exists && control.isHittable }, object: nil)
        return XCTWaiter.wait(for: [hittable], timeout: timeout) == .completed
    }

    private func label(containing value: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    private func selectPart(_ identifier: String, in app: XCUIApplication) {
        if !element("part-overview", in: app).exists { tap("model-parts", in: app) }
        tap(identifier, in: app)
        if element("model-parts-sheet-done", in: app).exists { tap("model-parts-sheet-done", in: app) }
    }

    private func tapModelSurface(offsetX: CGFloat, in app: XCUIApplication) {
        let topTrailing = element("model-parts", in: app).frame
        let bottomLeading = element("model-mode-外观", in: app).frame
        let centerX = (topTrailing.maxX + bottomLeading.minX) / 2
        let centerY = (topTrailing.minY + bottomLeading.maxY) / 2
        let offset = CGVector(dx: centerX - app.frame.minX + offsetX, dy: centerY - app.frame.minY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(offset).tap()
    }

    private func findRoute(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let route = app.buttons.matching(identifier: identifier).firstMatch
        for _ in 0..<8 {
            if route.isHittable { return route }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(route.isHittable, "Missing route \(identifier)")
        return route
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        XCTAssertEqual(app.state, .runningForeground)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
