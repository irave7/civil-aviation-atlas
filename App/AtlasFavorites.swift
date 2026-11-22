import SwiftUI

@MainActor
@Observable
final class AtlasFavorites {
    enum Kind: String {
        case airport
        case aircraft

        var displayName: String {
            switch self {
            case .airport: "机场"
            case .aircraft: "客机"
            }
        }

        fileprivate var defaultsKey: String { "AtlasFavoriteIDs.\(rawValue)" }
    }

    private let defaults: UserDefaults
    private(set) var airportIDs: Set<String>
    private(set) var aircraftIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        airportIDs = Set(defaults.stringArray(forKey: Kind.airport.defaultsKey) ?? [])
        aircraftIDs = Set(defaults.stringArray(forKey: Kind.aircraft.defaultsKey) ?? [])
    }

    func contains(_ id: String, kind: Kind) -> Bool {
        ids(for: kind).contains(id)
    }

    func toggle(_ id: String, kind: Kind) {
        var selected = ids(for: kind)
        if selected.remove(id) == nil { selected.insert(id) }

        switch kind {
        case .airport: airportIDs = selected
        case .aircraft: aircraftIDs = selected
        }
        defaults.set(selected.sorted(), forKey: kind.defaultsKey)
    }

    private func ids(for kind: Kind) -> Set<String> {
        switch kind {
        case .airport: airportIDs
        case .aircraft: aircraftIDs
        }
    }
}

struct AtlasFavoriteButton: View {
    let favorites: AtlasFavorites
    let id: String
    let kind: AtlasFavorites.Kind

    var body: some View {
        let isFavorite = favorites.contains(id, kind: kind)
        Button {
            favorites.toggle(id, kind: kind)
        } label: {
            Label(isFavorite ? "取消收藏\(kind.displayName)" : "收藏\(kind.displayName)",
                  systemImage: isFavorite ? "star.fill" : "star")
        }
        .accessibilityIdentifier("favorite-\(kind.rawValue)-\(id)")
        .accessibilityValue(isFavorite ? "已收藏" : "未收藏")
    }
}
