import SwiftUI

struct AtlasPrivacyPane: View {
    let favorites: AtlasFavorites
    @State private var confirmsClear = false

    var body: some View {
        List {
            Section("资料与权限") {
                Text("浏览图鉴无需注册或登录。应用不包含广告、跨应用追踪或运营方分析服务，也不会请求设备定位、相机、麦克风、通讯录或照片库权限。")
                Text("搜索在设备上执行。机场与客机收藏、自定义涂装保存在设备上。应用提供本机收藏清除功能，设备备份由系统设置管理。")
            }
            Section("在线服务") {
                if DistributionPolicy.mapsAvailable {
                    Text("地图通过 Apple MapKit 请求当前显示区域的资料。选取机场使用目录中的机场资料。Apple 地图会按其隐私说明处理服务请求。")
                    Link("Apple 地图与隐私", destination: URL(string: "https://www.apple.com.cn/legal/privacy/data/zh-cn/apple-maps/")!)
                }
                if DistributionPolicy.mapsAvailable && !DistributionPolicy.isMainlandReview {
                    Text("境外机场的历史卫星影像通过 EOX 加载瓦片。影像提供方会收到所显示区域和访问所需的网络信息。")
                }
                if DistributionPolicy.liveFlightsAvailable {
                    Text("查询航班动态或历史记录时，机场或数据提供方会收到查询所需的机场、日期或方向，以及访问所需的网络信息。")
                    Text("在航线探索中主动读取观测时，NOAA 会收到两端机场代码，adsb.lol 可能收到资料中的航班呼号。服务提供方也会收到访问所需的网络信息。")
                }
                Text("点按外部资料链接时会打开相应网站，网站按其自身规则处理访问。")
            }
            Section("本机收藏") {
                Button("清除本机收藏", role: .destructive) { confirmsClear = true }
                    .disabled(favorites.airportIDs.isEmpty && favorites.aircraftIDs.isEmpty)
                    .accessibilityIdentifier("privacy-clear-favorites")
            }
            if DistributionPolicy.privacyPolicyURL != nil || DistributionPolicy.supportURL != nil || DistributionPolicy.icpRecordNumber != nil {
                Section("政策与支持") {
                    if let link = DistributionPolicy.privacyPolicyURL { Link("隐私政策", destination: link) }
                    if let link = DistributionPolicy.supportURL { Link("联系与反馈", destination: link) }
                    if let number = DistributionPolicy.icpRecordNumber {
                        Link(number, destination: DistributionPolicy.icpLookupURL)
                            .accessibilityLabel("APP 备案号 \(number)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("atlas-privacy")
        .alert("清除本机收藏？", isPresented: $confirmsClear) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { favorites.clear() }
        } message: {
            Text("此操作会删除当前设备上的机场及客机收藏。")
        }
    }
}
