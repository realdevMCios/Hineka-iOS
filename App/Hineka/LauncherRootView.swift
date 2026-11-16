import SwiftUI

public struct LauncherRootView: View {
    public init() {}

    public var body: some View {
        TabView {
            HomeDashboardView()
                .tabItem {
                    Label("Trang chủ", systemImage: "house.fill")
                }

            MinecraftVersionsView()
                .tabItem {
                    Label("Phiên bản", systemImage: "square.stack.3d.up")
                }

            LocalLibraryView()
                .tabItem {
                    Label("Thư viện", systemImage: "shippingbox")
                }

            CoinsStoreView()
                .tabItem {
                    Label("Wallet", systemImage: "circle.hexagongrid.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Cài đặt", systemImage: "gearshape.fill")
                }
        }
        .tint(.indigo)
    }
}

private struct HomeDashboardView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HINEKA")
                            .font(.largeTitle.weight(.black))
                        Text("Minecraft Java Launcher cho iOS")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("0.1-dev")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(
                        LinearGradient(
                            colors: [.indigo.opacity(0.22), .purple.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 22)
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Runtime Java chưa được tích hợp", systemImage: "wrench.and.screwdriver")
                            .font(.headline)
                        Text("Đây là khung giao diện ban đầu. Nút khởi chạy sẽ được mở khi runtime, thư viện và quy trình cấp quyền đã được tích hợp và kiểm thử.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Khởi chạy Minecraft") {}
                            .buttonStyle(.borderedProminent)
                            .disabled(true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.quaternary, lineWidth: 1)
                    }

                    NavigationLink {
                        SkinStudioView()
                    } label: {
                        Label("Skin Studio", systemImage: "person.crop.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .navigationTitle("Hineka")
        }
    }
}

private struct VersionsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Minecraft Java") {
                    Label("Danh sách phiên bản sẽ tải từ API", systemImage: "arrow.down.circle")
                    Text("Chưa kết nối catalog hoặc trình tải phiên bản.")
                        .foregroundStyle(.secondary)
                }

                Section("Trạng thái") {
                    LabeledContent("Runtime", value: "Chưa tích hợp")
                    LabeledContent("Forge", value: "Chưa tích hợp")
                    LabeledContent("Fabric", value: "Chưa tích hợp")
                }
            }
            .navigationTitle("Phiên bản")
        }
    }
}

private struct SkinStudioView: View {
    var body: some View {
        List {
            Section("Skin Studio") {
                Label("Trình xem và chỉnh sửa skin sẽ được thêm ở bước sau.", systemImage: "person.crop.square")
                Text("Chưa có công cụ chỉnh sửa hoặc xuất PNG.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Skin Studio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Hineka") {
                    LabeledContent("Phiên bản", value: "0.1-dev")
                    LabeledContent("Nền tảng", value: "iOS / iPadOS")
                    LabeledContent("Minecraft", value: "Java Edition")
                }

                Section("Tài khoản & đồng bộ") {
                    Text("Đăng nhập khách và đồng bộ mod/resource pack chưa được kết nối.")
                        .foregroundStyle(.secondary)
                }

                Section("An toàn") {
                    Text("Không nhập mã PIN/serial thẻ nạp vào bản dev hiện tại.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cài đặt")
        }
    }
}
