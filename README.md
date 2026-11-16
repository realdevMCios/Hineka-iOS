# Hineka iOS

**Hineka** is a planned Minecraft Java launcher for iPhone and iPad.

Current development label: **0.1-dev** (not a release).

## Source layout

- `App/Hineka/` — SwiftUI app entry point and initial tab/navigation shell.
- `App/Wallet/` — Coin package model and draft Wallet screen.
- `App/Versions/` — live Mojang version-manifest browser and selected-version preference.
- `App/Library/` — local .jar/.zip file import, inventory, enable flags, and delete controls.
- `Package.swift` — iOS 18 Swift package for the HinekaUI source.
- `Docs/MONETIZATION-PLAN.md` — Coin packages, Premium, and payment requirements.
- `Docs/API-DRAFT.md` — proposed backend API contract.
- `Docs/SECURITY-PLAN.md` — security design notes.

## Current Coin top-up draft

| Top-up | Coins |
|---:|---:|
| 20,000 VND | 90 |
| 50,000 VND | 130 |
| 100,000 VND | 200 |
| 200,000 VND | 500 |
| 500,000 VND | 900 |
| 1,000,000 VND | 1,800 |

Requested card brands: Viettel, MobiFone, and Zing. They are **not integrated**. Purchase controls remain disabled until a lawful payment route, provider account, and server verification are in place.

## Launcher code added in 0.1-dev

- Fetch and display the official Minecraft Java version manifest; select a preferred version (selection only, not installation).
- Import local `.jar` mods and `.zip` resource packs into Hineka's private app storage, list them, mark them enabled/disabled, and delete them.
- Local library metadata is stored in the app container.

The current local-file screen does not scan files for malware, install them into a game profile, or apply toggles to a running Minecraft instance. The remote mod catalogue remains demo-only.

## Build and runtime status

This repository currently contains a SwiftUI source package and early launcher shell, not a complete Minecraft launcher. The Java runtime, game renderer, version installer, Forge/Fabric installation, mod/resource-pack management, authentication, backend, and real payments are not implemented. A GitHub Actions workflow was added to attempt an iOS Simulator source build on pushes; the first run must complete successfully before claiming that build check passed. The app has not been run on a device or packaged as an IPA.

Add the Swift files to an iOS App target in Xcode, then build and test on supported devices before calling it installable. Do not distribute a release IPA until runtime licensing, security, signing, and device testing are completed.
