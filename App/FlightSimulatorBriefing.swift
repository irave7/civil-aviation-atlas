import Charts
import SwiftUI

@MainActor
struct FlightSimulatorBriefing: View {
    let origin: Airport
    let destination: Airport
    let route: FlightRoute
    let distance: Double
    let profile: AircraftProfile?
    let livery: AircraftLivery
    let usesReferenceAircraft: Bool
    let departureRunways: [Runway]
    let destinationRunways: [Runway]
    @Binding var departureRunway: Runway?
    @Binding var destinationRunway: Runway?
    @Binding var guided: Bool
    let windLabel: String
    let showWeather: () -> Void
    let chooseAircraft: () -> Void
    let showImagery: (Airport) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        VStack(alignment: .leading, spacing: palette.contentGap) {
            routeHeader
            flightStyle
            aircraftAndSource
            runwaysAndWind
        }
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exploration-simulator-briefing")
    }

    private var routeHeader: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    briefingTitle
                    Spacer(minLength: 0)
                    distanceLabel
                }
                VStack(alignment: .leading, spacing: 5) {
                    briefingTitle
                    distanceLabel
                }
            }
            Rectangle().fill(palette.stageMuted.opacity(0.32)).frame(height: 1)
                .accessibilityHidden(true)
            layout {
                endpoint(origin, role: "出发")
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "airplane")
                        .font(.caption)
                        .foregroundStyle(palette.stageAccent)
                        .padding(.top, 27)
                        .accessibilityHidden(true)
                }
                endpoint(destination, role: "抵达")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.stage, in: .rect(cornerRadius: palette.corner))
        .overlay {
            RoundedRectangle(cornerRadius: palette.corner)
                .strokeBorder(palette.stageAccent.opacity(0.25), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var briefingTitle: some View {
        Text("飞行简报")
            .font(AtlasTypography.font(.headline, weight: .semibold))
            .foregroundStyle(palette.stageInk)
            .accessibilityAddTraits(.isHeader)
    }

    private var distanceLabel: some View {
        Text("大圆距离 \(distance.formatted(.number.precision(.fractionLength(0)))) 公里")
            .font(AtlasTypography.font(.footnote))
            .foregroundStyle(palette.stageMuted)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var aircraftAndSource: some View {
        VStack(alignment: .leading, spacing: 8) {
            title("机型与涂装")
            Text(profile?.displayName ?? route.displayAircraftName)
                .font(AtlasTypography.font(.body, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(livery.name)
                .foregroundStyle(palette.muted)
            Button("选择模拟机型", systemImage: "airplane", action: chooseAircraft)
                .buttonStyle(.glass)
                .accessibilityIdentifier("simulator-briefing-choose-aircraft")
            if usesReferenceAircraft {
                Text("模拟采用参考机型与涂装。")
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(palette.muted)
            }
            if route.origin == origin.id, let flight = route.flightNumber {
                Text("资料航班 \(flight) · \(route.airline)")
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(palette.muted)
            }
            if let source = route.source {
                Text("航线资料 \(source.title)")
                    .font(AtlasTypography.font(.caption))
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .atlasPanel(palette)
    }

    private var flightStyle: some View {
        VStack(alignment: .leading, spacing: 9) {
            title("飞行方式")
            Picker("飞行方式", selection: $guided) {
                Text("导览飞行").tag(true)
                Text("手动操纵").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("simulator-pilot-style")
            Text(guided ? "飞机会示范各阶段的操作。飞行中可随时接手。" : "由你操纵推力、机头姿态、襟翼、起落架和刹车。")
                .font(AtlasTypography.font(.subheadline))
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .atlasPanel(palette)
    }

    private var runwaysAndWind: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("跑道与天气")
            runwayPicker("起飞跑道", options: departureRunways, selection: $departureRunway,
                         id: "exploration-departure-runway")
            runwayPicker("着陆跑道", options: destinationRunways, selection: $destinationRunway,
                         id: "exploration-destination-runway")
            Text("天气情境 \(windLabel)")
                .font(AtlasTypography.font(.subheadline))
                .foregroundStyle(palette.muted)
            Button(DistributionPolicy.liveFlightsAvailable ? "实际航班与天气" : "天气情境",
                   systemImage: "wind", action: showWeather)
                .buttonStyle(.glass)
                .accessibilityIdentifier("exploration-simulator-weather")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .atlasPanel(palette)
    }

    private func endpoint(_ airport: Airport, role: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role)
                .font(AtlasTypography.font(.caption, weight: .semibold))
                .foregroundStyle(palette.stageMuted)
            Text(airport.displayCode)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(palette.stageAccent)
            Text(airport.displayName)
                .font(AtlasTypography.font(.subheadline, weight: .semibold))
                .foregroundStyle(palette.stageInk)
                .fixedSize(horizontal: false, vertical: true)
            if DistributionPolicy.mapsAvailable && airport.hasCoordinates {
                Button {
                    showImagery(airport)
                } label: {
                    Label("查看实景", systemImage: "globe.asia.australia")
                        .font(AtlasTypography.font(.footnote, weight: .semibold))
                        .foregroundStyle(palette.stageAccent)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(airport.displayName)实景")
                .accessibilityIdentifier("exploration-simulator-imagery-\(airport.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runwayPicker(_ label: String, options: [Runway], selection: Binding<Runway?>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AtlasTypography.font(.subheadline, weight: .semibold))
                .foregroundStyle(palette.ink)
            if options.isEmpty {
                Text("本场暂无跑道记录，模拟采用参考跑道。")
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(palette.muted)
            } else {
                Picker(label, selection: selection) {
                    Text("自动选择").tag(nil as Runway?)
                    ForEach(options) { runway in
                        Text("\(runway.id) · \(runway.lengthM.formatted(.number.precision(.fractionLength(0)))) 米")
                            .tag(runway as Runway?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier(id)
            }
        }
    }

    private func title(_ text: String, size: Font.TextStyle = .headline) -> some View {
        Text(text)
            .font(AtlasTypography.font(size, weight: .bold))
            .foregroundStyle(palette.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
struct FlightSimulatorDebrief: View {
    let summary: FlightSimulation.Summary
    let destination: Airport
    let restart: () -> Void
    let openAirport: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var trace: Trace = .altitude
    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    private enum Trace: String, CaseIterable, Identifiable {
        case altitude = "高度", speed = "空速"
        var id: Self { self }
        var unit: String { self == .altitude ? "英尺" : "节" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("飞行记录")
                .font(AtlasTypography.font(.title2, weight: .bold))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("\(destination.displayCode) · \(destination.displayName)")
                .foregroundStyle(palette.muted)
            if summary.samples.count > 1 { profileChart }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 232 : 152), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                metric("模拟用时", elapsedText)
                metric("复飞次数", summary.goArounds.formatted())
                metric("起飞滑跑", value(summary.takeoffRollM, unit: "米"))
                if summary.taxiOutM > 0 { metric("滑出里程", value(summary.taxiOutM, unit: "米")) }
                metric("最高海拔", value(summary.peakAltitude, unit: "英尺"))
                metric("最高空速", value(summary.peakSpeed, unit: "节"))
                metric("最大倾斜角", value(summary.maxBank, unit: "°"))
                if let landingSpeed = summary.landingSpeed {
                    metric("接地速度", value(landingSpeed, unit: "节"))
                }
                if let verticalSpeed = summary.touchdownVerticalSpeed {
                    metric("接地垂直速度", value(verticalSpeed, unit: "英尺/分"))
                }
                metric("着陆滑跑", value(summary.landingRollM, unit: "米"))
                if summary.taxiInM > 0 { metric("滑入里程", value(summary.taxiInM, unit: "米")) }
            }
            if summary.landingRunwayExceeded {
                Label("模拟滑跑超出所选跑道长度", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(palette.ink)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .atlasPanel(palette)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exploration-simulator-debrief")
    }

    private var profileChart: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("飞行曲线")
                .font(AtlasTypography.font(.headline, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Picker("飞行曲线", selection: $trace) {
                ForEach(Trace.allCases) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented)
            Chart(summary.samples) { sample in
                AreaMark(x: .value("模拟秒数", sample.elapsed),
                         y: .value(trace.rawValue, trace == .altitude ? sample.altitude : sample.airspeed))
                    .foregroundStyle(.linearGradient(colors: [palette.accent.opacity(0.20), palette.accent.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
                LineMark(x: .value("模拟秒数", sample.elapsed),
                         y: .value(trace.rawValue, trace == .altitude ? sample.altitude : sample.airspeed))
                    .foregroundStyle(palette.accent)
            }
            .chartXAxisLabel("模拟用时（秒）")
            .chartYAxisLabel(trace.unit)
            .frame(height: typeSize.isAccessibilitySize ? 210 : 164)
            .accessibilityLabel("模拟\(trace.rawValue)随时间变化")
            .accessibilityIdentifier("simulator-debrief-profile")
        }
    }

    private var elapsedText: String {
        let seconds = max(0, Int(summary.elapsed.rounded()))
        if seconds < 60 { return "\(seconds) 秒" }
        return "\(seconds / 60) 分 \(seconds % 60) 秒"
    }

    private func value(_ number: Double, unit: String) -> String {
        "\(number.formatted(.number.precision(.fractionLength(0)))) \(unit)"
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AtlasTypography.font(.caption, weight: .semibold))
                .foregroundStyle(palette.muted)
            Text(value)
                .font(palette.readout(.body))
                .foregroundStyle(palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.subtle, in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        Button("重新模拟", systemImage: "arrow.counterclockwise", action: restart)
            .buttonStyle(.glassProminent)
            .foregroundStyle(palette.onAccent)
            .accessibilityIdentifier("exploration-simulator-restart")
        Button("查看抵达机场", systemImage: "airplane.arrival", action: openAirport)
            .buttonStyle(.glass)
            .accessibilityIdentifier("exploration-simulator-arrival-airport")
    }
}
