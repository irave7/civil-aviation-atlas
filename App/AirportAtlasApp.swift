import SwiftUI

@main
struct AirportAtlasApp: App {
    init() {
        AtlasTypography.prepare()
    }

    var body: some Scene {
        WindowGroup {
            AtlasHome(library: .shared)
                .font(AtlasTypography.font(.body))
                .tint(Color(red: 0.02, green: 0.44, blue: 0.46))
        }
    }
}

private enum AtlasDestination: Equatable {
    case favorites
    case globe
    case airports
    case airport(String)
    case fleet
    case aircraft(String)
    case sources
}

@MainActor
struct AtlasHome: View {
    let library: AtlasLibrary
    @State private var favorites = AtlasFavorites()
    @State private var destination: AtlasDestination = .globe
    @State private var query = ""
    @State private var visibility: NavigationSplitViewVisibility = .detailOnly
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            sidebar
                .navigationTitle("民航图鉴")
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
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .navigationTitle(detailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { sidebarButton }
                ToolbarItem(placement: .principal) {
                    Text(detailTitle)
                        .font(AtlasTypography.font(.headline))
                        .foregroundStyle(destination == .globe ? Color.white : Color.primary)
                        .accessibilityAddTraits(.isHeader)
                }
                if destination == .globe {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("机场目录", systemImage: "magnifyingglass") { navigate(.airports) }
                            .accessibilityIdentifier("globe-airports")
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task(priority: .utility) { await library.prepareObservedRoutes() }
        .task(priority: .utility) {
            guard let sample = library.airport("FOC") else { return }
            await Task.detached(priority: .utility) { AirportSiteCatalog.preload(for: sample) }.value
        }
    }

    private var sidebar: some View {
        List {
            Section {
                entry("收藏", symbol: "star", target: .favorites, id: "entry-favorites")
                entry("地球", symbol: "globe.asia.australia.fill", target: .globe, id: "entry-globe")
                entry("机场图鉴", symbol: "airplane.arrival", target: .airports, id: "entry-airports")
                entry("客机图鉴", symbol: "airplane", target: .fleet, id: "entry-aircraft")
            } header: {
                Text("浏览")
            }
            Section(query.isEmpty ? "精选机场" : "机场搜索") {
                ForEach(library.search(query).prefix(query.isEmpty ? 3 : 40)) { airport in
                    Button { navigate(.airport(airport.id)) } label: {
                        HStack(spacing: 8) {
                            Text(airport.displayCode)
                                .font(AtlasTypography.font(.subheadline).monospaced().weight(.semibold))
                                .foregroundStyle(.teal)
                                .frame(width: 49, alignment: .leading)
                            Text(airport.displayName)
                                .font(AtlasTypography.font(.subheadline))
                                .foregroundStyle(.primary)
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
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .sidebar, prompt: "机场名称或代码")
    }

    private var aircraftShortcuts: [AircraftProfile] {
        let featured = ["a350-900", "a350-900ulr", "c919"].compactMap(library.aircraft)
        if case .aircraft(let id) = destination, let current = library.aircraft(id), !featured.contains(current) {
            return featured + [current]
        }
        return featured
    }

    @ViewBuilder
    private var detail: some View {
        switch destination {
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
                    ToolbarItem(placement: .topBarLeading) {
                        globeButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        AtlasFavoriteButton(favorites: favorites, id: airport.id, kind: .airport)
                    }
                }
            } else {
                ContentUnavailableView("机场资料暂不可用", systemImage: "airplane.arrival")
            }
        case .fleet:
            FleetDirectory(aircraft: library.aircraft) { navigate(.aircraft($0.id)) }
        case .aircraft(let id):
            if let profile = library.aircraft(id) {
                AircraftDetail(profile: profile, library: library, onAirport: { navigate(.airport($0.id)) }, setImmersive: setImmersive)
                    .id(id)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            globeButton
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            AtlasFavoriteButton(favorites: favorites, id: profile.id, kind: .aircraft)
                        }
                    }
            } else {
                ContentUnavailableView("客机资料暂不可用", systemImage: "airplane")
            }
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
                .atlasReadingWidth()
            }
        }
    }

    private var detailTitle: String {
        switch destination {
        case .favorites: "收藏"
        case .globe: "地球"
        case .airports: "机场图鉴"
        case .airport(let id): library.airport(id)?.displayName ?? "机场"
        case .fleet: "客机图鉴"
        case .aircraft(let id): library.aircraft(id)?.displayName ?? "客机"
        case .sources: "资料来源"
        }
    }

    private func navigate(_ next: AtlasDestination) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            destination = next
            if horizontal == .compact { compactColumn = .detail }
            switch next {
            case .globe, .airport, .aircraft: setImmersive(true)
            case .favorites, .airports, .fleet, .sources: setImmersive(false)
            }
        }
    }

    private func setImmersive(_ immersive: Bool) {
        guard horizontal != .compact else { return }
        visibility = immersive ? .detailOnly : .all
    }

    private var globeButton: some View {
        Button("返回地球", systemImage: "globe.asia.australia") { navigate(.globe) }
            .accessibilityIdentifier("return-to-globe")
    }

    private var sidebarButton: some View {
        let closed = horizontal == .compact || visibility == .detailOnly
        return Button(closed ? "显示目录" : "收起目录", systemImage: "sidebar.left") {
            if horizontal == .compact {
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
                .foregroundStyle(isSelected(target) ? Color.teal : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(isSelected(target) ? .isSelected : [])
    }

    private func isSelected(_ target: AtlasDestination) -> Bool {
        switch (target, destination) {
        case (.airports, .airport), (.fleet, .aircraft): true
        default: target == destination
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

    var body: some View {
        List {
            Section("收藏的机场") {
                if airports.isEmpty {
                    Button("浏览机场", systemImage: "airplane.arrival", action: browseAirports)
                        .accessibilityIdentifier("favorites-open-airports")
                }
                ForEach(airports) { airport in
                    Button { openAirport(airport) } label: {
                        AirportRow(airport: airport)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("favorites-airport-\(airport.id)")
                }
            }
            Section("收藏的客机") {
                if aircraft.isEmpty {
                    Button("浏览客机", systemImage: "airplane", action: browseAircraft)
                        .accessibilityIdentifier("favorites-open-aircraft")
                }
                ForEach(aircraft) { profile in
                    Button { openAircraft(profile) } label: {
                        HStack(spacing: 15) {
                            Image(systemName: "airplane")
                                .font(AtlasTypography.font(.title3))
                                .foregroundStyle(.teal)
                                .frame(width: 61, alignment: .leading)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.displayName).font(AtlasTypography.font(.headline))
                                Text(profile.title).font(AtlasTypography.font(.subheadline)).foregroundStyle(.secondary)
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
                    .accessibilityIdentifier("favorites-aircraft-\(profile.id)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("favorites-home")
    }
}

private struct AirportDirectory: View {
    let library: AtlasLibrary
    let open: (Airport) -> Void
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
                Toggle("有建筑模型", isOn: $buildingsOnly)
                    .accessibilityIdentifier("airport-building-filter")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("机场索引收录 \(library.airports.count.formatted()) 座机场。支持 IATA、ICAO 代码和中英文关键词。")
                    if scope == .large { Text("大型机场沿用来源目录的规模分类。") }
                }
            }
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
                        .accessibilityIdentifier("airport-\(airport.id)")
                }
            } header: {
                Text("\(resultsHeading) · \(entries.count.formatted()) 座")
                    .accessibilityIdentifier("airport-directory-result-count")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct AirportRow: View {
    let airport: Airport

    var body: some View {
        let coverage = airport.modelLabel
        HStack(spacing: 15) {
            Text(airport.displayCode)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .foregroundStyle(.teal)
                .frame(width: 61, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(airport.displayName).font(AtlasTypography.font(.title3, weight: .semibold))
                Text(airport.displayCity).font(AtlasTypography.font(.subheadline)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text(coverage)
                .font(AtlasTypography.font(.caption))
                .foregroundStyle(.secondary)
                .accessibilityLabel("模型覆盖 · \(coverage)")
            Image(systemName: "chevron.right")
                .font(AtlasTypography.font(.caption).weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
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
    @State private var query = ""
    @State private var filter = CabinFilter.all
    @FocusState private var searchFocused: Bool

    private var results: [AircraftProfile] {
        aircraft.filter { filter.matches($0) && $0.matchesSearch(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("按机型探索").font(AtlasTypography.font(.largeTitle).bold())
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("输入机型或制造商", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($searchFocused)
                        .accessibilityIdentifier("aircraft-search-field")
                }
                .padding(13)
                .background(.quaternary, in: .rect(cornerRadius: 13))
                Picker("筛选客机", selection: $filter) {
                    ForEach(CabinFilter.allCases) { choice in Text(choice.rawValue).tag(choice) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("aircraft-size-filter")
                .onChange(of: filter) { searchFocused = false }
                Text("\(results.count.formatted()) 款客机")
                    .font(AtlasTypography.font(.footnote))
                    .foregroundStyle(.secondary)
                if results.isEmpty {
                    ContentUnavailableView("没有匹配的客机", systemImage: "airplane")
                }
                ForEach(results) { profile in
                    Button { open(profile) } label: {
                        HStack(spacing: 20) {
                            Image(systemName: "airplane")
                                .font(.system(size: 33, weight: .light))
                                .foregroundStyle(.teal)
                                .frame(width: 67)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.displayName).font(AtlasTypography.font(.title3).weight(.semibold)).foregroundStyle(.primary)
                                Text(profile.title)
                                    .font(AtlasTypography.font(.subheadline)).foregroundStyle(.secondary)
                                Text(profile.series)
                                    .font(AtlasTypography.font(.subheadline)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(AtlasTypography.font(.footnote).weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(.quaternary, in: .rect(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aircraft-\(profile.id)")
                }
            }
            .atlasReadingWidth()
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct SourceLinks: View {
    let sources: [AtlasSource]

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
                                Text(note).font(AtlasTypography.font(.footnote)).foregroundStyle(.secondary)
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
