import CryptoKit
import Foundation

public enum HinekaRendererIntegrationStatus: String, Codable {
    /// Research notes only. No Hineka renderer adapter is implemented.
    case referenceOnly
    /// Native files are present and verified, but no Hineka backend adapter is registered.
    case binariesVerified
    /// A HinekaRendererBackend implementation exists and matches this manifest.
    case integrated
}

public struct HinekaRendererNativeArtifact: Codable, Equatable {
    public let relativePath: String
    public let sha256: String
    public let platform: String
    public let architecture: String

    public init(relativePath: String, sha256: String, platform: String, architecture: String) {
        self.relativePath = relativePath
        self.sha256 = sha256.lowercased()
        self.platform = platform.lowercased()
        self.architecture = architecture.lowercased()
    }
}

public struct HinekaRendererManifest: Codable, Equatable {
    public let identifier: String
    public let displayName: String
    public let integrationStatus: HinekaRendererIntegrationStatus
    public let supportedJavaMajorVersions: Set<Int>
    public let artifacts: [HinekaRendererNativeArtifact]

    public init(
        identifier: String,
        displayName: String,
        integrationStatus: HinekaRendererIntegrationStatus,
        supportedJavaMajorVersions: Set<Int>,
        artifacts: [HinekaRendererNativeArtifact]
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.integrationStatus = integrationStatus
        self.supportedJavaMajorVersions = supportedJavaMajorVersions
        self.artifacts = artifacts
    }
}

public struct HinekaRendererLaunchConfiguration {
    public let minecraftVersion: String
    public let javaMajorVersion: Int
    public let width: Int
    public let height: Int

    public init(minecraftVersion: String, javaMajorVersion: Int, width: Int, height: Int) {
        self.minecraftVersion = minecraftVersion
        self.javaMajorVersion = javaMajorVersion
        self.width = max(1, width)
        self.height = max(1, height)
    }
}

/// Adapter boundary only. A renderer implementation must own its UIKit/Metal/EGL
/// surface bridge and must not call game callbacks from arbitrary UIKit threads.
public protocol HinekaRendererBackend {
    var manifest: HinekaRendererManifest { get }
    func prepare(configuration: HinekaRendererLaunchConfiguration) throws
    func resize(width: Int, height: Int) throws
    func shutdown() throws
}

public struct HinekaRendererValidationResult {
    public let blockers: [String]
    public var isReady: Bool { blockers.isEmpty }
}

public enum HinekaRendererManifestValidator {
    public static func validate(
        manifest: HinekaRendererManifest,
        backend: HinekaRendererBackend?,
        rendererDirectory: URL,
        requiredJavaMajorVersion: Int,
        platform: String = "ios",
        architecture: String = "arm64"
    ) -> HinekaRendererValidationResult {
        var blockers: [String] = []

        guard isSafeIdentifier(manifest.identifier), !manifest.displayName.isEmpty else {
            blockers.append("Renderer manifest thiếu ID hoặc tên hợp lệ.")
            return HinekaRendererValidationResult(blockers: blockers)
        }

        if manifest.integrationStatus != .integrated {
            blockers.append("Renderer \(manifest.displayName) chưa được tích hợp thành backend Hineka.")
        }
        if backend == nil {
            blockers.append("Chưa đăng ký HinekaRendererBackend cho renderer này.")
        }
        if let registeredBackend = backend,
           registeredBackend.manifest.identifier != manifest.identifier {
            blockers.append("Backend được đăng ký không khớp renderer manifest.")
        }

        if !manifest.supportedJavaMajorVersions.contains(requiredJavaMajorVersion) {
            blockers.append("Renderer không khai báo hỗ trợ Java \(requiredJavaMajorVersion).")
        }
        guard !manifest.artifacts.isEmpty else {
            blockers.append("Renderer chưa khai báo native artifact nào.")
            return HinekaRendererValidationResult(blockers: unique(blockers))
        }

        for artifact in manifest.artifacts {
            if artifact.platform != platform.lowercased() {
                blockers.append("Native artifact \(artifact.relativePath) không dành cho \(platform).")
                continue
            }
            if !architectureMatches(artifact.architecture, architecture) {
                blockers.append("Native artifact \(artifact.relativePath) không hỗ trợ kiến trúc \(architecture).")
                continue
            }
            guard isSHA256(artifact.sha256) else {
                blockers.append("SHA-256 của native artifact \(artifact.relativePath) không hợp lệ.")
                continue
            }
            do {
                let file = try safeArtifactURL(root: rendererDirectory, relativePath: artifact.relativePath)
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    blockers.append("Native artifact \(artifact.relativePath) không phải tệp thường.")
                    continue
                }
                let data = try Data(contentsOf: file, options: [.mappedIfSafe])
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest.caseInsensitiveCompare(artifact.sha256) == .orderedSame else {
                    blockers.append("Native artifact \(artifact.relativePath) không khớp SHA-256.")
                    continue
                }
                let inspection = inspectIOSArm64MachO(data)
                if !inspection.isValid {
                    blockers.append("Native artifact \(artifact.relativePath): \(inspection.reason).")
                }
            } catch {
                blockers.append("Không xác minh được native artifact \(artifact.relativePath): \(error.localizedDescription)")
            }
        }

        return HinekaRendererValidationResult(blockers: unique(blockers))
    }

    private static func safeArtifactURL(root: URL, relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.contains("\0"),
              !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw HinekaRendererArtifactError.unsafePath
        }

        let manager = FileManager.default
        let rootURL = root.standardizedFileURL
        guard
            let rootAttributes = try? manager.attributesOfItem(atPath: rootURL.path),
            rootAttributes[.type] as? FileAttributeType == .typeDirectory
        else {
            throw HinekaRendererArtifactError.missingRoot
        }

        var cursor = rootURL
        for (index, component) in components.enumerated() {
            cursor.appendPathComponent(String(component), isDirectory: index < components.count - 1)
            guard let attributes = try? manager.attributesOfItem(atPath: cursor.path) else {
                throw HinekaRendererArtifactError.missingFile
            }
            let type = attributes[.type] as? FileAttributeType
            if type == .typeSymbolicLink {
                throw HinekaRendererArtifactError.unsafePath
            }
            if index < components.count - 1, type != .typeDirectory {
                throw HinekaRendererArtifactError.unsafePath
            }
        }

        let destination = cursor.standardizedFileURL
        guard destination.path.hasPrefix(rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/") else {
            throw HinekaRendererArtifactError.unsafePath
        }
        return destination
    }

    private static func inspectIOSArm64MachO(_ data: Data) -> (isValid: Bool, reason: String) {
        guard data.count >= 32 else {
            return (false, "tệp quá ngắn để là Mach-O 64-bit")
        }
        guard readUInt32(data, at: 0) == 0xfeedfacf else {
            return (false, "không phải Mach-O 64-bit little-endian")
        }
        guard readUInt32(data, at: 4) == 0x0100000c else {
            return (false, "Mach-O không phải arm64")
        }
        let fileType = readUInt32(data, at: 12)
        guard fileType == 6 || fileType == 8 else {
            return (false, "Mach-O không phải dynamic library hoặc bundle")
        }

        guard let commandCountValue = readUInt32(data, at: 16) else {
            return (false, "Mach-O thiếu số lượng load command")
        }
        let commandCount = Int(commandCountValue)
        var offset = 32
        var foundIOSPlatform = false
        for _ in 0..<commandCount {
            guard offset + 8 <= data.count,
                  let command = readUInt32(data, at: offset),
                  let commandSizeRaw = readUInt32(data, at: offset + 4) else {
                return (false, "load command bị cắt cụt")
            }
            let commandSize = Int(commandSizeRaw)
            guard commandSize >= 8, offset + commandSize <= data.count else {
                return (false, "load command có kích thước không hợp lệ")
            }
            if command == 0x32 {
                guard commandSize >= 24, let platform = readUInt32(data, at: offset + 8) else {
                    return (false, "LC_BUILD_VERSION không hợp lệ")
                }
                // PLATFORM_IOS = 2. Simulator and macOS binaries are not accepted.
                if platform == 2 {
                    foundIOSPlatform = true
                }
            } else if command == 0x25 {
                // Legacy LC_VERSION_MIN_IPHONEOS.
                foundIOSPlatform = true
            }
            offset += commandSize
        }
        guard foundIOSPlatform else {
            return (false, "Mach-O không khai báo nền tảng iOS device")
        }
        return (true, "")
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private static func architectureMatches(_ artifact: String, _ required: String) -> Bool {
        let left = artifact.lowercased()
        let right = required.lowercased()
        return (left == "arm64" || left == "aarch64") &&
            (right == "arm64" || right == "aarch64")
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80 &&
            value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

public enum HinekaRendererArtifactError: LocalizedError {
    case unsafePath
    case missingRoot
    case missingFile

    public var errorDescription: String? {
        switch self {
        case .unsafePath: return "Đường dẫn native artifact không an toàn hoặc chứa symlink."
        case .missingRoot: return "Không tìm thấy thư mục renderer native."
        case .missingFile: return "Thiếu renderer native artifact."
        }
    }
}

public struct HinekaGameStartupPreflightReport {
    public let blockers: [String]
    public var canStart: Bool { blockers.isEmpty }

    public var summary: String {
        if canStart {
            return "Startup preflight: PASS. Runtime, renderer và launch-plan đã qua kiểm tra cấu hình."
        }
        return "Startup preflight: BLOCKED\n" + blockers.map { "• " + $0 }.joined(separator: "\n")
    }
}

public enum HinekaGameStartupPreflight {
    public static func evaluate(
        requiredJavaMajorVersion: Int,
        runtime: HinekaJavaRuntimeReport,
        rendererManifest: HinekaRendererManifest,
        rendererBackend: HinekaRendererBackend?,
        rendererDirectory: URL,
        launchPlanBlockers: [String] = [],
        platform: String = "ios",
        architecture: String = "arm64"
    ) -> HinekaGameStartupPreflightReport {
        var blockers = launchPlanBlockers

        if runtime.javaMajorVersion != requiredJavaMajorVersion {
            blockers.append("Runtime Java \(runtime.javaMajorVersion) không khớp Java \(requiredJavaMajorVersion) của Minecraft.")
        }
        let normalizedOS = runtime.osName.lowercased()
        if !(normalizedOS.contains("ios") || normalizedOS.contains("iphone")) {
            blockers.append("Java runtime báo hệ điều hành \(runtime.osName), không phải iOS.")
        }
        let targetArchitecture = architecture.lowercased()
        let targetIsARM64 = targetArchitecture == "arm64" || targetArchitecture == "aarch64"
        if !runtime.is64BitARM || !targetIsARM64 {
            blockers.append("Java runtime không chạy trên iOS arm64.")
        }
        if !runtime.hasBaselineModuleCoverage {
            blockers.append("Runtime thiếu module baseline: " + runtime.missingBaselineModules.joined(separator: ", ") + ".")
        }

        let renderer = HinekaRendererManifestValidator.validate(
            manifest: rendererManifest,
            backend: rendererBackend,
            rendererDirectory: rendererDirectory,
            requiredJavaMajorVersion: requiredJavaMajorVersion,
            platform: platform,
            architecture: architecture
        )
        blockers.append(contentsOf: renderer.blockers)

        var seen = Set<String>()
        let uniqueBlockers = blockers.filter { seen.insert($0).inserted }
        return HinekaGameStartupPreflightReport(blockers: uniqueBlockers)
    }
}
