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
    private static let defaultSeparation = 0.45

    let model: AtlasModel
    let title: String
    let subtitle: String
    let expandsSplitZoom: Bool
    private let liveryName: String?
    private let chooseLivery: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var scene: ModelSceneController
    @State private var activePart: String?
    @State private var mode: ModelMode = .exterior
    @State private var modeBeforeSplit: ModelMode = .exterior
    @State private var isolateSelection = true
    @State private var showParts: Bool
    @State private var partsSheet = false
    @State private var showGestures = false
    @State private var bottomControlsHeight: CGFloat = 0
    @State private var controlFrames: [CGRect] = []
    @State private var measuring = false
    @State private var measurePoints: [SIMD3<Float>] = []
    @State private var separation = ModelWorkspace.defaultSeparation
    @State private var transparency = 0.28
    @State private var target: SIMD3<Float>
    @State private var distance: Float
    @State private var azimuth: Float = -0.53
    @State private var elevation: Float = 0.56
    @State private var sceneTransition = 0
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var palette: AtlasPalette { AtlasPalette(colorScheme, contrast: contrast) }

    init(
        model: AtlasModel,
        title: String,
        subtitle: String,
        expandsSplitZoom: Bool = false,
        startsWithPartsVisible: Bool = true,
        liveryName: String? = nil,
        chooseLivery: (() -> Void)? = nil
    ) {
        self.model = model
        self.title = title
        self.subtitle = subtitle
        self.expandsSplitZoom = expandsSplitZoom
        self.liveryName = liveryName
        self.chooseLivery = chooseLivery
        _scene = StateObject(wrappedValue: ModelSceneController(model: model, expandsSplitZoom: expandsSplitZoom))
        _showParts = State(initialValue: startsWithPartsVisible)
        _target = State(initialValue: model.overviewTarget)
        _distance = State(initialValue: model.overviewDistance)
    }

    private var part: AtlasPart? { activePart.flatMap(scene.part(withID:)) }
    private var hasSplitZoom: Bool { expandsSplitZoom && mode == .exploded }
    private var zoomPercent: Int { Int(((part?.focusDistance ?? model.overviewDistance) * 100 / distance).rounded()) }
    private var canAdjustSeparation: Bool { !measuring && availableModes.contains(.exploded) }

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
            let wide = !textSize.isAccessibilitySize && geometry.size.width >= (isPhone ? 680 : 760)
            let isInspecting = wide && showParts
            HStack(spacing: 0) {
                stage(isWide: wide)
                if isInspecting {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(palette.line)
                            .frame(width: 1)
                            .accessibilityHidden(true)
                        inspector(compact: geometry.size.height < 370, showsLivery: true)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("model-inspector")
                            .frame(width: min(300, max(220, geometry.size.width * 0.28)))
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()
            .sheet(isPresented: $partsSheet) {
                NavigationStack {
                    inspector()
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
            .sheet(isPresented: $showGestures) {
                NavigationStack {
                    AtlasTouchGuide()
                        .navigationTitle("触控教程")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showGestures = false }
                                    .accessibilityIdentifier("model-gesture-help-done")
                            }
                        }
                }
            }
        }
    }

    private func stage(isWide: Bool) -> some View {
        GeometryReader { viewport in
            let aspect = Float(viewport.size.width / max(1, viewport.size.height))
            let distanceFit = min(2.6, max(1, 1.16 / max(0.1, aspect)))
            let shortStage = isPhone && viewport.size.height < 320 && viewport.size.width >= 400
            let padding = shortStage ? 8.0 : Self.stageControlPadding
            let horizontalPadding: CGFloat = isWide && !isPhone ? 22 : 14
            let clearCanvas = ModelTouchSurface.canvasFrame(
                in: CGRect(origin: .zero, size: viewport.size), bottomHUDClearance: bottomControlsHeight + padding + 12
            )
            let visibleLift = shortStage ? max(0, (bottomControlsHeight - 42) / 2) : 0
            let centerLift = Float(min(0.16, visibleLift / max(1, viewport.size.height)))
            ZStack {
                Rectangle().fill(palette.isDark
                    ? LinearGradient(colors: [palette.stage, palette.page], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : AtlasModelStage.backdrop)
                    .allowsHitTesting(false)
                renderSurface(distanceFit: distanceFit, centerLift: centerLift)
                touchSurface(distanceFit: distanceFit, controlPadding: padding)
                    .zIndex(1)
                VStack(spacing: 0) {
                    header(isWide: isWide, shortStage: shortStage)
                    Spacer(minLength: 12)
                    tools(viewportHeight: viewport.size.height, distanceFit: distanceFit, shortStage: shortStage)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomControlsHeight = $0 }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, padding)
                .zIndex(2)
            }
            .overlay(alignment: .bottomLeading) {
                if measuring || mode == .exploded || mode == .xray {
                    let leading = max(horizontalPadding, clearCanvas.minX - (shortStage ? 20 : 0)) + 1
                    floatingModelControls(compact: shortStage)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: mode)
                        .padding(.leading, leading)
                        .padding(.trailing, shortStage ? horizontalPadding : leading)
                        .padding(.bottom, max(bottomControlsHeight + padding + 6, viewport.size.height - clearCanvas.maxY + 1))
                }
            }
            .coordinateSpace(.named(ModelControlFrames.space))
            .onPreferenceChange(ModelControlFrames.self) { frames in
                controlFrames = frames
            }
            .clipped()
            .colorScheme(.dark)
        }
    }

    private func renderSurface(distanceFit: Float, centerLift: Float) -> some View {
        let viewAzimuth = azimuth
        let viewElevation = elevation
        let viewDistance = distance * distanceFit
        let partID = activePart
        let currentMode = mode
        let isolated = isolateSelection
        let backgroundDimmed = (isolated && partID != nil) || (model.stageSurface == .studio && currentMode != .exterior)
        let anchored = target
        let spread = Float(separation)
        let opacity = Float(transparency)
        let points = measurePoints
        let transition = sceneTransition
        let motionReduced = reduceMotion

        return RealityView { content in
            content.camera = .virtual
            content.renderingEffects.motionBlur = .disabled
            content.add(scene.world)
            _ = scene.consumeTransition(transition, reduceMotion: motionReduced)
            scene.moveCamera(to: anchored, angle: viewAzimuth, height: viewElevation, distance: viewDistance,
                             centerLift: centerLift, dimGround: backgroundDimmed, animated: false)
            scene.update(partID: partID, mode: currentMode, isolated: isolated, spread: spread, opacity: opacity,
                         points: points, animated: false)
        } update: { _ in
            let animated = scene.consumeTransition(transition, reduceMotion: motionReduced)
            scene.moveCamera(to: anchored, angle: viewAzimuth, height: viewElevation, distance: viewDistance,
                             centerLift: centerLift, dimGround: backgroundDimmed, animated: animated)
            scene.update(partID: partID, mode: currentMode, isolated: isolated, spread: spread, opacity: opacity,
                         points: points, animated: animated)
        } placeholder: {
            ProgressView("载入三维模型")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func touchSurface(distanceFit: Float, controlPadding: CGFloat) -> some View {
        ModelTouchSurface(
            zoomLabel: "\(zoomPercent)%",
            gestureHint: canAdjustSeparation
                ? "单指旋转，双指平移或缩放，三指拆分或合并"
                : "单指旋转，双指平移或缩放",
            bottomHUDClearance: bottomControlsHeight + controlPadding + 12,
            controlFrames: controlFrames,
            canToggleTransparency: !measuring && availableModes.contains(.xray),
            canToggleSection: !measuring && availableModes.contains(.section)
        ) { point, size in
            tapModel(at: point, in: size)
        } orbit: { delta in
            azimuth -= Float(delta.dx) * 0.007
            elevation = max(-0.70, min(1.47, elevation + Float(delta.dy) * 0.006))
        } transform: { translation, scale, size in
            transformModel(translation: translation, scale: scale, size: size, distanceFit: distanceFit)
        } adjustZoom: { scale in
            distance = clampedDistance(distance / scale)
        } toggleTransparency: {
            toggleMode(.xray)
        } toggleSection: {
            toggleMode(.section)
        } adjustSeparation: { scale in
            adjustSeparation(by: scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            distance = clampedDistance(distance / Float(scale))
        }
        guard translation != .zero else { return }
        let unitsPerPoint = ModelSceneController.frustumHeight(at: distance * distanceFit) / Float(max(1, size.height))
        let right = SIMD3<Float>(cos(azimuth), 0, -sin(azimuth))
        let up = simd_cross(ModelSceneController.cameraDirection(angle: azimuth, height: elevation), right)
        target += (up * Float(translation.dy) - right * Float(translation.dx)) * unitsPerPoint
    }

    private func adjustSeparation(by scale: CGFloat) {
        guard canAdjustSeparation else { return }
        let change = log(Double(scale)) * 1.25
        if mode != .exploded {
            guard change > 0 else { return }
            separation = 0
            changeMode(.exploded, animated: false)
        }
        separation = min(1, max(0, separation + change))
        if separation == 0, change < 0 {
            changeMode(availableModes.contains(modeBeforeSplit) ? modeBeforeSplit : .exterior, animated: false)
            separation = Self.defaultSeparation
        }
    }

    private func header(isWide: Bool, shortStage: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AtlasTypography.font(shortStage ? .headline : isWide ? .title : .title2, weight: .bold))
                    .foregroundStyle(palette.stageInk)
                    .lineLimit(shortStage ? 1 : 2)
                    .minimumScaleFactor(shortStage ? 0.82 : 0.9)
                    .accessibilityAddTraits(.isHeader)
                if !shortStage {
                    Text(subtitle)
                        .font(AtlasTypography.font(isWide ? .subheadline : .footnote, weight: .semibold))
                        .foregroundStyle(palette.stageAccent)
                        .lineLimit(2)
                }
                if let part {
                    Label(part.label, systemImage: part.symbol)
                        .font(AtlasTypography.font(.callout, weight: .medium))
                        .foregroundStyle(palette.stageInk)
                        .lineLimit(shortStage ? 1 : 2)
                        .minimumScaleFactor(shortStage ? 0.82 : 0.9)
                }
            }
            .allowsHitTesting(false)
            .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
            Spacer(minLength: 3)
            Button {
                showGestures.toggle()
            } label: {
                Image(systemName: "hand.draw")
                    .frame(minWidth: 34, minHeight: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(.glass)
            .foregroundStyle(palette.stageInk)
            .accessibilityLabel("触控教程")
            .accessibilityIdentifier("model-gesture-help")
            .reportsModelControlFrame()
            Button {
                if isWide { animateWorkspace { showParts.toggle() } } else { partsSheet.toggle() }
            } label: {
                if isPhone {
                    Image(systemName: "sidebar.trailing")
                        .frame(minWidth: 34, minHeight: 34)
                        .contentShape(.rect)
                } else {
                    Label("部件", systemImage: "sidebar.trailing")
                        .font(AtlasTypography.font(.subheadline, weight: .semibold))
                        .frame(minHeight: 34)
                        .contentShape(.rect)
                }
            }
            .buttonStyle(.glass)
            .foregroundStyle(palette.stageInk)
            .accessibilityLabel(isWide && showParts ? "隐藏部件" : "显示部件")
            .accessibilityIdentifier("model-parts")
            .reportsModelControlFrame()
        }
    }

    private func tools(viewportHeight: CGFloat, distanceFit: Float, shortStage: Bool) -> some View {
        VStack(alignment: .leading, spacing: shortStage ? 5 : 9) {
            if shortStage {
                HStack(spacing: 6) {
                    modeButtons(labels: false)
                    Spacer(minLength: 0)
                    actions
                }
            } else {
                HStack(spacing: 6) {
                    if model.metersPerUnit > 0 {
                        let showsRuler = !measuring && mode != .exploded
                        ruler(viewportHeight: viewportHeight, distanceFit: distanceFit)
                            .opacity(showsRuler ? 1 : 0)
                            .accessibilityHidden(!showsRuler)
                    }
                    Spacer(minLength: 2)
                    actions
                }
                if isPhone {
                    ViewThatFits(in: .horizontal) {
                        modeButtons(labels: false, stacked: true)
                        ScrollView(.horizontal) {
                            modeButtons(labels: false, stacked: true)
                        }
                        .scrollIndicators(.hidden)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        modeButtons(labels: true)
                        modeButtons(labels: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.metersPerUnit > 0 {
            Button {
                if mode == .exploded { changeMode(.exterior) }
                measuring.toggle()
                measurePoints.removeAll()
            } label: {
                Label("测距", systemImage: measuring ? "ruler.fill" : "ruler")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(measuring ? Color.orange : palette.stageInk)
                    .contentShape(.rect)
            }
            .buttonStyle(.glass)
            .tint(measuring ? .orange : nil)
            .accessibilityIdentifier("model-measure")
            .reportsModelControlFrame()
        }
        Button {
            elevation = elevation > 1.3 ? 0.56 : 1.45
        } label: {
            Label("俯视", systemImage: "view.2d")
                .labelStyle(.iconOnly)
                .foregroundStyle(palette.stageInk)
                .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .tint(nil)
        .accessibilityIdentifier("model-top-view")
        .reportsModelControlFrame()
        Button {
            reset()
        } label: {
            Label("复位", systemImage: "arrow.counterclockwise")
                .labelStyle(.iconOnly)
                .foregroundStyle(palette.stageInk)
                .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .tint(nil)
        .accessibilityIdentifier("model-reset")
        .reportsModelControlFrame()
    }

    @ViewBuilder
    private func floatingModelControls(compact: Bool) -> some View {
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
                    separationControl(compact: compact)
                    splitZoomControl(compact: compact)
                }
                VStack(alignment: .leading, spacing: 7) {
                    separationControl(compact: compact)
                    splitZoomControl(compact: compact)
                }
            }
        } else if mode == .exploded {
            separationControl(compact: compact)
        } else if mode == .xray {
            transparencyControl(compact: compact)
        }
    }

    private func separationControl(compact: Bool) -> some View {
        modelSlider("拆分程度", caption: "拆分", symbol: ModelMode.exploded.symbol, value: $separation, interval: 0...1,
                    id: "model-separation", reading: separation.formatted(.percent.precision(.fractionLength(0))), compact: compact)
    }

    private func transparencyControl(compact: Bool) -> some View {
        modelSlider("外壳不透明度", caption: "外壳", symbol: ModelMode.xray.symbol, value: $transparency, interval: 0.05...0.85,
                    id: "model-opacity", reading: transparency.formatted(.percent.precision(.fractionLength(0))), compact: compact)
    }

    private func splitZoomControl(compact: Bool) -> some View {
        let limits = distanceLimits(for: .exploded)
        let maximum = Double(limits.upperBound)
        let logarithmicRange = log(maximum / Double(limits.lowerBound))
        let scale = Binding {
            min(1, max(0, log(maximum / Double(distance)) / logarithmicRange))
        } set: { position in
            distance = clampedDistance(Float(maximum * exp(-position * logarithmicRange)))
        }
        let reading = compact ? zoomPercent.formatted(.number.notation(.compactName)) : zoomPercent.formatted()
        return modelSlider("镜头缩放", caption: "缩放", symbol: "magnifyingglass", value: scale, interval: 0...1,
                           id: "model-split-zoom", reading: "\(reading)%", compact: compact)
    }

    private func modelSlider(
        _ title: String, caption: String, symbol: String, value: Binding<Double>, interval: ClosedRange<Double>,
        id: String, reading: String, compact: Bool
    ) -> some View {
        HStack(spacing: compact ? 5 : 7) {
            Group {
                if compact {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 13)
                } else {
                    Label(caption, systemImage: symbol)
                        .font(AtlasTypography.font(.footnote, weight: .semibold))
                        .fixedSize()
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            Slider(value: value, in: interval)
                .frame(minWidth: compact ? 48 : 72, maxWidth: compact ? 48 : 126, minHeight: 44)
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
                .reportsModelControlFrame()
            Text(reading)
                .font(compact ? .system(size: 12, weight: .medium, design: .monospaced) : AtlasTypography.font(.footnote).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.60)
                .frame(minWidth: compact ? 30 : 34, maxWidth: compact ? 32 : nil, alignment: .trailing)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .foregroundStyle(palette.stageInk)
        .tint(palette.stageAccent)
        .padding(.horizontal, compact ? 7 : 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay { Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1) }
                .allowsHitTesting(false)
        }
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
        .foregroundStyle(palette.stageInk)
        .background(palette.stage.opacity(0.94), in: .rect(cornerRadius: 7))
        .accessibilityLabel("近似比例尺 \(label)")
        .allowsHitTesting(false)
    }

    private func modeButtons(labels: Bool, stacked: Bool = false) -> some View {
        GlassEffectContainer(spacing: 5) {
            HStack(spacing: 4) {
                ForEach(availableModes) { candidate in
                    Button {
                        changeMode(candidate)
                    } label: {
                        Group {
                            if stacked {
                                VStack(spacing: 3) {
                                    Image(systemName: candidate.symbol)
                                    Text(candidate.rawValue)
                                        .font(AtlasTypography.font(.caption, weight: .medium))
                                        .fixedSize()
                                }
                                .frame(minWidth: 40, minHeight: 40)
                            } else if labels {
                                Label(candidate.rawValue, systemImage: candidate.symbol)
                                    .frame(minHeight: 30)
                            } else {
                                Label(candidate.rawValue, systemImage: candidate.symbol).labelStyle(.iconOnly)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.glass)
                    .font(AtlasTypography.font(.body, weight: .semibold))
                    .tint(mode == candidate ? palette.stageAccent : nil)
                    .buttonBorderShape(palette.isDark ? .roundedRectangle(radius: 9) : .capsule)
                    .accessibilityLabel(candidate.rawValue)
                    .accessibilityAddTraits(mode == candidate ? .isSelected : [])
                    .accessibilityIdentifier("model-mode-\(candidate.rawValue)")
                    .reportsModelControlFrame()
                }
            }
        }
    }

    private func inspector(compact: Bool = false, showsLivery: Bool = false) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 12 : palette.contentGap) {
                if showsLivery, let liveryName, let chooseLivery {
                    inspectorLivery(liveryName, choose: chooseLivery)
                }
                inspectorHeading("模型部件")
                VStack(spacing: 6) {
                    Button { select(nil) } label: {
                        partLabel("完整模型", symbol: "cube.transparent", selected: activePart == nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("part-overview")
                    ForEach(partRows(model.parts)) { row in
                        Button { select(row.id) } label: {
                            partLabel(row.part.label, symbol: row.part.symbol, selected: activePart == row.id, depth: row.depth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("part-\(row.id)")
                    }
                }
                if let part {
                    VStack(alignment: .leading, spacing: 9) {
                        inspectorHeading(part.label)
                        Text(part.detail)
                            .font(AtlasTypography.font(.subheadline))
                            .lineSpacing(3)
                        if let dimensions = part.sizeText {
                            Label(dimensions, systemImage: "ruler")
                                .font(AtlasTypography.font(.subheadline).monospacedDigit())
                                .foregroundStyle(palette.accent)
                        }
                        Toggle("仅显示此部件", isOn: $isolateSelection)
                            .font(AtlasTypography.font(.subheadline))
                            .accessibilityIdentifier("model-isolate")
                    }
                    .contentTransition(.opacity)
                }
                VStack(alignment: .leading, spacing: 7) {
                    inspectorHeading("模型资料")
                    Text(model.sourceNote)
                        .font(AtlasTypography.font(.subheadline))
                        .foregroundStyle(palette.muted)
                        .lineSpacing(3)
                }
            }
            .padding(compact ? 10 : palette.isDark ? 14 : 17)
        }
        .background(palette.surface)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
    }

    private func inspectorHeading(_ title: String) -> some View {
        Text(title)
            .font(AtlasTypography.font(.headline, weight: .bold))
            .accessibilityAddTraits(.isHeader)
    }

    private func inspectorLivery(_ name: String, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack(spacing: 8) {
                Label(name, systemImage: "paintpalette")
                    .font(AtlasTypography.font(.subheadline, weight: .semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(palette.selectionInk)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(palette.selection, in: .rect(cornerRadius: palette.corner))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更换涂装")
        .accessibilityValue(name)
        .accessibilityIdentifier("model-inspector-livery")
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

    private func partLabel(_ label: String, symbol: String, selected: Bool, depth: Int = 0) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(AtlasTypography.font(.subheadline, weight: .semibold))
                .foregroundStyle(selected ? palette.selectionInk : palette.muted)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(AtlasTypography.font(.body, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.selectionInk : palette.ink)
            Spacer(minLength: 2)
            Image(systemName: selected ? "checkmark" : "chevron.forward")
                .font(AtlasTypography.font(.caption, weight: .semibold))
                .foregroundStyle(selected ? palette.selectionInk : palette.muted)
                .accessibilityHidden(true)
        }
        .padding(.leading, CGFloat(depth * 14) + 10)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(selected ? palette.selection : palette.subtle, in: .rect(cornerRadius: palette.corner))
        .overlay {
            RoundedRectangle(cornerRadius: palette.corner)
                .strokeBorder(selected ? Color.clear : palette.line)
                .allowsHitTesting(false)
        }
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
        animateWorkspace { setSelection(id) }
    }

    private func setSelection(_ id: String?) {
        activePart = id
        if !availableModes.contains(mode) { mode = .exterior }
        measurePoints.removeAll()
        target = part?.focus ?? model.overviewTarget
        distance = clampedDistance(part?.focusDistance ?? model.overviewDistance)
    }

    private func changeMode(_ newMode: ModelMode, animated: Bool = true) {
        guard mode != newMode else { return }
        if animated {
            animateWorkspace { setMode(newMode) }
        } else {
            setMode(newMode)
        }
    }

    private func setMode(_ newMode: ModelMode) {
        if newMode == .exploded {
            modeBeforeSplit = mode
            measuring = false
        }
        mode = newMode
        if expandsSplitZoom { distance = clampedDistance(distance, for: newMode) }
        measurePoints.removeAll()
    }

    private func toggleMode(_ targetMode: ModelMode) {
        guard !measuring, availableModes.contains(targetMode) else { return }
        changeMode(mode == targetMode ? .exterior : targetMode)
    }

    private func reset() {
        animateWorkspace {
            mode = .exterior
            measuring = false
            isolateSelection = true
            separation = Self.defaultSeparation
            azimuth = -0.53
            elevation = 0.56
            setSelection(nil)
        }
    }

    private func animateWorkspace(_ changes: () -> Void) {
        guard !reduceMotion else {
            changes()
            return
        }
        withAnimation(.easeInOut(duration: 0.30)) {
            sceneTransition &+= 1
            changes()
        }
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

private struct ModelControlFrames: PreferenceKey {
    static let space = "model-stage-controls"
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    func reportsModelControlFrame() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: ModelControlFrames.self,
                    value: [geometry.frame(in: .named(ModelControlFrames.space))])
            }
            .allowsHitTesting(false)
        }
    }
}

private struct ModelTouchSurface: UIViewRepresentable {
    static func canvasFrame(in bounds: CGRect, bottomHUDClearance: CGFloat) -> CGRect {
        let horizontalInset = min(72, bounds.width * 0.12)
        let topInset = min(124, bounds.height * 0.18)
        let bottomInset = min(bounds.height * 0.50, max(topInset, bottomHUDClearance))
        return CGRect(
            x: bounds.minX + horizontalInset, y: bounds.minY + topInset,
            width: bounds.width - 2 * horizontalInset, height: bounds.height - topInset - bottomInset
        )
    }

    let zoomLabel: String
    let gestureHint: String
    let bottomHUDClearance: CGFloat
    let controlFrames: [CGRect]
    let canToggleTransparency: Bool
    let canToggleSection: Bool
    let tap: (CGPoint, CGSize) -> Void
    let orbit: (CGVector) -> Void
    let transform: (CGVector, CGFloat, CGSize) -> Void
    let adjustZoom: (Float) -> Void
    let toggleTransparency: () -> Void
    let toggleSection: () -> Void
    let adjustSeparation: (CGFloat) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.isMultipleTouchEnabled = true
        view.isOpaque = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "model-viewport"
        view.accessibilityLabel = "三维模型"
        view.accessibilityTraits = .adjustable
        view.installTapRecognizers()
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.onTap = tap
        view.onOrbit = orbit
        view.onTransform = transform
        view.onAdjustZoom = adjustZoom
        view.onToggleTransparency = toggleTransparency
        view.onToggleSection = toggleSection
        view.onAdjustSeparation = adjustSeparation
        view.bottomHUDClearance = bottomHUDClearance
        view.controlFrames = controlFrames
        view.accessibilityValue = zoomLabel
        view.accessibilityHint = gestureHint
        if view.transparencyTap.isEnabled != canToggleTransparency { view.transparencyTap.isEnabled = canToggleTransparency }
        if view.sectionTap.isEnabled != canToggleSection { view.sectionTap.isEnabled = canToggleSection }
    }

    final class TouchView: UIView {
        var onTap: ((CGPoint, CGSize) -> Void)?
        var onOrbit: ((CGVector) -> Void)?
        var onTransform: ((CGVector, CGFloat, CGSize) -> Void)?
        var onAdjustZoom: ((Float) -> Void)?
        var onToggleTransparency: (() -> Void)?
        var onToggleSection: (() -> Void)?
        var onAdjustSeparation: ((CGFloat) -> Void)?
        var bottomHUDClearance: CGFloat = 0
        var controlFrames: [CGRect] = []

        private(set) lazy var transparencyTap = makeRecognizer(taps: 2, action: #selector(didTapTransparency))
        private(set) lazy var sectionTap = makeRecognizer(taps: 2, touches: 2, action: #selector(didTapSection))

        func installTapRecognizers() {
            let select = makeRecognizer(taps: 1, action: #selector(didTap(_:)))
            select.require(toFail: transparencyTap)
            addGestureRecognizer(select)
            addGestureRecognizer(transparencyTap)
            addGestureRecognizer(sectionTap)
        }

        private func makeRecognizer(taps: Int, touches: Int = 1, action: Selector) -> UITapGestureRecognizer {
            let tap = UITapGestureRecognizer(target: self, action: action)
            tap.cancelsTouchesInView = false
            tap.delaysTouchesEnded = false
            tap.numberOfTapsRequired = taps
            tap.numberOfTouchesRequired = touches
            return tap
        }

        @objc private func didTap(_ recognizer: UITapGestureRecognizer) {
            onTap?(recognizer.location(in: self), bounds.size)
        }

        @objc private func didTapTransparency() { onToggleTransparency?() }
        @objc private func didTapSection() { onToggleSection?() }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            super.point(inside: point, with: event) && !controlFrames.contains { $0.contains(point) }
        }

        override var accessibilityFrame: CGRect {
            get {
                // Describe the unobstructed canvas separately from its surrounding buttons.
                let canvas = ModelTouchSurface.canvasFrame(in: bounds, bottomHUDClearance: bottomHUDClearance)
                return UIAccessibility.convertToScreenCoordinates(canvas, in: self)
            }
            set { super.accessibilityFrame = newValue }
        }

        override func accessibilityIncrement() { onAdjustZoom?(1.2) }
        override func accessibilityDecrement() { onAdjustZoom?(1 / 1.2) }

        private var fingers: Set<UITouch> = []
        private var movement = ModelTouchMovement()

        private var contactPoints: [CGPoint] { fingers.map { $0.location(in: self) } }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            fingers.formUnion(touches)
            movement.contactsChanged(contactPoints)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let change = movement.move(contactPoints) else { return }
            switch change {
            case .orbit(let translation):
                onOrbit?(translation)
            case .transform(let translation, let scale):
                onTransform?(translation, scale, bounds.size)
            case .separation(let scale):
                onAdjustSeparation?(scale)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        private func finish(_ touches: Set<UITouch>) {
            fingers.subtract(touches)
            movement.contactsChanged(contactPoints)
        }
    }
}

@MainActor
private final class ModelSceneController: ObservableObject {
    private struct CameraPose: Equatable {
        let target: SIMD3<Float>
        let angle: Float
        let height: Float
        let distance: Float
        let centerLift: Float
    }

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
    private static let transitionDuration: TimeInterval = 0.30
    private let cameraOrbit = Entity()
    private let camera = PerspectiveCamera()
    private let marks = Entity()
    private let ground: ModelEntity?
    private var groundOpacity: Float = 1
    private let model: AtlasModel
    let orderedParts: [AtlasPart]
    private let origins: [String: SIMD3<Float>]
    private let entities: [String: AtlasPart]
    private var lastPose: CameraPose?
    private var lastConfiguration: Configuration?
    private var lastTransition: Int?
    private var animatedEntities: Set<ObjectIdentifier> = []

    init(model: AtlasModel, expandsSplitZoom: Bool) {
        self.model = model
        ground = AtlasModelStage.make(for: model)
        let parts = model.parts.flatMap(\.hierarchy)
        orderedParts = parts
        origins = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0.entity.position) })
        entities = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0) })
        for part in parts { part.entity.name = part.id }
        let farDistance = model.overviewDistance * (expandsSplitZoom ? 24 : 16)
        camera.camera = PerspectiveCameraComponent(near: 0.005, far: farDistance, fieldOfViewInDegrees: Self.fov, fieldOfViewOrientation: .vertical)
        if let ground { world.addChild(ground) }
        world.addChild(model.root)
        cameraOrbit.addChild(camera)
        world.addChild(cameraOrbit)
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

    func consumeTransition(_ transition: Int, reduceMotion: Bool) -> Bool {
        defer { lastTransition = transition }
        return !reduceMotion && lastTransition != nil && lastTransition != transition
    }

    func moveCamera(to point: SIMD3<Float>, angle: Float, height: Float, distance: Float,
                    centerLift: Float, dimGround: Bool, animated: Bool) {
        let direction = Self.cameraDirection(angle: angle, height: height)
        let screenUp = simd_cross(direction, SIMD3<Float>(cos(angle), 0, -sin(angle)))
        let lift = Self.frustumHeight(at: distance) * centerLift
        let cameraPosition = point - screenUp * lift + direction * distance
        let pose = CameraPose(target: point, angle: angle, height: height, distance: distance, centerLift: centerLift)
        if lastPose != pose {
            // Orbit around the focus so a reset across the model never takes a path through it.
            let rotation = simd_quatf(angle: angle, axis: [0, 1, 0]) * simd_quatf(angle: -height, axis: [1, 0, 0])
            let orbitTransform = Transform(scale: .one, rotation: rotation, translation: point)
            var cameraTransform = Transform()
            cameraTransform.translation = [0, -lift, distance]
            place(cameraOrbit, at: orbitTransform, animated: animated)
            place(camera, at: cameraTransform, animated: animated)
            lastPose = pose
        }
        if let ground {
            let fadeHeight = max(0.04, model.overviewDistance * 0.028)
            let visibility = min(1, max(0, (cameraPosition.y - ground.position.y) / fadeHeight))
            let opacity = (dimGround ? Float(0.30) : 1) * visibility * visibility * (3 - 2 * visibility)
            if abs(opacity - groundOpacity) > 0.008 {
                groundOpacity = opacity
                ground.isEnabled = opacity > 0.008
                ground.components.set(OpacityComponent(opacity: opacity))
            }
        }
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

    func update(partID: String?, mode: ModelMode, isolated: Bool, spread: Float, opacity: Float,
                points: [SIMD3<Float>], animated: Bool) {
        let next = Configuration(partID: partID, mode: mode, isolated: isolated, spread: spread, opacity: opacity, points: points)
        let previous = lastConfiguration
        guard next != previous else { return }
        if points != previous?.points { draw(points: points) }
        lastConfiguration = next

        let visibilityChanges = partID != previous?.partID || mode != previous?.mode || isolated != previous?.isolated
        let positionChanges = (mode == .exploded || previous?.mode == .exploded)
            && (visibilityChanges || spread != previous?.spread)
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
                var transform = part.entity.transform
                transform.translation = origin + offset
                place(part.entity, at: transform, animated: animated)
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

    private func place(_ entity: Entity, at transform: Transform, animated: Bool) {
        let id = ObjectIdentifier(entity)
        if animatedEntities.remove(id) != nil {
            let current = entity.transform
            entity.stopAllAnimations(recursive: false)
            if animated { entity.transform = current }
        }
        if animated {
            animatedEntities.insert(id)
            entity.move(to: transform, relativeTo: entity.parent, duration: Self.transitionDuration, timingFunction: .easeInOut)
        } else {
            entity.transform = transform
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
