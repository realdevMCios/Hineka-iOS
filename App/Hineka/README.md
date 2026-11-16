# Hineka iOS app shell

This is the first SwiftUI navigation shell for **Hineka**, a planned Minecraft Java launcher for iOS/iPadOS.

## Included
- App entry point and five-tab navigation.
- Home dashboard.
- Minecraft version status screen.
- Mods and resource-packs library placeholder.
- Coins Wallet screen with the owner-provided top-up mapping.
- Skin Studio and Settings placeholders.

## Not included yet
- Minecraft Java runtime, JVM, JRE packaging, game renderer, controls, keyboard/mouse support, or actual game launch.
- Microsoft authentication or Minecraft account entitlement checks.
- Version manifest/download/install pipeline.
- Forge/Fabric installer.
- Modrinth/CurseForge catalog clients, archive validation, mod/resource-pack manager, or cloud sync.
- StoreKit, card gateway, server API, real Coins balance, or payment verification.

The app shell is source code only. It has not been built with Xcode, run on an iPhone/iPad, or packaged as an IPA. Add the Swift files to a new iOS App target in Xcode and validate the deployment target, entitlements, and compile before distribution.
