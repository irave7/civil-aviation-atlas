# 民航图鉴

面向 iPhone 和 iPad 的机场、客机和航线图鉴，最低支持 iOS 26 和 iPadOS 26。使用 SwiftUI、MapKit 和 RealityKit。

- 标准构建从地球进入。默认显示民航运输机场，可独立开启直升机场和其他机场，点选后进入三维场景。
- 标准构建的机场页包含三维场区、实景、平面图及航线资料。双指可旋转平面图。场区建模精度取决于各机场的公开资料。
- 三维视图支持旋转、缩放、拆分和部件选择。双指竖向拉开进入拆分。支持内部结构的模型可单指双击切换透视，双指双击切换剖视。
- 航线和航班详情在应用内展示，实时情况以受支持的官方来源为限。距离为大圆距离，置顶最远航线以收录范围为限。航线探索支持国内与全球航程、客机外部三维、互动操纵、观测风速、预设气流、设备中文朗读与本机自定义涂装。关联实景与公开航班观测随构建和资料覆盖提供。
- 大陆审查配置提供离线机场目录、航线探索和客机三维查看。正式发布的备案、地图及数据授权事项见[中国大陆 App Store 发布手册](docs/mainland-release.md)。

## 构建与校验

在 Xcode 中打开 `AirportAtlas.xcodeproj`，选择 `AirportAtlas` 或 `AirportAtlasMainlandReview` scheme，以及 iPhone 或 iPad 模拟器。

```sh
./Build/build.sh simulator
python3 Build/check-data.py
python3 Build/prepare-mainland-catalog.py --check
```

用 `xcrun simctl list devices available` 查询模拟器 UUID，再运行 `./Build/build.sh test SIMULATOR_UUID`。设备打包使用归档命令，发布由拥有相应团队权限的账号完成。

## 版本记录

以 `main` 的提交记录为准。发布记录应对应应用版本、构建号、验证结果和实际分发状态。

| 应用版本 | 主要更新 |
| --- | --- |
| 1.2 (8) | iPhone 和 iPad 通用构建、触控改进、3D 场景、飞机与机场细节、原生航班详情、航线探索及中国大陆 App Store 审查配置。使用 iOS/iPadOS 27.2 模拟器验收并生成两份开发签名预览包。尚未提交分发。 |
| 1.1 (7) | 全宽地球入口、机场点击直达 3D、实景回退、客机拆分镜头范围、航班动态入口和已收录最远航线。2026-11-22 已取得 TestFlight 仅内部测试上传回执。 |
| 1.1 (6) | 中英文名称检索、本机收藏、独立涂装和客舱选择 |

## 数据与素材

机场和航线资源随应用分发，实时影像与航班看板来自在线服务。逐数据集授权和署名见 [NOTICE.md](NOTICE.md)。本仓库公开可读，应用代码与第三方数据各自适用相应权利条款。
