import SwiftUI

public enum HinekaModLoader: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case forge = "Forge"
    case fabric = "Fabric"
    case quilt = "Quilt"

    public var id: String { rawValue }
}

/// Metadata-only catalog model. Entries should come from the reviewed server catalog later.
public struct HinekaModListing: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let author: String
    public let minecraftVersions: String
    public let loader: HinekaModLoader
    public let coinPrice: Int
    public let quality: String
    public let summary: String

    public static let previewExamples: [HinekaModListing] = [
        .init(
            id: "demo-fabric-utility",
            title: "Mod mẫu Fabric",
            author: "Dữ liệu minh họa",
            minecraftVersions: "1.20.x",
            loader: .fabric,
            coinPrice: 0,
            quality: "Demo",
            summary: "Thẻ minh họa giao diện catalog; không có tệp tải xuống."
        ),
        .init(
            id: "demo-forge-addon",
            title: "Mod mẫu Forge",
            author: "Dữ liệu minh họa",
            minecraftVersions: "1.19.x",
            loader: .forge,
            coinPrice: 0,
            quality: "Demo",
            summary: "Chưa phải mod thật và không thể cài đặt."
        )
    ]
}

public struct ModCatalogView: View {
    @State private var selectedLoader: HinekaModLoader = .all
    @State private var searchText = ""

    private var visibleListings: [HinekaModListing] {
        HinekaModListing.previewExamples.filter { item in
            let matchesLoader = selectedLoader == .all || item.loader == selectedLoader
            let matchesSearch = searchText.isEmpty
                || item.title.localizedCaseInsensitiveContains(searchText)
                || item.author.localizedCaseInsensitiveContains(searchText)
            return matchesLoader && matchesSearch
        }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Loader", selection: $selectedLoader) {
                    ForEach(HinekaModLoader.allCases) { loader in
                        Text(loader.rawValue).tag(loader)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                List {
                    Section {
                        ForEach(visibleListings) { listing in
                            listingRow(listing)
                        }
                    } header: {
                        Text("Mod Minecraft Java")
                    } footer: {
                        Text("Catalog hiện dùng dữ liệu demo. Chưa kết nối Modrinth, CurseForge hoặc nguồn mod Trung Quốc.")
                    }

                    Section("Resource Packs") {
                        Label("Chưa có resource pack", systemImage: "archivebox")
                        Text("Trình nhập .zip, xem trước và sắp xếp pack sẽ được bổ sung.")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .searchable(text: $searchText, prompt: "Tìm mod")
            .navigationTitle("Thư viện")
        }
    }

    @ViewBuilder
    private func listingRow(_ listing: HinekaModListing) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(listing.title)
                    .font(.headline)
                Spacer()
                Text(listing.quality)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(listing.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(listing.loader.rawValue)
                Text("Minecraft " + listing.minecraftVersions)
                Text(listing.coinPrice == 0 ? "Chưa định giá" : "\(listing.coinPrice) Coin")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Tác giả: " + listing.author)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }
}

#Preview {
    ModCatalogView()
}
