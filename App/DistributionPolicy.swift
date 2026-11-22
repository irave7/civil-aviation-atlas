import Foundation

enum DistributionPolicy {
    #if MAINLAND_DISTRIBUTION
    static let isMainlandReview = true
    static let airportCatalog = "airport-data-mainland"
    static let observedRoutesCatalog = "observed-routes-mainland"
    static let airportSiteModelsAvailable = false
    #else
    static let isMainlandReview = false
    static let airportCatalog = "airport-data"
    static let observedRoutesCatalog = "observed-routes"
    static let airportSiteModelsAvailable = true
    #endif

    #if MAINLAND_DISTRIBUTION && !MAINLAND_APPROVED_MAPS
    static let mapsAvailable = false
    #else
    static let mapsAvailable = true
    #endif

    #if MAINLAND_DISTRIBUTION
    static let liveFlightsAvailable = false
    #else
    static let liveFlightsAvailable = true
    #endif

    static let privacyPolicyURL = publicURL(for: "AtlasPrivacyPolicyURL")
    static let supportURL = publicURL(for: "AtlasSupportURL")
    static let icpRecordNumber = Bundle.main.string(forReleaseKey: "AtlasICPRecordNumber")
    static let icpLookupURL = URL(string: "https://beian.miit.gov.cn/")!

    private static func publicURL(for key: String) -> URL? {
        guard let value = Bundle.main.string(forReleaseKey: key),
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

private extension Bundle {
    func string(forReleaseKey key: String) -> String? {
        guard let value = object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
