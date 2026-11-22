import MapKit
import SwiftUI
import UIKit

private enum AirportPanel: String, CaseIterable, Identifiable {
    case model = "三维模型"
    case plan = "平面图"
    case imagery = "实景"
    case routes = "航线"
    case overview = "机场资料"
    var id: Self { self }
    var usesImmersiveLayout: Bool {
        switch self {
        case .model, .imagery, .plan: true
        case .routes, .overview: false
        }
    }
    var controlID: String {
        switch self {
        case .model: "airport-mode-model"
        case .plan: "airport-mode-plan"
        case .imagery: "airport-mode-imagery"
        case .routes: "airport-mode-routes"
        case .overview: "airport-mode-overview"
        }
    }
    var symbol: String {
        switch self {
        case .model: "cube"
        case .plan: "map"
        case .imagery: "globe.asia.australia"
        case .routes: "point.topleft.down.to.point.bottomright.curvepath"
        case .overview: "info.circle"
        }
    }
}

@MainActor
struct AirportDetail: View {
    let airport: Airport
    let library: AtlasLibrary
    let onAirport: (Airport) -> Void
    let onAircraft: (AircraftProfile) -> Void
    let setImmersive: (Bool) -> Void
    @State private var selected: AirportPanel = DistributionPolicy.airportSiteModelsAvailable ? .model : .overview
    #if !MAINLAND_DISTRIBUTION
    @State private var model: AtlasModel?
    #endif
    @State private var highlightedRoute: FlightRoute?

    private var availablePanels: [AirportPanel] {
        AirportPanel.allCases.filter { panel in
            switch panel {
            case .model: DistributionPolicy.airportSiteModelsAvailable
            case .plan: DistributionPolicy.airportSiteModelsAvailable && DistributionPolicy.mapsAvailable
                && (airport.hasBasicModel || airport.hasSiteModel)
            case .imagery: DistributionPolicy.airportSiteModelsAvailable && DistributionPolicy.mapsAvailable
            case .routes, .overview: true
            }
        }
    }

    var body: some View {
        let header = airportHeader
        let content = airportContent.frame(maxWidth: .infinity, maxHeight: .infinity)
        let stack = VStack(spacing: 0) {
            header
            content
        }
        return stack.sheet(item: $highlightedRoute, content: routeSheet)
    }

    @ViewBuilder
    private var airportContent: some View {
        Group {
            switch selected {
            case .model:
                #if MAINLAND_DISTRIBUTION
                AirportOverview(airport: airport)
                #else
                if let model {
                    ModelWorkspace(
                        model: model, title: airport.displayName, subtitle: "\(airport.displayCode)  /  \(airport.icao)",
                        startsWithPartsVisible: false
                    )
                } else {
                    ProgressView("载入机场模型")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task { model = AirportModels.make(for: airport) }
                }
                #endif
            case .imagery:
                AirportImagery(airport: airport)
            case .plan:
                #if MAINLAND_DISTRIBUTION
                AirportOverview(airport: airport)
                #else
                AirportPlanView(airport: airport)
                #endif
            case .routes:
                AirportRoutePanel(airport: airport, library: library, onAirport: onAirport, onAircraft: onAircraft)
            case .overview:
                AirportOverview(airport: airport)
            }
        }
    }

    private var airportHeader: some View {
        VStack(spacing: 0) {
            AtlasPanelBar { compact in
                ForEach(availablePanels) { panel in
                    PanelButton(title: panel.rawValue, symbol: panel.symbol, selected: selected == panel, id: panel.controlID, compact: compact) {
                        selectPanel(panel)
                    }
                }
            }
            AirportLongestRouteBanner(airport: airport, library: library) { highlightedRoute = $0 }
        }
    }

    private func routeSheet(_ route: FlightRoute) -> some View {
        let detail = RouteDetail(route: route, library: library, day: FlightCalendar.isoDate(Date()),
                                 openAirport: openAirportFromRoute, openAircraft: openAircraftFromRoute)
        return NavigationStack { detail }.presentationSizing(.page)
    }

    private func openAirportFromRoute(_ next: Airport) {
        highlightedRoute = nil
        if next.id == airport.id {
            selectPanel(DistributionPolicy.airportSiteModelsAvailable ? .model : .overview)
        } else {
            onAirport(next)
        }
    }

    private func openAircraftFromRoute(_ next: AircraftProfile) {
        highlightedRoute = nil
        onAircraft(next)
    }

    private func selectPanel(_ panel: AirportPanel) {
        guard panel != selected else { return }
        selected = panel
        setImmersive(panel.usesImmersiveLayout)
    }
}

@MainActor
struct AircraftDetail: View {
    private enum Page { case model, routes, data }
    let profile: AircraftProfile
    let library: AtlasLibrary
    let onAirport: (Airport) -> Void
    let setImmersive: (Bool) -> Void
    @State private var page = Page.model
    @State private var configuration: AircraftConfiguration?
    @State private var model: AtlasModel?
    @State private var choosingConfiguration = false
    @State private var livery = AircraftLiveries.reference
    @State private var choosingLivery = false
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        Group {
            switch page {
            case .model:
                if let model, let configuration {
                    ModelWorkspace(
                        model: model, title: profile.displayName,
                        subtitle: "涂装 \(livery.name) · 客舱 \(configuration.airline) / \(configuration.name)",
                        expandsSplitZoom: true, startsWithPartsVisible: false,
                        liveryName: livery.name, chooseLivery: { choosingLivery = true }
                    )
                    .id("\(configuration.id)/\(livery.id)")
                } else {
                    ProgressView("载入客机模型")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task {
                            if let configuration = profile.configurations.first { set(configuration) }
                        }
                }
            case .routes:
                FlightRouteList(
                    title: "\(profile.displayName) 执飞航线", subtitle: "按机场间大圆距离排序。执飞示例和有有效期的计划班表分别标注。", routes: library.routes(for: profile), library: library, distanceOrder: true,
                    onAirport: onAirport, onAircraft: nil
                )
            case .data:
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(profile.displayName).font(AtlasTypography.font(.largeTitle).bold())
                            Text(profile.title).font(AtlasTypography.font(.subheadline)).foregroundStyle(.secondary)
                        }
                        Text(profile.description).font(AtlasTypography.font(.body))
                        adaptiveFacts {
                            AtlasFact(label: "机身长", value: "\(profile.lengthM.formatted()) m", symbol: "arrow.left.and.right")
                            AtlasFact(label: "翼展", value: "\(profile.wingspanM.formatted()) m", symbol: "arrow.up.and.down")
                        }
                        Text(profile.rangeDescription).foregroundStyle(.secondary)
                        ForEach(profile.configurations) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(item.airline) · \(item.name)").font(AtlasTypography.font(.headline))
                                Text(item.seats.map { "\($0.label) \($0.seatCount) 座" }.joined(separator: " · "))
                                    .font(AtlasTypography.font(.subheadline).monospacedDigit())
                                Text(item.cabinDescription).foregroundStyle(.secondary)
                            }
                        }
                        SourceLinks(sources: profile.sources)
                    }
                    .atlasReadingWidth()
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AtlasPanelBar { compact in
                PanelButton(title: "三维模型", symbol: "cube", selected: page == .model, id: "aircraft-mode-model", compact: compact) { page = .model }
                PanelButton(title: "执飞航线", symbol: "point.topleft.down.to.point.bottomright.curvepath", selected: page == .routes, id: "aircraft-mode-routes", compact: compact) { page = .routes }
                PanelButton(title: "机型资料", symbol: "info.circle", selected: page == .data, id: "aircraft-mode-data", compact: compact) { page = .data }
            }
        }
        .toolbar {
            if page == .model && !profile.configurations.isEmpty && isPhone {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("外观与客舱", systemImage: "slider.horizontal.3") {
                        liveryButton
                        Button("客舱布局", systemImage: "chair.lounge") { choosingConfiguration = true }
                            .accessibilityIdentifier("aircraft-configuration")
                    }
                    .accessibilityIdentifier("aircraft-model-options")
                    .sheet(isPresented: $choosingConfiguration) {
                        NavigationStack {
                            List { configurationOptions }
                                .navigationTitle("客舱布局")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("完成") { choosingConfiguration = false }
                                    }
                                }
                        }
                    }
                }
            } else if page == .model && !profile.configurations.isEmpty {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    liveryButton
                    Button {
                        choosingConfiguration.toggle()
                    } label: {
                        Label("客舱布局", systemImage: "chair.lounge")
                    }
                    .accessibilityIdentifier("aircraft-configuration")
                    .popover(isPresented: $choosingConfiguration, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("客舱布局").font(AtlasTypography.font(.headline))
                            configurationOptions
                        }
                        .padding(20)
                        .frame(minWidth: 240, idealWidth: 260)
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
        .sheet(isPresented: $choosingLivery) {
            AircraftLiveryPicker(options: AircraftLiveries.options(for: profile), selected: livery) { option in
                guard livery.id != option.id else { return }
                livery = option
                if let configuration {
                    model = AircraftModels.make(aircraft: profile, configuration: configuration, livery: option)
                }
            }
            .presentationSizing(.page)
        }
        .onChange(of: page) { _, current in
            setImmersive(current == .model)
        }
    }

    private var liveryButton: some View {
        Button("涂装", systemImage: "paintpalette") { choosingLivery = true }
            .accessibilityValue(livery.name)
            .accessibilityIdentifier("aircraft-livery")
    }

    private var configurationOptions: some View {
        ForEach(profile.configurations) { item in
            Button {
                choosingConfiguration = false
                set(item)
            } label: {
                Label("\(item.airline) · \(item.name)", systemImage: item.id == configuration?.id ? "checkmark" : "airplane")
                    .font(AtlasTypography.font(.body))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(item.id == configuration?.id ? .isSelected : [])
            .accessibilityIdentifier("configuration-\(item.id)")
        }
    }

    private func set(_ configuration: AircraftConfiguration) {
        guard self.configuration?.id != configuration.id || model == nil else { return }
        self.configuration = configuration
        model = AircraftModels.make(aircraft: profile, configuration: configuration, livery: livery)
    }
}

private struct AircraftLiveryPicker: View {
    let options: [AircraftLivery]
    let selected: AircraftLivery
    let choose: (AircraftLivery) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var results: [AircraftLivery] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { item in
            [item.name, item.operatorName, item.registration, item.period, item.category.rawValue]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let displayed = results
                if displayed.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(AircraftLivery.Category.allCases) { category in
                    let entries = displayed.filter { $0.category == category }
                    if !entries.isEmpty {
                        Section(category.rawValue) {
                            ForEach(entries) { option in
                                Button {
                                    choose(option)
                                    dismiss()
                                } label: {
                                    row(option)
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(option.id == selected.id ? .isSelected : [])
                                .accessibilityIdentifier("livery-\(option.id)")
                            }
                        }
                    }
                }
                if let source = selected.source, let url = URL(string: source.url) {
                    Section {
                        if let detail = source.detail {
                            Text(detail).font(AtlasTypography.font(.subheadline)).foregroundStyle(.secondary)
                        }
                        Link(destination: url) {
                            Label(source.title, systemImage: "arrow.up.right.square")
                        }
                    } header: {
                        Text("当前涂装资料")
                    } footer: {
                        Text("涂装按公开实机资料参考重绘。")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("livery-results")
            .searchable(text: $search, prompt: "搜索涂装、航司或注册号")
            .navigationTitle("选择涂装")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("aircraft-livery-picker")
    }

    private func row(_ option: AircraftLivery) -> some View {
        HStack(spacing: 13) {
            HStack(spacing: 1) {
                Rectangle().fill(option.palette.bodyColor)
                Rectangle().fill(option.palette.primaryColor)
                Rectangle().fill(option.palette.accentColor)
            }
            .frame(width: 45, height: 28)
            .clipShape(.rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(option.name).font(AtlasTypography.font(.headline))
                let detail = [option.operatorName, option.registration, option.period].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail).font(AtlasTypography.font(.caption)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if option.id == selected.id {
                Image(systemName: "checkmark").foregroundStyle(.teal).accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

private struct AirportOverview: View {
    let airport: Airport
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    private var runways: [Runway] {
        AirportSiteCatalog.runwayRecords(for: airport)
    }

    private var sources: [AtlasSource] {
        var entries = airport.sources ?? [AtlasSource(title: "OurAirports · 开放机场数据", url: "https://ourairports.com/data/")]
        if DistributionPolicy.airportSiteModelsAvailable {
            entries.append(contentsOf: AirportSiteCatalog.modelDataSources(for: airport))
            if AirportSiteCatalog.hasTerrain(for: airport), let source = AirportSiteCatalog.terrainSource {
                entries.append(source)
            }
        }
        return entries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(airport.displayCode)  /  \(airport.icao)")
                        .font(palette.readout(.headline)).foregroundStyle(palette.accent)
                    Text(airport.displayName)
                        .font(AtlasTypography.font(.largeTitle).bold())
                        .accessibilityIdentifier("airport-localized-title")
                    Text(airport.name == airport.displayName ? airport.displayCity : airport.name)
                        .font(AtlasTypography.font(.subheadline)).foregroundStyle(palette.muted)
                        .accessibilityIdentifier("airport-original-title")
                    if airport.localizedNameSource == "参考译名" {
                        Text("参考译名")
                            .font(AtlasTypography.font(.caption))
                            .foregroundStyle(palette.muted)
                    }
                    if let civilUse = airport.civilUse {
                        let classification = [civilUse, airport.publicAccess].compactMap { $0 }.joined(separator: " · ")
                        Label(classification, systemImage: "airplane")
                            .font(AtlasTypography.font(.subheadline, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .accessibilityIdentifier("airport-civil-use")
                    }
                    if let operatingStatus = airport.operatingStatus {
                        Text(operatingStatus).font(AtlasTypography.font(.subheadline)).foregroundStyle(palette.muted)
                    }
                }
                if let description = airport.description { Text(description).lineSpacing(4) }
                adaptiveFacts {
                    AtlasFact(label: "跑道记录", value: runways.count.formatted(), symbol: "equal")
                    if let elevation = airport.elevationFt {
                        AtlasFact(label: "机场海拔", value: "\(Int((Double(elevation) * 0.3048).rounded()).formatted()) m", symbol: "mountain.2")
                    }
                    if let opened = airport.opened {
                        AtlasFact(label: "启用", value: String(opened.prefix(4)), symbol: "calendar")
                    }
                }
                if !runways.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("跑道").font(AtlasTypography.font(.title2).bold())
                        ForEach(runways) { runway in
                            HStack(alignment: .firstTextBaseline) {
                                Text(runway.id).font(.system(.body, design: .monospaced, weight: .semibold))
                                Spacer()
                                if let surface = runway.surface {
                                    Text(surface).font(AtlasTypography.font(.footnote)).foregroundStyle(palette.muted)
                                }
                                Text("\(runway.lengthM.formatted(.number.precision(.fractionLength(0)))) m")
                                    .monospacedDigit()
                            }
                            Divider()
                        }
                    }
                } else {
                    Text(DistributionPolicy.mapsAvailable && DistributionPolicy.airportSiteModelsAvailable
                         ? "公开目录尚未收录此机场的跑道尺寸。可在实景页查看卫星影像。"
                         : "公开目录尚未收录此机场的跑道尺寸。")
                        .foregroundStyle(palette.muted)
                }
                if let terminals = airport.terminals, !terminals.isEmpty {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("航站楼与设施").font(AtlasTypography.font(.title2).bold())
                        ForEach(terminals) { terminal in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(terminal.name).font(AtlasTypography.font(.headline))
                                Text(terminal.description).foregroundStyle(palette.muted)
                            }
                        }
                    }
                }
                SourceLinks(sources: sources)
            }
            .foregroundStyle(palette.ink)
            .atlasReadingWidth()
        }
        .background(palette.page)
    }
}

private struct AtlasPanelBar<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                ViewThatFits(in: .horizontal) {
                    compactPanels
                    ScrollView(.horizontal) { compactPanels }.scrollIndicators(.hidden)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 9) { content(false) }
                        .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.line).frame(height: 1).allowsHitTesting(false)
        }
    }

    private var compactPanels: some View {
        HStack(spacing: 4) { content(true) }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

private struct PanelButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let id: String
    let compact: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = AtlasPalette(scheme, contrast: contrast)
        Button(action: action) {
            Group {
                if compact {
                    VStack(spacing: 3) {
                        Image(systemName: symbol).font(AtlasTypography.font(.body, weight: .semibold))
                        Text(title).font(AtlasTypography.font(.caption, weight: .semibold))
                    }
                } else {
                    Label(title, systemImage: symbol)
                        .font(AtlasTypography.font(.subheadline, weight: .semibold))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(selected ? palette.selectionInk : palette.muted)
            .padding(.horizontal, compact ? 8 : 15)
            .frame(minWidth: 44, minHeight: compact ? 48 : 44)
            .background(selected ? palette.selection : .clear,
                        in: .rect(cornerRadius: palette.isDark ? 9 : 17))
            .overlay(alignment: .bottom) {
                if selected && palette.isDark {
                    Capsule().fill(palette.accent).frame(height: 2).padding(.horizontal, 8)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

private func adaptiveFacts<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 12) { content() }
        VStack(alignment: .leading, spacing: 8) { content() }
    }
}

struct AtlasFact: View {
    let label: String
    let value: String
    let symbol: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: symbol)
                .font(AtlasTypography.font(.footnote)).foregroundStyle(palette.muted)
            Text(value).font(palette.readout(.title3)).monospacedDigit().foregroundStyle(palette.ink)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .atlasPanel(palette)
    }
}
