# Experimental OpenJDK Mobile bridge

This target is an **experimental device-side JVM smoke test**, not a Minecraft runtime.

- `Bridge/` wraps the upstream JNI entry point in Objective-C.
- `Swift/` stages the Java home and calls the short-lived smoke-test VM.
- `SmokeTest/` contains a tiny Java class compiled by the CI bootstrap script.
- `Swift/Resources/lib/modules` and `HinekaRuntimeSmokeTest.jar` are generated locally/inside CI and are not committed.

The bootstrap script downloads only pinned public release artifacts and verifies their published SHA-256 digests before extracting them. It also compiles the Java smoke-test JAR as Java 17 bytecode and runs that JAR on the macOS build host before Xcode builds the iOS app.

**Important limitations**
- The pinned upstream snapshot is a prerelease and is older than the current ios-tools source tree.
- The smoke test must be run on a real iOS device to prove actual VM startup; the current CI build only compiles the app.
- This packages only the OpenJDK VM and `java.base` image used by the upstream HelloWorld example. It does not provide every Java module required by Minecraft.
- It does not add LWJGL/iOS graphics, audio/input integration, Minecraft's complete library rules, Microsoft login, Forge/Fabric or a game process supervisor.
- Do not distribute this runtime until the OpenJDK, OpenJDK Mobile and `openjdk-mobile/ios-tools` licensing obligations have been reviewed. See `Docs/RUNTIME-PLAN.md`.
