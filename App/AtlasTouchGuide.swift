import SwiftUI

@MainActor
struct AtlasTouchGuide: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    private var palette: AtlasPalette { AtlasPalette(scheme, contrast: contrast) }

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 640 && !typeSize.isAccessibilitySize
            let cards = sideBySide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                : AnyLayout(VStackLayout(spacing: 12))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    heading("操作 3D 模型", size: .title)
                    Text("让手指同时落在模型画布上，再张开或捏合。")
                        .foregroundStyle(palette.muted)
                    cards {
                        zoomCard
                        splitCard
                    }
                    otherGestures
                        .padding(.top, 8)
                    controls
                        .padding(.top, 8)
                }
                .atlasReadingWidth()
            }
            .accessibilityIdentifier("gesture-guide")
        }
        .background(palette.page)
    }

    private var otherGestures: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("旋转、平移与观察", size: .title3)
            VStack(alignment: .leading, spacing: 14) {
                instruction("单指拖动", detail: "环绕模型旋转。", symbol: "rotate.right")
                instruction("双指同向拖动", detail: "平移画面。", symbol: "arrow.up.and.down.and.arrow.left.and.right")
                instruction("单指双击", detail: "在支持的模型中切换透视。", symbol: "eye")
                instruction("双指双击", detail: "在支持的模型中切换剖视。", symbol: "rectangle.split.2x1")
            }
            .padding(16)
            .atlasPanel(palette)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("使用屏幕控件", size: .title3)
            instruction("飞行模拟 · 机外", detail: "在飞机周围双指张开或捏合，可以拉近或拉远跟拍镜头。点右上角的倍率可恢复标准视距。", symbol: "camera.viewfinder")
            instruction("拆分与缩放", detail: "点按「拆分」后可用滑杆调整部件间距，客机还可用滑杆缩放镜头。结束测距后可使用三指拆分。", symbol: "slider.horizontal.3")
            instruction("模拟飞行的机外视角", detail: "双指张开可拉近跟拍镜头，捏合可拉远。点按右上角的倍率即可恢复标准视距。", symbol: "viewfinder")
            if DistributionPolicy.airportSiteModelsAvailable && DistributionPolicy.mapsAvailable {
                instruction("机场平面图", detail: "双指捏合或张开缩放，双指转动可调整平面图方向。", symbol: "map")
            }
        }
    }

    private var zoomCard: some View {
        gestureCard("双指缩放", detail: "张开放大，捏合缩小。拆分时仍可用双指缩放镜头。",
                    id: "gesture-guide-zoom", threeFingers: false)
    }

    private var splitCard: some View {
        gestureCard("三指拆分与合并", detail: "张开拆分部件，捏合收拢。完全合并后回到拆分前的视图。",
                    id: "gesture-guide-split", threeFingers: true)
    }

    private func gestureCard(_ title: String, detail: String, id: String, threeFingers: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            gestureDiagram(threeFingers: threeFingers)
            heading(title, size: .title3)
                .accessibilityIdentifier(id)
            Text(detail)
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .atlasPanel(palette)
    }

    private func gestureDiagram(threeFingers: Bool) -> some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: threeFingers ? "arrow.up.left" : "arrow.left")
                touchPoint
                touchPoint
                Image(systemName: threeFingers ? "arrow.up.right" : "arrow.right")
            }
            .offset(y: threeFingers ? -15 : 0)
            if threeFingers {
                VStack(spacing: 3) {
                    touchPoint
                    Image(systemName: "arrow.down")
                }
                .offset(y: 14)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(palette.stageAccent)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(palette.stage, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private var touchPoint: some View {
        Circle()
            .fill(palette.stageAccent)
            .frame(width: 11, height: 11)
    }

    private func heading(_ title: String, size: Font.TextStyle) -> some View {
        Text(title)
            .font(AtlasTypography.font(size, weight: .bold))
            .foregroundStyle(palette.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func instruction(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AtlasTypography.font(.headline))
                    .foregroundStyle(palette.ink)
                Text(detail)
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
