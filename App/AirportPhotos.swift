import SwiftUI
import UIKit

struct AirportPhotos: View {
    let airport: Airport

    @Environment(\.dismiss) private var dismiss
    @State private var selected: AirportPhoto?

    static func available(for airport: Airport) -> Bool {
        images(for: airport).contains { $0.fileURL != nil }
    }

    private static func images(for airport: Airport) -> [AirportPhoto] {
        airport.iata == "HKG" ? AirportPhoto.hongKong : []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(Self.images(for: airport)) { photo in
                        if let image = photo.image {
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    selected = photo
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .clipShape(.rect(cornerRadius: 20))
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                .font(AtlasTypography.font(.callout).weight(.semibold))
                                                .padding(11)
                                                .glassEffect(in: .circle)
                                                .padding(12)
                                                .accessibilityHidden(true)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(photo.altText)
                                .accessibilityHint("打开大图")
                                .accessibilityIdentifier("airport-photo-\(photo.identifier)")
                                AirportPhotoCredit(photo: photo)
                            }
                        }
                    }
                }
                .frame(maxWidth: 960)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
            .navigationTitle("\(airport.displayName) · 实景照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $selected) { photo in
            AirportPhotoDetail(photo: photo)
        }
    }
}

private struct AirportPhoto: Identifiable {
    let identifier: String
    let title: String
    let altText: String
    let date: String
    let author: String
    let adjustment: String
    let source: URL
    let license = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!

    var id: String { identifier }
    var fileURL: URL? {
        Bundle.main.url(forResource: identifier, withExtension: "jpg")
            ?? Bundle.main.url(forResource: identifier, withExtension: "jpg", subdirectory: "Resources")
    }
    var image: UIImage? { fileURL.flatMap { UIImage(contentsOfFile: $0.path) } }

    static let hongKong: [AirportPhoto] = [
        AirportPhoto(
            identifier: "HKGPhotoExterior",
            title: "一号客运大楼外观",
            altText: "实景照片，夕阳下的一号客运大楼玻璃外墙、连续拱形屋顶与远处山脊",
            date: "2025 年 12 月 20 日",
            author: "LN9267",
            adjustment: "已缩放",
            source: URL(string: "https://commons.wikimedia.org/wiki/File:Hong_Kong_International_Airport_Terminal_1_20-12-2025.jpg")!
        ),
        AirportPhoto(
            identifier: "HKGPhotoInterior",
            title: "一号客运大楼登机区",
            altText: "实景照片，一号客运大楼登机区的拱形顶棚、玻璃幕墙、自动步道和 24 号登机口指示牌",
            date: "2025 年 2 月 23 日",
            author: "Windmemories",
            adjustment: "已压缩",
            source: URL(string: "https://commons.wikimedia.org/wiki/File:20250222_Interior_of_Terminal_1,_HKG.jpg")!
        )
    ]
}

private struct AirportPhotoCredit: View {
    let photo: AirportPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(photo.title)
                .font(AtlasTypography.font(.headline))
                .accessibilityAddTraits(.isHeader)
            Text("摄于 \(photo.date) · \(photo.author)")
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 13) { links }
                VStack(alignment: .leading, spacing: 5) { links }
            }
        }
        .font(AtlasTypography.font(.footnote))
    }

    @ViewBuilder private var links: some View {
        Link("Wikimedia Commons 原图", destination: photo.source)
        Link("CC BY-SA 4.0", destination: photo.license)
        Text(photo.adjustment)
            .foregroundStyle(.secondary)
    }
}

private struct AirportPhotoDetail: View {
    let photo: AirportPhoto

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = photo.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(photo.altText)
                }
                AirportPhotoCredit(photo: photo)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }
            .navigationTitle(photo.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct HongKongTerminalCover: View {
    private static let photo = AirportPhoto.hongKong[0]
    private static let image = photo.image

    var body: some View {
        if let image = Self.image {
            VStack(alignment: .leading, spacing: 4) {
                Color.clear.aspectRatio(1.85, contentMode: .fit)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityLabel(Self.photo.altText)
                Link("LN9267 · CC BY-SA 4.0", destination: Self.photo.source)
                    .font(AtlasTypography.font(.caption))
            }
        }
    }
}
