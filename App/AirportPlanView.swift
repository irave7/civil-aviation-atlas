import SwiftUI

struct AirportPlanView: View {
    private enum Layer: String, CaseIterable, Identifiable {
        case runway = "跑道"
        case taxiway = "滑行道"
        case apron = "停机坪"
        case terminal = "航站楼"
        case tower = "塔台"
        case serviceBuildings = "机库与附属建筑"

        var id: Self { self }

        var color: Color {
            switch self {
            case .runway: Color(red: 0.81, green: 0.86, blue: 0.90)
            case .taxiway: Color(red: 0.80, green: 0.65, blue: 0.39)
            case .apron: Color(red: 0.36, green: 0.47, blue: 0.53)
            case .terminal: Color(red: 0.42, green: 0.85, blue: 0.89)
            case .tower: Color(red: 0.97, green: 0.63, blue: 0.46)
            case .serviceBuildings: Color(red: 0.71, green: 0.82, blue: 0.91)
            }
        }
    }

    let airport: Airport
    private let plan: AirportSitePlan
    @State private var layers = Set(Layer.allCases)
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification: CGFloat = 1

    init(airport: Airport) {
        self.airport = airport
        self.plan = AirportSiteCatalog.plan(for: airport)
    }

    private var availableLayers: [Layer] {
        Layer.allCases.filter { layer in
            layer == .runway ? !plan.runways.isEmpty : plan.features.contains { Self.layer(for: $0.source.kind) == layer }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = plan.bounds
            let fit = max(0.1, min(geometry.size.width / CGFloat(max(6, bounds.size.x)), geometry.size.height / CGFloat(max(6, bounds.size.y))) * 0.75)
            let scale = fit * min(12, max(0.65, zoom * magnification))
            Canvas { context, size in
                draw(in: context, size: size, center: bounds.center, scale: scale)
            }
            .background(Color(red: 0.063, green: 0.104, blue: 0.145))
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 5)
                .updating($drag) { value, current, _ in current = value.translation }
                .onEnded { value in
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                })
            .simultaneousGesture(MagnifyGesture()
                .updating($magnification) { value, current, _ in current = value.magnification }
                .onEnded { value in zoom = min(12, max(0.65, zoom * value.magnification)) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(airport.displayName)机场平面图")
            .accessibilityValue(availableLayers.map(\.rawValue).joined(separator: "、"))
            .accessibilityIdentifier("airport-plan-canvas")
            .overlay(alignment: .topLeading) { header.padding(17) }
            .overlay(alignment: .topTrailing) { controls.padding(17) }
            .overlay(alignment: .bottomLeading) { legend(scale: scale).padding(16) }
            .clipped()
            .colorScheme(.dark)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(airport.displayCode)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.mint)
            Text(airport.displayName)
                .font(AtlasTypography.font(.title2, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .allowsHitTesting(false)
    }

    private var controls: some View {
        HStack(spacing: 7) {
            Label("北", systemImage: "location.north.line")
                .font(AtlasTypography.font(.caption, weight: .semibold))
                .padding(9)
                .glassEffect(in: .capsule)
                .accessibilityLabel("正北朝上")
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    zoom = 1
                    offset = .zero
                }
            } label: {
                Label("查看全场", systemImage: "viewfinder")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("airport-plan-reset")
        }
    }

    private func legend(scale: CGFloat) -> some View {
        let meters = [10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000].last { CGFloat($0) * scale / 100 <= 100 } ?? 10
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(meters.formatted()) m").monospacedDigit()
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: max(3, CGFloat(meters) * scale / 100), height: 2)
            }
            .accessibilityLabel("比例尺 \(meters.formatted()) 米")
            ViewThatFits(in: .horizontal) {
                layerControls.fixedSize(horizontal: true, vertical: false)
                ScrollView(.horizontal) { layerControls }
                    .scrollIndicators(.hidden)
            }
            HStack(spacing: 7) {
                if plan.hasOpenStreetMapData || AirportSiteCatalog.usesSupplementalRunways(for: airport) {
                    Link(AirportSiteCatalog.source.title, destination: URL(string: AirportSiteCatalog.source.url)!)
                }
                if plan.hasOvertureData {
                    Link("© Overture Maps", destination: URL(string: AirportSiteCatalog.overtureSource.url)!)
                }
                if !plan.runways.isEmpty && !AirportSiteCatalog.usesSupplementalRunways(for: airport) {
                    Text("跑道 · 公开机场资料")
                }
            }
            .font(AtlasTypography.font(.caption2))
            .foregroundStyle(.white.opacity(0.68))
        }
        .font(AtlasTypography.font(.caption2))
        .padding(11)
        .glassEffect(in: .rect(cornerRadius: 15))
    }

    private var layerControls: some View {
        HStack(spacing: 7) {
            ForEach(availableLayers) { layer in
                Button {
                    if layers.contains(layer) {
                        layers.remove(layer)
                    } else {
                        layers.insert(layer)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(layer.color).frame(width: 6, height: 6)
                        Text(layer.rawValue)
                            .font(AtlasTypography.font(.caption2, weight: .semibold))
                    }
                    .opacity(layers.contains(layer) ? 1 : 0.52)
                }
                .buttonStyle(.glass)
                .accessibilityAddTraits(layers.contains(layer) ? .isSelected : [])
            }
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, center: SIMD2<Float>, scale: CGFloat) {
        let origin = CGPoint(x: size.width / 2 + offset.width + drag.width, y: size.height / 2 + offset.height + drag.height)
        func point(_ value: SIMD2<Float>) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(value.x - center.x) * scale, y: origin.y + CGFloat(value.y - center.y) * scale)
        }
        func path(_ points: [SIMD2<Float>], area: Bool) -> Path {
            Path { path in
                guard let first = points.first else { return }
                path.move(to: point(first))
                for next in points.dropFirst() { path.addLine(to: point(next)) }
                if area { path.closeSubpath() }
            }
        }

        drawGrid(in: context, size: size, origin: origin, scale: scale)
        for feature in plan.features where feature.source.kind == .boundary {
            let boundary = path(feature.points, area: feature.source.area)
            context.fill(boundary, with: .color(Color(red: 0.11, green: 0.24, blue: 0.25).opacity(0.75)))
            context.stroke(boundary, with: .color(.mint.opacity(0.25)), lineWidth: 1.1)
        }
        for layer in [Layer.apron, .taxiway, .runway, .serviceBuildings, .terminal, .tower] where layers.contains(layer) {
            if layer == .runway {
                for runway in plan.runways {
                    let centerline = path(runway.ends, area: false)
                    context.stroke(centerline, with: .color(layer.color.opacity(runway.approximatePlacement ? 0.52 : 0.92)), lineWidth: max(2.5, CGFloat(runway.width) * scale))
                    let dash = StrokeStyle(lineWidth: 0.8, dash: [4, 4])
                    context.stroke(centerline, with: .color(Color(red: 0.22, green: 0.30, blue: 0.35)), style: dash)
                    let label = Text(runway.id).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                    let midpoint = point(runway.center)
                    context.draw(label, at: CGPoint(x: midpoint.x, y: midpoint.y - max(9, CGFloat(runway.width) * scale / 2 + 6)))
                }
                continue
            }
            for feature in plan.features where Self.layer(for: feature.source.kind) == layer {
                let shape = path(feature.points, area: feature.source.area)
                if feature.source.area {
                    context.fill(shape, with: .color(layer.color.opacity(layer == .terminal ? 0.72 : 0.53)))
                    context.stroke(shape, with: .color(layer.color.opacity(0.81)), lineWidth: layer == .terminal ? 1.1 : 0.65)
                } else if layer == .tower, let location = feature.points.first {
                    let center = point(location)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(layer.color))
                } else {
                    let width = CGFloat(feature.source.widthM ?? 18) / 100 * scale
                    context.stroke(shape, with: .color(layer.color.opacity(0.77)), style: StrokeStyle(lineWidth: max(0.85, width), lineCap: .round, lineJoin: .round))
                }
            }
        }
        if layers.contains(.terminal) {
            for feature in plan.features where feature.source.kind == .terminal {
                let bounds = feature.bounds
                guard let name = feature.source.name, !name.isEmpty, CGFloat(bounds.span) * scale >= 65 else { continue }
                let label = Text(name).font(AtlasTypography.font(.caption2, weight: .semibold)).foregroundStyle(.white)
                context.draw(label, at: point(bounds.center))
            }
        }
    }

    private func drawGrid(in context: GraphicsContext, size: CGSize, origin: CGPoint, scale: CGFloat) {
        let step = max(24, scale * 5)
        let grid = Path { path in
            for x in stride(from: origin.x.truncatingRemainder(dividingBy: step), through: size.width, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: origin.y.truncatingRemainder(dividingBy: step), through: size.height, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 0.7)
    }

    private static func layer(for kind: AirportSiteFeature.Kind) -> Layer? {
        switch kind {
        case .terminal: .terminal
        case .taxiway: .taxiway
        case .apron: .apron
        case .tower: .tower
        case .hangar, .building: .serviceBuildings
        case .boundary: nil
        }
    }
}
