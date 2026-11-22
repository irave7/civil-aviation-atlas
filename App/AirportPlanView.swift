import SwiftUI
import UIKit

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
    @State private var rotation = Angle.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(airport: Airport) {
        self.airport = airport
        self.plan = AirportSiteCatalog.plan(for: airport)
    }

    private var availableLayers: [Layer] {
        Layer.allCases.filter { layer in
            layer == .runway ? !plan.runways.isEmpty : plan.features.contains { Self.layer(for: $0.source.kind) == layer }
        }
    }

    private var headingLabel: String {
        let degrees = Int(rotation.degrees.rounded()) % 360
        return degrees == 0 ? "正北朝上" : "正北朝向 \((degrees + 360) % 360)°"
    }

    private var nearestNorth: Angle {
        .degrees((rotation.degrees / 360).rounded() * 360)
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = plan.bounds
            let fit = max(0.1, min(geometry.size.width / CGFloat(max(6, bounds.size.x)), geometry.size.height / CGFloat(max(6, bounds.size.y))) * 0.75)
            let scale = fit * zoom
            AirportPlanSurface(scale: scale, angle: rotation.radians, offset: offset) { context, size, drawScale, angle, drawOffset in
                draw(in: context, size: size, center: bounds.center, scale: drawScale, rotation: .radians(angle), offset: drawOffset)
            }
            .background(Color(red: 0.063, green: 0.104, blue: 0.145))
            .overlay {
                AirportPlanTouchSurface { translation in
                    offset.width += translation.x
                    offset.height += translation.y
                } pinch: { factor, anchor in
                    applyTransform(factor: factor, angle: .zero, anchor: anchor)
                } twist: { radians, anchor in
                    applyTransform(factor: 1, angle: .radians(radians), anchor: anchor)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(airport.displayName)平面图")
            .accessibilityValue(([headingLabel, "缩放 \(Int((zoom * 100).rounded()))%"] + availableLayers.map(\.rawValue)).joined(separator: "、"))
            .accessibilityHint("拖动平移，双指捏合缩放，双指转动旋转")
            .accessibilityAction(named: Text("顺时针旋转")) { rotate(by: .degrees(15)) }
            .accessibilityAction(named: Text("逆时针旋转")) { rotate(by: .degrees(-15)) }
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
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { rotation = nearestNorth }
            } label: {
                Label {
                    Text("北")
                } icon: {
                    Image(systemName: "location.north.line")
                        .rotationEffect(rotation)
                }
                .font(AtlasTypography.font(.caption, weight: .semibold))
            }
            .buttonStyle(.glass)
            .accessibilityLabel("恢复正北朝上")
            .accessibilityValue(headingLabel)
            .accessibilityIdentifier("airport-plan-north")
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                    zoom = 1
                    offset = .zero
                    rotation = nearestNorth
                }
            } label: {
                Label("查看全场", systemImage: "viewfinder")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("airport-plan-reset")
        }
    }

    private func rotate(by delta: Angle) {
        rotation = .radians((rotation.radians + delta.radians).truncatingRemainder(dividingBy: 2 * .pi))
    }

    private func applyTransform(factor: CGFloat, angle: Angle, anchor: CGPoint) {
        let nextZoom = min(12, max(0.65, zoom * factor))
        let relative = CGPoint(x: offset.width - anchor.x, y: offset.height - anchor.y)
        let transformed = relative.applying(
            CGAffineTransform(scaleX: nextZoom / zoom, y: nextZoom / zoom).rotated(by: angle.radians)
        )
        offset = CGSize(width: anchor.x + transformed.x, height: anchor.y + transformed.y)
        zoom = nextZoom
        rotate(by: angle)
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

    private func draw(in context: GraphicsContext, size: CGSize, center: SIMD2<Float>, scale: CGFloat, rotation: Angle, offset: CGSize) {
        let origin = CGPoint(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
        let transform = CGAffineTransform(rotationAngle: rotation.radians).concatenating(
            CGAffineTransform(translationX: origin.x, y: origin.y)
        )
        func point(_ value: SIMD2<Float>) -> CGPoint {
            CGPoint(x: CGFloat(value.x - center.x) * scale, y: CGFloat(value.y - center.y) * scale).applying(transform)
        }
        func path(_ points: [SIMD2<Float>], area: Bool) -> Path {
            Path { path in
                guard let first = points.first else { return }
                path.move(to: point(first))
                for next in points.dropFirst() { path.addLine(to: point(next)) }
                if area { path.closeSubpath() }
            }
        }

        drawGrid(in: context, size: size, transform: transform, scale: scale)
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
                    let labelOffset = max(9, CGFloat(runway.width) * scale / 2 + 6)
                    let labelPosition = runway.center - SIMD2<Float>(0, Float(labelOffset / scale))
                    context.draw(label, at: point(labelPosition))
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

    private func drawGrid(in context: GraphicsContext, size: CGSize, transform: CGAffineTransform, scale: CGFloat) {
        let step = max(24, scale * 5)
        let inverse = transform.inverted()
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height),
                       CGPoint(x: size.width, y: size.height)].map { $0.applying(inverse) }
        let minX = corners.map(\.x).min() ?? 0
        let maxX = corners.map(\.x).max() ?? 0
        let minY = corners.map(\.y).min() ?? 0
        let maxY = corners.map(\.y).max() ?? 0
        let grid = Path { path in
            for x in stride(from: (minX / step).rounded(.down) * step, through: maxX, by: step) {
                path.move(to: CGPoint(x: x, y: minY).applying(transform))
                path.addLine(to: CGPoint(x: x, y: maxY).applying(transform))
            }
            for y in stride(from: (minY / step).rounded(.down) * step, through: maxY, by: step) {
                path.move(to: CGPoint(x: minX, y: y).applying(transform))
                path.addLine(to: CGPoint(x: maxX, y: y).applying(transform))
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

private struct AirportPlanSurface: View, Animatable {
    var scale: CGFloat
    var angle: Double
    var offset: CGSize
    let draw: (GraphicsContext, CGSize, CGFloat, Double, CGSize) -> Void

    var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(angle, AnimatablePair(scale, AnimatablePair(offset.width, offset.height))) }
        set {
            angle = newValue.first
            scale = newValue.second.first
            offset = CGSize(width: newValue.second.second.first, height: newValue.second.second.second)
        }
    }

    var body: some View {
        Canvas { context, size in draw(context, size, scale, angle, offset) }
    }
}

private struct AirportPlanTouchSurface: UIViewRepresentable {
    let pan: (CGPoint) -> Void
    let pinch: (CGFloat, CGPoint) -> Void
    let twist: (Double, CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let surface = UIView()
        surface.backgroundColor = .clear
        surface.isOpaque = false
        surface.isMultipleTouchEnabled = true
        let coordinator = context.coordinator
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: coordinator, action: #selector(Coordinator.rotate(_:)))
        for gesture in [pan, pinch, rotate] {
            gesture.delegate = coordinator
            surface.addGestureRecognizer(gesture)
        }
        return surface
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: AirportPlanTouchSurface

        init(parent: AirportPlanTouchSurface) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer.view === otherGestureRecognizer.view
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            parent.pan(gesture.translation(in: gesture.view))
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed, let anchor = anchor(of: gesture) else { return }
            parent.pinch(gesture.scale, anchor)
            gesture.scale = 1
        }

        @objc func rotate(_ gesture: UIRotationGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed, let anchor = anchor(of: gesture) else { return }
            parent.twist(gesture.rotation, anchor)
            gesture.rotation = 0
        }

        private func anchor(of gesture: UIGestureRecognizer) -> CGPoint? {
            guard let view = gesture.view else { return nil }
            let location = gesture.location(in: view)
            return CGPoint(x: location.x - view.bounds.midX, y: location.y - view.bounds.midY)
        }
    }
}
