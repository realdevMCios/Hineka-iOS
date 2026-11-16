# Wallet UI draft

This folder contains the first SwiftUI draft for the Hineka iOS Coins shop.

- `CoinTopUpPackage.swift`: owner-provided denomination-to-Coins mapping.
- `CoinsStoreView.swift`: display-only shop screen with Viettel, MobiFone, and Zing as requested provider labels.

All purchase buttons are intentionally disabled. No payment provider, StoreKit product, server API, or Coin ledger is connected. Do not treat this screen as a working payment flow. The 100,000 VND package has no Coin quantity yet and is marked unconfigured.

Add these source files to the future Xcode target when the iOS app project is created. Build and device testing still need to be performed in Xcode.
