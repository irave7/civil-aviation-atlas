# 民航图鉴中国大陆 App Store 发布手册

候选版本为 1.2（11），在现有 `com.aerodromeatlas.ipad` 应用记录下原生支持 iPhone 和 iPad，最低系统为 iOS 26 和 iPadOS 26。本候选版本尚未提交 App Store 审核。以下手续与验证由发布负责人在正式提交前留存结果。

## 1. 确认提交范围

- `AirportAtlasMainlandReview` scheme 使用 `MainlandReview` 配置。此候选版本提供机场目录和资料、原生航班资料页、收录的历史航线及其来源、客机三维查看和拆分，以及本机收藏。历史最远航线按收录数据及统计期显示，距离按应用内口径说明。首发采用无地图元素的图标。
- 航线探索属于应用内离线导览。可核对的航司机型使用图鉴客机模型和参考涂装，用户可模拟机头姿态和起落架，三种预制合成语音随包离线播放，播放和选择界面标明 AI 配音。可选系统朗读与自定义涂装均在本机处理。当前时刻查询、航空气象、ADS-B 和机场实景不进入大陆审查功能。按实际交互和商店类别向发布审核方确认出版与其他额外要求。
- 此配置停用地球、地图、机场实景和场区三维场景，也停用实时航班接口和动态跳转。带精确坐标的目录、跑道和场区布局、高程及机场影像资源由打包配置排除。发布时核对目录、航线、客机模型和涂装的数据来源、授权及归属声明。截图和商店文案应展示此构建可操作的功能。[数据与素材署名](../NOTICE.md)
- App Store Connect 针对同一 App 的 iOS 平台版本选择一个构建。销售范围调整的是各地区商店的供应情况。发布负责人须确认正式版本的共同功能范围和地区供应安排。同一版本选用本候选构建时，启用的其他地区也收到该构建。[Apple 构建选择](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit) · [Apple 地区供应范围](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/)

## 2. 准备真实的运营资料

| 负责人 | 提交前应保留的凭据和操作 |
| --- | --- |
| 实际运营主体 | 核对 App Store Connect 的开发者记录、运营主体、App 展示名及 Bundle ID。由主体向接入服务商和属地通信管理局确认本次离线功能、对外支持网页以及后续在线功能的 APP 备案适用性。适用时先取得可查询的本 App 备案号，在 App Store Connect 的简体中文 App 信息填报与备案一致的编号及元数据，并在应用显著位置展示编号及备案查询链接。留存核验结果。 [工信部 APP 备案通知](https://www.miit.gov.cn/zwgk/zcwj/wjfb/tz/art/2023/art_920db564162e4312916a01bed6540ad8.html) · [Apple 中国大陆供应信息](https://developer.apple.com/cn/help/app-store-connect/reference/app-information/app-information/) |
| 实际运营主体 | 发布由主体控制、适用地区可直接访问的 HTTPS 隐私政策及支持页面。政策注明运营者及联系方式、实际处理目的与方式、信息项目、保存期限、第三方、退出和权利请求途径。支持页面提供可工作的反馈渠道。在中国大陆网络上验证访问与反馈流程。 [个人信息保护法](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm) · [Apple App Review 指南](https://developer.apple.com/app-store/review/guidelines/) |
| Apple 发布负责人 | 核对团队角色、协议状态及收款计划。按 App Store Connect 提示完成适用的主体/税务信息。若引入付费下载或 App 内数字内容收费，完成对应付费协议、税务和银行资料，并按 Apple 规则配置购买。按实际内容核对类别、年龄分级和是否触发额外许可。 [Apple 国务院令第 810 号信息](https://developer.apple.com/cn/help/app-store-connect/manage-compliance-information/manage-information-for-state-council-decree-no-810/) · [Apple 付费 App 协议](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/) · [Apple App Review 指南](https://developer.apple.com/app-store/review/guidelines/) |

运营者公布正式页面后，在 `Build/ReleaseIdentity.local.xcconfig` 配置 `ATLAS_PRIVACY_POLICY_URL`、`ATLAS_SUPPORT_URL` 和适用的 `ATLAS_ICP_RECORD_NUMBER`。以 Xcode 实际解析的 HTTPS 值及打包后的 `AtlasPrivacyPolicyURL`、`AtlasSupportURL`、`AtlasICPRecordNumber` 为准。确认 App 内链路可达、备案号及查询链接实际展示、Connect 填报匹配。该文件与签名、账号、税务和联系人资料保存在公开仓库之外。ICP备案系统见[工信部备案查询](https://beian.miit.gov.cn/)。

## 3. 核验资料与隐私

- 建立最终 `.app` 的资源清单，按目录名称、来源、版本/统计期、许可范围和署名逐项对照。有第三方航司涂装、商标、照片、三维模型或重分发的数据时，保留授权依据与必要署名；权利暂不能核实的条目先从候选包和商店截图移除。机场来源和风险范围随资料更新复核。 [Apple App Review 指南第 5.2 节](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)
- 地图或实景后续进入大陆发布范围前，核验提供方资质、许可范围、实际图层、审图适用性、审图号及展示位置。另行核查自有机场点位、航线叠加、投影图标、地理场景和商店截图。供应商底图的核验材料应与上架时实际使用的图层和新增内容对应。 [自然资源部与工信部关于 APP 地图的通知](https://hnca.miit.gov.cn/zwgk/tzgg/tz/art/2024/art_270c90866b994bb69a020ce812de6278.html)
- 使用中国大陆网络在真机检查冷启动、搜索、机场、航线、客机和收藏的实际网络行为。确认收藏持久化和清除、自定义涂装只在设备保存、应用内隐私入口、外部链接的按需跳转，以及归档中的 `PrivacyInfo.xcprivacy`。按最终构建和运营方及第三方处理方式填写 App Store Connect「App 隐私」，其中包括实际保留或可关联的访问、支持资料。当前应用无需注册，无运行时生成式 AI、用户发布内容或设备定位请求。若后续引入在线服务，发布前核对大陆可达性、商业显示和再分发权、接收方及网络日志，按实际处理复核告知、同意及数据出境义务。 [Apple 隐私申报](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/) · [Apple 隐私清单](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) · [个人信息保护法](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm) · [促进和规范数据跨境流动规定](https://www.cac.gov.cn/2024-03/22/c_1712776611775634.htm)
- 后续评估 Avinor 官方动态时，按提供者建议评估服务端缓存、查询频率和署名，并确认新的数据链路及其合规要求。香港机场管理局的开放航班资料更新至上一自然日，应继续标明历史数据时间范围。 [Avinor 航班数据说明](https://partner.avinor.no/en/services/flight-data/) · [香港机场管理局开放航班资料](https://data.gov.hk/sc-data/dataset/aahk-team1-flight-info)
- 若有离线生成或合成的文案、视觉素材或三维内容，记录来源及处理过程并按实际分发职责核对标识要求。新增面向公众的生成、传播或用户发布功能时，重新评估适用义务。 [生成式人工智能服务管理暂行办法](https://www.cac.gov.cn/2023-07/13/c_1690898327029107.htm) · [人工智能生成合成内容标识办法](https://www.cac.gov.cn/2025-03/14/c_1743654684782215.htm)
- 若把离线航线导览纳入候选版，需用实机验证预置路线示意、离线预制合成语音和可选的系统朗读。导览范围限于应用内置路线，用户无需录入或发布路线，也不需要生成式 AI 服务。按最终交互方式、玩法和商店分类向 Apple 及主管部门核验类别和许可。实际分类涉及中国大陆网络游戏时，按 Apple 中国大陆供应要求提交网络游戏出版物号等材料。 [Apple 中国大陆供应信息](https://developer.apple.com/cn/help/app-store-connect/reference/app-information/app-information/)

## 4. 构建、验收并送审

在仓库根目录执行资料校验并构建候选配置。通过 `xcrun simctl list devices available` 找到可用的 iPhone 和 iPad 模拟器，用 Xcode 的同一 scheme 分别运行测试。本次模拟器覆盖 iOS / iPadOS 27.2。最低系统为 26，正式发布前补测该系统的真机。

```sh
python3 Build/check-data.py
python3 Build/prepare-mainland-catalog.py --check
xcodebuild -project AirportAtlas.xcodeproj -scheme AirportAtlasMainlandReview \
  -configuration MainlandReview -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

1. 真机验证 iPhone 和 iPad 的横竖屏、窄屏导航、动态字体、VoiceOver、客机平移旋转及多指缩放拆分、离线目录、原生航班资料页、收藏重启持久化及清除。在断网和中国大陆常用网络下浏览核心内容。记录候选构建默认无应用发起的第三方航班、地图和实景请求，来源网页、正式隐私及支持页按用户点按打开。
2. 用 `AirportAtlasMainlandReview` 在 Xcode Organizer 创建由授权团队签名的 iOS 设备归档，也可在设置 `ATLAS_DEVELOPMENT_TEAM` 后运行 `./Build/build.sh mainland-archive-signed`。使用 `./Build/verify-device-product.sh Build/.products/AirportAtlas-MainlandReview.xcarchive --require-signed` 校验默认输出路径下的归档，核对发布信息和资源清单。正式 App Store 审核选用具备 App Store 分发资格的构建。
3. 在 App Store Connect 准备简体中文名称、描述、iPhone/iPad 截图、支持和隐私网址、年龄分级、版权和出口合规。审核备注写明离线入口、客机拆分和收藏清除步骤，以及实际采用的第三方内容和授权材料。使用已有的审核联系人前核对其当前可用性，将必要附件直接提交给 Apple。 [Apple 审核信息](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/)
4. 保留真机验证、审核资料、归档校验、上传处理回执和地区供应范围。审核通过后核对实际选用的构建与地区，再按选定的发布方式上线。将实测和分发状态记录到版本日志。
