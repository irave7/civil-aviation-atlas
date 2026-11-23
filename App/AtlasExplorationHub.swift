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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var tabAnimation

    private enum Category: String, CaseIterable {
        case airports = "机场", aircraft = "机型", routes = "航线"

        var symbol: String {
            switch self {
            case .airports: "building.2"
            case .aircraft: "airplane"
            case .routes: "point.topleft.down.curvedto.point.bottomright.up"
            }
        }
    }

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Category.allCases, id: \.self) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { category = item }
                    } label: {
                        HStack(spacing: 7) {
                            if !typeSize.isAccessibilitySize {
                                Image(systemName: item.symbol)
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(item.rawValue).font(AtlasTypography.font(.headline, weight: .semibold))
                        }
                        .foregroundStyle(category == item ? palette.accent : palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(alignment: .bottom) {
                            if category == item {
                                Capsule().fill(palette.accent)
                                    .frame(width: 32, height: 3)
                                    .matchedGeometryEffect(id: "active-category", in: tabAnimation)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("atlas-exploration-category")
            .frame(maxWidth: 760)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(palette.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 0.5) }

            switch category {
            case .airports: airportPage
            case .aircraft: aircraftPage
            case .routes: routes()
            }
        }
        .background(palette.page)
        .tint(palette.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ExplorationVoiceMenu() }
        }
    }

    private var airportPage: some View {
        ScrollView {
            FlightAirportChapters(library: library, openAirport: openAirport)
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

// Each segment represents a task available in the current chapter.
struct ExplorationChapterHeader: View {
    let title: String
    let done: Int
    let total: Int
    let unit: String
    let palette: AtlasPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    heading
                    Spacer(minLength: 4)
                    progressLabel
                }
                VStack(alignment: .leading, spacing: 6) { heading; progressLabel }
            }
            if total > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<total, id: \.self) { index in
                        Capsule().fill(index < done ? palette.stageAccent : palette.stageMuted.opacity(0.30))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(palette.stage, in: .rect(cornerRadius: palette.corner))
    }

    private var heading: some View {
        Text(title)
            .font(AtlasTypography.font(.title2, weight: .bold))
            .foregroundStyle(palette.stageInk)
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var progressLabel: some View {
        Text("已完成 \(done) / \(total)\(unit)")
            .font(AtlasTypography.font(.subheadline, weight: .medium).monospacedDigit())
            .foregroundStyle(palette.stageAccent)
            .fixedSize(horizontal: false, vertical: true)
    }
}
