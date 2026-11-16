import SwiftUI
import HinekaJavaRuntime

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
    @AppStorage("hineka.selectedMinecraftVersion") private var selectedVersionID = ""
    @State private var isTestingJavaRuntime = false
    @State private var javaRuntimeOutput = "Chưa chạy kiểm tra Java."

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

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Phiên bản đã chọn", systemImage: "square.stack.3d.up")
                                .font(.headline)
                            Spacer()
                            Text(selectedVersionID.isEmpty ? "Chưa chọn" : selectedVersionID)
                                .font(.subheadline.weight(.semibold))
                        }

                        NavigationLink {
                            MinecraftVersionsView()
                        } label: {
                            Label("Chọn phiên bản Minecraft", systemImage: "arrow.right.circle")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.quaternary, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("OpenJDK Zero · thử nghiệm", systemImage: "terminal")
                            .font(.headline)

                        Text("Kiểm tra Java độc lập trước. Bài kiểm tra này chưa khởi chạy Minecraft.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            runJavaRuntimeSmokeTest()
                        } label: {
                            if isTestingJavaRuntime {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Thử chạy Java", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTestingJavaRuntime)

                        Text(javaRuntimeOutput)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                        Button("Khởi chạy Minecraft") {}
                            .buttonStyle(.bordered)
                            .disabled(true)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func runJavaRuntimeSmokeTest() {
        guard !isTestingJavaRuntime else { return }
        isTestingJavaRuntime = true
        defer { isTestingJavaRuntime = false }

        do {
            javaRuntimeOutput = try HinekaJavaRuntime.runSmokeTest()
        } catch {
            javaRuntimeOutput = "Java smoke test failed:\n" + error.localizedDescription
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
