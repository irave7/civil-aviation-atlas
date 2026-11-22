# 数据与素材署名

- 机场及跑道基础资料采用 [OurAirports](https://ourairports.com/data/) 的公有领域数据。相关机场名还使用了 [Wikidata](https://www.wikidata.org/wiki/Wikidata:Licensing) 的 CC0 数据及 [GeoNames](https://www.geonames.org/export/) 的 CC BY 4.0 数据。图鉴进行了匹配、译名补充与筛选。
- 场区和建筑轮廓包含 © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright) 和 [Overture Maps Foundation](https://docs.overturemaps.org/attribution/) 的 [ODbL 数据库内容](https://opendatacommons.org/licenses/odbl/1-0/)。数据经过选区、分类和坐标转换。东亚建筑轮廓还使用 Qian Shi 等的 [East Asian Buildings](https://doi.org/10.5281/zenodo.8174931)，按 CC BY 4.0 经 Overture Maps 提供。
- 香港国际机场 T1 外部模型依据[香港特别行政区政府地政总署可视化三维地图（单体化模型）](https://data.gov.hk/en-data/dataset/hk-landsd-openmap-3d-visualisation-map-individualised-models)，经 DATA.GOV.HK 提供。资料所有权属地政总署。图鉴转换了坐标并应用自制材质。[开放数据平台使用条款](https://data.gov.hk/sc/terms-and-conditions)
- 香港机场两张实景照片来自 Wikimedia Commons。作者为 [LN9267，T1 外部](https://commons.wikimedia.org/wiki/File:Hong_Kong_International_Airport_Terminal_1_20-12-2025.jpg) 和 [Windmemories，T1 内部](https://commons.wikimedia.org/wiki/File:20250222_Interior_of_Terminal_1,_HKG.jpg)。图片经过缩放或压缩，按 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 提供。
- 随包中文字体为 Noto Sans CJK SC Regular 子集，适用 SIL Open Font License 1.1。完整声明见 [字体许可证](App/Resources/AtlasFallbackChinese-LICENSE.txt)。
- 场址高程为 [Mapzen Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) 的采样结果。各底层数据源的署名和采样方法见 [机场场址高程数据](App/Resources/airport-site-terrain.json) 与 [Tilezen 高程署名说明](https://github.com/tilezen/joerd/blob/master/docs/attribution.md)。
- 统计航线数据的 11 个上游机构、各统计期及许可见 [observed-routes.json](App/Resources/observed-routes.json) 的 `sources`。其中部分数据经 AirportMiles 整理，图鉴再次匹配机场、筛选记录及计算大圆距离。[AirportMiles 来源](https://airportmiles.com/sources) · [再利用条款](https://airportmiles.com/api#licence-and-fair-use)
- 探索模式使用公开机场间大圆距离。国内精选机场对依据[中国国际航空公开航点示例](https://webresource.airchina.com.cn/zh-CN/content/marketing/yxhdymjh/2025scck/)，用途为资料演示，不代表当前可售班表。
- Apple 卫星影像通过 MapKit 在线访问。境外机场的首选历史影像为 [EOxCloudless](https://cloudless.eox.at/) © EOX IT Services GmbH，包含经修改的 Copernicus Sentinel 2016 及 2017 数据，适用 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。影像瓦片随在线视图请求。
- 标准构建的航程观测由用户主动发起。机场风况来自 [NOAA 航空气象中心 METAR API](https://aviationweather.gov/data/api/)。符合条件的航班呼号从 [adsb.lol](https://www.adsb.lol/docs/open-data/api) 查询，公开信号适用 [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/)，覆盖和观测时间按来源显示。
