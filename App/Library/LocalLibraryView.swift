import SwiftUI
import UniformTypeIdentifiers

public struct LocalLibraryView: View {
    @StateObject private var store = HinekaLocalLibraryStore()
    @State private var selectedKind: HinekaLocalFileKind = .mod
    @State private var showingImporter = false
    @State private var alertMessage = ""
    @State private var showingAlert = false

    public init() {}

    private var visibleFiles: [HinekaLocalFile] {
        store.files.filter { $0.kind == selectedKind }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Loại tệp", selection: $selectedKind) {
                    ForEach(HinekaLocalFileKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                HStack {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Nhập tệp", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Text("\(visibleFiles.count) tệp")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                List {
                    Section {
                        if visibleFiles.isEmpty {
                            ContentUnavailableView(
                                "Chưa có tệp",
                                systemImage: selectedKind == .mod ? "shippingbox" : "archivebox",
                                description: Text(
                                    selectedKind == .mod
                                        ? "Nhập mod .jar từ ứng dụng Tệp."
                                        : "Nhập resource pack .zip từ ứng dụng Tệp."
                                )
                            )
                        } else {
                            ForEach(visibleFiles) { item in
                                fileRow(item)
                            }
                        }
                    } header: {
                        Text(selectedKind.displayName)
                    }

                    Section("Khám phá mod") {
                        NavigationLink {
                            ModCatalogView()
                        } label: {
                            Label("Mở danh mục mod", systemImage: "globe.asia.australia")
                        }
                        Text("Danh mục online hiện chỉ có dữ liệu demo; chưa tải mod thật.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Lưu ý") {
                        Text("Tệp được sao chép vào vùng riêng của Hineka. Bật/tắt ở đây mới chỉ lưu lựa chọn; chưa tác động vào Minecraft cho tới khi runtime và bộ quản lý profile được tích hợp.")
                        Text("Chỉ nhập mod/resource pack từ nguồn tin cậy. Bản dev chưa có trình quét mã độc hoặc kiểm tra tương thích.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Thư viện")
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: selectedKind == .mod ? [.data] : [.zip],
                allowsMultipleSelection: true,
                onCompletion: handleImport
            )
            .alert("Thư viện Hineka", isPresented: $showingAlert) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    @ViewBuilder
    private func fileRow(_ item: HinekaLocalFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.originalFileName)
                        .font(.headline)
                        .lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button(role: .destructive) {
                        deleteFile(item)
                    } label: {
                        Label("Xóa khỏi Hineka", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }

            Toggle(
                "Đánh dấu bật trong profile",
                isOn: Binding(
                    get: { item.isEnabled },
                    set: { store.setEnabled($0, for: item.id) }
                )
            )
            .font(.footnote)

            Text("Đã nhập · Chưa được áp dụng vào Minecraft runtime")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            do {
                let count = try store.importFiles(urls, as: selectedKind)
                alertMessage = "Đã nhập \(count) tệp vào vùng lưu trữ riêng của Hineka."
            } catch {
                alertMessage = error.localizedDescription
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
        showingAlert = true
    }

    private func deleteFile(_ item: HinekaLocalFile) {
        do {
            try store.delete(item)
            alertMessage = "Đã xóa tệp khỏi vùng lưu trữ Hineka."
        } catch {
            alertMessage = error.localizedDescription
        }
        showingAlert = true
    }
}

#Preview {
    LocalLibraryView()
}
