import Foundation
import CryptoKit

private struct LaunchPlanTestFailure: Error, CustomStringConvertible {
    let description: String
}

private struct LaunchPlanFixture {
    let root: URL
    let versionDirectory: URL
    let librariesDirectory: URL
    let assetsDirectory: URL
    let workingDirectory: URL
    let javaHome: URL
    let nativeDirectory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HinekaLaunchPlanTests-\(UUID().uuidString)", isDirectory: true)
        versionDirectory = root.appendingPathComponent("versions/1.20.4", isDirectory: true)
        librariesDirectory = root.appendingPathComponent("libraries", isDirectory: true)
        assetsDirectory = root.appendingPathComponent("assets", isDirectory: true)
        workingDirectory = root.appendingPathComponent("game", isDirectory: true)
        javaHome = root.appendingPathComponent("java", isDirectory: true)
        nativeDirectory = root.appendingPathComponent("natives", isDirectory: true)

        for directory in [versionDirectory, librariesDirectory, assetsDirectory.appendingPathComponent("indexes"),
                          workingDirectory, javaHome, nativeDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try Data("client-jar".utf8).write(to: versionDirectory.appendingPathComponent("1.20.4.jar"))
        try Data("{}".utf8).write(to: assetsDirectory.appendingPathComponent("indexes/legacy.json"))
        let library = librariesDirectory.appendingPathComponent("org/example/test/1.0/test-1.0.jar")
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pure-java-library".utf8).write(to: library)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@main
private struct MinecraftLaunchPlanSmokeTests {
    static func main() throws {
        try testOfflineIdentityValidation()
        try testModernArgumentsAndClasspath()
        try testIOSRuleFilteringIsTheDefault()
        try testConditionalFeatureRules()
        try testNativeLibrariesRemainBlocked()
        try testLegacyArgumentTokenization()
        try testUnresolvedPlaceholderIsReported()
        try testUnsafeLibraryPathIsRejected()
        try testUnsafeLoggingPathIsRejected()
        try testAssetIndexMismatchIsRejected()
        try testRuntimeMismatchIsReported()
        try testLegacyVirtualAssetsAreMaterialized()
        try testMapToResourcesAssetsAreMaterialized()
        try testUnsafeAssetNamesAreRejected()
        try testCorruptAssetObjectsAreRejected()
        try testNonCompatibilityIndexesAreNoOps()
        try testRuntimeReportParsesCompleteModuleInventory()
        try testRuntimeReportFindsMissingModules()
        try testRuntimeReportRejectsMalformedOutput()
        try testRuntimeReportRejectsMissingJavaBase()
        try testSessionMachineHappyPath()
        try testSessionMachineStopPath()
        try testSessionMachineFailureAndReset()
        try testSessionMachineRejectsInvalidStart()
        try testSessionMachineRejectsStopWhileIdle()
        try testRendererManifestRejectsReferenceOnlyBackend()
        try testRendererManifestAcceptsVerifiedIOSArm64Backend()
        try testRendererManifestRejectsChecksumMismatch()
        try testRendererManifestRejectsNonIOSMachO()
        try testRendererManifestRejectsUnsupportedJavaMajor()
        try testRendererManifestRejectsUnsafeArtifactPath()
        try testPreflightRejectsIncompleteRuntime()
        try testPreflightPreservesLaunchPlanBlockers()
        try testPreflightRejectsMissingBackendRegistration()
        print("Hineka launch-plan, asset, runtime, session, renderer and preflight tests: 34/34 passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw LaunchPlanTestFailure(description: message) }
    }

    private static func testOfflineIdentityValidation() throws {
        let first = try HinekaLaunchIdentity.offline(username: "Hineka_01")
        let second = try HinekaLaunchIdentity.offline(username: "Hineka_01")
        let notch = try HinekaLaunchIdentity.offline(username: "Notch")
        try expect(first.uuid == second.uuid, "Offline UUID must be deterministic.")
        try expect(notch.uuid == "b50ad385-829d-3141-a216-7e7d7539ba7f",
                   "Offline UUID must match Java's nameUUIDFromBytes algorithm.")
        try expect(!first.isAuthenticated && first.accessToken.isEmpty, "Offline identity must not claim authentication.")

        do {
            _ = try HinekaLaunchIdentity.offline(username: "bad name")
            throw LaunchPlanTestFailure(description: "Invalid username was accepted.")
        } catch HinekaGameLaunchPlanError.invalidUsername {
            // Expected.
        }

        do {
            _ = try HinekaLaunchIdentity(
                username: "Hineka",
                uuid: "not-a-uuid",
                accessToken: "",
                isAuthenticated: false
            )
            throw LaunchPlanTestFailure(description: "Invalid UUID was accepted.")
        } catch HinekaGameLaunchPlanError.invalidUUID {
            // Expected.
        }
    }

    private static func testModernArgumentsAndClasspath() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        let identity = try HinekaLaunchIdentity(
            username: "HinekaTester",
            uuid: "12345678-1234-4234-8234-123456789abc",
            accessToken: "test-secret-token",
            isAuthenticated: true
        )
        let plan = try build(fixture, metadata: baseMetadata(), identity: identity)

        try expect(plan.versionID == "1.20.4", "Version id was not resolved.")
        try expect(plan.javaMajorVersion == 17, "Java version was not resolved.")
        try expect(plan.classpath.count == 2, "Expected one library and the client JAR.")
        try expect(plan.vmOptions.contains(where: { $0.hasPrefix("-Djava.class.path=") }),
                   "JVM classpath option was not converted for JNI.")
        try expect(plan.vmOptions.contains("-Xmx2G"), "JVM memory option was lost.")
        try expect(argumentValue("--username", in: plan.gameArguments) == "HinekaTester",
                   "Player-name placeholder was not replaced.")
        try expect(argumentValue("--version", in: plan.gameArguments) == "1.20.4",
                   "Version placeholder was not replaced.")
        try expect(argumentValue("--width", in: plan.gameArguments) == "1170",
                   "Resolution placeholder was not replaced.")
        try expect(!plan.diagnosticSummary.contains("test-secret-token"),
                   "Access token leaked into diagnostic summary.")
        try expect(plan.blockers.contains(where: { $0.contains("process supervisor") }),
                   "Plan should remain blocked until the game supervisor exists.")
    }

    private static func testIOSRuleFilteringIsTheDefault() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        var metadata = baseMetadata()
        var libraries = metadata["libraries"] as! [[String: Any]]
        libraries.append([
            "name": "org.example:windows-only:1.0",
            "rules": [["action": "allow", "os": ["name": "windows"]]],
            "downloads": [
                "artifact": [
                    "path": "org/example/windows-only/1.0/windows-only-1.0.jar",
                    "url": "https://libraries.minecraft.net/org/example/windows-only/1.0/windows-only-1.0.jar"
                ]
            ]
        ])
        metadata["libraries"] = libraries

        let plan = try build(fixture, metadata: metadata)
        try expect(plan.classpath.count == 2, "Windows-only library was incorrectly included for iOS.")
        try expect(!plan.blockers.contains(where: { $0.contains("windows-only") }),
                   "Skipped Windows library should not become a missing-file blocker.")
    }

    private static func testConditionalFeatureRules() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        var metadata = baseMetadata()
        metadata["arguments"] = [
            "jvm": [["value": "-Xmx2G"]],
            "game": [
                [
                    "rules": [["action": "allow", "features": ["is_demo_user": true]]],
                    "value": "--demo"
                ],
                [
                    "rules": [["action": "allow", "features": ["is_demo_user": false]]],
                    "value": "--standard"
                ]
            ]
        ]

        let plan = try build(fixture, metadata: metadata)
        try expect(plan.gameArguments == ["--standard"],
                   "Conditional Minecraft feature rules were not evaluated.")
    }

    private static func testNativeLibrariesRemainBlocked() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        var metadata = baseMetadata()
        var libraries = metadata["libraries"] as! [[String: Any]]
        libraries.append([
            "name": "org.lwjgl:lwjgl:3.3.1",
            "natives": ["osx": "natives-osx"],
            "downloads": [
                "classifiers": [
                    "natives-osx": [
                        "path": "org/lwjgl/lwjgl/3.3.1/lwjgl-3.3.1-natives-osx.jar",
                        "url": "https://libraries.minecraft.net/org/lwjgl/lwjgl/3.3.1/lwjgl-3.3.1-natives-osx.jar"
                    ]
                ]
            ]
        ])
        metadata["libraries"] = libraries

        let plan = try build(fixture, metadata: metadata, operatingSystemName: "osx")
        try expect(plan.nativeClassifierCount == 1, "Native classifier was not detected.")
        try expect(plan.blockers.contains(where: { $0.contains("renderer replacement") }),
                   "Native renderer requirement was not surfaced as a blocker.")
    }

    private static func testLegacyArgumentTokenization() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        var metadata = baseMetadata()
        metadata.removeValue(forKey: "arguments")
        metadata["minecraftArguments"] =
            "--username ${auth_player_name} --session ${auth_session} --server \"play.example.net\" " +
            "--assetsDir ${game_assets} --userProperties ${user_properties} " +
            "--profileProperties ${profile_properties} --width ${resolution_width}"
        let identity = try HinekaLaunchIdentity(
            username: "HinekaTester",
            uuid: "12345678-1234-4234-8234-123456789abc",
            accessToken: "legacy-session-token",
            isAuthenticated: true
        )

        let plan = try build(fixture, metadata: metadata, identity: identity)
        try expect(argumentValue("--server", in: plan.gameArguments) == "play.example.net",
                   "Quoted legacy argument was not preserved as one token.")
        try expect(argumentValue("--username", in: plan.gameArguments) == "HinekaTester",
                   "Legacy player placeholder was not replaced.")
        try expect(argumentValue("--session", in: plan.gameArguments) == "legacy-session-token",
                   "Legacy auth_session placeholder was not replaced.")
        try expect(argumentValue("--assetsDir", in: plan.gameArguments) ==
                   fixture.assetsDirectory.appendingPathComponent("virtual/legacy").path,
                   "Legacy game_assets directory was not resolved.")
        try expect(argumentValue("--userProperties", in: plan.gameArguments) == "{}",
                   "Fallback user properties were not supplied.")
        try expect(argumentValue("--profileProperties", in: plan.gameArguments) == "{}",
                   "Fallback profile properties were not supplied.")
        try expect(plan.blockers.contains(where: { $0.contains("legacy virtual assets") }),
                   "Missing legacy virtual assets directory was not reported.")
    }

    private static func testUnresolvedPlaceholderIsReported() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        var metadata = baseMetadata()
        metadata["arguments"] = [
            "jvm": [["value": "-Xmx2G"]],
            "game": [["value": "--future"], ["value": "${future_argument}"]]
        ]

        let plan = try build(fixture, metadata: metadata)
        try expect(plan.blockers.contains(where: { $0.contains("future_argument") }),
                   "Unknown launch placeholder was not reported.")
    }

    private static func testUnsafeLibraryPathIsRejected() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        var metadata = baseMetadata()
        var libraries = metadata["libraries"] as! [[String: Any]]
        libraries.append([
            "name": "org.example:escape:1.0",
            "downloads": [
                "artifact": [
                    "path": "../../outside.jar",
                    "url": "https://libraries.minecraft.net/outside.jar"
                ]
            ]
        ])
        metadata["libraries"] = libraries

        do {
            _ = try build(fixture, metadata: metadata)
            throw LaunchPlanTestFailure(description: "Path traversal library was accepted.")
        } catch HinekaGameLaunchPlanError.unsafePath {
            // Expected.
        }
    }

    private static func testUnsafeLoggingPathIsRejected() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        var metadata = baseMetadata()
        metadata["logging"] = [
            "client": [
                "argument": "-Dlog4j.configurationFile=${path}",
                "file": [
                    "id": "../../outside.xml",
                    "sha1": String(repeating: "0", count: 40),
                    "size": 1,
                    "url": "https://piston-meta.mojang.com/logs/outside.xml"
                ]
            ]
        ]

        do {
            _ = try build(fixture, metadata: metadata)
            throw LaunchPlanTestFailure(description: "Path traversal logging config was accepted.")
        } catch HinekaGameLaunchPlanError.unsafePath {
            // Expected.
        }
    }

    private static func testAssetIndexMismatchIsRejected() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        do {
            _ = try build(fixture, metadata: baseMetadata(), expectedAssetIndexID: "different-index")
            throw LaunchPlanTestFailure(description: "Mismatched installed asset index was accepted.")
        } catch HinekaGameLaunchPlanError.invalidMetadata {
            // Expected.
        }
    }

    private static func testRuntimeMismatchIsReported() throws {
        let fixture = try LaunchPlanFixture()
        defer { fixture.remove() }
        let plan = try build(fixture, metadata: baseMetadata(), runtimeJavaMajorVersion: 21)
        try expect(plan.blockers.contains(where: { $0.contains("Java 21") && $0.contains("Java 17") }),
                   "Java runtime mismatch was not reported.")
    }

    private static func testLegacyVirtualAssetsAreMaterialized() throws {
        let fixture = try AssetStagerFixture()
        defer { fixture.remove() }
        let logicalName = "minecraft/sounds/random/click.ogg"
        let payload = Data("legacy-audio-asset".utf8)
        let object = try fixture.writeObject(payload)
        let index = try fixture.decodeIndex([
            "virtual": true,
            "objects": [logicalName: object]
        ])

        let result = try MinecraftAssetCompatibilityStager.stage(
            assetIndex: index,
            assetsDirectory: fixture.assetsDirectory,
            resourcesDirectory: fixture.resourcesDirectory
        )
        let destination = fixture.assetsDirectory
            .appendingPathComponent("virtual/legacy", isDirectory: true)
            .appendingPathComponent(logicalName)

        try expect(result.virtualFileCount == 1 && result.resourceFileCount == 0,
                   "Virtual asset mapping count is incorrect.")
        let virtualPayload = try Data(contentsOf: destination)
        try expect(virtualPayload == payload,
                   "Legacy virtual asset was not copied to the expected path.")

        let secondRun = try MinecraftAssetCompatibilityStager.stage(
            assetIndex: index,
            assetsDirectory: fixture.assetsDirectory,
            resourcesDirectory: fixture.resourcesDirectory
        )
        try expect(secondRun.virtualFileCount == 1, "Virtual asset staging should be idempotent.")
    }

    private static func testMapToResourcesAssetsAreMaterialized() throws {
        let fixture = try AssetStagerFixture()
        defer { fixture.remove() }
        let logicalName = "sound/old_menu.ogg"
        let payload = Data("legacy-resource".utf8)
        let object = try fixture.writeObject(payload)
        let index = try fixture.decodeIndex([
            "map_to_resources": true,
            "objects": [logicalName: object]
        ])

        let result = try MinecraftAssetCompatibilityStager.stage(
            assetIndex: index,
            assetsDirectory: fixture.assetsDirectory,
            resourcesDirectory: fixture.resourcesDirectory
        )
        let destination = fixture.resourcesDirectory.appendingPathComponent(logicalName)
        try expect(result.resourceFileCount == 1 && result.virtualFileCount == 0,
                   "map_to_resources count is incorrect.")
        let resourcePayload = try Data(contentsOf: destination)
        try expect(resourcePayload == payload,
                   "map_to_resources asset was not materialized.")
    }

    private static func testUnsafeAssetNamesAreRejected() throws {
        let fixture = try AssetStagerFixture()
        defer { fixture.remove() }
        let payload = Data("safe-object".utf8)
        let object = try fixture.writeObject(payload)
        let index = try fixture.decodeIndex([
            "virtual": true,
            "objects": ["../escape.bin": object]
        ])

        do {
            _ = try MinecraftAssetCompatibilityStager.stage(
                assetIndex: index,
                assetsDirectory: fixture.assetsDirectory,
                resourcesDirectory: fixture.resourcesDirectory
            )
            throw LaunchPlanTestFailure(description: "Path traversal asset name was accepted.")
        } catch let error as MinecraftVersionInstallerError {
            try expect(error.localizedDescription == "Đường dẫn tệp trong manifest không hợp lệ.",
                       "Unsafe asset path failed for an unexpected reason.")
        }
    }

    private static func testCorruptAssetObjectsAreRejected() throws {
        let fixture = try AssetStagerFixture()
        defer { fixture.remove() }
        let payload = Data("good-object".utf8)
        let corrupt = Data("bad-object!".utf8)
        let object = try fixture.writeObject(corrupt, expectedPayloadForHash: payload)
        let index = try fixture.decodeIndex([
            "virtual": true,
            "objects": ["minecraft/textures/missing.png": object]
        ])

        do {
            _ = try MinecraftAssetCompatibilityStager.stage(
                assetIndex: index,
                assetsDirectory: fixture.assetsDirectory,
                resourcesDirectory: fixture.resourcesDirectory
            )
            throw LaunchPlanTestFailure(description: "Corrupt source asset object was accepted.")
        } catch let error as MinecraftVersionInstallerError {
            try expect(error.localizedDescription.contains("SHA-1"),
                       "Corrupt source asset failed for an unexpected reason.")
        }
    }

    private static func testNonCompatibilityIndexesAreNoOps() throws {
        let fixture = try AssetStagerFixture()
        defer { fixture.remove() }
        let payload = Data("modern-object".utf8)
        let object = try fixture.writeObject(payload)
        let index = try fixture.decodeIndex(["objects": ["minecraft/lang/en_us.json": object]])

        let result = try MinecraftAssetCompatibilityStager.stage(
            assetIndex: index,
            assetsDirectory: fixture.assetsDirectory,
            resourcesDirectory: fixture.resourcesDirectory
        )
        try expect(result.virtualFileCount == 0 && result.resourceFileCount == 0,
                   "Modern non-virtual indexes should not duplicate assets.")
        let virtualRoot = fixture.assetsDirectory.appendingPathComponent("virtual")
        try expect(!FileManager.default.fileExists(atPath: virtualRoot.path),
                   "A virtual directory was created for an index without compatibility flags.")
    }

    private struct AssetStagerFixture {
        let root: URL
        let assetsDirectory: URL
        let resourcesDirectory: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("HinekaAssetStagerTests-\(UUID().uuidString)", isDirectory: true)
            assetsDirectory = root.appendingPathComponent("assets", isDirectory: true)
            resourcesDirectory = root.appendingPathComponent("resources", isDirectory: true)
            try FileManager.default.createDirectory(
                at: assetsDirectory.appendingPathComponent("objects"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
        }

        func writeObject(_ stored: Data, expectedPayloadForHash: Data? = nil) throws -> [String: Any] {
            let hashPayload = expectedPayloadForHash ?? stored
            let hash = Insecure.SHA1.hash(data: hashPayload)
                .map { String(format: "%02x", $0) }
                .joined()
            let objectURL = assetsDirectory.appendingPathComponent("objects/\(hash.prefix(2))/\(hash)")
            try FileManager.default.createDirectory(
                at: objectURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try stored.write(to: objectURL)
            return ["hash": hash, "size": stored.count]
        }

        func decodeIndex(_ json: [String: Any]) throws -> MinecraftAssetIndex {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            return try JSONDecoder().decode(MinecraftAssetIndex.self, from: data)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private static func testRuntimeReportParsesCompleteModuleInventory() throws {
        let modules = HinekaJavaRuntimeReport.minecraftBaselineModules.sorted().joined(separator: ",")
        let output = runtimeReport(
            javaVersion: "24.0.1",
            javaMajor: "24",
            vmName: "OpenJDK 64-Bit Zero VM",
            architecture: "aarch64",
            modules: modules
        )
        let report = try HinekaJavaRuntimeReport.parse(output)
        try expect(report.javaMajorVersion == 24, "Runtime Java major was not parsed.")
        try expect(report.is64BitARM, "ARM64 architecture was not detected.")
        try expect(report.isZeroVM, "OpenJDK Zero VM was not identified.")
        try expect(report.hasBaselineModuleCoverage, "Complete baseline module set was marked incomplete.")
        try expect(report.missingBaselineModules.isEmpty, "Unexpected missing baseline modules.")
        try expect(report.summary.contains("chưa có JIT"), "Zero interpreter warning was not displayed.")
    }

    private static func testRuntimeReportFindsMissingModules() throws {
        let output = runtimeReport(
            javaVersion: "24.0.1",
            javaMajor: "24",
            vmName: "OpenJDK 64-Bit Zero VM",
            architecture: "arm64",
            modules: "java.base,java.logging"
        )
        let report = try HinekaJavaRuntimeReport.parse(output)
        try expect(!report.hasBaselineModuleCoverage, "Incomplete module image was marked complete.")
        try expect(report.missingBaselineModules.contains("java.desktop"),
                   "Missing java.desktop module was not reported.")
        try expect(report.missingBaselineModules.contains("jdk.unsupported"),
                   "Missing jdk.unsupported module was not reported.")
    }

    private static func testRuntimeReportRejectsMalformedOutput() throws {
        do {
            _ = try HinekaJavaRuntimeReport.parse("not a runtime report")
            throw LaunchPlanTestFailure(description: "Malformed runtime report was accepted.")
        } catch HinekaJavaRuntimeReportError.invalidFormat {
            // Expected.
        }
    }

    private static func testRuntimeReportRejectsMissingJavaBase() throws {
        let output = runtimeReport(
            javaVersion: "24.0.1",
            javaMajor: "24",
            vmName: "OpenJDK 64-Bit Zero VM",
            architecture: "aarch64",
            modules: "java.logging,java.xml"
        )
        do {
            _ = try HinekaJavaRuntimeReport.parse(output)
            throw LaunchPlanTestFailure(description: "A runtime without java.base was accepted.")
        } catch HinekaJavaRuntimeReportError.missingJavaBase {
            // Expected.
        }
    }

    private static func runtimeReport(
        javaVersion: String,
        javaMajor: String,
        vmName: String,
        architecture: String,
        modules: String
    ) -> String {
        """
        HINEKA_RUNTIME_REPORT=1
        java.version=\(javaVersion)
        java.major=\(javaMajor)
        vm.name=\(vmName)
        vm.info=interpreted mode
        os.name=iOS
        os.arch=\(architecture)
        processors=6
        modules=\(modules)
        """
    }

    private static func testRendererManifestRejectsReferenceOnlyBackend() throws {
        let fixture = try RendererFixture()
        defer { fixture.remove() }
        let artifact = try fixture.writeArtifact(makeIOSArm64MachO())
        let manifest = fixture.manifest(
            artifact: artifact,
            status: .referenceOnly
        )
        let backend = TestRendererBackend(manifest: manifest)
        let result = HinekaRendererManifestValidator.validate(
            manifest: manifest,
            backend: backend,
            rendererDirectory: fixture.root,
            requiredJavaMajorVersion: 17
        )
        try expect(!result.isReady, "A research-only renderer must not pass preflight.")
        try expect(result.blockers.contains(where: { $0.contains("chưa được tích hợp") }),
                   "Research-only renderer blocker was not surfaced.")
    }

    private static func testRendererManifestAcceptsVerifiedIOSArm64Backend() throws {
        let fixture = try RendererFixture()
        defer { fixture.remove() }
        let artifact = try fixture.writeArtifact(makeIOSArm64MachO())
        let manifest = fixture.manifest(artifact: artifact, status: .integrated)
        let backend = TestRendererBackend(manifest: manifest)
        let report = try makeCompleteRuntimeReport(javaMajor: 17)
        let result = HinekaGameStartupPreflight.evaluate(
            requiredJavaMajorVersion: 17,
            runtime: report,
            rendererManifest: manifest,
            rendererBackend: backend,
            rendererDirectory: fixture.root
        )
        try expect(result.canStart, "A complete synthetic iOS arm64 renderer setup should pass.")
    }

    private static func testRendererManifestRejectsChecksumMismatch() throws {
        let fixture = try RendererFixture()
        defer { fixture.remove() }
        let artifact = try fixture.writeArtifact(makeIOSArm64MachO(), overrideSHA256: String(repeating: "0", count: 64))
        let manifest = fixture.manifest(artifact: artifact, status: .integrated)
        let backend = TestRendererBackend(manifest: manifest)
        let result = HinekaRendererManifestValidator.validate(
            manifest: manifest,
            backend: backend,
            rendererDirectory: fixture.root,
            requiredJavaMajorVersion: 17
        )
        try expect(result.blockers.contains(where: { $0.contains("không khớp SHA-256") }),
                   "Renderer checksum mismatch was not rejected.")
    }

    private static func testRendererManifestRejectsNonIOSMachO() throws {
        let fixture = try RendererFixture()
        defer { fixture.remove() }
        let artifact = try fixture.writeArtifact(makeIOSArm64MachO(platform: 1))
        let manifest = fixture.manifest(artifact: artifact, status: .integrated)
        let backend = TestRendererBackend(manifest: manifest)
        let result = HinekaRendererManifestValidator.validate(
            manifest: manifest,
            backend: backend,
            rendererDirectory: fixture.root,
            requiredJavaMajorVersion: 17
        )
        try expect(result.blockers.contains(where: { $0.contains("không khai báo nền tảng iOS") }),
                   "macOS Mach-O was incorrectly accepted as iOS.")
    }

    private static func testRendererManifestRejectsUnsupportedJavaMajor() throws {
        let fixture = try RendererFixture()
        defer { fixture.remove() }
        let artifact = try fixture.writeArtifact(makeIOSArm64MachO())
        let manifest = fixture.manifest(artifact: artifact, status: .integrated, supportedJavaMajorVersions: [21])
        let result = HinekaRendererManifestValidator.validate(
            manifest: manifest,
            backend: TestRendererBackend(manifest: manifest),
            rendererDirectory: fixture.root,
            requiredJavaMajorVersion: 17
        )
        try expect(result.blockers.contains(where: { $0.contains("không khai báo hỗ trợ Java 17") }),
                   "Unsupported Java major was not rejected.")
    }

    private static func testRendererManifestRejectsUnsafeArtifactPath() throws {
        let fixture = try RendererFixture()
        defer { fixture.remove() }
        let artifact = HinekaRendererNativeArtifact(
            relativePath: "../outside.dylib",
            sha256: String(repeating: "a", count: 64),
            platform: "ios",
            architecture: "arm64"
        )
        let manifest = HinekaRendererManifest(
            identifier: "test-renderer",
            displayName: "Test Renderer",
            integrationStatus: .integrated,
            supportedJavaMajorVersions: [17],
            artifacts: [artifact]
        )
        let result = HinekaRendererManifestValidator.validate(
            manifest: manifest,
            backend: TestRendererBackend(manifest: manifest),
            rendererDirectory: fixture.root,
            requiredJavaMajorVersion: 17
        )
        try expect(result.blockers.contains(where: { $0.contains("Đường dẫn native artifact") }),
                   "Unsafe native artifact path was not rejected.")
    }

    private static func testPreflightRejectsIncompleteRuntime() throws {
        let fixture = try RendererFixture()
        defer { fixture.remove() }
        let artifact = try fixture.writeArtifact(makeIOSArm64MachO())
        let manifest = fixture.manifest(artifact: artifact, status: .integrated)
        let report = try makeCompleteRuntimeReport(javaMajor: 21, modules: ["java.base", "java.logging"])
        let result = HinekaGameStartupPreflight.evaluate(
            requiredJavaMajorVersion: 17,
            runtime: report,
            rendererManifest: manifest,
            rendererBackend: TestRendererBackend(manifest: manifest),
            rendererDirectory: fixture.root
        )
        try expect(!result.canStart, "Runtime mismatch and missing modules must block startup.")
        try expect(result.blockers.contains(where: { $0.contains("không khớp Java 17") }),
                   "Java major mismatch was not surfaced.")
        try expect(result.blockers.contains(where: { $0.contains("thiếu module baseline") }),
                   "Missing module baseline was not surfaced.")
    }

    private static func testPreflightPreservesLaunchPlanBlockers() throws {
        let fixture = try RendererFixture()
        defer { fixture.remove() }
        let artifact = try fixture.writeArtifact(makeIOSArm64MachO())
        let manifest = fixture.manifest(artifact: artifact, status: .integrated)
        let report = try makeCompleteRuntimeReport(javaMajor: 17)
        let result = HinekaGameStartupPreflight.evaluate(
            requiredJavaMajorVersion: 17,
            runtime: report,
            rendererManifest: manifest,
            rendererBackend: TestRendererBackend(manifest: manifest),
            rendererDirectory: fixture.root,
            launchPlanBlockers: ["JNI game supervisor chưa được triển khai."]
        )
        try expect(!result.canStart, "An incomplete launch plan must block startup.")
        try expect(result.blockers.contains("JNI game supervisor chưa được triển khai."),
                   "Launch-plan blockers were not preserved by preflight.")
    }

    private static func testPreflightRejectsMissingBackendRegistration() throws {
        let fixture = try RendererFixture()
        defer { fixture.remove() }
        let artifact = try fixture.writeArtifact(makeIOSArm64MachO())
        let manifest = fixture.manifest(artifact: artifact, status: .integrated)
        let result = HinekaRendererManifestValidator.validate(
            manifest: manifest,
            backend: nil,
            rendererDirectory: fixture.root,
            requiredJavaMajorVersion: 17
        )
        try expect(result.blockers.contains(where: { $0.contains("Chưa đăng ký HinekaRendererBackend") }),
                   "Missing renderer backend registration was not rejected.")
    }

    private struct RendererFixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("HinekaRendererTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func writeArtifact(_ data: Data, overrideSHA256: String? = nil) throws -> HinekaRendererNativeArtifact {
            let file = root.appendingPathComponent("libHinekaRenderer.dylib")
            try data.write(to: file)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return HinekaRendererNativeArtifact(
                relativePath: file.lastPathComponent,
                sha256: overrideSHA256 ?? hash,
                platform: "ios",
                architecture: "arm64"
            )
        }

        func manifest(
            artifact: HinekaRendererNativeArtifact,
            status: HinekaRendererIntegrationStatus,
            supportedJavaMajorVersions: Set<Int> = [17]
        ) -> HinekaRendererManifest {
            HinekaRendererManifest(
                identifier: "test-renderer",
                displayName: "Test Renderer",
                integrationStatus: status,
                supportedJavaMajorVersions: supportedJavaMajorVersions,
                artifacts: [artifact]
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private struct TestRendererBackend: HinekaRendererBackend {
        let manifest: HinekaRendererManifest
        func prepare(configuration: HinekaRendererLaunchConfiguration) throws {}
        func resize(width: Int, height: Int) throws {}
        func shutdown() throws {}
    }

    private static func makeCompleteRuntimeReport(
        javaMajor: Int,
        modules: Set<String> = HinekaJavaRuntimeReport.minecraftBaselineModules
    ) throws -> HinekaJavaRuntimeReport {
        let output = runtimeReport(
            javaVersion: "\(javaMajor).0.1",
            javaMajor: String(javaMajor),
            vmName: "OpenJDK 64-Bit Zero VM",
            architecture: "aarch64",
            modules: modules.sorted().joined(separator: ",")
        )
        return try HinekaJavaRuntimeReport.parse(output)
    }

    private static func makeIOSArm64MachO(
        platform: UInt32 = 2,
        cpuType: UInt32 = 0x0100000c
    ) -> Data {
        var data = Data()
        func append(_ value: UInt32) {
            data.append(UInt8(value & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8((value >> 16) & 0xff))
            data.append(UInt8((value >> 24) & 0xff))
        }
        append(0xfeedfacf) // MH_MAGIC_64
        append(cpuType)    // CPU_TYPE_ARM64
        append(0)          // cpusubtype
        append(6)          // MH_DYLIB
        append(1)          // ncmds
        append(24)         // sizeofcmds
        append(0)          // flags
        append(0)          // reserved
        append(0x32)       // LC_BUILD_VERSION
        append(24)         // cmdsize
        append(platform)   // PLATFORM_IOS = 2
        append(0x00120000) // min OS
        append(0x00120000) // SDK
        append(0)          // ntools
        return data
    }

    private static func testSessionMachineHappyPath() throws {
        var machine = HinekaGameSessionStateMachine()
        let preparing = try machine.apply(.beginPreparation)
        try expect(preparing == .preparing, "Session did not enter preparing.")
        let starting = try machine.apply(.runtimeReady)
        try expect(starting == .starting, "Session did not enter starting.")
        let running = try machine.apply(.didStart)
        try expect(running == .running, "Session did not enter running.")
        let exited = try machine.apply(.didExit(0))
        try expect(exited == .exited(0), "Successful process exit was not recorded.")
        try expect(!machine.state.isActive && machine.state.isTerminal,
                   "Exited session must be terminal and inactive.")
    }

    private static func testSessionMachineStopPath() throws {
        var machine = HinekaGameSessionStateMachine()
        try machine.apply(.beginPreparation)
        try machine.apply(.runtimeReady)
        try machine.apply(.didStart)
        let stopping = try machine.apply(.requestStop)
        try expect(stopping == .stopping, "Stop request did not enter stopping.")
        let exited = try machine.apply(.didExit(143))
        try expect(exited == .exited(143), "Stopped process exit code was not retained.")
    }

    private static func testSessionMachineFailureAndReset() throws {
        var machine = HinekaGameSessionStateMachine()
        try machine.apply(.beginPreparation)
        let failed = try machine.apply(.didFail("runtime missing"))
        try expect(failed == .failed("runtime missing"), "Preparation failure was not retained.")
        let reset = try machine.apply(.reset)
        try expect(reset == .idle, "Terminal failure did not reset to idle.")
    }

    private static func testSessionMachineRejectsInvalidStart() throws {
        var machine = HinekaGameSessionStateMachine()
        do {
            try machine.apply(.didStart)
            throw LaunchPlanTestFailure(description: "Session started without preparation.")
        } catch HinekaGameSessionStateMachineError.invalidTransition {
            // Expected.
        }
    }

    private static func testSessionMachineRejectsStopWhileIdle() throws {
        var machine = HinekaGameSessionStateMachine()
        do {
            try machine.apply(.requestStop)
            throw LaunchPlanTestFailure(description: "Idle session accepted a stop request.")
        } catch HinekaGameSessionStateMachineError.invalidTransition {
            // Expected.
        }
    }

    private static func baseMetadata() -> [String: Any] {
        [
            "id": "1.20.4",
            "type": "release",
            "mainClass": "net.minecraft.client.main.Main",
            "assets": "legacy",
            "assetIndex": [
                "id": "legacy",
                "url": "https://piston-meta.mojang.com/assets/legacy.json"
            ],
            "downloads": [
                "client": ["url": "https://piston-data.mojang.com/client.jar"]
            ],
            "libraries": [[
                "name": "org.example:test:1.0",
                "downloads": [
                    "artifact": [
                        "path": "org/example/test/1.0/test-1.0.jar",
                        "url": "https://libraries.minecraft.net/org/example/test/1.0/test-1.0.jar"
                    ]
                ]
            ]],
            "javaVersion": [
                "component": "java-runtime-gamma",
                "majorVersion": 17
            ],
            "arguments": [
                "jvm": [
                    ["value": "-Xmx2G"],
                    ["value": "-cp"],
                    ["value": "${classpath}"]
                ],
                "game": [
                    ["value": "--username"],
                    ["value": "${auth_player_name}"],
                    ["value": "--version"],
                    ["value": "${version_name}"],
                    ["value": "--gameDir"],
                    ["value": "${game_directory}"],
                    ["value": "--assetsDir"],
                    ["value": "${assets_root}"],
                    ["value": "--assetIndex"],
                    ["value": "${assets_index_name}"],
                    ["value": "--width"],
                    ["value": "${resolution_width}"]
                ]
            ]
        ]
    }

    private static func build(
        _ fixture: LaunchPlanFixture,
        metadata: [String: Any],
        identity: HinekaLaunchIdentity? = nil,
        expectedAssetIndexID: String? = nil,
        runtimeJavaMajorVersion: Int? = 17,
        operatingSystemName: String = "ios"
    ) throws -> HinekaGameLaunchPlan {
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        let launchIdentity = try identity ?? HinekaLaunchIdentity.offline(username: "HinekaTester")
        return try HinekaGameLaunchPlanBuilder.build(
            metadataData: data,
            versionDirectory: fixture.versionDirectory,
            librariesDirectory: fixture.librariesDirectory,
            assetsDirectory: fixture.assetsDirectory,
            workingDirectory: fixture.workingDirectory,
            javaHome: fixture.javaHome,
            nativeDirectory: fixture.nativeDirectory,
            identity: launchIdentity,
            runtimeJavaMajorVersion: runtimeJavaMajorVersion,
            expectedAssetIndexID: expectedAssetIndexID,
            operatingSystemName: operatingSystemName
        )
    }

    private static func argumentValue(_ key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
