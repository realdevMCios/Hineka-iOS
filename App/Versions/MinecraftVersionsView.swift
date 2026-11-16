import SwiftUI

private enum HinekaVersionChannel: String, CaseIterable, Identifiable {
    case release = "Release"
    case snapshot = "Snapshot"
    case all = "Tất cả"

    var id: String { rawValue }
}

private struct MinecraftVersionManifest: Decodable {
    struct Latest: Decodable {
        let release: String
        let snapshot: String
    }

    let latest: Latest
    let versions: [MinecraftVersion]
}

private struct MinecraftVersion: Decodable, Identifiable {
    let id: String
    let type: String
    let url: URL
    let time: String
    let releaseTime: String
    let sha1: String
    let complianceLevel: Int

    var isStableRelease: Bool { type == "release" }
}

/// Reads Mojang's public version manifest. Selecting a version only stores a launcher preference;
/// downloading game files and launching Java are separate, not-yet-implemented stages.
@MainActor
private final class MinecraftVersionCatalog: ObservableObject {
    @Published private(set) var versions: [MinecraftVersion] = []
    @Published private(set) var latestRelease = ""
    @Published private(set) var latestSnapshot = ""
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json") else {
            errorMessage = "Địa chỉ manifest không hợp lệ."
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Máy chủ phiên bản trả về phản hồi không hợp lệ."
                return
            }

            let manifest = try JSONDecoder().decode(MinecraftVersionManifest.self, from: data)
            versions = manifest.versions
            latestRelease = manifest.latest.release
            latestSnapshot = manifest.latest.snapshot
        } catch {
            errorMessage = "Không tải được danh sách phiên bản: \(error.localizedDescription)"
        }
    }
}

public struct MinecraftVersionsView: View {
    @StateObject private var catalog = MinecraftVersionCatalog()
    @AppStorage("hineka.selectedMinecraftVersion") private var selectedVersionID = ""
    @State private var channel: HinekaVersionChannel = .release
    @State private var searchText = ""

    public init() {}

    private var visibleVersions: [MinecraftVersion] {
        catalog.versions.filter { version in
            let matchesChannel: Bool
            switch channel {
            case .release:
                matchesChannel = version.type == "release"
            case .snapshot:
                matchesChannel = version.type == "snapshot"
            case .all:
                matchesChannel = true
            }
            let matchesSearch = searchText.isEmpty
                || version.id.localizedCaseInsensitiveContains(searchText)
            return matchesChannel && matchesSearch
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                latestVersionsCard

                Picker("Kênh phiên bản", selection: $channel) {
                    ForEach(HinekaVersionChannel.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                List {
                    if let error = catalog.errorMessage {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error)
                                    .foregroundStyle(.secondary)
                                Button("Thử tải lại") {
                                    Task { await catalog.refresh() }
                                }
                                .disabled(catalog.isLoading)
                            }
                        }
                    }

                    Section("Danh sách phiên bản") {
                        ForEach(visibleVersions) { version in
                            Button {
                                selectedVersionID = version.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(version.id)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(version.type.uppercased() + " · " + String(version.releaseTime.prefix(10)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedVersionID == version.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if catalog.isLoading && catalog.versions.isEmpty {
                        ProgressView("Đang tải catalog phiên bản…")
                    }
                }
                .refreshable {
                    await catalog.refresh()
                }
            }
            .navigationTitle("Phiên bản")
            .searchable(text: $searchText, prompt: "Tìm phiên bản Java")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await catalog.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(catalog.isLoading)
                    .accessibilityLabel("Làm mới danh sách")
                }
            }
            .task {
                if catalog.versions.isEmpty {
                    await catalog.refresh()
                }
            }
        }
    }

    private var latestVersionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manifest Minecraft Java")
                .font(.headline)
            HStack {
                Label("Release: \(catalog.latestRelease.isEmpty ? "—" : catalog.latestRelease)", systemImage: "checkmark.seal")
                Spacer()
                Label("Snapshot: \(catalog.latestSnapshot.isEmpty ? "—" : catalog.latestSnapshot)", systemImage: "hammer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text("Đang chọn")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedVersionID.isEmpty ? "Chưa chọn" : selectedVersionID)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            Text("Chọn phiên bản chỉ lưu lựa chọn. Tải game, cài loader và khởi chạy Java chưa được tích hợp.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

#Preview {
    MinecraftVersionsView()
}
