import Foundation

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
        try testNativeLibrariesRemainBlocked()
        try testLegacyArgumentTokenization()
        try testUnresolvedPlaceholderIsReported()
        try testUnsafeLibraryPathIsRejected()
        try testAssetIndexMismatchIsRejected()
        try testRuntimeMismatchIsReported()
        print("Hineka launch-plan smoke tests: 9/9 passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw LaunchPlanTestFailure(description: message) }
    }

    private static func testOfflineIdentityValidation() throws {
        let first = try HinekaLaunchIdentity.offline(username: "Hineka_01")
        let second = try HinekaLaunchIdentity.offline(username: "Hineka_01")
        try expect(first.uuid == second.uuid, "Offline UUID must be deterministic.")
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
            "--username ${auth_player_name} --server \"play.example.net\" --width ${resolution_width}"

        let plan = try build(fixture, metadata: metadata)
        try expect(argumentValue("--server", in: plan.gameArguments) == "play.example.net",
                   "Quoted legacy argument was not preserved as one token.")
        try expect(argumentValue("--username", in: plan.gameArguments) == "HinekaTester",
                   "Legacy player placeholder was not replaced.")
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
