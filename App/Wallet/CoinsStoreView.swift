import SwiftUI

/// Draft Coins shop UI for Hineka iOS.
/// Purchases intentionally remain disabled until a compliant payment route and verified backend exist.
public struct CoinsStoreView: View {
    @State private var selectedProvider: CoinCardProvider = .viettel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    walletHeader

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phương thức nạp dự kiến")
                            .font(.headline)

                        Picker("Loại thẻ", selection: $selectedProvider) {
                            ForEach(CoinCardProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Chưa kết nối nhà cung cấp thanh toán. Không nhập mã thẻ hoặc PIN ở phiên bản này.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Gói nạp Coin")
                            .font(.headline)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(CoinTopUpPackage.ownerDraft) { package in
                                packageCard(package)
                            }
                        }
                    }

                    Text("Coin chỉ được cộng sau khi máy chủ xác minh giao dịch thành công. Gói nạp hiển thị theo bảng giá đã chốt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .navigationTitle("Hineka Coins")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var walletHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hineka Wallet")
                .font(.title2.weight(.bold))
            Text("Coin dùng cho nội dung và tiện ích trong launcher Minecraft Java.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Số dư sẽ hiển thị khi tài khoản được kết nối máy chủ.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func packageCard(_ package: CoinTopUpPackage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(package.denominationVND.formatted(.number.locale(Locale(identifier: "vi_VN"))) + "đ")
                .font(.headline)

            if let coins = package.coins {
                Text(coins.formatted(.number.locale(Locale(identifier: "vi_VN"))) + " Coins")
                    .font(.title3.weight(.bold))
            } else {
                Text("Chờ chốt số Coin")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Button(package.isConfigured ? "Chưa mở nạp" : "Chưa cấu hình") {}
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .disabled(true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    CoinsStoreView()
}
