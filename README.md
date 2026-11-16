# Hineka iOS

**Hineka** is a planned Minecraft Java launcher for iPhone and iPad.

Current development label: **0.1-dev** (not a release).

## Source layout

- `App/Hineka/` — SwiftUI app entry point and initial tab/navigation shell.
- `App/Wallet/` — Coin package model and draft Wallet screen.
- `App/Runtime/` — experimental OpenJDK Mobile Zero JNI bridge and Java smoke test.
- `App/Versions/` — Mojang version-manifest browser and first-pass vanilla client/library/asset downloader.
- `App/Library/` — local .jar/.zip file import, inventory, enable flags, and delete controls.
- `Package.swift` — iOS 18 Swift package for the HinekaUI source.
- `Scripts/prepare-openjdk-ios-runtime.sh` — downloads and SHA-256 verifies pinned OpenJDK Mobile device runtime inputs for the Java smoke test.
- `Docs/MONETIZATION-PLAN.md` — Coin packages, Premium, and payment requirements.
- `Docs/API-DRAFT.md` — proposed backend API contract.
- `Docs/SECURITY-PLAN.md` — security design notes.
- `Docs/RUNTIME-PLAN.md` — runtime, JIT, licensing, and installation approach.

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

- Fetch and display Mojang's official Minecraft Java version manifest, filter releases/snapshots, select a version, and default to the latest release.
- First-pass vanilla installer downloads the selected version metadata, official client JAR, pure-Java library artifacts, asset index, and referenced assets; verifies SHA-1 values when supplied; and records a local installed marker.
- Import local `.jar` mods and `.zip` resource packs into Hineka's private app storage, list them, mark them enabled/disabled, and delete them.
- Local library metadata is stored in the app container.

The downloader intentionally skips desktop native classifiers. It does not yet install an iOS JRE, construct the final classpath/JVM arguments, authenticate a Minecraft account, launch a game, install Forge/Fabric, scan mods for malware, or apply mod toggles to a running game. The remote mod catalogue remains demo-only.

## Build and runtime status

This repository currently contains a SwiftUI source package, an early launcher shell, a first-pass vanilla asset downloader, and an experimental JNI bridge around the OpenJDK Mobile Zero VM. The bridge exposes a Java smoke-test control on Home; it has not yet been run on a physical iPhone/iPad. The pinned package contains only the upstream HelloWorld-style Java base-module image, not the complete set of Java modules or iOS native graphics needed by Minecraft. The game renderer, Minecraft launch pipeline, Forge/Fabric installation, authentication, backend, and real payments are not implemented. Runtime redistribution is blocked pending an AGPL-3.0/provenance review. GitHub Actions now prepares the pinned runtime and attempts an unsigned generic iOS-device build; no successful Xcode build has yet been confirmed. The app has not been installed on a device or packaged as an IPA.

Add the Swift files to an iOS App target in Xcode, then build and test on supported devices before calling it installable. Do not distribute a release IPA until runtime licensing, security, signing, and device testing are completed.
