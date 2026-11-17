# Experimental OpenJDK Mobile bridge

This target is an **experimental device-side JVM smoke test**, not a Minecraft runtime.

- `Bridge/` wraps the upstream JNI entry point in Objective-C.
- `Swift/` stages the Java home and calls the short-lived smoke-test VM.
- `SmokeTest/` contains a tiny Java class compiled by the CI bootstrap script.
- `Swift/Resources/lib/modules` and `HinekaRuntimeSmokeTest.jar` are generated locally/inside CI and are not committed.

The bootstrap script downloads only pinned public release artifacts and verifies their published SHA-256 digests before extracting them. It also compiles the Java smoke-test JAR as Java 17 bytecode and runs that JAR on the macOS build host before Xcode builds the iOS app.

**Important limitations**
- The pinned upstream snapshot is a prerelease and is older than the current ios-tools source tree.
- The smoke test must be run on a real iOS device to prove actual VM startup; CI currently runs the diagnostic JAR on the macOS host and builds the iOS target without launching it.
- The Java diagnostic now reports the actual Java major version, VM, operating system/architecture, boot-layer modules, and a conservative Minecraft module baseline. The parser is host-tested with synthetic full and incomplete reports; only the result captured on a physical device describes the bundled runtime.
- This packages only the OpenJDK VM and `java.base` image used by the upstream HelloWorld example. The runtime diagnostic checks for a conservative module baseline including `java.desktop`, `java.logging`, `java.management`, `java.naming`, `java.xml`, and `jdk.unsupported`; passing that baseline still does not prove all modules or Minecraft compatibility.
- It does not add LWJGL/iOS graphics, audio/input integration, Minecraft's complete library rules, Microsoft login, or Forge/Fabric.
- `HinekaGameSessionStateMachine` defines/test-drives future session transitions only; CI passed its happy-path, stop, failure/reset, and invalid-transition tests. It does not create a persistent JVM or invoke Minecraft.
- Do not distribute this runtime until the OpenJDK, OpenJDK Mobile and `openjdk-mobile/ios-tools` licensing obligations have been reviewed. See `Docs/RUNTIME-PLAN.md`.
