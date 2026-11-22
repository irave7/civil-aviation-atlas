import SwiftUI
import UIKit

@main
struct AirportAtlasApp: App {
    @AppStorage("atlas.appearance") private var appearance = AtlasAppearance.system

    init() {
        AtlasTypography.prepare()
    }

    var body: some Scene {
        WindowGroup {
            AtlasHome(library: .shared, appearance: $appearance)
                .font(AtlasTypography.font(.body))
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

private enum AtlasDestination: Hashable {
    case favorites
    case globe
    case airports
    case airport(String)
    case fleet
    case explore
    case simulator
    case aircraft(String)
    case gestureGuide
    case privacy
    case sources
}

@MainActor
struct AtlasHome: View {
    let library: AtlasLibrary
    @Binding var appearance: AtlasAppearance
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorContrast
    @State private var favorites = AtlasFavorites()
    @State private var tabletDestination: AtlasDestination = .globe
    @State private var phonePath: [AtlasDestination] = []
    @State private var showsPhoneDirectory = false
    @State private var showsAppearance = false
    @State private var query = ""
    @State private var visibility: NavigationSplitViewVisibility = .detailOnly
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resolvedScheme: ColorScheme { appearance.colorScheme ?? colorScheme }
    private var palette: AtlasPalette { AtlasPalette(resolvedScheme, contrast: colorContrast) }
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var destination: AtlasDestination {
        isPhone ? phonePath.last ?? .globe : tabletDestination
    }

    var body: some View {
        Group {
            if isPhone {
                phoneApp
            } else {
                tabletApp
            }
        }
        .environment(\.colorScheme, resolvedScheme)
        .background(alignment: .topLeading) {
            AtlasWindowAppearance(selection: appearance)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .background(palette.page.ignoresSafeArea())
        .tint(palette.accent)
        .task(priority: .utility) { await library.prepareObservedRoutes() }
        .task(priority: .utility) {
            guard DistributionPolicy.airportSiteModelsAvailable, let sample = library.airport("FOC") else { return }
            await Task.detached(priority: .utility) { AirportSiteCatalog.preload(for: sample) }.value
        }
    }

    private var phoneApp: some View {
        NavigationStack(path: $phonePath) {
            GlobeView(library: library, open: { navigate(.airport($0.id)) })
                .navigationTitle(title(for: .globe))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(palette.surface, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .toolbarColorScheme(resolvedScheme, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { sidebarButton }
                    ToolbarItem(placement: .principal) {
                        Text("民航图鉴")
                            .font(AtlasTypography.font(.headline, weight: .bold))
                            .foregroundStyle(palette.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        favoritesButton
                        airportDirectoryButton
                    }
                }
                .navigationDestination(for: AtlasDestination.self) { page in
                    detail(page)
                        .navigationTitle(phoneTitle(for: page))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(palette.surface, for: .navigationBar)
                        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                        .toolbarColorScheme(resolvedScheme, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) { sidebarButton }
                        }
                }
        }
        .sheet(isPresented: $showsPhoneDirectory, onDismiss: { query = "" }) {
            NavigationStack {
                sidebar
                    .navigationTitle("民航图鉴")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(palette.surface, for: .navigationBar)
                    .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                    .toolbarColorScheme(resolvedScheme, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { appearanceButton }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showsPhoneDirectory = false }
                                .accessibilityIdentifier("atlas-directory-done")
                        }
                    }
            }
            .preferredColorScheme(appearance.colorScheme)
            .sheet(isPresented: $showsAppearance, content: appearanceSheet)
        }
    }

    private var tabletApp: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            sidebar
                .navigationTitle("民航图鉴")
                .toolbarColorScheme(resolvedScheme, for: .navigationBar)
                .navigationSplitViewColumnWidth(min: 225, ideal: 265, max: 310)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ZStack {
                GlobeView(library: library, open: { navigate(.airport($0.id)) })
                    .opacity(destination == .globe ? 1 : 0)
                    .allowsHitTesting(destination == .globe)
                    .accessibilityHidden(destination != .globe)
                    .zIndex(0)
                if destination != .globe {
                    detail(destination)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(palette.page)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .navigationTitle(title(for: destination))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .sidebarToggle)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbarColorScheme(resolvedScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { sidebarButton }
                ToolbarItem(placement: .principal) {
                    Text(destination == .globe ? "民航图鉴" : title(for: destination))
                        .font(AtlasTypography.font(.headline, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                if destination == .globe {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        favoritesButton
                        airportDirectoryButton
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showsAppearance, content: appearanceSheet)
    }

    private var sidebar: some View {
        List {
            Section {
                entry("收藏", symbol: "star", target: .favorites, id: "entry-favorites")
                entry(title(for: .globe), symbol: "globe.asia.australia.fill", target: .globe, id: "entry-globe")
                entry("机场图鉴", symbol: "airplane.arrival", target: .airports, id: "entry-airports")
                entry("客机图鉴", symbol: "airplane", target: .fleet, id: "entry-aircraft")
                entry("航线探索", symbol: "point.topleft.down.to.point.bottomright.curvepath", target: .explore, id: "entry-exploration")
                entry("航线模拟", symbol: "airplane.circle", target: .simulator, id: "entry-flight-simulator")
                entry("隐私与数据", symbol: "hand.raised", target: .privacy, id: "entry-privacy")
                entry("触控教程", symbol: "hand.tap", target: .gestureGuide, id: "entry-gesture-guide")
                if !isPhone { appearanceButton }
            } header: {
                Text("浏览")
            }
            Section(query.isEmpty ? "精选机场" : "机场搜索") {
                ForEach(library.search(query).prefix(query.isEmpty ? 3 : 40)) { airport in
                    Button { navigate(.airport(airport.id)) } label: {
                        HStack(spacing: 8) {
                            Text(airport.displayCode)
                                .font(AtlasTypography.font(.subheadline).monospaced().weight(.semibold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 49, alignment: .leading)
                            Text(airport.displayName)
                                .font(AtlasTypography.font(.subheadline))
                                .foregroundStyle(palette.ink)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar-airport-\(airport.id)")
                }
                if !query.isEmpty && library.search(query).isEmpty {
                    Text("没有匹配的机场").foregroundStyle(.secondary)
                }
            }
            if query.isEmpty {
                Section("客机") {
                    ForEach(aircraftShortcuts) { profile in
                        entry(profile.displayName, symbol: "airplane", target: .aircraft(profile.id), id: "sidebar-aircraft-\(profile.id)")
                    }
                }
                Section {
                    entry("数据与素材来源", symbol: "doc.text.magnifyingglass", target: .sources, id: "entry-sources")
                }
            }
        }
        .modifier(DirectorySearch(query: $query, isPhone: isPhone))
        .scrollContentBackground(.hidden)
        .background(palette.page)
        .foregroundStyle(palette.ink)
    }

    private var aircraftShortcuts: [AircraftProfile] {
        let featured = ["a350-900", "a350-900ulr", "c919"].compactMap(library.aircraft)
        if case .aircraft(let id) = destination, let current = library.aircraft(id), !featured.contains(current) {
            return featured + [current]
        }
        return featured
    }

    @ViewBuilder
    private func detail(_ page: AtlasDestination) -> some View {
        switch page {
        case .favorites:
            FavoritesHome(
                airports: favorites.airportIDs.compactMap(library.airport).sorted { $0.displayCode < $1.displayCode },
                aircraft: library.aircraft.filter { favorites.aircraftIDs.contains($0.id) },
                openAirport: { navigate(.airport($0.id)) },
                openAircraft: { navigate(.aircraft($0.id)) },
                browseAirports: { navigate(.airports) },
                browseAircraft: { navigate(.fleet) }
            )
        case .globe:
            EmptyView()
        case .airports:
            AirportDirectory(library: library) { navigate(.airport($0.id)) }
        case .airport(let id):
            if let airport = library.airport(id) {
                AirportDetail(
                    airport: airport, library: library,
                    onAirport: { navigate(.airport($0.id)) }, onAircraft: { navigate(.aircraft($0.id)) },
                    setImmersive: setImmersive
                )
                .id(id)
                .toolbar {
                    if !isPhone {
                        ToolbarItem(placement: .topBarLeading) { globeButton }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        AtlasFavoriteButton(favorites: favorites, id: airport.id, kind: .airport)
                    }
                }
            } else {
                ContentUnavailableView("机场资料暂不可用", systemImage: "airplane.arrival")
            }
        case .explore, .simulator:
            FlightExploration(library: library, simulatesFlight: page == .simulator) { navigate(.airport($0.id)) }
        case .fleet:
            FleetDirectory(aircraft: library.aircraft) { navigate(.aircraft($0.id)) }
        case .aircraft(let id):
            if let profile = library.aircraft(id) {
                AircraftDetail(profile: profile, library: library, onAirport: { navigate(.airport($0.id)) }, setImmersive: setImmersive)
                    .id(id)
                    .toolbar {
                        if !isPhone {
                            ToolbarItem(placement: .topBarLeading) { globeButton }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            AtlasFavoriteButton(favorites: favorites, id: profile.id, kind: .aircraft)
                        }
                    }
            } else {
                ContentUnavailableView("客机资料暂不可用", systemImage: "airplane")
            }
        case .gestureGuide:
            AtlasTouchGuide()
        case .privacy:
            AtlasPrivacyPane(favorites: favorites)
        case .sources:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("数据与素材来源").font(AtlasTypography.font(.largeTitle).bold())
                    if let catalog = library.catalog {
                        Text("机场与航线资料整理于 \(catalog.updatedAt)。\(catalog.routeCoverage)")
                        Text(catalog.routeDistanceMethod)
                    }
                    SourceLinks(sources: library.catalog?.sources ?? [])
                    if let coverage = library.observedRouteCoverage {
                        Divider()
                        Text("客运航线实飞资料").font(AtlasTypography.font(.title2).bold())
                        Text(coverage)
                        SourceLinks(sources: library.observedRouteSources)
                    }
                    if DistributionPolicy.airportSiteModelsAvailable {
                        mapDataResources
                    }
                }
                .atlasReadingWidth()
            }
        }
    }

    @ViewBuilder
    private var mapDataResources: some View {
        let siteData = AirportSiteCatalog.resourceURL
        let runwayData = AirportSiteCatalog.runwaySupplementURL
        if siteData != nil || runwayData != nil {
            Divider()
            Text("机场场区地图数据").font(AtlasTypography.font(.title2).bold())
            SourceLinks(sources: [AirportSiteCatalog.source])
            if let siteData {
                ShareLink(item: siteData) {
                    Label("导出场区地图数据", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("export-site-data")
            }
            if let runwayData {
                ShareLink(item: runwayData) {
                    Label("导出补充跑道数据", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("export-airport-runway-data")
            }
        }
        if let buildings = AirportSiteCatalog.buildingResourceURL {
            Divider()
            Text("机场建筑轮廓").font(AtlasTypography.font(.title2).bold())
            SourceLinks(sources: AirportSiteCatalog.buildingDataSources)
            ShareLink(item: buildings) {
                Label("导出建筑轮廓数据", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("export-airport-buildings")
        }
        if !AirportSiteCatalog.terrainSources.isEmpty {
            Divider()
            Text("机场场址高程").font(AtlasTypography.font(.title2).bold())
            SourceLinks(sources: AirportSiteCatalog.terrainSources)
        }
    }

    private func title(for page: AtlasDestination) -> String {
        switch page {
        case .favorites: "收藏"
        case .globe: DistributionPolicy.mapsAvailable ? "地球" : "机场浏览"
        case .airports: "机场图鉴"
        case .airport(let id): library.airport(id)?.displayName ?? "机场"
        case .explore: "航线探索"
        case .simulator: "航线模拟"
        case .fleet: "客机图鉴"
        case .aircraft(let id): library.aircraft(id)?.displayName ?? "客机"
        case .gestureGuide: "触控教程"
        case .privacy: "隐私与数据"
        case .sources: "资料来源"
        }
    }

    private func phoneTitle(for page: AtlasDestination) -> String {
        switch page {
        case .airport(let id): library.airport(id)?.displayCode ?? title(for: page)
        case .aircraft(let id): library.aircraft(id)?.modelName ?? title(for: page)
        default: title(for: page)
        }
    }

    private func navigate(_ next: AtlasDestination) {
        if isPhone {
            if next == .globe {
                phonePath.removeAll()
            } else if showsPhoneDirectory {
                phonePath = [next]
            } else if next != phonePath.last {
                phonePath.append(next)
            }
            showsPhoneDirectory = false
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            tabletDestination = next
            if horizontal == .compact { compactColumn = .detail }
            switch next {
            case .globe, .airport, .aircraft: setImmersive(true)
            case .favorites, .airports, .fleet, .explore, .simulator, .gestureGuide, .privacy, .sources: setImmersive(false)
            }
        }
    }

    private func setImmersive(_ immersive: Bool) {
        guard !isPhone, horizontal != .compact else { return }
        visibility = immersive ? .detailOnly : .all
    }

    private var appearanceButton: some View {
        Button("外观", systemImage: appearance.symbol) { showsAppearance = true }
            .accessibilityIdentifier("atlas-appearance")
            .accessibilityLabel("外观，\(appearance.title)")
            .accessibilityValue(appearance.title)
            .listRowBackground(palette.surface)
    }

    private func appearanceSheet() -> some View {
        NavigationStack {
            List(AtlasAppearance.allCases) { option in
                Button {
                    appearance = option
                    showsAppearance = false
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: option.symbol)
                            .foregroundStyle(palette.accent)
                            .frame(width: 34)
                            .accessibilityHidden(true)
                        Text(option.title)
                            .foregroundStyle(palette.ink)
                            .font(AtlasTypography.font(.body, weight: .semibold))
                        Spacer(minLength: 4)
                        if appearance == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(palette.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowBackground(appearance == option ? palette.selection : palette.surface)
                .accessibilityIdentifier("atlas-appearance-\(option.rawValue)")
                .accessibilityAddTraits(appearance == option ? .isSelected : [])
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.page)
            .navigationTitle("外观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showsAppearance = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(appearance.colorScheme)
    }

    private var globeButton: some View {
        Button(DistributionPolicy.mapsAvailable ? "返回地球" : "返回机场浏览", systemImage: "globe.asia.australia") { navigate(.globe) }
            .accessibilityIdentifier("return-to-globe")
    }

    private var favoritesButton: some View {
        Button("收藏", systemImage: "star") { navigate(.favorites) }
            .accessibilityIdentifier("globe-favorites")
    }

    private var airportDirectoryButton: some View {
        Button("机场目录", systemImage: "magnifyingglass") { navigate(.airports) }
            .accessibilityIdentifier("globe-airports")
    }

    private var sidebarButton: some View {
        let closed = isPhone || horizontal == .compact || visibility == .detailOnly
        return Button(closed ? "显示目录" : "收起目录", systemImage: isPhone ? "list.bullet" : "sidebar.left") {
            if isPhone {
                showsPhoneDirectory = true
            } else if horizontal == .compact {
                compactColumn = .sidebar
            } else {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    visibility = closed ? .all : .detailOnly
                }
            }
        }
        .accessibilityIdentifier("atlas-sidebar-toggle")
    }

    private func entry(_ label: String, symbol: String, target: AtlasDestination, id: String) -> some View {
        Button {
            navigate(target)
        } label: {
            Label(label, systemImage: symbol)
                .foregroundStyle(isSelected(target) ? palette.selectionInk : palette.ink)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(isSelected(target) ? .isSelected : [])
        .listRowBackground(isSelected(target) ? palette.selection : palette.surface)
    }

    private func isSelected(_ target: AtlasDestination) -> Bool {
        switch (target, destination) {
        case (.airports, .airport), (.fleet, .aircraft): true
        default: target == destination
        }
    }
}

private struct DirectorySearch: ViewModifier {
    @Binding var query: String
    let isPhone: Bool

    func body(content: Content) -> some View {
        if isPhone {
            content
                .listStyle(.insetGrouped)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "机场名称或代码")
        } else {
            content
                .listStyle(.sidebar)
                .searchable(text: $query, placement: .sidebar, prompt: "机场名称或代码")
        }
    }
}

private struct FavoritesHome: View {
    let airports: [Airport]
    let aircraft: [AircraftProfile]
    let openAirport: (Airport) -> Void
    let openAircraft: (AircraftProfile) -> Void
    let browseAirports: () -> Void
    let browseAircraft: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        List {
            Section("收藏的机场") {
                if airports.isEmpty {
                    Button("浏览机场", systemImage: "airplane.arrival", action: browseAirports)
                        .accessibilityIdentifier("favorites-open-airports")
                        .listRowBackground(palette.surface)
                }
                ForEach(airports) { airport in
                    Button { openAirport(airport) } label: {
                        AirportRow(airport: airport)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(palette.surface)
                    .accessibilityIdentifier("favorites-airport-\(airport.id)")
                }
            }
            Section("收藏的客机") {
                if aircraft.isEmpty {
                    Button("浏览客机", systemImage: "airplane", action: browseAircraft)
                        .accessibilityIdentifier("favorites-open-aircraft")
                        .listRowBackground(palette.surface)
                }
                ForEach(aircraft) { profile in
                    Button { openAircraft(profile) } label: {
                        HStack(spacing: 15) {
                            Image(systemName: "airplane")
                                .font(AtlasTypography.font(.title3))
                                .foregroundStyle(palette.accent)
                                .frame(width: 61, alignment: .leading)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.displayName).font(AtlasTypography.font(.headline))
                                Text(profile.title).font(AtlasTypography.font(.subheadline)).foregroundStyle(palette.muted)
                            }
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.right")
                                .font(AtlasTypography.font(.caption).weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(palette.surface)
                    .accessibilityIdentifier("favorites-aircraft-\(profile.id)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.page)
        .foregroundStyle(palette.ink)
        .accessibilityIdentifier("favorites-home")
    }
}

private struct AirportDirectory: View {
    let library: AtlasLibrary
    let open: (Airport) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }
    @State private var search = ""
    @State private var scope: AirportScope = .all
    @State private var buildingsOnly = false
    @FocusState private var searchFocused: Bool

    private enum AirportScope: String, CaseIterable, Identifiable {
        case all = "全部"
        case domestic = "中国民用机场"
        case large = "全球大型机场"

        var id: Self { self }

        func includes(_ airport: Airport) -> Bool {
            switch self {
            case .all:
                true
            case .domestic:
                ["CN", "HK", "MO", "TW"].contains(airport.countryCode ?? "")
                    || airport.civilUse == "运输机场" || airport.civilUse == "通用机场"
            case .large:
                airport.type == "large_airport"
            }
        }
    }

    private var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isShowingFeatured: Bool { searchTerm.isEmpty && scope == .all && !buildingsOnly }

    private var results: [Airport] {
        if isShowingFeatured { return library.featured }
        let include: (Airport) -> Bool = { airport in
            scope.includes(airport) && (!buildingsOnly || airport.hasDetailedModel || airport.hasSiteModel)
        }
        return searchTerm.isEmpty ? library.airports.filter(include) : library.search(searchTerm, including: include)
    }

    private var resultsHeading: String {
        if isShowingFeatured { return "精选机场" }
        if scope != .all { return scope.rawValue }
        return searchTerm.isEmpty ? "有建筑模型的机场" : "搜索结果"
    }

    var body: some View {
        let entries = results
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("输入城市、机场或代码", text: $search)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .onSubmit { searchFocused = false }
                        .accessibilityIdentifier("search-field")
                }
                Picker("机场范围", selection: $scope) {
                    ForEach(AirportScope.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("airport-directory-scope")
                if DistributionPolicy.airportSiteModelsAvailable {
                    Toggle("有建筑模型", isOn: $buildingsOnly)
                        .accessibilityIdentifier("airport-building-filter")
                }
            }
            .listRowBackground(palette.surface)
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("机场索引收录 \(library.airports.count.formatted()) 座机场。支持 IATA、ICAO 代码和中英文关键词。")
                    if scope == .large { Text("大型机场沿用来源目录的规模分类。") }
                }
                .font(AtlasTypography.font(.footnote))
                .foregroundStyle(palette.muted)
            }
            .listRowBackground(palette.subtle)
            Section {
                if entries.isEmpty {
                    if searchTerm.isEmpty {
                        ContentUnavailableView("暂无符合条件的机场", systemImage: "airplane.arrival")
                    } else {
                        ContentUnavailableView.search(text: searchTerm)
                    }
                }
                ForEach(entries) { airport in
                    Button { open(airport) } label: { AirportRow(airport: airport) }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.surface)
                        .accessibilityIdentifier("airport-\(airport.id)")
                }
            } header: {
                Text("\(resultsHeading) · \(entries.count.formatted()) 座")
                    .accessibilityIdentifier("airport-directory-result-count")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.page)
        .foregroundStyle(palette.ink)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct AirportRow: View {
    let airport: Airport
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }
    @Environment(\.horizontalSizeClass) private var horizontal

    var body: some View {
        HStack(spacing: 15) {
            Text(airport.displayCode)
                .font(palette.readout(.title3))
                .foregroundStyle(palette.accent)
                .frame(width: 61, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(airport.displayName).font(AtlasTypography.font(.title3, weight: .semibold))
                Text(airport.displayCity).font(AtlasTypography.font(.subheadline)).foregroundStyle(palette.muted)
                if DistributionPolicy.airportSiteModelsAvailable && horizontal == .compact {
                    coverageBadge
                }
            }
            Spacer(minLength: 2)
            if DistributionPolicy.airportSiteModelsAvailable && horizontal != .compact {
                coverageBadge
            }
            Image(systemName: "chevron.right")
                .font(AtlasTypography.font(.caption).weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, palette.isDark ? 6 : 10)
        .frame(minHeight: 44)
        .foregroundStyle(palette.ink)
        .contentShape(.rect)
    }

    private var coverageBadge: some View {
        let coverage = airport.modelLabel
        return Text(coverage)
            .font(AtlasTypography.font(.caption))
            .foregroundStyle(palette.muted)
            .accessibilityLabel("模型覆盖 · \(coverage)")
    }
}

private struct FleetDirectory: View {
    private enum CabinFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case single = "单通道"
        case twin = "双通道"

        var id: Self { self }

        func matches(_ profile: AircraftProfile) -> Bool {
            self == .all || (self == .twin) == profile.isTwinAisle
        }
    }

    let aircraft: [AircraftProfile]
    let open: (AircraftProfile) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }
    @State private var query = ""
    @State private var filter = CabinFilter.all
    @FocusState private var searchFocused: Bool

    private var results: [AircraftProfile] {
        aircraft.filter { filter.matches($0) && $0.matchesSearch(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: palette.contentGap) {
                Text("按机型探索")
                    .font(AtlasTypography.font(.largeTitle, weight: .bold))
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.muted)
                    TextField("输入机型或制造商", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($searchFocused)
                        .accessibilityIdentifier("aircraft-search-field")
                }
                .padding(13)
                .atlasPanel(palette, radius: 13)
                Picker("筛选客机", selection: $filter) {
                    ForEach(CabinFilter.allCases) { choice in Text(choice.rawValue).tag(choice) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("aircraft-size-filter")
                .onChange(of: filter) { searchFocused = false }
                Text("\(results.count.formatted()) 款客机")
                    .font(AtlasTypography.font(.footnote))
                    .foregroundStyle(palette.muted)
                if results.isEmpty {
                    ContentUnavailableView("没有匹配的客机", systemImage: "airplane")
                }
                ForEach(results) { profile in
                    Button { open(profile) } label: {
                        HStack(spacing: 20) {
                            Image(systemName: "airplane")
                                .font(.system(size: 33, weight: .light))
                                .foregroundStyle(palette.accent)
                                .frame(width: 67)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.displayName).font(AtlasTypography.font(.title3).weight(.semibold)).foregroundStyle(palette.ink)
                                Text(profile.title)
                                    .font(AtlasTypography.font(.subheadline)).foregroundStyle(palette.muted)
                                Text(profile.series)
                                    .font(AtlasTypography.font(.subheadline)).foregroundStyle(palette.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(AtlasTypography.font(.footnote).weight(.semibold)).foregroundStyle(palette.muted)
                        }
                        .padding(palette.isDark ? 14 : 20)
                        .frame(maxWidth: .infinity)
                        .atlasPanel(palette)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aircraft-\(profile.id)")
                }
            }
            .atlasReadingWidth()
        }
        .background(palette.page)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct SourceLinks: View {
    let sources: [AtlasSource]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("参考资料").font(AtlasTypography.font(.headline))
                ForEach(sources) { source in
                    if let destination = URL(string: source.url) {
                        VStack(alignment: .leading, spacing: 4) {
                            Link(destination: destination) {
                                Label(source.title, systemImage: "arrow.up.right.square")
                            }
                            if let note = source.detail {
                                Text(note).font(AtlasTypography.font(.footnote)).foregroundStyle(palette.muted)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func atlasReadingWidth() -> some View {
        frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 25)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
