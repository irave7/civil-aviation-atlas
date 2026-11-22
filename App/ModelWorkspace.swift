import RealityKit
import SwiftUI
import UIKit

private enum ModelMode: String, CaseIterable, Identifiable {
    case exterior = "外观"
    case inside = "内部"
    case xray = "透视"
    case section = "剖视"
    case exploded = "拆分"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .exterior: "cube"
        case .inside: "door.left.hand.open"
        case .xray: "square.on.square.intersection.dashed"
        case .section: "viewfinder.rectangular"
        case .exploded: "square.3.layers.3d"
        }
    }
}

@MainActor
struct ModelWorkspace: View {
    private static let stageControlPadding: CGFloat = 16

    let model: AtlasModel
    let title: String
    let subtitle: String
    let expandsSplitZoom: Bool

    @StateObject private var scene: ModelSceneController
    @State private var activePart: String?
    @State private var mode: ModelMode = .exterior
    @State private var isolateSelection = true
    @State private var showParts: Bool
    @State private var partsSheet = false
    @State private var showGestures = false
    @State private var bottomControlsHeight: CGFloat = 0
    @State private var measuring = false
    @State private var measurePoints: [SIMD3<Float>] = []
    @State private var separation = 0.45
    @State private var pinchZoomsInSplit = false
    @State private var transparency = 0.28
    @State private var target: SIMD3<Float>
    @State private var distance: Float
    @State private var azimuth: Float = -0.53
    @State private var elevation: Float = 0.56

    init(
        model: AtlasModel,
        title: String,
        subtitle: String,
        expandsSplitZoom: Bool = false,
        startsWithPartsVisible: Bool = true
    ) {
        self.model = model
        self.title = title
        self.subtitle = subtitle
        self.expandsSplitZoom = expandsSplitZoom
        _scene = StateObject(wrappedValue: ModelSceneController(model: model, expandsSplitZoom: expandsSplitZoom))
        _showParts = State(initialValue: startsWithPartsVisible)
        _target = State(initialValue: model.overviewTarget)
        _distance = State(initialValue: model.overviewDistance)
    }

    private var part: AtlasPart? { activePart.flatMap(scene.part(withID:)) }
    private var hasSplitZoom: Bool { expandsSplitZoom && mode == .exploded }
    private var pinchMovesParts: Bool { mode == .exploded && !(hasSplitZoom && pinchZoomsInSplit) }
    private var zoomPercent: Int { Int(((part?.focusDistance ?? model.overviewDistance) * 100 / distance).rounded()) }

    private var availableModes: [ModelMode] {
        let scope = part?.hierarchy ?? scene.orderedParts
        return ModelMode.allCases.filter { option in
            switch option {
            case .exterior: true
            case .inside: scope.contains { $0.interior != nil }
            case .xray: scope.contains { $0.shell != nil && $0.interior != nil }
            case .section: scope.contains { $0.section != nil }
            case .exploded: scope.contains { $0.id != activePart && $0.explodeOffset != .zero }
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            HStack(spacing: 0) {
                stage(isWide: wide)
                if showParts && wide {
                    Divider()
                    partInspector
                        .frame(width: 265)
                        .background(.background)
                }
            }
            .sheet(isPresented: $partsSheet) {
                NavigationStack {
                    partInspector
                        .navigationTitle("模型部件")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { partsSheet = false }
                                    .accessibilityIdentifier("model-parts-sheet-done")
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func stage(isWide: Bool) -> some View {
        GeometryReader { viewport in
            let aspect = Float(viewport.size.width / max(1, viewport.size.height))
            let distanceFit = min(2.6, max(1, 1.16 / max(0.1, aspect)))
            ZStack {
                Rectangle().fill(Color(red: 0.055, green: 0.085, blue: 0.132).gradient)
                renderSurface(distanceFit: distanceFit)
                VStack(spacing: 0) {
                    header(isWide: isWide)
                    Spacer(minLength: 12)
                    tools(viewportHeight: viewport.size.height, distanceFit: distanceFit)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomControlsHeight = $0 }
                }
                .padding(.horizontal, isWide ? 22 : 14)
                .padding(.vertical, Self.stageControlPadding)
            }
            .clipped()
            .colorScheme(.dark)
        }
    }

    private func renderSurface(distanceFit: Float) -> some View {
        let viewAzimuth = azimuth
        let viewElevation = elevation
        let viewDistance = distance * distanceFit
        let partID = activePart
        let currentMode = mode
        let isolated = isolateSelection
        let anchored = target
        let spread = Float(separation)
        let opacity = Float(transparency)
        let points = measurePoints

        return RealityView { content in
            content.camera = .virtual
            content.renderingEffects.motionBlur = .disabled
            content.add(scene.world)
            scene.moveCamera(to: anchored, angle: viewAzimuth, height: viewElevation, distance: viewDistance)
            scene.update(partID: partID, mode: currentMode, isolated: isolated, spread: spread, opacity: opacity, points: points)
        } update: { _ in
            scene.moveCamera(to: anchored, angle: viewAzimuth, height: viewElevation, distance: viewDistance)
            scene.update(partID: partID, mode: currentMode, isolated: isolated, spread: spread, opacity: opacity, points: points)
        } placeholder: {
            ProgressView("载入三维模型")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .overlay {
            ModelTouchSurface(
                zoomLabel: "\(zoomPercent)%",
                gestureHint: pinchMovesParts ? "单指旋转，双指平移，捏合调整部件间距" : "单指旋转，双指平移或捏合缩放",
                bottomHUDClearance: bottomControlsHeight + Self.stageControlPadding + 12
            ) { point, size in
                tapModel(at: point, in: size)
            } orbit: { delta in
                azimuth -= Float(delta.dx) * 0.007
                elevation = max(-0.70, min(1.47, elevation + Float(delta.dy) * 0.006))
            } transform: { translation, scale, size in
                transformModel(translation: translation, scale: scale, size: size, distanceFit: distanceFit)
            } adjustZoom: { scale in
                distance = clampedDistance(distance / scale)
            }
        }
    }

    private func tapModel(at point: CGPoint, in size: CGSize) {
        guard let hit = scene.hit(at: point, in: size) else { return }
        if measuring {
            if measurePoints.count == 2 { measurePoints.removeAll(keepingCapacity: true) }
            measurePoints.append(hit.position)
        } else if let id = scene.partID(for: hit.entity) {
            select(id)
        }
    }

    private func transformModel(translation: CGVector, scale: CGFloat, size: CGSize, distanceFit: Float) {
        if scale != 1 {
            if pinchMovesParts {
                // Logarithmic increments make opening and closing equally responsive at any finger span.
                separation = min(1, max(0, separation + log(Double(scale))))
            } else {
                distance = clampedDistance(distance / Float(scale))
            }
        }
        guard translation != .zero else { return }
        let unitsPerPoint = ModelSceneController.frustumHeight(at: distance * distanceFit) / Float(max(1, size.height))
        let right = SIMD3<Float>(cos(azimuth), 0, -sin(azimuth))
        let up = simd_cross(ModelSceneController.cameraDirection(angle: azimuth, height: elevation), right)
        target += (up * Float(translation.dy) - right * Float(translation.dx)) * unitsPerPoint
    }

    private func header(isWide: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AtlasTypography.font(isWide ? .title : .title2, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(AtlasTypography.font(isWide ? .subheadline : .footnote, weight: .semibold))
                    .foregroundStyle(.mint)
                    .lineLimit(2)
                if let part {
                    Label(part.label, systemImage: part.symbol)
                        .font(AtlasTypography.font(.callout, weight: .medium))
                        .foregroundStyle(.white.opacity(0.90))
                        .lineLimit(2)
                }
            }
            .allowsHitTesting(false)
            .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
            Spacer(minLength: 3)
            Button {
                showGestures.toggle()
            } label: {
                Label("触控操作", systemImage: "hand.draw").labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("model-gesture-help")
            .popover(isPresented: $showGestures, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("触控操作").font(AtlasTypography.font(.title3, weight: .semibold))
                    Text("单指拖动旋转｜双指拖动平移")
                    Text("双指张开或捏合缩放模型")
                    if availableModes.contains(.exploded) {
                        if expandsSplitZoom {
                            Text("在「拆分」模式下，默认捏合调整部件间距。点「捏合」可切换手势，也可以直接拖动镜头缩放滑杆。")
                        } else {
                            Text("在「拆分」模式下，双指张开分离部件，捏合收拢。")
                        }
                    }
                }
                .font(AtlasTypography.font(.body))
                .padding(20)
                .frame(maxWidth: 320, alignment: .leading)
                .presentationCompactAdaptation(.popover)
            }
            Button {
                if isWide { showParts.toggle() } else { partsSheet.toggle() }
            } label: {
                Label("部件", systemImage: "sidebar.trailing")
                    .font(AtlasTypography.font(.subheadline, weight: .semibold))
            }
            .buttonStyle(.glass)
            .accessibilityLabel(isWide && showParts ? "隐藏部件" : "显示部件")
            .accessibilityIdentifier("model-parts")
        }
    }

    private func tools(viewportHeight: CGFloat, distanceFit: Float) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                if hasSplitZoom {
                    splitPinchControl
                } else if model.metersPerUnit > 0 && !measuring && mode != .exploded {
                    ruler(viewportHeight: viewportHeight, distanceFit: distanceFit)
                }
                Spacer()
                if model.metersPerUnit > 0 {
                    Button {
                        if mode == .exploded { changeMode(.exterior) }
                        measuring.toggle()
                        measurePoints.removeAll()
                    } label: {
                        Label("测距", systemImage: measuring ? "ruler.fill" : "ruler")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)
                    .tint(measuring ? .orange : nil)
                    .accessibilityIdentifier("model-measure")
                }
                Button {
                    elevation = elevation > 1.3 ? 0.56 : 1.45
                } label: {
                    Label("俯视", systemImage: "view.2d")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                Button {
                    reset()
                } label: {
                    Label("复位", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("model-reset")
            }
            if measuring {
                Text(measurementText)
                    .font(AtlasTypography.font(.headline).monospacedDigit())
                    .contentTransition(.numericText())
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .foregroundStyle(.orange)
                    .glassEffect(in: .capsule)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("model-distance")
            }
            if hasSplitZoom {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        separationControl
                        splitZoomControl
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        separationControl
                        splitZoomControl
                    }
                }
            } else if mode == .exploded {
                separationControl
            } else if mode == .xray {
                modelSlider("外壳不透明度", symbol: mode.symbol, value: $transparency, interval: 0.05...0.85, id: "model-opacity")
            }
            ViewThatFits(in: .horizontal) {
                modeButtons(labels: true)
                modeButtons(labels: false)
            }
        }
    }

    private var splitPinchControl: some View {
        Button {
            pinchZoomsInSplit.toggle()
        } label: {
            Label(pinchZoomsInSplit ? "捏合缩放" : "捏合拆分",
                  systemImage: pinchZoomsInSplit ? "arrow.up.left.and.arrow.down.right" : ModelMode.exploded.symbol)
                .font(AtlasTypography.font(.footnote, weight: .semibold))
        }
        .buttonStyle(.glass)
        .accessibilityLabel("双指捏合")
        .accessibilityValue(pinchZoomsInSplit ? "缩放" : "拆分")
        .accessibilityHint("轻点切换缩放与拆分")
        .accessibilityIdentifier("model-split-pinch-mode")
    }

    private var separationControl: some View {
        modelSlider("拆分程度", symbol: ModelMode.exploded.symbol, value: $separation, interval: 0...1, id: "model-separation")
    }

    private var splitZoomControl: some View {
        let limits = distanceLimits(for: .exploded)
        let maximum = Double(limits.upperBound)
        let logarithmicRange = log(maximum / Double(limits.lowerBound))
        let scale = Binding {
            min(1, max(0, log(maximum / Double(distance)) / logarithmicRange))
        } set: { position in
            distance = clampedDistance(Float(maximum * exp(-position * logarithmicRange)))
        }
        return modelSlider("镜头缩放", symbol: "magnifyingglass", value: scale, interval: 0...1, id: "model-split-zoom", reading: "\(zoomPercent.formatted())%")
    }

    private func modelSlider(
        _ title: String, symbol: String, value: Binding<Double>, interval: ClosedRange<Double>, id: String, reading: String? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: symbol)
                .font(AtlasTypography.font(.footnote, weight: .semibold))
                .fixedSize()
            Slider(value: value, in: interval)
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
                .frame(minWidth: 88, maxWidth: 185)
            if let reading {
                Text(reading)
                    .font(AtlasTypography.font(.footnote).monospacedDigit())
                    .frame(minWidth: 58, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .tint(.mint)
        .padding(.horizontal, 13)
        .padding(.vertical, 5)
        .glassEffect(in: .capsule)
    }

    private func ruler(viewportHeight: CGFloat, distanceFit: Float) -> some View {
        let metersPerPoint = Double(ModelSceneController.frustumHeight(at: distance * distanceFit) * model.metersPerUnit) / max(1, viewportHeight)
        let reference = max(0.001, metersPerPoint * 100)
        let base = pow(10.0, floor(log10(reference)))
        let length = [5.0, 2.0, 1.0].map { $0 * base }.first { $0 <= reference } ?? base
        let label = length >= 1_000 ? "\((length / 1_000).formatted()) km" : "\(length.formatted()) m"
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(AtlasTypography.font(.footnote, weight: .semibold).monospacedDigit())
            HStack(spacing: 0) {
                Rectangle().frame(width: 2, height: 7)
                Rectangle().frame(height: 2)
                Rectangle().frame(width: 2, height: 7)
            }
            .frame(width: max(12, min(110, length / metersPerPoint)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(.white)
        .background(.black.opacity(0.64), in: .rect(cornerRadius: 7))
        .accessibilityLabel("近似比例尺 \(label)")
        .allowsHitTesting(false)
    }

    private func modeButtons(labels: Bool) -> some View {
        GlassEffectContainer(spacing: 5) {
            HStack(spacing: 4) {
                ForEach(availableModes) { candidate in
                    Button {
                        changeMode(candidate)
                    } label: {
                        if labels {
                            Label(candidate.rawValue, systemImage: candidate.symbol)
                        } else {
                            Label(candidate.rawValue, systemImage: candidate.symbol).labelStyle(.iconOnly)
                        }
                    }
                    .buttonStyle(.glass)
                    .font(AtlasTypography.font(.body, weight: .semibold))
                    .tint(mode == candidate ? .mint : nil)
                    .accessibilityAddTraits(mode == candidate ? .isSelected : [])
                    .accessibilityIdentifier("model-mode-\(candidate.rawValue)")
                }
            }
        }
    }

    private var partInspector: some View {
        List {
            Section {
                Button { select(nil) } label: {
                    partLabel("完整模型", symbol: "cube.transparent", selected: activePart == nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("part-overview")
                ForEach(partRows(model.parts)) { row in
                    Button { select(row.id) } label: {
                        partLabel(row.part.label, symbol: row.part.symbol, selected: activePart == row.id)
                            .padding(.leading, CGFloat(row.depth * 17))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("part-\(row.id)")
                }
            } header: {
                Text("部件")
                    .font(AtlasTypography.font(.footnote, weight: .semibold))
            }
            if let part {
                Section {
                    Text(part.detail)
                        .font(AtlasTypography.font(.body))
                        .lineSpacing(3)
                    if let dimensions = part.sizeText {
                        Label(dimensions, systemImage: "ruler")
                            .font(AtlasTypography.font(.subheadline).monospacedDigit())
                    }
                    Toggle("仅显示此部件", isOn: $isolateSelection)
                        .font(AtlasTypography.font(.subheadline))
                        .accessibilityIdentifier("model-isolate")
                } header: {
                    Text(part.label)
                        .font(AtlasTypography.font(.footnote, weight: .semibold))
                }
            }
            Section("模型资料") {
                Text(model.sourceNote)
                    .font(AtlasTypography.font(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 44)
    }

    private struct PartRow: Identifiable {
        let part: AtlasPart
        let depth: Int
        var id: String { part.id }
    }

    private func partRows(_ parts: [AtlasPart], depth: Int = 0) -> [PartRow] {
        parts.flatMap { part in
            let row = PartRow(part: part, depth: depth)
            if activePart != nil && !part.children.isEmpty && part.hierarchy.contains(where: { $0.id == activePart }) {
                return [row] + partRows(part.children, depth: depth + 1)
            }
            return [row]
        }
    }

    private func partLabel(_ label: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(AtlasTypography.font(.subheadline, weight: .semibold))
                .foregroundStyle(selected ? Color.teal : Color.secondary)
                .frame(width: 23)
                .accessibilityHidden(true)
            Text(label)
                .font(AtlasTypography.font(.body, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.teal : Color.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(AtlasTypography.font(.caption, weight: .semibold))
                    .foregroundStyle(.teal)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var measurementText: String {
        if measurePoints.count == 2 {
            let length = Double(simd_distance(measurePoints[0], measurePoints[1]) * model.metersPerUnit)
            let display = length >= 1_000
                ? Measurement(value: length / 1_000, unit: UnitLength.kilometers)
                    .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))))
                : Measurement(value: length, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
            return "模型直线距离约 \(display)"
        }
        return measurePoints.isEmpty ? "点选测距起点" : "点选测距终点"
    }

    private func select(_ id: String?) {
        activePart = id
        if !availableModes.contains(mode) { mode = .exterior }
        measurePoints.removeAll()
        target = part?.focus ?? model.overviewTarget
        distance = clampedDistance(part?.focusDistance ?? model.overviewDistance)
    }

    private func changeMode(_ newMode: ModelMode) {
        guard mode != newMode else { return }
        if newMode == .exploded { measuring = false }
        mode = newMode
        if expandsSplitZoom { distance = clampedDistance(distance, for: newMode) }
        measurePoints.removeAll()
    }

    private func reset() {
        mode = .exterior
        measuring = false
        isolateSelection = true
        separation = 0.45
        pinchZoomsInSplit = false
        azimuth = -0.53
        elevation = 0.56
        select(nil)
    }

    private func distanceLimits(for mode: ModelMode) -> ClosedRange<Float> {
        let expanded = expandsSplitZoom && mode == .exploded
        return (expanded ? 0.03 : 0.09)...(model.overviewDistance * (expanded ? 6 : 3))
    }

    private func clampedDistance(_ candidate: Float, for mode: ModelMode? = nil) -> Float {
        let limits = distanceLimits(for: mode ?? self.mode)
        return max(limits.lowerBound, min(limits.upperBound, candidate))
    }
}

private struct ModelTouchSurface: UIViewRepresentable {
    let zoomLabel: String
    let gestureHint: String
    let bottomHUDClearance: CGFloat
    let tap: (CGPoint, CGSize) -> Void
    let orbit: (CGVector) -> Void
    let transform: (CGVector, CGFloat, CGSize) -> Void
    let adjustZoom: (Float) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.isMultipleTouchEnabled = true
        view.isOpaque = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "model-viewport"
        view.accessibilityLabel = "三维模型"
        view.accessibilityTraits = .adjustable
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.onTap = tap
        view.onOrbit = orbit
        view.onTransform = transform
        view.onAdjustZoom = adjustZoom
        view.bottomHUDClearance = bottomHUDClearance
        view.accessibilityValue = zoomLabel
        view.accessibilityHint = gestureHint
    }

    final class TouchView: UIView {
        var onTap: ((CGPoint, CGSize) -> Void)?
        var onOrbit: ((CGVector) -> Void)?
        var onTransform: ((CGVector, CGFloat, CGSize) -> Void)?
        var onAdjustZoom: ((Float) -> Void)?
        var bottomHUDClearance: CGFloat = 0

        override var accessibilityFrame: CGRect {
            get {
                // Describe the unobstructed canvas separately from its surrounding buttons.
                let horizontalInset = min(72, bounds.width * 0.12)
                let topInset = min(124, bounds.height * 0.18)
                let bottomInset = min(bounds.height * 0.50, max(topInset, bottomHUDClearance))
                let canvas = CGRect(
                    x: bounds.minX + horizontalInset,
                    y: bounds.minY + topInset,
                    width: bounds.width - 2 * horizontalInset,
                    height: bounds.height - topInset - bottomInset
                )
                return UIAccessibility.convertToScreenCoordinates(canvas, in: self)
            }
            set { super.accessibilityFrame = newValue }
        }

        override func accessibilityIncrement() { onAdjustZoom?(1.2) }
        override func accessibilityDecrement() { onAdjustZoom?(1 / 1.2) }

        private struct Pair {
            let center: CGPoint
            let span: CGFloat
        }

        private var fingers: Set<UITouch> = []
        private var tapStart: CGPoint?
        private var orbitPoint: CGPoint?
        private var panCenter: CGPoint?
        private var pinchSpan: CGFloat?
        private var isPanning = false
        private var isPinching = false
        private let dragThreshold: CGFloat = 6

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            fingers.formUnion(touches)
            if fingers.count == 1 {
                tapStart = fingers.first?.location(in: self)
            } else {
                // A touch sequence that becomes multi-touch can never trigger a part tap.
                tapStart = nil
                orbitPoint = nil
                resetPair()
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let pair, let panCenter, let pinchSpan {
                let translation = delta(from: panCenter, to: pair.center)
                isPanning = isPanning || hypot(translation.dx, translation.dy) >= dragThreshold
                isPinching = isPinching || abs(pair.span - pinchSpan) >= dragThreshold
                if isPanning { self.panCenter = pair.center }
                if isPinching { self.pinchSpan = pair.span }
                onTransform?(isPanning ? translation : .zero, isPinching ? pair.span / pinchSpan : 1, bounds.size)
            } else if fingers.count == 1, let point = fingers.first?.location(in: self),
                      let origin = orbitPoint ?? tapStart {
                let translation = delta(from: origin, to: point)
                guard orbitPoint != nil || hypot(translation.dx, translation.dy) >= dragThreshold else { return }
                tapStart = nil
                orbitPoint = point
                onOrbit?(translation)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            if fingers.count == 1, let start = tapStart, let point = touches.first?.location(in: self) {
                let translation = delta(from: start, to: point)
                if hypot(translation.dx, translation.dy) < dragThreshold {
                    onTap?(point, bounds.size)
                }
            }
            finish(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        private var pair: Pair? {
            guard fingers.count == 2 else { return nil }
            let points = fingers.map { $0.location(in: self) }
            let first = points[0]
            let second = points[1]
            return Pair(
                center: CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2),
                span: max(12, hypot(first.x - second.x, first.y - second.y))
            )
        }

        private func resetPair() {
            let pair = pair
            panCenter = pair?.center
            pinchSpan = pair?.span
            isPanning = false
            isPinching = false
        }

        private func finish(_ touches: Set<UITouch>) {
            fingers.subtract(touches)
            tapStart = nil
            orbitPoint = nil
            resetPair()
        }

        private func delta(from origin: CGPoint, to point: CGPoint) -> CGVector {
            CGVector(dx: point.x - origin.x, dy: point.y - origin.y)
        }
    }
}

@MainActor
private final class ModelSceneController: ObservableObject {
    private struct Configuration: Equatable {
        let partID: String?
        let mode: ModelMode
        let isolated: Bool
        let spread: Float
        let opacity: Float
        let points: [SIMD3<Float>]
    }

    let world = Entity()
    private static let fov: Float = 46
    private let camera = PerspectiveCamera()
    private let marks = Entity()
    private let model: AtlasModel
    let orderedParts: [AtlasPart]
    private let origins: [String: SIMD3<Float>]
    private let entities: [String: AtlasPart]
    private var lastConfiguration: Configuration?

    init(model: AtlasModel, expandsSplitZoom: Bool) {
        self.model = model
        let parts = model.parts.flatMap(\.hierarchy)
        orderedParts = parts
        origins = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0.entity.position) })
        entities = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0) })
        for part in parts { part.entity.name = part.id }
        let farDistance = model.overviewDistance * (expandsSplitZoom ? 24 : 16)
        camera.camera = PerspectiveCameraComponent(near: 0.005, far: farDistance, fieldOfViewInDegrees: Self.fov, fieldOfViewOrientation: .vertical)
        world.addChild(model.root)
        world.addChild(camera)
        world.addChild(marks)
        addLight(at: SIMD3<Float>(-3, 7, 5), intensity: 2_100, color: .white)
        addLight(at: SIMD3<Float>(5, 3, -5), intensity: 1_250, color: UIColor(red: 0.53, green: 0.74, blue: 1.0, alpha: 1))
        addLight(at: SIMD3<Float>(-5, 2, -4), intensity: 450, color: UIColor(red: 0.64, green: 0.91, blue: 1.0, alpha: 1))
    }

    static func cameraDirection(angle: Float, height: Float) -> SIMD3<Float> {
        SIMD3<Float>(sin(angle) * cos(height), sin(height), cos(angle) * cos(height))
    }

    static func frustumHeight(at distance: Float) -> Float {
        2 * distance * tan(Float.pi * fov / 360)
    }

    func moveCamera(to point: SIMD3<Float>, angle: Float, height: Float, distance: Float) {
        let direction = Self.cameraDirection(angle: angle, height: height)
        camera.look(at: point, from: point + direction * distance, relativeTo: world)
    }

    func hit(at point: CGPoint, in size: CGSize) -> CollisionCastHit? {
        guard let scene = world.scene, size.height > 0 else { return nil }
        let scale = Self.frustumHeight(at: 1) / Float(size.height)
        let viewDirection = SIMD3<Float>(Float(point.x - size.width / 2) * scale, Float(size.height / 2 - point.y) * scale, -1)
        let direction = camera.orientation(relativeTo: world).act(simd_normalize(viewDirection))
        return scene.raycast(
            origin: camera.position(relativeTo: world), direction: direction, length: camera.camera.far,
            query: .nearest, relativeTo: world
        ).first
    }

    func partID(for selected: Entity) -> String? {
        var entity: Entity? = selected
        while let current = entity {
            if let part = entities[current.name], part.entity === current { return part.id }
            entity = current.parent
        }
        return nil
    }

    func part(withID id: String) -> AtlasPart? {
        entities[id]
    }

    func update(partID: String?, mode: ModelMode, isolated: Bool, spread: Float, opacity: Float, points: [SIMD3<Float>]) {
        let next = Configuration(partID: partID, mode: mode, isolated: isolated, spread: spread, opacity: opacity, points: points)
        let previous = lastConfiguration
        guard next != previous else { return }
        if points != previous?.points { draw(points: points) }
        lastConfiguration = next

        let visibilityChanges = partID != previous?.partID || mode != previous?.mode || isolated != previous?.isolated
        let positionChanges = visibilityChanges || (mode == .exploded && spread != previous?.spread)
        let opacityChanges = visibilityChanges || opacity != previous?.opacity
        guard positionChanges || opacityChanges else { return }

        let selected = partID.flatMap { entities[$0] }
        let descendants = selected.map { Set($0.hierarchy.map(\.id)) }
        if visibilityChanges { model.context?.isEnabled = !isolated || selected == nil }
        for part in orderedParts {
            let inScope = descendants?.contains(part.id) ?? true
            let currentMode = inScope ? mode : .exterior
            if positionChanges, part.explodeOffset != .zero, let origin = origins[part.id] {
                let offset = currentMode == .exploded && selected?.id != part.id ? part.explodeOffset * spread : .zero
                part.entity.position = origin + offset
            }
            if visibilityChanges {
                let isAncestor = selected.map { isDescendant($0.entity, of: part.entity) && $0.id != part.id } ?? false
                let visibilityAllowed = !part.interiorOnly || selected?.id == part.id || isAncestor || (inScope && mode != .exterior)
                part.entity.isEnabled = (!isolated || inScope || isAncestor) && visibilityAllowed
                let contextVisible = !isolated || !isAncestor || selected.map { isDescendant($0.entity, of: part.shell) } == true
                part.shell?.isEnabled = contextVisible && (currentMode != .inside || part.interior == nil) && (currentMode != .section || part.section == nil)
                let keepInteriorParent = selected.map { isDescendant($0.entity, of: part.interior) } ?? false
                part.interior?.isEnabled = keepInteriorParent || (inScope && currentMode != .exterior)
                part.section?.isEnabled = inScope && currentMode == .section
            }
            if opacityChanges, let shell = part.shell {
                let transparent = (currentMode == .xray || currentMode == .exploded) && part.interior != nil
                shell.components.set(OpacityComponent(opacity: transparent ? opacity : 1))
            }
        }
    }

    private func isDescendant(_ entity: Entity, of ancestor: Entity?) -> Bool {
        guard let ancestor else { return false }
        var current: Entity? = entity.parent
        while let item = current {
            if item === ancestor { return true }
            current = item.parent
        }
        return false
    }

    private func draw(points: [SIMD3<Float>]) {
        for entity in Array(marks.children) { entity.removeFromParent() }
        let markerRadius = min(model.overviewDistance * 0.0024, 1.2 / max(model.metersPerUnit, 0.25))
        for point in points {
            let marker = ModelEntity(mesh: .generateSphere(radius: markerRadius), materials: [UnlitMaterial(color: .systemOrange)])
            marker.position = point
            marks.addChild(marker)
        }
        if points.count == 2 {
            marks.addChild(AtlasGeometry.cylinder(from: points[0], to: points[1], radius: markerRadius * 0.35, color: .systemOrange, unlit: true))
        }
    }

    private func addLight(at position: SIMD3<Float>, intensity: Float, color: UIColor) {
        let light = DirectionalLight()
        light.light.color = color
        light.light.intensity = intensity
        light.look(at: .zero, from: position, relativeTo: nil)
        world.addChild(light)
    }
}
