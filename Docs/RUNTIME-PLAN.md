# Hineka Java runtime and installation plan

Status: architecture and integration plan. The vanilla downloader is implemented in the SwiftUI source package; the Java VM, iOS native libraries, renderer, and actual game launch are not implemented.

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
- The CI workflow now prepares the pinned runtime inputs and compiles an unsigned generic iOS device target. A successful CI compile would still not prove that the Java VM starts on hardware; that needs a signed development build and a real iPhone/iPad test.

## Runtime architecture
1. **Version manifest and vanilla downloader** — implemented in this repository as an early first pass. It retrieves Mojang metadata, verifies the metadata SHA-1, downloads the selected client JAR, Maven Java library artifacts, asset index, and asset objects, then writes a Hineka installed marker.
2. **Java runtime provider** — not implemented. Hineka needs a supported OpenJDK/JRE build for iOS arm64, correct Java major versions for selected Minecraft versions, and a documented no-JIT vs authorized-JIT strategy.
3. **Native library layer** — not implemented. Minecraft libraries with Linux/macOS/Windows native classifiers cannot be treated as iOS binaries. Hineka needs specifically built iOS arm64-compatible native components and license review.
4. **Graphics and input bridge** — not implemented. Define a renderer surface, OpenGL compatibility strategy, audio/input bridge, safe-area handling, touch controls, external keyboard/mouse, and controller support.
5. **Launch profile and process supervisor** — not implemented. Build a classpath and JVM arguments from validated version metadata, apply profile-specific mods/resource packs, capture logs, support cancellation, and cleanly stop the Java process.
6. **Loader installers** — Forge/Fabric/Quilt are not implemented. Add only after vanilla can launch and runtime compatibility has been tested.

## JIT and performance
- Amethyst's own public README states that its iOS Minecraft Java launcher uses JIT to reach usable performance, and describes separate installation/JIT paths. This is a technical warning, not permission to copy its privileged configuration.
- The first prototype is the tiny Java JNI smoke test described above. The next proof point is to run it on a physical device, inspect the reported Java/VM version, and only then evaluate whether the pinned runtime can support Minecraft's Java requirements. Benchmark frame rate and memory; Zero interpretation may be too slow for a playable experience.
- The smoke-test JAR is compiled with Java 17-compatible bytecode, but that alone does not prove the bundled VM's exact version or compatibility with Minecraft 8/17/21 requirements. The test reports the actual VM version; separate runtimes may be required.
- If an authorized JIT route is ever considered, document the exact supported Apple signing/debug mechanism or approved installation channel. Do not manufacture private entitlements or bypass platform code-signing and sandbox protections.
- Do not advertise "Minecraft Java works" until a clean device test has launched a real game world.

## Current installer limitations
- The installer downloads the vanilla version JSON, client JAR, Java artifact libraries, asset index, and asset objects.
- It deliberately does not download native classifiers, because desktop native libraries are not compatible with iOS.
- It does not yet perform Mojang argument/rule resolution, install a JRE, authenticate a Microsoft account, prepare the final classpath, launch Java, or install Forge/Fabric.
- The installer needs device testing and a review of older versions and special library metadata before it is considered production-ready.

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
