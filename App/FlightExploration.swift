import SwiftUI

private enum ExplorationScope: String, CaseIterable, Identifiable {
    case mainland = "中国大陆"
    case worldwide = "全球"

    var id: Self { self }
    var preferredOrigins: [String] {
        switch self {
        case .mainland: ["SHA", "FOC", "PEK", "TFU", "CAN", "SZX"]
        case .worldwide: ["PVG", "PEK", "CAN", "HKG", "SIN", "SFO", "JFK"]
        }
    }
}

private enum ExplorationRouteMode: String, CaseIterable, Identifiable {
    case custom = "自由航线"
    case challenge = "航线关卡"

    var id: Self { self }
}

struct ExplorationLeg: Identifiable {
    let start: Airport
    let end: Airport
    let evidence: FlightRoute
    let distance: Double

    var id: String { "\(start.id)-\(end.id)" }

    var aircraftProfile: AircraftProfile? {
        guard evidence.origin == start.id, let aircraftID = evidence.aircraftID else { return nil }
        return AircraftProfile.byID[aircraftID]
    }

    var aircraftLivery: AircraftLivery? {
        guard let aircraftProfile else { return nil }
        return AircraftLiveries.options(for: aircraftProfile).first {
            $0.operatorName == evidence.airline && ($0.category == .domestic || $0.category == .international)
        }
    }
}

@MainActor
struct FlightExploration: View {
    private struct Selection: Identifiable {
        let leg: ExplorationLeg
        let challenge: FlightChallenge?

        var id: String { leg.id }
    }

    let library: AtlasLibrary
    let favorites: AtlasFavorites
    let openAirport: (Airport) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var routeMode = ExplorationRouteMode.custom
    @State private var scope = ExplorationScope.mainland
    @State private var originID = "SHA"
    @State private var picksOrigin = false
    @State private var availableOrigins: (scope: ExplorationScope, airports: [Airport])?
    @State private var destinationFilter = ""
    @State private var selection: Selection?

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        let origins = availableOrigins.flatMap { $0.scope == scope ? $0.airports : nil }
        ScrollView {
            VStack(alignment: .leading, spacing: palette.contentGap + 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("航线探索")
                        .font(AtlasTypography.font(.largeTitle, weight: palette.isDark ? .semibold : .bold))
                        .foregroundStyle(palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("选择航程，在同一套驾驶舱中导览或手动飞行。")
                        .font(AtlasTypography.font(.subheadline))
                        .foregroundStyle(palette.muted)
                }
                Picker("航线模式", selection: $routeMode) {
                    ForEach(ExplorationRouteMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("exploration-route-mode")

                if routeMode == .challenge {
                    FlightChallengeBrowser(library: library) { challenge, leg in
                        selection = Selection(leg: leg, challenge: challenge)
                    }
                } else {
                    Picker("探索范围", selection: $scope) {
                        ForEach(ExplorationScope.allCases) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("exploration-scope")

                    let origin = library.airport(originID)
                    departureButton(for: origin)
                    if let origin { legsSection(for: origin) }
                }
            }
            .atlasReadingWidth()
        }
        .background(palette.page)
        .tint(palette.accent)
        .accessibilityIdentifier("flight-exploration")
        .task(id: scope) {
            let currentScope = scope
            await library.prepareObservedRoutes()
            guard !Task.isCancelled, currentScope == scope else { return }
            let origins = library.airports.filter { hasLegs(from: $0, scope: currentScope) }
                .sorted { $0.displayCode < $1.displayCode }
            if !origins.contains(where: { $0.id == originID }) {
                originID = currentScope.preferredOrigins.first { id in origins.contains { $0.id == id } }
                    ?? origins.first?.id ?? ""
            }
            availableOrigins = (currentScope, origins)
        }
        .onChange(of: scope) { _, next in
            destinationFilter = ""
            if let preferred = next.preferredOrigins.first { originID = preferred }
        }
        .sheet(isPresented: $picksOrigin) {
            ExplorationOriginPicker(
                airports: origins ?? [],
                preferred: scope.preferredOrigins, favoriteIDs: favorites.airportIDs,
                selectedID: originID, loading: origins == nil
            ) { airport in
                originID = airport.id
                destinationFilter = ""
                picksOrigin = false
            }
        }
        .fullScreenCover(item: $selection) { active in
            let showAirport: (Airport) -> Void = { airport in
                selection = nil
                openAirport(airport)
            }
            FlightSimulatorSession(leg: active.leg, favorites: favorites, challenge: active.challenge, openAirport: showAirport)
        }
    }

    private func departureButton(for origin: Airport?) -> some View {
        Button {
            picksOrigin = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "airplane.departure")
                    .foregroundStyle(palette.selectionInk)
                    .font(.title3)
                    .padding(12)
                    .background(palette.selection, in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("出发机场")
                        .font(AtlasTypography.font(.caption))
                        .foregroundStyle(palette.muted)
                    Text(origin.map { "\($0.displayCode) · \($0.displayName)" } ?? "选择机场")
                        .font(AtlasTypography.font(.headline))
                        .foregroundStyle(palette.ink)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(palette.isDark ? 13 : 16)
            .atlasPanel(palette)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exploration-origin")
    }

    @ViewBuilder
    private func legsSection(for origin: Airport) -> some View {
        let available = legs(from: origin, scope: scope)
        let search = destinationFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = search.isEmpty ? available : available.filter { leg in
            leg.end.nameSearchTerms.contains { $0.localizedStandardContains(search) }
        }
        VStack(alignment: .leading, spacing: 12) {
            Text("目的地")
                .font(AtlasTypography.font(.title2, weight: .bold))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            if available.count > 7 {
                TextField("搜索目的地或机场代码", text: $destinationFilter)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            if matches.isEmpty {
                ContentUnavailableView(
                    library.isPreparingObservedRoutes ? "正在载入航线" : "当前没有对应航线",
                    systemImage: "airplane.arrival"
                )
            }
            LazyVStack(spacing: palette.isDark ? 6 : 9) {
                ForEach(matches) { leg in
                    Button {
                        selection = Selection(leg: leg, challenge: nil)
                    } label: {
                        HStack(spacing: 12) {
                            Text(leg.end.displayCode)
                                .font(.system(.headline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(palette.accent)
                                .frame(minWidth: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(leg.end.displayName)
                                    .font(AtlasTypography.font(.subheadline, weight: .semibold))
                                    .foregroundStyle(palette.ink)
                                if let model = leg.aircraftProfile, let livery = leg.aircraftLivery, let airline = livery.operatorName {
                                    Text("\(airline) · \(model.displayName)")
                                        .font(AtlasTypography.font(.caption))
                                        .foregroundStyle(palette.muted)
                                }
                            }
                            Spacer()
                            Text("\(Int(leg.distance.rounded()).formatted()) km")
                                .font(palette.readout(.caption, weight: .medium).monospacedDigit())
                                .foregroundStyle(palette.isDark ? palette.accent : palette.muted)
                                .accessibilityLabel("\(Int(leg.distance.rounded()).formatted()) 公里")
                            Image(systemName: "play.circle")
                                .foregroundStyle(palette.accent)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .frame(minHeight: 48)
                        .atlasPanel(palette)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exploration-route-\(leg.end.id)")
                }
            }
        }
    }

    private func hasLegs(from origin: Airport, scope: ExplorationScope) -> Bool {
        if scope == .mainland && origin.countryCode != "CN" { return false }
        return library.routes(at: origin).contains { destination(of: $0, from: origin, scope: scope) != nil }
            || library.observedRoutes(at: origin).contains { destination(of: $0, from: origin, scope: scope) != nil }
    }

    private func destination(of route: FlightRoute, from origin: Airport, scope: ExplorationScope) -> Airport? {
        let otherID = route.origin == origin.id ? route.destination : route.origin
        guard route.hasVerifiedNonstop, (route.distanceKm ?? 0) > 0,
              let end = library.airport(otherID), end.id != origin.id else { return nil }
        guard !DistributionPolicy.mapsAvailable || (origin.hasCoordinates && end.hasCoordinates) else { return nil }
        let domestic = origin.countryCode == "CN" && end.countryCode == "CN"
        return (scope == .mainland ? domestic : !domestic) ? end : nil
    }

    private func legs(from origin: Airport, scope: ExplorationScope) -> [ExplorationLeg] {
        if scope == .mainland && origin.countryCode != "CN" { return [] }
        let localRoutes = library.routes(at: origin)
        let aircraftEvidence = localRoutes.filter { $0.origin == origin.id && $0.aircraftID != nil }
        let remaining = localRoutes.filter { $0.origin != origin.id || $0.aircraftID == nil }
        var seen: Set<String> = []
        return (aircraftEvidence + remaining + library.observedRoutes(at: origin)).compactMap { route in
            guard let end = destination(of: route, from: origin, scope: scope),
                  let distance = route.distanceKm, seen.insert(end.id).inserted else { return nil }
            return ExplorationLeg(start: origin, end: end, evidence: route, distance: distance)
        }.sorted { lhs, rhs in
            let leftHasModel = lhs.aircraftProfile != nil
            let rightHasModel = rhs.aircraftProfile != nil
            if leftHasModel != rightHasModel { return leftHasModel }
            return lhs.end.displayCode < rhs.end.displayCode
        }
    }
}

private struct ExplorationOriginPicker: View {
    let airports: [Airport]
    let preferred: [String]
    let favoriteIDs: Set<String>
    let selectedID: String
    let loading: Bool
    let select: (Airport) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var query = ""

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = search.isEmpty ? airports : airports.filter { airport in
            airport.nameSearchTerms.contains { $0.localizedStandardContains(search) }
        }
        let saved = matches.filter { favoriteIDs.contains($0.id) }
        let remaining = matches.filter { !favoriteIDs.contains($0.id) }
        let featured = search.isEmpty ? preferred.compactMap { id in remaining.first { $0.id == id } } : []
        let featuredIDs = Set(featured.map(\.id))
        let choices = remaining.filter { !featuredIDs.contains($0.id) }
        NavigationStack {
            List {
                if loading {
                    ProgressView("正在载入可用机场")
                } else if matches.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView("当前范围没有可用的出发机场", systemImage: "airplane.departure")
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                } else {
                    if !saved.isEmpty {
                        Section("收藏的出发机场") { ForEach(saved, content: airportButton) }
                    }
                    if !featured.isEmpty {
                        Section("精选出发机场") { ForEach(featured, content: airportButton) }
                    }
                    if !choices.isEmpty {
                        Section(search.isEmpty ? "其他出发机场" : "搜索结果") {
                            ForEach(choices, content: airportButton)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.page)
            .tint(palette.accent)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "机场名称或代码")
            .navigationTitle("选择出发机场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func airportButton(_ airport: Airport) -> some View {
        Button {
            select(airport)
        } label: {
            HStack {
                Text(airport.displayCode).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .frame(minWidth: 47, alignment: .leading)
                Text(airport.displayName).foregroundStyle(palette.ink)
                Spacer(minLength: 6)
                if airport.id == selectedID { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
        }
        .listRowBackground(palette.surface)
        .accessibilityIdentifier("exploration-origin-\(airport.id)")
        .accessibilityAddTraits(airport.id == selectedID ? .isSelected : [])
    }
}
