# Hineka Java runtime and installation plan

Status: **GitHub Actions build #56 passed on 2026-11-17**, including 16 launch-plan/asset-compatibility smoke tests and an unsigned generic iOS device Xcode build. This validates compilation and host-side launch-plan logic only. The Java smoke-test bridge has not yet been run on a signed physical iPhone/iPad. The full Minecraft-compatible Java runtime, iOS native libraries, renderer, and actual game launch are not implemented.

## Non-negotiable project boundaries
- This is the separate **Hineka iOS** project. Do not modify `realdevMCios/test-script` or any other unrelated repository.
- Do not copy Amethyst/Pojav private entitlements, sandbox bypasses, code-signing bypasses, private Apple APIs, or jailbreak/TrollStore-only setup into Hineka.
- Do not bundle Mojang's game JARs/assets or Java distributions without checking the relevant license and distribution terms. Prefer downloading permitted game files from official Mojang metadata after the user selects a version.
- Keep every runtime component's source, binary provenance, architecture, version, license, and SHA-256 recorded.
- Preserve OpenJDK Mobile's `LICENSE`, `ASSEMBLY_EXCEPTION`, and `ADDITIONAL_LICENSE_INFO` with any future runtime artifact. The experimental script currently builds for evaluation only; do not ship the generated static library until its complete license and linkage obligations are reviewed.

## OpenJDK Mobile Zero smoke-test integration
- Hineka now has a first **JNI smoke-test integration** using the upstream `openjdk-mobile/ios-tools` snapshot. The Objective-C bridge calls `loadfunctions()`, starts `JNI_CreateJavaVM`, invokes `HinekaRuntimeSmokeTest.run()`, collects its output, and shuts down this short-lived test VM.
- The Swift wrapper locates the staged `lib/modules` image and test JAR from its Swift Package resource bundle. Home has a development-only **Thử chạy Java** control. It is a Java startup test only and does not start Minecraft.
- `Scripts/prepare-openjdk-ios-runtime.sh` downloads `OpenJDK.xcframework.zip` and `java_bundle-device.zip` from the upstream `snapshot` release, checks the published SHA-256 digests, verifies that the XCFramework contains an iOS arm64 device slice, stages `lib/modules`, and compiles the smoke-test JAR with Java 17-compatible bytecode.
- The pinned release asset digests are recorded in the script. The snapshot assets were uploaded in March 2026; they are not the same as rebuilding the newer upstream source tree updated in September 2026. This is a reproducible **proof-of-concept dependency**, not a claim that the artifact is the latest OpenJDK Mobile build.
- The upstream `openjdk-mobile/ios-tools` repository is licensed AGPL-3.0. Its build tree includes `symbol_keeper.cpp` in the static runtime link. The exact obligations for redistributing this prebuilt XCFramework with Hineka have **not** been legally reviewed. Keep this integration experimental and do not publish or distribute a bundled runtime until the license/provenance has been reviewed and the required notices/source-offer obligations are clear.
- GitHub Actions build **#56** passed all steps, including 11 launch-plan smoke tests and `xcodebuild` for a generic iOS device target with code signing disabled. The Java smoke-test JAR is run on the macOS CI host; this is not a test of the JVM on an iPhone/iPad. A signed device build and real-device test are still required.

## Runtime architecture
1. **Version manifest and vanilla downloader** — implemented in this repository as an early first pass. It retrieves Mojang metadata, verifies the metadata SHA-1, downloads the selected client JAR, Maven Java library artifacts, asset index, and asset objects, then writes a Hineka installed marker.
2. **Java runtime provider** — an upstream OpenJDK Mobile Zero image and a minimal JNI smoke-test bridge are wired into source. The app must still build and run on a physical device before this counts as a working runtime. A complete Minecraft-compatible JRE/module set for the selected Java major versions is not yet verified.
3. **Native library layer** — not implemented. Minecraft libraries with Linux/macOS/Windows native classifiers cannot be treated as iOS binaries. Hineka needs specifically built iOS arm64-compatible native components and license review.
4. **Graphics and input bridge** — not implemented. Define a renderer surface, OpenGL compatibility strategy, audio/input bridge, safe-area handling, touch controls, external keyboard/mouse, and controller support.
5. **Launch profile / plan** — implemented as an inspectable first pass in `App/Versions/MinecraftLaunchPlan.swift`. It decodes modern JVM/game arguments and legacy `minecraftArguments`, evaluates OS/architecture/feature rules, resolves common and legacy placeholders (`auth_session`, `game_assets`, user-properties fallbacks), constructs a Java classpath, converts `-cp` to the `java.class.path` VM property for a future JNI-created VM, and reports missing Java/native/runtime prerequisites. Unsafe library and logging paths are rejected; offline identity uses Java-compatible version-3 UUIDs. The installer also stages verified copies for `virtual: true` asset indexes under `assets/virtual/legacy` and supports legacy `map_to_resources: true` indexes under the game `resources/` directory. The builder does not execute Java. **Game process supervisor** remains unimplemented; add log streaming, cancellation, pause/stop and lifecycle only after the JNI game entry point exists.
6. **Loader installers** — Forge/Fabric/Quilt are not implemented. Add only after vanilla can launch and runtime compatibility has been tested.

## JIT and performance
- Amethyst's own public README states that its iOS Minecraft Java launcher uses JIT to reach usable performance, and describes separate installation/JIT paths. This is a technical warning, not permission to copy its privileged configuration.
- The first prototype is the tiny Java JNI smoke test described above. The next proof point is to run it on a physical device, inspect the reported Java/VM version, and only then evaluate whether the pinned runtime can support Minecraft's Java requirements. Benchmark frame rate and memory; Zero interpretation may be too slow for a playable experience.
- The smoke-test JAR is compiled with Java 17-compatible bytecode, but that alone does not prove the bundled VM's exact version or compatibility with Minecraft 8/17/21 requirements. The test reports the actual VM version; separate runtimes may be required.
- If an authorized JIT route is ever considered, document the exact supported Apple signing/debug mechanism or approved installation channel. Do not manufacture private entitlements or bypass platform code-signing and sandbox protections.
- Do not advertise "Minecraft Java works" until a clean device test has launched a real game world.

## Current installer limitations
- The installer downloads the vanilla version JSON, client JAR, Java artifact libraries, asset index, and asset objects.
- The launch-plan builder is dependency-injected for tests and has an installed-profile entry point. It produces an inspectable plan but deliberately reports blockers until a matching complete runtime, native renderer/LWJGL layer, and persistent game-JVM bridge exist. The CI smoke suite covers modern and legacy arguments, OS/feature rules, placeholders, Java version matching, identity validation, and unsafe metadata paths.
- The installer deliberately does not download desktop native classifiers, because desktop native libraries are not compatible with iOS.
- The launch-plan builder resolves Mojang argument/rule metadata and prepares a candidate classpath, but it does not install a JRE, authenticate a Microsoft account, launch Java, or install Forge/Fabric.
- Older virtual/resource asset layouts are now materialized from already-downloaded objects. The staging step verifies SHA-1 and size before copying, checks the logical asset paths and destination file types, and is idempotent for already-correct files. The installer still needs device testing and review of older versions and special library metadata before it is considered production-ready.

## Distribution and "install directly" requirement
- Hineka will not require ESign or KSign.
- An iOS IPA cannot simply be installed unsigned. iOS requires a valid Apple signature/provisioning or an Apple-authorized distribution channel.
- App Store submission also needs an explicit review of Apple Guideline 2.5.2 and the Apple Developer Program executable-code rules because the launcher downloads and interprets Minecraft Java bytecode. A TestFlight build is still signed and subject to Apple's developer program terms.
- The current Apple alternative-app/web-distribution availability list covers Brazil, Japan, and the European Union; it does not list Vietnam. Users must also physically be in an eligible region and use an eligible Apple Account region.
- Practical no-ESign/KSign routes to evaluate:
  - **TestFlight** for beta testing. Apple requires an uploaded build with application identifiers/provisioning information; builds can be tested for up to 90 days.
  - **App Store** for public release, subject to review and platform policy.
  - **Direct development install from Xcode** to a registered device, which requires access to a Mac/Xcode and Apple's development signing/provisioning flow.
- A web page that offers an IPA download does not remove the signing requirement. Do not promise a no-signature installation.
- Any Apple Developer account, certificate, provisioning profile, financial contract, or release operation must be handled by the account holder/parent or guardian as appropriate.

## Backend requirement
No new server repository is needed for the current local vanilla-download step. A separate backend repository/service will become necessary before implementing:
- user identity and recovery;
- private cloud sync for mods/resource packs;
- paid/curated mod catalogue and server-side authorization;
- Premium and Coin wallet, top-up gateway, transaction verification, and audit ledger;
- remote abuse prevention and account/device rate limits.

When backend work begins, keep it in a new repository (for example `Hineka-API`) and leave `test-script` completely untouched.
