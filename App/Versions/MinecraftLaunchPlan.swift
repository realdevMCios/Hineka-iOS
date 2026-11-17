import Foundation
import CryptoKit

public enum HinekaGameLaunchPlanError: LocalizedError {
    case invalidUsername
    case invalidUUID
    case invalidMetadata(String)
    case unsafePath

    public var errorDescription: String? {
        switch self {
        case .invalidUsername:
            return "Tên người chơi phải dài 3–16 ký tự và chỉ gồm chữ, số hoặc dấu gạch dưới."
        case .invalidUUID:
            return "UUID người chơi không hợp lệ."
        case .invalidMetadata(let message):
            return message
        case .unsafePath:
            return "Metadata Minecraft chứa đường dẫn thư viện không an toàn."
        }
    }
}

/// The minimum identity data needed to resolve Mojang's launch placeholders.
/// Access tokens are never included in diagnostic summaries.
public struct HinekaLaunchIdentity {
    public let username: String
    public let uuid: String
    public let accessToken: String
    public let userType: String
    public let xuid: String?
    public let clientID: String?
    public let isAuthenticated: Bool

    public init(
        username: String,
        uuid: String,
        accessToken: String,
        userType: String = "msa",
        xuid: String? = nil,
        clientID: String? = nil,
        isAuthenticated: Bool
    ) throws {
        guard Self.isValidUsername(username) else {
            throw HinekaGameLaunchPlanError.invalidUsername
        }
        guard UUID(uuidString: uuid) != nil else {
            throw HinekaGameLaunchPlanError.invalidUUID
        }
        self.username = username
        self.uuid = uuid.lowercased()
        self.accessToken = accessToken
        self.userType = userType
        self.xuid = xuid
        self.clientID = clientID
        self.isAuthenticated = isAuthenticated
    }

    /// Creates Minecraft's deterministic offline-player UUID.
    /// This does not authenticate the player or grant online-server access.
    public static func offline(username: String) throws -> HinekaLaunchIdentity {
        guard isValidUsername(username) else {
            throw HinekaGameLaunchPlanError.invalidUsername
        }
        let digest = Array(Insecure.MD5.hash(data: Data("OfflinePlayer:\(username)".utf8)))
        let bytes = Array(digest.prefix(16))
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )).uuidString
        return try HinekaLaunchIdentity(
            username: username,
            uuid: uuid,
            accessToken: "",
            userType: "legacy",
            isAuthenticated: false
        )
    }

    private static func isValidUsername(_ value: String) -> Bool {
        (3...16).contains(value.count) &&
        value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }
}

/// A resolved, inspectable Minecraft launch request. This type never executes Java.
public struct HinekaGameLaunchPlan {
    public let versionID: String
    public let javaMajorVersion: Int
    public let javaHome: URL
    public let mainClass: String
    public let vmOptions: [String]
    public let gameArguments: [String]
    public let classpath: [URL]
    public let workingDirectory: URL
    public let environment: [String: String]
    public let nativeClassifierCount: Int
    public let blockers: [String]
    public let warnings: [String]

    public var isReadyToBoot: Bool { blockers.isEmpty }

    public var diagnosticSummary: String {
        var lines = [
            "Minecraft: \(versionID)",
            "Java yêu cầu: \(javaMajorVersion)",
            "Main class: \(mainClass)",
            "Thư viện Java: \(max(0, classpath.count - 1))",
            "VM options: \(vmOptions.count)",
            "Game arguments: \(gameArguments.count)",
            "Native classifiers: \(nativeClassifierCount)",
            "Sẵn sàng khởi chạy: \(isReadyToBoot ? "có" : "chưa")"
        ]
        if !blockers.isEmpty {
            lines.append("")
            lines.append("Các điều kiện còn thiếu:")
            lines.append(contentsOf: blockers.map { "• " + $0 })
        }
        if !warnings.isEmpty {
            lines.append("")
            lines.append("Lưu ý:")
            lines.append(contentsOf: warnings.map { "• " + $0 })
        }
        return lines.joined(separator: "\n")
    }
}

public enum HinekaGameLaunchPlanBuilder {
    /// Builds a launch plan from an installed Hineka vanilla profile.
    public static func buildInstalled(
        versionID: String,
        identity: HinekaLaunchIdentity,
        javaHome: URL,
        runtimeJavaMajorVersion: Int?,
        screenWidth: Int = 1170,
        screenHeight: Int = 2532
    ) throws -> HinekaGameLaunchPlan {
        guard isSafeIdentifier(versionID) else {
            throw HinekaGameLaunchPlanError.invalidMetadata("Mã phiên bản Minecraft không hợp lệ.")
        }
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw HinekaGameLaunchPlanError.invalidMetadata("Không tìm thấy vùng lưu trữ Hineka.")
        }

        let gameRoot = support.appendingPathComponent("Hineka/Minecraft", isDirectory: true)
        let versionDirectory = gameRoot.appendingPathComponent("versions/\(versionID)", isDirectory: true)
        let metadataURL = versionDirectory.appendingPathComponent("\(versionID).json")
        let markerURL = versionDirectory.appendingPathComponent(".hineka-installed.json")
        guard
            let markerData = try? Data(contentsOf: markerURL),
            let marker = try? JSONDecoder().decode(HinekaInstalledVersion.self, from: markerData),
            marker.id == versionID,
            marker.clientJarRelativePath == "\(versionID)/\(versionID).jar"
        else {
            throw HinekaGameLaunchPlanError.invalidMetadata("Profile chưa có dấu xác nhận cài đặt của Hineka.")
        }

        return try build(
            metadataData: Data(contentsOf: metadataURL),
            versionDirectory: versionDirectory,
            librariesDirectory: gameRoot.appendingPathComponent("libraries", isDirectory: true),
            assetsDirectory: gameRoot.appendingPathComponent("assets", isDirectory: true),
            workingDirectory: gameRoot,
            javaHome: javaHome,
            nativeDirectory: gameRoot.appendingPathComponent("natives/\(versionID)", isDirectory: true),
            identity: identity,
            runtimeJavaMajorVersion: runtimeJavaMajorVersion,
            expectedAssetIndexID: marker.assetIndexID,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )
    }

    /// Dependency-injected entry point for deterministic tests and future loader adapters.
    public static func build(
        metadataData: Data,
        versionDirectory: URL,
        librariesDirectory: URL,
        assetsDirectory: URL,
        workingDirectory: URL,
        javaHome: URL,
        nativeDirectory: URL,
        identity: HinekaLaunchIdentity,
        runtimeJavaMajorVersion: Int?,
        expectedAssetIndexID: String? = nil,
        screenWidth: Int = 1170,
        screenHeight: Int = 2532,
        operatingSystemName: String = "ios",
        architecture: String = "aarch64",
        operatingSystemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        features: [String: Bool] = [:]
    ) throws -> HinekaGameLaunchPlan {
        let metadata: MinecraftVersionMetadata
        do {
            metadata = try JSONDecoder().decode(MinecraftVersionMetadata.self, from: metadataData)
        } catch {
            throw HinekaGameLaunchPlanError.invalidMetadata(
                "Không giải mã được metadata Minecraft: \(error.localizedDescription)"
            )
        }
        guard isSafeIdentifier(metadata.id), !metadata.mainClass.isEmpty else {
            throw HinekaGameLaunchPlanError.invalidMetadata("Metadata thiếu ID hoặc main class hợp lệ.")
        }

        let assetIndexID = metadata.assetIndex?.id ?? metadata.assets ?? metadata.id
        guard isSafeIdentifier(assetIndexID) else {
            throw HinekaGameLaunchPlanError.invalidMetadata("Asset Index ID không hợp lệ.")
        }
        if let expectedAssetIndexID, expectedAssetIndexID != assetIndexID {
            throw HinekaGameLaunchPlanError.invalidMetadata("Asset Index ID không khớp profile đã cài.")
        }

        let clientJar = versionDirectory.appendingPathComponent("\(metadata.id).jar")
        let assetIndex = assetsDirectory
            .appendingPathComponent("indexes", isDirectory: true)
            .appendingPathComponent("\(assetIndexID).json")
        var blockers: [String] = []
        var warnings: [String] = []
        if !FileManager.default.fileExists(atPath: clientJar.path) {
            blockers.append("Thiếu Minecraft client JAR.")
        }
        if !FileManager.default.fileExists(atPath: assetIndex.path) {
            blockers.append("Thiếu Asset Index.")
        }

        let effectiveFeatures = [
            "is_demo_user": false,
            "has_custom_resolution": screenWidth > 0 && screenHeight > 0,
            "has_quick_plays_support": false,
            "is_quick_play_singleplayer": false,
            "is_quick_play_multiplayer": false,
            "is_quick_play_realms": false
        ].merging(features) { _, supplied in supplied }

        var classpath: [URL] = []
        var seenClasspathPaths = Set<String>()
        var nativeClassifierCount = 0

        for library in metadata.libraries {
            guard ruleAllows(
                library.rules,
                operatingSystemName: operatingSystemName,
                architecture: architecture,
                operatingSystemVersion: operatingSystemVersion,
                features: effectiveFeatures
            ) else {
                continue
            }

            let classifierKeys = library.downloads?.classifiers.map { Array($0.keys) } ?? []
            if library.natives != nil || classifierKeys.contains(where: { $0.hasPrefix("natives-") }) {
                nativeClassifierCount += 1
            }

            guard let artifact = library.downloads?.artifact else { continue }
            guard let relativePath = artifact.path ?? mavenRelativePath(from: library.name) else {
                blockers.append("Không xác định được đường dẫn thư viện \(library.name).")
                continue
            }
            let artifactURL = try safeDestination(root: librariesDirectory, relativePath: relativePath)
            guard FileManager.default.fileExists(atPath: artifactURL.path) else {
                blockers.append("Thiếu thư viện Java \(artifactURL.lastPathComponent).")
                continue
            }
            if seenClasspathPaths.insert(artifactURL.path).inserted {
                classpath.append(artifactURL)
            }
        }

        if seenClasspathPaths.insert(clientJar.path).inserted {
            classpath.append(clientJar)
        }
        if nativeClassifierCount > 0 {
            blockers.append("Profile cần \(nativeClassifierCount) native classifier; iOS LWJGL/renderer replacement chưa được tích hợp.")
        }

        guard let javaMajor = metadata.javaVersion?.majorVersion, javaMajor > 0 else {
            throw HinekaGameLaunchPlanError.invalidMetadata("Không xác định được Java major version từ metadata.")
        }
        if let runtimeJavaMajorVersion {
            if runtimeJavaMajorVersion != javaMajor {
                blockers.append("Runtime Java \(runtimeJavaMajorVersion) không khớp Java \(javaMajor) mà Minecraft yêu cầu.")
            }
        } else {
            blockers.append("Chưa có runtime Java \(javaMajor) đầy đủ được xác minh cho Minecraft.")
        }
        blockers.append("JNI game launcher/process supervisor của Hineka chưa được tích hợp.")

        let classpathString = classpath.map(\.path).joined(separator: ":")
        let libraryPath = nativeDirectory.path
        var substitutions: [String: String] = [
            "auth_player_name": identity.username,
            "version_name": metadata.id,
            "game_directory": workingDirectory.path,
            "assets_root": assetsDirectory.path,
            "assets_index_name": assetIndexID,
            "auth_uuid": identity.uuid,
            "auth_access_token": identity.accessToken,
            "clientid": identity.clientID ?? "",
            "auth_xuid": identity.xuid ?? "",
            "user_type": identity.userType,
            "version_type": metadata.type ?? "release",
            "natives_directory": libraryPath,
            "launcher_name": "Hineka",
            "launcher_version": "0.1-dev",
            "classpath": classpathString,
            "classpath_separator": ":",
            "library_directory": librariesDirectory.path,
            "resolution_width": String(max(screenWidth, 1)),
            "resolution_height": String(max(screenHeight, 1)),
            "quickPlayPath": "",
            "quickPlaySingleplayer": "",
            "quickPlayMultiplayer": "",
            "quickPlayRealms": "",
            "arch": "64",
            "path": ""
        ]

        var rawJVMArguments = metadata.arguments?.jvm?
            .filter {
                ruleAllows(
                    $0.rules,
                    operatingSystemName: operatingSystemName,
                    architecture: architecture,
                    operatingSystemVersion: operatingSystemVersion,
                    features: effectiveFeatures
                )
            }
            .flatMap { $0.value.strings } ?? []

        if let logging = metadata.logging?.client {
            let logFile = assetsDirectory
                .appendingPathComponent("log_configs", isDirectory: true)
                .appendingPathComponent(logging.file.id)
            if FileManager.default.fileExists(atPath: logFile.path) {
                substitutions["path"] = logFile.path
                if let argument = logging.argument {
                    rawJVMArguments.append(argument)
                }
            } else {
                blockers.append("Thiếu cấu hình log \(logging.file.id).")
            }
        }

        var vmOptions: [String] = []
        var hasClasspathOption = false
        let resolvedJVMArguments = rawJVMArguments.map {
            substitute($0, values: substitutions, unresolved: &blockers)
        }
        var index = 0
        while index < resolvedJVMArguments.count {
            let argument = resolvedJVMArguments[index]
            if argument == "-cp" || argument == "-classpath" || argument == "--class-path" {
                guard index + 1 < resolvedJVMArguments.count else {
                    blockers.append("JVM arguments có cờ classpath nhưng thiếu giá trị.")
                    index += 1
                    continue
                }
                vmOptions.append("-Djava.class.path=\(resolvedJVMArguments[index + 1])")
                hasClasspathOption = true
                index += 2
                continue
            }
            if argument.hasPrefix("-Djava.class.path=") {
                hasClasspathOption = true
            }
            vmOptions.append(argument)
            index += 1
        }
        if !hasClasspathOption {
            vmOptions.append("-Djava.class.path=\(classpathString)")
        }
        if !vmOptions.contains(where: { $0.hasPrefix("-Djava.library.path=") }) {
            vmOptions.append("-Djava.library.path=\(libraryPath)")
        }

        let rawGameArguments: [String]
        if let game = metadata.arguments?.game {
            rawGameArguments = game
                .filter {
                    ruleAllows(
                        $0.rules,
                        operatingSystemName: operatingSystemName,
                        architecture: architecture,
                        operatingSystemVersion: operatingSystemVersion,
                        features: effectiveFeatures
                    )
                }
                .flatMap { $0.value.strings }
        } else if let legacy = metadata.minecraftArguments {
            rawGameArguments = try tokenizeLegacyArguments(legacy)
        } else {
            rawGameArguments = []
            blockers.append("Metadata không có game arguments kiểu mới hoặc minecraftArguments kiểu cũ.")
        }
        let gameArguments = rawGameArguments.map {
            substitute($0, values: substitutions, unresolved: &blockers)
        }

        if !identity.isAuthenticated {
            warnings.append("Đang tạo profile offline; chơi đơn có thể dùng được nhưng multiplayer cần đăng nhập Microsoft hợp lệ.")
        }

        return HinekaGameLaunchPlan(
            versionID: metadata.id,
            javaMajorVersion: javaMajor,
            javaHome: javaHome,
            mainClass: metadata.mainClass,
            vmOptions: vmOptions,
            gameArguments: gameArguments,
            classpath: classpath,
            workingDirectory: workingDirectory,
            environment: ["HOME": workingDirectory.path],
            nativeClassifierCount: nativeClassifierCount,
            blockers: Array(NSOrderedSet(array: blockers)) as? [String] ?? blockers,
            warnings: warnings
        )
    }

    private static func ruleAllows(
        _ rules: [MinecraftVersionMetadata.ArgumentRule]?,
        operatingSystemName: String,
        architecture: String,
        operatingSystemVersion: String,
        features: [String: Bool]
    ) -> Bool {
        guard let rules, !rules.isEmpty else { return true }
        var allowed = false
        for rule in rules where ruleMatches(
            rule,
            operatingSystemName: operatingSystemName,
            architecture: architecture,
            operatingSystemVersion: operatingSystemVersion,
            features: features
        ) {
            allowed = rule.action == "allow"
        }
        return allowed
    }

    private static func ruleMatches(
        _ rule: MinecraftVersionMetadata.ArgumentRule,
        operatingSystemName: String,
        architecture: String,
        operatingSystemVersion: String,
        features: [String: Bool]
    ) -> Bool {
        if let os = rule.os {
            if let name = os.name {
                let normalized = name.lowercased()
                let target = operatingSystemName.lowercased()
                let aliases = target == "osx" ? ["osx", "macos"] : [target]
                if !aliases.contains(normalized) { return false }
            }
            if let pattern = os.arch, !regularExpression(pattern, matches: architecture) {
                return false
            }
            if let pattern = os.version, !regularExpression(pattern, matches: operatingSystemVersion) {
                return false
            }
        }
        if let requiredFeatures = rule.features {
            for (name, requiredValue) in requiredFeatures where features[name] != requiredValue {
                return false
            }
        }
        return true
    }

    private static func regularExpression(_ pattern: String, matches value: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, range: range) != nil
    }

    private static func substitute(
        _ argument: String,
        values: [String: String],
        unresolved: inout [String]
    ) -> String {
        var resolved = argument
        for (key, value) in values {
            resolved = resolved.replacingOccurrences(of: "$"+"{\(key)}", with: value)
        }
        let pattern = #"\$\{([^}]+)\}"#
        if let expression = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(resolved.startIndex..<resolved.endIndex, in: resolved)
            for match in expression.matches(in: resolved, range: range) {
                guard match.numberOfRanges > 1,
                      let nameRange = Range(match.range(at: 1), in: resolved) else { continue }
                unresolved.append("Không hỗ trợ placeholder Minecraft $"+"{\(resolved[nameRange])}.")
            }
        }
        return resolved
    }

    private static func tokenizeLegacyArguments(_ input: String) throws -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var started = false

        for character in input {
            if escaped {
                current.append(character)
                escaped = false
                started = true
                continue
            }
            if character == "\\" {
                escaped = true
                started = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                started = true
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character.isWhitespace {
                if started {
                    arguments.append(current)
                    current = ""
                    started = false
                }
            } else {
                current.append(character)
                started = true
            }
        }
        if escaped { current.append("\\") }
        guard quote == nil else {
            throw HinekaGameLaunchPlanError.invalidMetadata("minecraftArguments chứa dấu nháy chưa đóng.")
        }
        if started { arguments.append(current) }
        return arguments
    }

    private static func mavenRelativePath(from coordinate: String) -> String? {
        let coordinateParts = coordinate.split(separator: "@", maxSplits: 1).map(String.init)
        let withoutExtension = coordinateParts.first ?? coordinate
        let fileExtension = coordinateParts.count == 2 ? coordinateParts[1] : "jar"
        guard !fileExtension.isEmpty,
              fileExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        let parts = withoutExtension.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts.count <= 4,
              parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("..") }) else {
            return nil
        }
        let group = parts[0].replacingOccurrences(of: ".", with: "/")
        let artifact = parts[1]
        let version = parts[2]
        let classifier = parts.count == 4 ? "-\(parts[3])" : ""
        return "\(group)/\(artifact)/\(version)/\(artifact)-\(version)\(classifier).\(fileExtension)"
    }

    private static func safeDestination(root: URL, relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains(".."),
              !relativePath.contains("\\") else {
            throw HinekaGameLaunchPlanError.unsafePath
        }
        let destination = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.standardizedFileURL.path + "/"
        guard destination.path.hasPrefix(rootPath) else {
            throw HinekaGameLaunchPlanError.unsafePath
        }
        return destination
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
        }
    }
}
