# Hineka Java runtime and installation plan

Status: architecture and integration plan. The vanilla downloader is implemented in the SwiftUI source package; the Java VM, iOS native libraries, renderer, and actual game launch are not implemented.

## Non-negotiable project boundaries
- This is the separate **Hineka iOS** project. Do not modify `realdevMCios/test-script` or any other unrelated repository.
- Do not copy Amethyst/Pojav private entitlements, sandbox bypasses, code-signing bypasses, private Apple APIs, or jailbreak/TrollStore-only setup into Hineka.
- Do not bundle Mojang's game JARs/assets or Java distributions without checking the relevant license and distribution terms. Prefer downloading permitted game files from official Mojang metadata after the user selects a version.
- Keep every runtime component's source, binary provenance, architecture, version, license, and SHA-256 recorded.

## Runtime architecture
1. **Version manifest and vanilla downloader** — implemented in this repository as an early first pass. It retrieves Mojang metadata, verifies the metadata SHA-1, downloads the selected client JAR, Maven Java library artifacts, asset index, and asset objects, then writes a Hineka installed marker.
2. **Java runtime provider** — not implemented. Hineka needs a supported OpenJDK/JRE build for iOS arm64, correct Java major versions for selected Minecraft versions, and a documented no-JIT vs authorized-JIT strategy.
3. **Native library layer** — not implemented. Minecraft libraries with Linux/macOS/Windows native classifiers cannot be treated as iOS binaries. Hineka needs specifically built iOS arm64-compatible native components and license review.
4. **Graphics and input bridge** — not implemented. Define a renderer surface, OpenGL compatibility strategy, audio/input bridge, safe-area handling, touch controls, external keyboard/mouse, and controller support.
5. **Launch profile and process supervisor** — not implemented. Build a classpath and JVM arguments from validated version metadata, apply profile-specific mods/resource packs, capture logs, support cancellation, and cleanly stop the Java process.
6. **Loader installers** — Forge/Fabric/Quilt are not implemented. Add only after vanilla can launch and runtime compatibility has been tested.

## JIT and performance
- Amethyst's own public README states that its iOS Minecraft Java launcher uses JIT to reach usable performance, and describes separate installation/JIT paths. This is a technical warning, not permission to copy its privileged configuration.
- First prototype should investigate a sandbox-respecting interpreter/no-JIT runtime. Measure whether a tiny Java program and then vanilla Minecraft can run at an acceptable speed.
- If an authorized JIT route is required, document the exact supported Apple signing/debug mechanism or approved installation channel. Do not attempt to manufacture private entitlements or bypass platform code-signing and sandbox protections.
- Do not advertise "Minecraft Java works" until a clean device test has launched a real game world.

## Current installer limitations
- The installer downloads the vanilla version JSON, client JAR, Java artifact libraries, asset index, and asset objects.
- It deliberately does not download native classifiers, because desktop native libraries are not compatible with iOS.
- It does not yet perform Mojang argument/rule resolution, install a JRE, authenticate a Microsoft account, prepare the final classpath, launch Java, or install Forge/Fabric.
- The installer needs device testing and a review of older versions and special library metadata before it is considered production-ready.

## Distribution and "install directly" requirement
- Hineka will not require ESign or KSign.
- An iOS IPA cannot simply be installed unsigned. iOS requires a valid Apple signature/provisioning or an Apple-authorized distribution channel.
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
