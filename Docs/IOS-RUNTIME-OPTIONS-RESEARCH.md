# iOS Minecraft Java runtime options — research snapshot

Research date: **2026-11-17**

Status: **research and architecture screening only**. No external launcher source or binary has been copied into Hineka. Statements about third-party project capabilities below are descriptions published by those projects, not independent device-test results from Hineka.

## Findings

### 1. OpenJDK Mobile

The OpenJDK Mobile project documents an iOS build using the **Zero** VM. Its iOS build instructions identify Zero as the default because iOS does not permit writable-and-executable memory; the project documents building an `aarch64-macos-ios` target and producing a static JVM image. Its iOS HelloWorld milestone says the device path works, while the simulator still has an outstanding limitation.

That is useful evidence that a native Java VM can run on a real iOS device. It does **not** establish that a full JRE, Minecraft's required modules, desktop-oriented native libraries, LWJGL, a renderer, or Forge/Fabric can run in Hineka. The current Hineka-pinned package remains a minimal smoke-test input, not a Minecraft runtime.

Sources:
- https://github.com/openjdk/mobile
- https://openjdk-mobile.github.io/ios/helloworld/
- https://openjdk-mobile.github.io/openjdk-mobile/

### 2. Amethyst iOS — closest maintained Java-launcher reference

The archived PojavLauncher iOS repository identifies **AngelAuraMC/Amethyst-iOS** as its successor. Amethyst's README describes support for Minecraft Java versions, Forge, Fabric, OptiFine and Quilt, and it says the launcher uses JIT to reach usable performance. Its installation documentation describes JIT-dependent routes; the project is not a no-JIT performance reference.

The Amethyst-iOS repository's current `LICENSE` file is **GPL-3.0**. Treat its implementation as a technical reference only unless Hineka's distribution model and complete GPL obligations are reviewed and expressly accepted. Do not copy source files, build scripts, entitlements, binaries, or patched native components into Hineka as a shortcut.

Sources:
- https://github.com/AngelAuraMC/Amethyst-iOS
- https://github.com/AngelAuraMC/Amethyst-iOS/blob/main/LICENSE
- https://github.com/PojavLauncherTeam/PojavLauncher_iOS

### 3. FlameLauncher iOS — newer integrated stack, stronger licence constraint

FlameLauncher publicly describes a newer iOS launcher stack with Minecraft Java versions 1.7–26.3, Fabric/Forge/NeoForge/Quilt, MobileGlues/Zink/GL4ES renderer choices, and Microsoft sign-in using the user's own account. These are project README claims and have not been verified by Hineka on a device.

Its repository declares **AGPL-3.0**. Its NOTICE explains that the combined app includes GPL-3.0 Amethyst/Pojav components and statically links an AGPL-3.0 Terracotta component. The README also says its practical game performance depends on JIT and describes external debugger-based JIT setup.

This is not a drop-in dependency for Hineka. Reusing or linking its components could impose substantial source-distribution and licence obligations on a combined work. Do not transplant any part without a component-by-component licence review and a project-owner decision to accept the resulting obligations.

Sources:
- https://github.com/FlameLaunchers/FlameLauncher-iOS
- https://github.com/FlameLaunchers/FlameLauncher-iOS/blob/main/LICENSE
- https://github.com/FlameLaunchers/FlameLauncher-iOS/blob/main/NOTICE

### 4. Horizon for iOS — different engine strategy

Horizon describes itself as a community port of Minecraft Java Edition 26.3 rewritten in Rust, using native Metal and not embedding a Java runtime. Its README calls the project experimental and says device, server, resource-pack and shader compatibility are still being tested. It also says desktop Java `.jar` mods do not run directly; its mod system is separate.

This may be worth watching as a separate native-engine research project, but it does not meet Hineka's current goal of a conventional Minecraft Java launcher with standard Java mod-loader compatibility.

Source:
- https://github.com/Kelly-Inc/horizon-ios

## Hineka decision

1. **Keep Hineka's own launcher/UI and Mojang metadata downloader.** These parts do not need to be replaced by another launcher.
2. **Keep the current OpenJDK Mobile JNI smoke test labelled experimental.** It proves neither Minecraft compatibility nor playable performance. Keep the launch preflight fail-closed until a complete, compatible runtime and renderer have been verified.
3. **Do not import Amethyst or FlameLauncher code/binaries at this stage.** Both are useful architectural references, but their GPL/AGPL terms must be considered against Hineka's planned distribution and monetization before any integration. This document is not a legal opinion.
4. **Do not pivot to Horizon silently.** It is a distinct Rust client/engine approach and does not currently provide direct compatibility with ordinary Java `.jar` mods.
5. The next meaningful runtime milestone is a reproducible **device-side Java/runtime test**, followed by a measured compatibility/performance decision. Only after that should Hineka commit to a renderer/native-library path or loader integration.

## CI note

GitHub Actions build **#66** remains the last successful Hineka iOS source build in this research snapshot. Build **#67** (commit `b6b995d9c14aaeb7adee690ef75fe2257d73566f`) ended with a failed workflow conclusion because its only job was marked **cancelled** on both attempts. GitHub returned no job steps and no log URL for the retry. That is not evidence of a Swift/Xcode compile error; the exact cancellation cause is not exposed by the available run data. Do not call #67 a successful build or infer a source-code failure from it.

Workflow:
- https://github.com/realdevMCios/Hineka-iOS/actions/runs/44070913458
- Last successful build #66: https://github.com/realdevMCios/Hineka-iOS/actions/runs/44016181343
