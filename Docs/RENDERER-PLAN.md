# Hineka iOS renderer and game-session architecture

Status: **research and interface design only**. No renderer, patched LWJGL native, SDL bridge, game JVM supervisor, or physical-device graphics test has been integrated.

## Why this is a separate subsystem

Minecraft Java does not render through SwiftUI. The Java client expects a desktop-like platform surface, input/window APIs, audio, and native graphics libraries. Hineka must supply iOS-native implementations or compatible translation layers for those boundaries. Bundling desktop Windows/macOS/Linux native classifiers is not a solution.

OpenJDK Mobile documents Zero as the default iOS VM because iOS does not permit the normal writable-and-executable memory model. That provides a Java execution experiment, not the graphics/window/audio layer. The current Hineka snapshot is only a HelloWorld-style module image and remains a diagnostic input, not a game runtime. See [OpenJDK Mobile iOS build notes](https://github.com/openjdk/mobile#build-static-image-for-ios).

## Public implementation patterns reviewed

| Project | What it demonstrates | License / decision |
|---|---|---|
| [Amethyst iOS](https://github.com/bmcmc/Amethyst-iOS) | UIKit game surface, native CMake target, input bridge, EGL/OpenGL bridge, GLFW compatibility and patched Java-side LWJGL classes | GPL-3.0. Study the architecture; do not copy code or binaries into Hineka without an explicit license decision |
| [FlameLauncher iOS](https://github.com/FlameLaunchers/FlameLauncher-iOS) | Version-aware renderer choices (MobileGlues, GL4ES, Zink), iOS GLFW/input bridge, SDL path for newer Minecraft generations | AGPL-3.0 for the combined project, as declared in its NOTICE. No source/binary reuse is planned |
| [MobileGL](https://github.com/MobileGL-Dev/MobileGL) | Separate GLES and Vulkan backends for translating desktop-style GL workloads to mobile graphics APIs | The repository LICENSE is LGPL-3.0. iOS arm64 compatibility and Minecraft/LWJGL behavior still need a clean build and test |
| [MetalUniversal](https://github.com/EternityQwQ/MetalUniversal) | A Fabric mod can add a native Metal path for supported setups | It is a Fabric mod path, not a general replacement for LWJGL windowing, input, audio, or native runtime integration |

These are reference implementations, not dependencies selected for Hineka. License review must include transitive libraries and generated binaries, not only the top-level repository license. Keep copyright notices and corresponding source obligations for every component actually selected.

## Proposed Hineka boundaries

### 1. Java runtime provider

- Select an iOS arm64 runtime by the Minecraft profile's exact Java major version.
- Record runtime version, architecture, module inventory, native image hash, source URL and license.
- Require the diagnostic module inventory to pass a version-specific baseline before any game session can start.
- Keep Zero interpreter performance as a known risk. Benchmark startup, chunk loading, frame time, memory and thermal behavior on real devices before making a playability claim.

### 2. Platform surface and event bridge

- A UIKit-owned game surface provides lifecycle, safe-area, orientation and touch integration.
- Native input is queued and delivered on the thread expected by the Java windowing API; UIKit callbacks must not invoke Minecraft/LWJGL callbacks directly from arbitrary threads.
- Hardware keyboard, pointer/mouse and GameController input should map to the same event queue as touch controls.
- Audio must use an iOS-compatible implementation and a documented lifecycle for interruptions, route changes and backgrounding.

### 3. Renderer backend selection

- Renderer choice must be tied to the Minecraft/LWJGL generation, not only a global setting.
- Evaluate GL4ES for older fixed-function OpenGL versions, a MobileGlues/MobileGL GLES path for newer OpenGL profiles, and Zink/MoltenVK as an optional Vulkan translation path.
- Keep the renderer behind a Hineka-owned provider boundary: capability probe, native library manifest, environment settings, surface configuration, resize, and shutdown.
- Do not select any backend until its iOS arm64 artifacts, supported GL version/extensions, shader behavior, memory use, dependencies and license are recorded and tested.

### 4. Game JVM session supervisor

The future supervisor owns one long-lived game VM session and exposes:
- prepare: validate profile, runtime, classpath, natives, renderer and authentication;
- start: create/attach the JVM on the approved execution thread and invoke the game's entry point;
- output: stream stdout/stderr and structured stage events to the UI;
- stop: request cooperative shutdown, then report the actual exit result;
- cleanup: release renderer/audio/input resources after the JVM has stopped.

The current HinekaJavaRuntime.runSmokeTest() creates a short-lived VM, invokes a tiny Java method and destroys the VM. It must not be reused as a game session runner. HinekaGameSessionStateMachine is only the tested lifecycle contract; it does not start or stop Java.

## First vertical-slice acceptance plan

Start with one pinned profile rather than claiming every Minecraft version at once. The current test fixtures use Minecraft 1.20.4 / Java 17 as a convenient first investigation target; this is not yet a user-facing compatibility promise.

1. Build and inspect a full iOS arm64 Java runtime for the target major version; verify all required modules and licensing.
2. Prove a Java-created iOS surface can clear and present a frame using the selected renderer.
3. Prove keyboard, pointer, touch and audio lifecycle independently of Minecraft.
4. Launch a minimal Java main class through the long-lived supervisor and test start/stop/error/log events.
5. Only then try the official vanilla client for the pinned profile, followed by a clean world load and measured performance.

## Release gates

- No use of private Apple APIs, copied private entitlements, JIT/signing bypasses or sandbox escapes.
- No desktop native library is accepted as an iOS artifact; all native artifacts must be arm64 iOS builds and hash-verified.
- The runtime and each native component have a reviewed license/provenance record.
- A real device test must cover launch, render, input, audio, stop, crash handling, memory pressure and thermal behavior.
- The Play button remains disabled until all gates for the selected profile pass.
