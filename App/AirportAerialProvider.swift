#if !MAINLAND_DISTRIBUTION
import Foundation

enum AirportAerialProvider: String, Sendable {
    case usgs = "美国 · USGS 正射影像"
    case gsi = "日本 · 国土地理院航空影像"
    case ign = "法国 · IGN BD ORTHO"
    case pnoa = "西班牙 · PNOA 正射影像"
    case pdok = "荷兰 · PDOK 高清航空影像"
    case swisstopo = "瑞士 · SWISSIMAGE"

    static func covering(_ airport: Airport) -> Self? {
        guard airport.lat.isFinite, airport.lon.isFinite else { return nil }
        return switch airport.countryCode {
        // USGS's contiguous-U.S. NAIP contribution is public-domain. Other regions' imagery has separate rights.
        case "US" where (24...50).contains(airport.lat) && (-125 ... -66).contains(airport.lon): .usgs
        case "JP": .gsi
        case "FR": .ign
        case "ES": .pnoa
        case "NL": .pdok
        case "CH": .swisstopo
        default: nil
        }
    }

    var attribution: (title: String, url: URL) {
        switch self {
        case .usgs:
            ("USDA · USGS The National Map", URL(string: "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer")!)
        case .gsi:
            ("国土地理院 · 地理院タイル", URL(string: "https://maps.gsi.go.jp/development/ichiran.html")!)
        case .ign:
            ("© IGN France · BD ORTHO", URL(string: "https://cartes.gouv.fr/rechercher-une-donnee/dataset/IGNF_BD-ORTHO")!)
        case .pnoa:
            ("© Instituto Geográfico Nacional de España · PNOA", URL(string: "https://pnoa.ign.es/pnoa-imagen/visualizadores-y-servicios-web")!)
        case .pdok:
            ("Samenwerkingsverband Beeldmateriaal · PDOK · CC BY 4.0", URL(string: "https://www.pdok.nl/introductie/-/article/pdok-luchtfoto-rgb-open-")!)
        case .swisstopo:
            ("© swisstopo · SWISSIMAGE", URL(string: "https://www.swisstopo.admin.ch/en/orthoimage-swissimage-10")!)
        }
    }

    var nativeMaximumZoom: Int {
        switch self {
        case .usgs: 16
        case .gsi: 18
        case .ign, .pnoa: 19
        case .pdok, .swisstopo: 20
        }
    }

    func tileURL(z: Int, x: Int, y: Int) -> URL? {
        switch self {
        case .usgs:
            // Only fetch where a tile intersects the contiguous United States.
            let dimension = Double(1 << z)
            let west = Double(x) / dimension * 360 - 180
            let east = Double(x + 1) / dimension * 360 - 180
            let north = atan(sinh(.pi * (1 - 2 * Double(y) / dimension))) * 180 / .pi
            let south = atan(sinh(.pi * (1 - 2 * Double(y + 1) / dimension))) * 180 / .pi
            guard east >= -125, west <= -66, north >= 24, south <= 50 else { return nil }
            return URL(string: "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/\(z)/\(y)/\(x)")
        case .gsi:
            return URL(string: "https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/\(z)/\(x)/\(y).jpg")
        case .ign:
            return wmts("https://data.geopf.fr/wmts", layer: "ORTHOIMAGERY.ORTHOPHOTOS", style: "normal", matrix: "PM", z: z, x: x, y: y)
        case .pnoa:
            return wmts("https://www.ign.es/wmts/pnoa-ma", layer: "OI.OrthoimageCoverage", style: "default", matrix: "GoogleMapsCompatible", z: z, x: x, y: y)
        case .pdok:
            return wmts("https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0", layer: "Actueel_orthoHR", style: "default", matrix: "EPSG:3857", z: z, x: x, y: y)
        case .swisstopo:
            return URL(string: "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.swissimage/default/current/3857/\(z)/\(x)/\(y).jpeg")
        }
    }

    private func wmts(_ endpoint: String, layer: String, style: String, matrix: String, z: Int, x: Int, y: Int) -> URL? {
        var components = URLComponents(string: endpoint)
        let parameters = [
            ("SERVICE", "WMTS"), ("REQUEST", "GetTile"), ("VERSION", "1.0.0"),
            ("LAYER", layer), ("STYLE", style), ("TILEMATRIXSET", matrix), ("FORMAT", "image/jpeg"),
            ("TILEMATRIX", String(z)), ("TILEROW", String(y)), ("TILECOL", String(x))
        ]
        components?.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components?.url
    }
}
#endif
