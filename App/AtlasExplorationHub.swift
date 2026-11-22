import SwiftUI

@MainActor
struct AtlasExplorationHub<Routes: View>: View {
    let library: AtlasLibrary
    let openAirport: (Airport) -> Void
    let openAircraft: (AircraftProfile) -> Void
    @ViewBuilder let routes: () -> Routes

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @SceneStorage("atlas.exploration.category") private var category = Category.routes
    @SceneStorage("atlas.exploration.airport-region") private var airportRegion = AirportRegion.mainland

    private enum Category: String, CaseIterable {
        case airports = "机场", aircraft = "机型", routes = "航线"
    }

    private enum AirportRegion: String, CaseIterable {
        case mainland = "中国大陆", worldwide = "全球"
    }

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("探索类别", selection: $category) {
                ForEach(Category.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("atlas-exploration-category")
            .frame(maxWidth: 660)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(palette.surface)

            switch category {
            case .airports: airportPage
            case .aircraft: aircraftPage
            case .routes: routes()
            }
        }
        .background(palette.page)
        .tint(palette.accent)
    }

    private var airportPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: palette.contentGap) {
                Picker("机场范围", selection: $airportRegion) {
                    ForEach(AirportRegion.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("exploration-airport-region")

                FlightAirportChapters(
                    library: library, domestic: airportRegion == .mainland, openAirport: openAirport
                )
            }
            .atlasReadingWidth()
        }
        .accessibilityIdentifier("exploration-airport-scroll")
    }

    private var aircraftPage: some View {
        ScrollView {
            AtlasAircraftMissions(library: library, openAircraft: openAircraft)
                .atlasReadingWidth()
        }
        .accessibilityIdentifier("exploration-aircraft-scroll")
    }
}
