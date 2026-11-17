# Hineka iOS

**Hineka** is a planned Minecraft Java launcher for iPhone and iPad.

Current development label: **0.1-dev** (not a release).

## Source layout

- `App/Hineka/` — SwiftUI app entry point and initial tab/navigation shell.
- `App/Wallet/` — Coin package model and draft Wallet screen.
- `App/Runtime/` — experimental OpenJDK Mobile Zero JNI bridge, runtime module diagnostics, renderer backend contract, and game-session lifecycle contract.
- `App/Versions/` — Mojang version-manifest browser, vanilla installer, launch-plan builder, and readiness checks.
- `App/Library/` — local .jar/.zip file import, inventory, enable flags, and delete controls.
- `Package.swift` — iOS 18 Swift package for the HinekaUI source.
- `Scripts/prepare-openjdk-ios-runtime.sh` — downloads and SHA-256 verifies pinned OpenJDK Mobile device runtime inputs for the Java smoke test.
- `Scripts/MinecraftLaunchPlanSmokeTests.swift` — host-run smoke tests for Minecraft launch-plan parsing and validation.
- `Docs/MONETIZATION-PLAN.md` — Coin packages, Premium, and payment requirements.
- `Docs/API-DRAFT.md` — proposed backend API contract.
- `Docs/SECURITY-PLAN.md` — security design notes.
- `Docs/RUNTIME-PLAN.md` — runtime, JIT, licensing, and installation approach.
- `Docs/RENDERER-PLAN.md` — clean renderer, input/audio and game-session architecture research.

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

The downloader intentionally skips desktop native classifiers. A separate launch-plan builder resolves modern and legacy Mojang JVM/game arguments, evaluates OS/architecture/feature rules, replaces supported placeholders, and constructs an inspectable classpath. The installer materializes hash-verified legacy `assets/virtual/legacy` files and `resources/` mappings when the asset index requests them. It does not execute Java. The project still lacks a complete Minecraft-compatible iOS JRE, native renderer/LWJGL replacement, persistent JNI game supervisor, Microsoft authentication, Forge/Fabric installation, mod malware scanning, and live application of mod toggles. The remote mod catalogue remains demo-only.

## Build and runtime status

GitHub Actions build #61 completed successfully on 2026-11-17: all 25 launch-plan, legacy asset, runtime-report, and game-session state-machine smoke tests passed, XcodeGen generated the project, and Xcode built the generic iOS device target with code signing disabled. This confirms source compilation and host-side tests only. The experimental JNI bridge exposes a Java runtime diagnostic on Home. It now reports the running VM's actual Java major version, VM, architecture, and boot-layer module inventory, but it has not yet been run on a physical iPhone/iPad. The pinned package contains only the upstream HelloWorld-style Java base-module image, not the full conservative module baseline or iOS native graphics needed by Minecraft. The launch-plan builder does not launch a game. Runtime execution, renderer/LWJGL replacement, Forge/Fabric, Microsoft authentication, backend, and real payments are not implemented. Runtime redistribution is blocked pending an AGPL-3.0/provenance review. The app has not been signed, installed on a device, or packaged as an IPA.

Add the Swift files to an iOS App target in Xcode, then build and test on supported devices before calling it installable. Do not distribute a release IPA until runtime licensing, security, signing, and device testing are completed.
