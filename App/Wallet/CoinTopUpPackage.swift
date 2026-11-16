import Foundation

/// Owner-provided draft package mapping for the Hineka iOS Minecraft Java launcher.
/// This model is display-only: the server must remain authoritative for prices and grants.
public struct CoinTopUpPackage: Identifiable, Hashable {
    public let denominationVND: Int
    public let coins: Int?

    public var id: Int { denominationVND }
    public var isConfigured: Bool { coins != nil }

    public static let ownerDraft: [CoinTopUpPackage] = [
        .init(denominationVND: 10_000, coins: 40),
        .init(denominationVND: 20_000, coins: 90),
        .init(denominationVND: 50_000, coins: 150),
        .init(denominationVND: 100_000, coins: 700),
        .init(denominationVND: 200_000, coins: 500),
        .init(denominationVND: 500_000, coins: 900),
        .init(denominationVND: 1_000_000, coins: 1_500)
    ]
}

/// Requested card brands. Selecting one in the UI does not mean a gateway is connected.
public enum CoinCardProvider: String, CaseIterable, Identifiable {
    case viettel
    case mobifone
    case zing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .viettel: return "Viettel"
        case .mobifone: return "MobiFone"
        case .zing: return "Zing"
        }
    }
}
