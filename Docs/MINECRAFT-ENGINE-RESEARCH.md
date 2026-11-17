# Hineka Minecraft engine research

Research date: 2026-11-17

## Decision in one paragraph

Do **not** build the Minecraft engine from scratch and do **not** replace Hineka's SwiftUI launcher. Keep Hineka's screens, version browser, installer, local library and product identity. Build a separate game-engine adapter behind that UI, using the public iOS Pojav/Amethyst implementation as the primary architectural reference. Evaluate Hynis as a recent derivative and FlameLauncher as a useful launch-plan/runtime design reference. Do not import their signing/JIT/library-validation bypasses, and do not copy runtime binaries until every license and signing constraint has been reviewed.

## Repositories examined

### 1. Amethyst-iOS — best primary architecture reference

- Repository: https://github.com/AngelAuraMC/Amethyst-iOS
- The PojavLauncher iOS repository says it is discontinued/archived and names Amethyst as its successor: https://github.com/PojavLauncherTeam/PojavLauncher_iOS
- Amethyst's README describes an iOS/iPadOS Java Edition launcher with Minecraft version support, Forge/Fabric/OptiFine/Quilt, touch controls, keyboard/mouse/controller, and Microsoft/demo account support.
- The source is split into useful layers:
  - `JavaApp/`: Java-side Pojav/Boardwalk launcher classes, version/profile data, patched GLFW Java classes, LWJGL jars and Caciocavallo AWT support.
  - `Natives/JavaLauncher.m`: prepares process environment and JVM/game launch.
  - `Natives/JavaGUIViewController.m`: connects UIKit touch/keyboard input to Java/AWT.
  - `Natives/ctxbridges/gl_bridge.m` and `egl_bridge.m`: create the EGL/OpenGL rendering context against an iOS layer.
  - `Natives/resources/Frameworks/`: iOS native LWJGL libraries plus GL4ES, MobileGlues, EGL/GLES, MoltenVK and OpenAL components.
- This is the clearest end-to-end reference for the missing bridge between a Java launcher and native iOS rendering/input. Source entry points:
  - https://github.com/AngelAuraMC/Amethyst-iOS/blob/main/Natives/JavaLauncher.m
  - https://github.com/AngelAuraMC/Amethyst-iOS/blob/main/Natives/JavaGUIViewController.m
  - https://github.com/AngelAuraMC/Amethyst-iOS/blob/main/Natives/ctxbridges/gl_bridge.m
  - https://github.com/AngelAuraMC/Amethyst-iOS/blob/main/JavaApp/Makefile
- Important blockers for direct reuse:
  - Amethyst documents that JIT is needed for usable performance and describes external debugger/JIT activation paths.
  - Its Java launch code calls a Library Validation bypass for external runtimes/dylibs. Hineka must **not** copy that path.
  - Its README lists third-party components with mixed licenses, including GPL components and an LWJGLX component whose license it labels unknown. A full component-by-component audit is required before code or binary reuse.
  - Its minimum OS/device statements are project claims, not proof of Hineka compatibility.

### 2. HynisJE — recent Amethyst-derived comparison

- Repository: https://github.com/congcq/HynisJE
- Its README identifies it as based on Amethyst, claims iOS 26 support, and lists Java 8/17/21/25 runtimes in its build system.
- Its Makefile fetches iOS arm64 JRE archives, builds native components, and has a “slimmed” package mode that excludes bundled JRE folders.
- It is useful for checking newer iOS-version and Java-major-version changes, but it inherits the same fundamental architecture and several of the same JIT/signing restrictions.
- Its README also lists DyldDeNeuralyzer as a Library Validation bypass. That mechanism is explicitly out of scope for Hineka.
- Its build script removes some runtime legal/documentation files when staging JREs. Hineka must **not** copy that stripping step; preserve all required license and notice files.

### 3. FlameLauncher-iOS — useful separation of launch plan and runtime

- Repository: https://github.com/FlameLaunchers/FlameLauncher-iOS
- This is a newer, separate iOS launcher project licensed AGPL-3.0. Its README claims support across a broad Minecraft version range, mod loaders and several renderer choices; treat those as project claims until independently device-tested.
- Its Swift source has a clean conceptual split:
  - `GameLauncher` builds a launch plan containing Java home, argv, environment variables, renderer and instance settings.
  - `JavaRuntime` is a protocol between the Swift UI and the native Java/JVM bridge; it includes attachable render surface, boot, input, pause/stop and runtime diagnostics.
  - `Renderer` selects the backend and matching environment variables.
- Source entry points:
  - https://github.com/FlameLaunchers/FlameLauncher-iOS/blob/main/Sources/Service/GameLauncher.swift
  - https://github.com/FlameLaunchers/FlameLauncher-iOS/blob/main/Sources/Service/JavaRuntime.swift
  - https://github.com/FlameLaunchers/FlameLauncher-iOS/blob/main/Sources/Model/Renderer.swift
  - https://github.com/FlameLaunchers/FlameLauncher-iOS/blob/main/Scripts/fetch-runtime.sh
- It downloads runtime/native artifacts from PojavLauncher iOS and Amethyst rather than providing a fully self-contained new runtime. Its README estimates about 1 GB for the app plus game/runtime storage, so it is not a drop-in fit for Hineka's under-500-MB IPA goal.
- Its documented JIT workflow is also a platform constraint, not something Hineka should blindly copy. AGPL-3.0 obligations must be reviewed before any derivative reuse.

## Recommended Hineka architecture

Preserve Hineka's current SwiftUI UI and local installation code. Add an isolated engine layer, with no privileged iOS mechanisms:

1. **Launch-plan builder (Swift):** resolve Mojang version rules and placeholders; validate the installed client, libraries and assets; construct classpath, JVM arguments, game arguments, working directory and environment. Keep the plan inspectable and testable without booting Java.
2. **Runtime host (Objective-C/C + Swift wrapper):** use the existing JNI bridge as the foundation, but first determine whether the selected iOS runtime exposes a supported launcher entry point (JNI invocation versus JLI). Start on a dedicated thread with bounded lifecycle/logging. Do not assume the current smoke-test VM is a game-ready JRE.
3. **Java runtime decision:** verify a complete iOS arm64 runtime/module set for the game's required Java major version. The current OpenJDK Mobile Zero snapshot has only been used for a tiny smoke test; its device execution, module coverage and performance remain unknown. Compare this against properly licensed iOS OpenJDK/Zulu runtime options, while preserving required notices.
4. **Native window/input bridge:** create a UIKit-backed render surface; route touch, keyboard, mouse and controller events to the GLFW-compatible input bridge.
5. **Renderer proof:** build one iOS arm64 backend from source and embed/sign it as part of the app build. Evaluate MobileGlues for modern OpenGL compatibility and GL4ES for older versions; keep MoltenVK/Zink as a later alternative. Do not download unsigned native dylibs into Documents and attempt to load them. No Library Validation bypass.
6. **Audio:** add an iOS-compatible OpenAL Soft or equivalent native audio backend after the first frame renders.
7. **Vanilla-only milestone:** launch one pinned Java-compatible Minecraft version with no mods. Add Microsoft authentication, additional versions, Fabric/Forge/Quilt only after vanilla reaches a world and survives a basic play session.

## Proposed first vertical slice

- [x] Add a dependency-injected vanilla `HinekaGameLaunchPlanBuilder` that resolves common Mojang arguments and launch placeholders without executing Java.
- [ ] Add unit fixtures for a pinned official vanilla version and verify the resolved classpath, JVM options, game arguments, feature rules and OS/architecture rules.
- [ ] Pick one Minecraft release whose `javaVersion.majorVersion` and LWJGL dependencies are known from its official version metadata.
- Prove the full runtime on a **signed physical device**, not just in CI.
- First visual milestone: create a renderer context and clear the Hineka game surface to a known color.
- Second milestone: run a tiny GLFW window/input test through the same native bridge.
- Third milestone: launch vanilla Minecraft to the title screen, then load a disposable test world.
- Only after those succeed should the full mod/coin/catalogue roadmap connect to the engine.

## Constraints that can stop the project

- **JIT/performance:** Amethyst explicitly identifies JIT as necessary for usable performance. Hineka's current Zero smoke test does not establish that interpreted execution is fast enough. A supported signing/debug/JIT route must be tested before claiming playable performance. Do not use jailbreak-only or Library Validation bypasses.
- **Code signing:** all native executable code must be packaged and signed through a valid, supported app-signing flow. A successful unsigned CI build proves compilation/linking only; it is not installable and does not prove runtime loading.
- **IPA size:** the under-500-MB target needs measurement on a stripped, signed build. Start with one Java runtime and one renderer; do not bundle every Java major or renderer before proving they are needed.
- **Licensing:** Amethyst/Pojav descendants include GPL-family code; FlameLauncher is AGPL-3.0. These licenses permit commercial distribution under their terms but impose source, notice and downstream rights obligations. Unknown component licenses must be resolved before reuse. The project owner/guardian should review the final distribution plan.
- **Minecraft files:** do not ship Mojang's client JAR/assets in Hineka's binary. Continue downloading from official metadata and require users to use their own legitimate account.

## Current recommendation

Use **Amethyst-iOS as the main technical map**, **HynisJE to compare newer Java/iOS changes**, and **FlameLauncher to study the separation between launch plan, runtime interface and renderer selection**. Keep Hineka's own UI and installer. The first launch-plan source is now in `App/Versions/MinecraftLaunchPlan.swift`; add unit fixtures for one pinned vanilla profile next. Do not import large runtime binaries or attempt Forge/Fabric yet.
