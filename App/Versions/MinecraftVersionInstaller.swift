import Foundation
import Combine
import CryptoKit

struct MinecraftVersionInstallerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static let invalidVersionID = Self(message: "Mã phiên bản Minecraft không hợp lệ.")
    static let missingClientDownload = Self(message: "Manifest không có tệp Minecraft client.")
    static let missingAssetIndex = Self(message: "Manifest không có Asset Index.")
    static let invalidAssetHash = Self(message: "Asset Index chứa mã SHA-1 không hợp lệ.")
    static let checksumMismatch = Self(message: "Tệp tải về không khớp SHA-1 do Mojang cung cấp.")
    static let sizeMismatch = Self(message: "Dung lượng tệp tải về không khớp metadata Minecraft.")
    static let invalidRelativePath = Self(message: "Đường dẫn tệp trong manifest không hợp lệ.")
    static let invalidDownloadURL = Self(message: "Manifest chứa URL tải xuống không hợp lệ hoặc không thuộc máy chủ được phép.")
    static let missingIntegrityMetadata = Self(message: "Manifest thiếu SHA-1 hoặc dung lượng để xác minh tệp.")
    static let insufficientDiskSpace = Self(message: "Thiết bị không đủ dung lượng trống để cài phiên bản Minecraft này.")
    static let invalidMetadataSize = Self(message: "Metadata chứa dung lượng tệp không hợp lệ hoặc vượt giới hạn tính toán.")
}


/// Verifies SHA-1 incrementally so large client JARs and asset files do not need
/// to be loaded into memory as one Data value.
enum HinekaSHA1FileVerifier {
    static func matches(
        fileAt url: URL,
        expectedSHA1: String,
        chunkSize: Int = 1024 * 1024
    ) throws -> Bool {
        guard expectedSHA1.count == 40,
              expectedSHA1.allSatisfy({ $0.isHexDigit }),
              chunkSize > 0 else {
            return false
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = Insecure.SHA1()
        while true {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                break
            }
            hasher.update(data: chunk)
        }

        let actual = hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        return actual.caseInsensitiveCompare(expectedSHA1) == .orderedSame
    }
}

struct MinecraftVersionMetadata: Decodable {
    struct VerifiedDownload: Decodable {
        let sha1: String?
        let size: Int64?
        let url: URL
        let path: String?
    }

    struct VersionDownloads: Decodable {
        let client: VerifiedDownload?
    }

    struct AssetIndexInfo: Decodable {
        let id: String?
        let sha1: String?
        let size: Int64?
        let totalSize: Int64?
        let url: URL
    }

    struct LibraryDownloads: Decodable {
        let artifact: VerifiedDownload?
        let classifiers: [String: VerifiedDownload]?
    }

    struct OperatingSystemRule: Decodable {
        let name: String?
        let arch: String?
        let version: String?
    }

    struct ArgumentRule: Decodable {
        let action: String
        let os: OperatingSystemRule?
        let features: [String: Bool]?
    }

    enum ArgumentValue: Decodable {
        case single(String)
        case multiple([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .single(value)
                return
            }
            if let values = try? container.decode([String].self) {
                self = .multiple(values)
                return
            }
            throw DecodingError.typeMismatch(
                ArgumentValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Minecraft argument value must be a string or an array of strings."
                )
            )
        }

        var strings: [String] {
            switch self {
            case .single(let value): return [value]
            case .multiple(let values): return values
            }
        }
    }

    struct ConditionalArgument: Decodable {
        let rules: [ArgumentRule]?
        let value: ArgumentValue
    }

    struct LaunchArguments: Decodable {
        let game: [ConditionalArgument]?
        let jvm: [ConditionalArgument]?
    }

    struct Library: Decodable {
        let name: String
        let downloads: LibraryDownloads?
        let natives: [String: String]?
        let rules: [ArgumentRule]?
    }

    struct JavaVersion: Decodable {
        let component: String
        let majorVersion: Int
    }

    let id: String
    let mainClass: String
    let type: String?
    let assets: String?
    let assetIndex: AssetIndexInfo?
    let downloads: VersionDownloads
    let libraries: [Library]
    let javaVersion: JavaVersion?
    let arguments: LaunchArguments?
    let minecraftArguments: String?

    struct LoggingInfo: Decodable {
        struct Client: Decodable {
            struct LogFile: Decodable {
                let id: String
                let sha1: String
                let size: Int64
                let url: URL
            }

            let argument: String?
            let file: LogFile
        }
        let client: Client?
    }

    let logging: LoggingInfo?
}

struct MinecraftAssetIndex: Decodable {
    struct AssetObject: Decodable {
        let hash: String
        let size: Int64
    }

    let objects: [String: AssetObject]
    let virtual: Bool?
    let mapToResources: Bool?

    enum CodingKeys: String, CodingKey {
        case objects
        case virtual
        case mapToResources = "map_to_resources"
    }
}

/// Materializes the two compatibility layouts used by older Minecraft asset indexes.
/// The source objects stay in assets/objects; generated copies are always hash-verified.
struct MinecraftAssetCompatibilityStagingResult {
    let virtualFileCount: Int
    let resourceFileCount: Int
}

enum MinecraftAssetCompatibilityStager {
    static func stage(
        assetIndex: MinecraftAssetIndex,
        assetsDirectory: URL,
        resourcesDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> MinecraftAssetCompatibilityStagingResult {
        guard assetIndex.virtual == true || assetIndex.mapToResources == true else {
            return MinecraftAssetCompatibilityStagingResult(
                virtualFileCount: 0,
                resourceFileCount: 0
            )
        }

        let objectsDirectory = assetsDirectory.appendingPathComponent("objects", isDirectory: true)
        let virtualRoot = assetsDirectory
            .appendingPathComponent("virtual", isDirectory: true)
            .appendingPathComponent("legacy", isDirectory: true)
        var virtualFileCount = 0
        var resourceFileCount = 0

        for (logicalName, object) in assetIndex.objects.sorted(by: { $0.key < $1.key }) {
            guard isSHA1(object.hash), object.size >= 0 else {
                throw MinecraftVersionInstallerError.invalidAssetHash
            }

            let source = objectsDirectory
                .appendingPathComponent(String(object.hash.prefix(2)), isDirectory: true)
                .appendingPathComponent(object.hash)
            guard isVerifiedObject(source, sha1: object.hash, size: object.size, fileManager: fileManager) else {
                throw MinecraftVersionInstallerError(
                    message: "Asset object \(object.hash) bị thiếu hoặc không khớp SHA-1/dung lượng."
                )
            }

            if assetIndex.virtual == true {
                let destination = try safeAssetDestination(
                    root: virtualRoot,
                    relativePath: logicalName,
                    fileManager: fileManager
                )
                try copyVerifiedObject(
                    from: source,
                    to: destination,
                    sha1: object.hash,
                    size: object.size,
                    fileManager: fileManager
                )
                virtualFileCount += 1
            }

            if assetIndex.mapToResources == true {
                let destination = try safeAssetDestination(
                    root: resourcesDirectory,
                    relativePath: logicalName,
                    fileManager: fileManager
                )
                try copyVerifiedObject(
                    from: source,
                    to: destination,
                    sha1: object.hash,
                    size: object.size,
                    fileManager: fileManager
                )
                resourceFileCount += 1
            }
        }

        return MinecraftAssetCompatibilityStagingResult(
            virtualFileCount: virtualFileCount,
            resourceFileCount: resourceFileCount
        )
    }

    private static func safeAssetDestination(
        root: URL,
        relativePath: String,
        fileManager: FileManager
    ) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.contains("\0"),
              !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw MinecraftVersionInstallerError.invalidRelativePath
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        guard let rootAttributes = try? fileManager.attributesOfItem(atPath: root.path),
              rootAttributes[.type] as? FileAttributeType == .typeDirectory else {
            throw MinecraftVersionInstallerError.invalidRelativePath
        }

        var parent = root
        for component in components.dropLast() {
            parent.appendPathComponent(String(component), isDirectory: true)
            if fileManager.fileExists(atPath: parent.path) {
                guard let attributes = try? fileManager.attributesOfItem(atPath: parent.path),
                      attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw MinecraftVersionInstallerError.invalidRelativePath
                }
            } else {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
            }
        }

        let destination = parent.appendingPathComponent(String(components.last!), isDirectory: false)
        if fileManager.fileExists(atPath: destination.path) {
            guard let attributes = try? fileManager.attributesOfItem(atPath: destination.path),
                  attributes[.type] as? FileAttributeType == .typeRegular else {
                throw MinecraftVersionInstallerError.invalidRelativePath
            }
        }
        return destination
    }

    private static func copyVerifiedObject(
        from source: URL,
        to destination: URL,
        sha1: String,
        size: Int64,
        fileManager: FileManager
    ) throws {
        if isVerifiedObject(destination, sha1: sha1, size: size, fileManager: fileManager) {
            return
        }

        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".hineka-asset-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }

        try fileManager.copyItem(at: source, to: temporary)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
        guard isVerifiedObject(destination, sha1: sha1, size: size, fileManager: fileManager) else {
            try? fileManager.removeItem(at: destination)
            throw MinecraftVersionInstallerError.checksumMismatch
        }
    }

    private static func isVerifiedObject(
        _ url: URL,
        sha1: String,
        size: Int64,
        fileManager: FileManager
    ) -> Bool {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let actualSize = (attributes[.size] as? NSNumber)?.int64Value,
            actualSize == size
        else {
            return false
        }
        return (try? HinekaSHA1FileVerifier.matches(fileAt: url, expectedSHA1: sha1)) == true
    }

    private static func isSHA1(_ value: String) -> Bool {
        value.count == 40 && value.allSatisfy { $0.isHexDigit }
    }
}

struct HinekaInstalledVersion: Codable {
    let id: String
    let mainClass: String
    let javaMajorVersion: Int?
    let installedAt: Date
    let clientJarRelativePath: String
    let assetIndexID: String?
}

/// Downloads official Mojang version metadata, the vanilla client JAR, pure-Java
/// library artifacts, the asset index, and referenced game assets.
///
/// Native classifiers are intentionally not downloaded here: the project still
/// needs an iOS-compatible OpenJDK/LWJGL/rendering runtime before a profile can launch.
@MainActor
public final class MinecraftVersionInstaller: ObservableObject {
    @Published public private(set) var isInstalling = false
    @Published public private(set) var progress = 0.0
    @Published public private(set) var statusMessage = "Sẵn sàng"
    @Published public private(set) var installedVersionIDs: Set<String> = []
    @Published public var errorMessage: String?

    private let fileManager = FileManager.default
    private let baseManifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!

    public init() {
        reloadInstalledVersions()
    }

    public func reloadInstalledVersions() {
        guard let root = try? versionsDirectory() else {
            installedVersionIDs = []
            return
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        installedVersionIDs = Set(children.compactMap { directory in
            let markerURL = directory.appendingPathComponent(".hineka-installed.json")
            let clientURL = directory.appendingPathComponent(directory.lastPathComponent + ".jar")
            guard
                let markerData = try? Data(contentsOf: markerURL),
                let marker = try? JSONDecoder().decode(HinekaInstalledVersion.self, from: markerData),
                marker.id == directory.lastPathComponent,
                fileManager.fileExists(atPath: clientURL.path)
            else {
                return nil
            }
            return marker.id
        })
    }

    public func install(versionID: String, metadataURL: URL, metadataSHA1: String) async {
        guard !isInstalling else { return }
        guard Self.isSafeIdentifier(versionID) else {
            errorMessage = MinecraftVersionInstallerError.invalidVersionID.localizedDescription
            return
        }

        isInstalling = true
        progress = 0
        errorMessage = nil
        statusMessage = "Đang lấy metadata Minecraft…"
        defer {
            isInstalling = false
            if errorMessage != nil {
                statusMessage = "Cài đặt thất bại"
            }
        }

        do {
            try Self.requireAllowedMinecraftURL(metadataURL)
            let versionRoot = try versionDirectory(for: versionID)
            let metadataFile = versionRoot.appendingPathComponent("\(versionID).json")
            let metadataData = try await Self.fetchData(from: metadataURL)
            try Self.verify(data: metadataData, expectedSHA1: metadataSHA1)
            try metadataData.write(to: metadataFile, options: .atomic)

            let metadata = try JSONDecoder().decode(MinecraftVersionMetadata.self, from: metadataData)
            guard metadata.id == versionID else {
                throw MinecraftVersionInstallerError.invalidVersionID
            }
            guard let client = metadata.downloads.client else {
                throw MinecraftVersionInstallerError.missingClientDownload
            }
            guard let assetInfo = metadata.assetIndex else {
                throw MinecraftVersionInstallerError.missingAssetIndex
            }

            var artifacts: [(URL, URL, String?, Int64?)] = []
            let clientURL = versionRoot.appendingPathComponent("\(versionID).jar")
            artifacts.append((client.url, clientURL, client.sha1, client.size))

            let librariesRoot = try libraryDirectory()
            for library in metadata.libraries {
                guard let artifact = library.downloads?.artifact else { continue }
                guard !artifact.url.lastPathComponent.lowercased().contains("natives") else { continue }
                guard let relativePath = artifact.path ?? Self.mavenPath(from: library.name) else { continue }
                let destination = try Self.safeDestination(root: librariesRoot, relativePath: relativePath)
                artifacts.append((artifact.url, destination, artifact.sha1, artifact.size))
            }

            // The game needs a complete asset index and all referenced objects.
            // Estimate required storage before starting large downloads.
            guard
                (assetInfo.size ?? 0) >= 0,
                (assetInfo.totalSize ?? 0) >= 0
            else {
                throw MinecraftVersionInstallerError.invalidMetadataSize
            }
            let assetIndexSize = assetInfo.size
            let totalAssetSize = assetInfo.totalSize ?? 0
            let artifactSizes = artifacts.compactMap { $0.3 }
            guard artifactSizes.count == artifacts.count else {
                throw MinecraftVersionInstallerError.missingIntegrityMetadata
            }
            let estimatedBytes = try Self.checkedTotalSize(
                artifactSizes + [assetIndexSize ?? 0, totalAssetSize]
            )
            try requireAvailableSpace(
                in: appMinecraftDirectory(),
                estimatedBytes: estimatedBytes
            )

            if let loggingFile = metadata.logging?.client?.file {
                guard !loggingFile.id.isEmpty else {
                    throw MinecraftVersionInstallerError.invalidRelativePath
                }
                let logRoot = try assetsDirectory().appendingPathComponent("log_configs", isDirectory: true)
                try fileManager.createDirectory(at: logRoot, withIntermediateDirectories: true)
                let logDestination = try Self.safeDestination(root: logRoot, relativePath: loggingFile.id)
                statusMessage = "Đang tải cấu hình log…"
                try await Self.downloadVerified(
                    url: loggingFile.url,
                    to: logDestination,
                    sha1: loggingFile.sha1,
                    expectedSize: loggingFile.size
                )
            }

            progress = 0.03
            let totalFixed = max(artifacts.count + 2, 1)
            var completed = 0

            for (url, destination, sha1, expectedSize) in artifacts {
                statusMessage = "Đang tải \(destination.lastPathComponent)…"
                try await Self.downloadVerified(
                    url: url,
                    to: destination,
                    sha1: sha1,
                    expectedSize: expectedSize
                )
                completed += 1
                progress = min(0.03 + (Double(completed) / Double(totalFixed)) * 0.42, 0.45)
            }

            try Self.requireAllowedMinecraftURL(assetInfo.url)
            statusMessage = "Đang tải Asset Index…"
            let assetIndexData = try await Self.fetchData(from: assetInfo.url)
            try Self.verify(data: assetIndexData, expectedSHA1: assetInfo.sha1)
            if let assetIndexSize, Int64(assetIndexData.count) != assetIndexSize {
                throw MinecraftVersionInstallerError.sizeMismatch
            }
            let assetIndex = try JSONDecoder().decode(MinecraftAssetIndex.self, from: assetIndexData)

            let assetIndexID = assetInfo.id ?? metadata.assets ?? versionID
            guard Self.isSafeIdentifier(assetIndexID) else {
                throw MinecraftVersionInstallerError.invalidVersionID
            }
            let indexesRoot = try assetsDirectory().appendingPathComponent("indexes", isDirectory: true)
            try fileManager.createDirectory(at: indexesRoot, withIntermediateDirectories: true)
            try assetIndexData.write(
                to: indexesRoot.appendingPathComponent("\(assetIndexID).json"),
                options: .atomic
            )

            let objectsRoot = try assetsDirectory().appendingPathComponent("objects", isDirectory: true)
            try fileManager.createDirectory(at: objectsRoot, withIntermediateDirectories: true)
            var seenAssetHashes = Set<String>()
            let objects = assetIndex.objects.values
                .filter { seenAssetHashes.insert($0.hash).inserted }
                .sorted { $0.hash < $1.hash }
            let assetURLs: [(URL, URL, String, Int64)] = try objects.map { object in
                guard Self.isSHA1(object.hash) else {
                    throw MinecraftVersionInstallerError.invalidAssetHash
                }
                let folder = String(object.hash.prefix(2))
                let destination = objectsRoot.appendingPathComponent(folder, isDirectory: true)
                    .appendingPathComponent(object.hash)
                let url = URL(string: "https://resources.download.minecraft.net/\(folder)/\(object.hash)")!
                return (url, destination, object.hash, object.size)
            }

            let assetTotal = assetURLs.count
            var assetCompleted = 0
            statusMessage = "Đang tải tài nguyên Minecraft (0/\(assetTotal))…"

            try await withThrowingTaskGroup(of: Void.self) { group in
                var iterator = assetURLs.makeIterator()
                let concurrency = 8

                for _ in 0..<concurrency {
                    if let item = iterator.next() {
                        group.addTask {
                            try await Self.downloadVerified(
                                url: item.0,
                                to: item.1,
                                sha1: item.2,
                                expectedSize: item.3
                            )
                        }
                    }
                }

                while try await group.next() != nil {
                    assetCompleted += 1
                    let assetProgress = assetTotal == 0 ? 1 : Double(assetCompleted) / Double(assetTotal)
                    progress = 0.45 + (assetProgress * 0.50)
                    statusMessage = "Đang tải tài nguyên Minecraft (\(assetCompleted)/\(assetTotal))…"

                    if let next = iterator.next() {
                        group.addTask {
                            try await Self.downloadVerified(
                                url: next.0,
                                to: next.1,
                                sha1: next.2,
                                expectedSize: next.3
                            )
                        }
                    }
                }
            }

            let resourcesRoot = try appMinecraftDirectory().appendingPathComponent("resources", isDirectory: true)
            let compatibility = try MinecraftAssetCompatibilityStager.stage(
                assetIndex: assetIndex,
                assetsDirectory: assetsDirectory(),
                resourcesDirectory: resourcesRoot,
                fileManager: fileManager
            )
            if compatibility.virtualFileCount > 0 || compatibility.resourceFileCount > 0 {
                statusMessage = "Đã dựng tài nguyên tương thích cũ (virtual: \(compatibility.virtualFileCount), resources: \(compatibility.resourceFileCount))…"
            }

            let installed = HinekaInstalledVersion(
                id: versionID,
                mainClass: metadata.mainClass,
                javaMajorVersion: metadata.javaVersion?.majorVersion,
                installedAt: Date(),
                clientJarRelativePath: "\(versionID)/\(versionID).jar",
                assetIndexID: assetIndexID
            )
            let markerData = try JSONEncoder().encode(installed)
            try markerData.write(
                to: versionRoot.appendingPathComponent(".hineka-installed.json"),
                options: .atomic
            )

            installedVersionIDs.insert(versionID)
            progress = 1
            statusMessage = "Đã tải xong \(versionID). Runtime Java chưa được kết nối."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func versionsDirectory() throws -> URL {
        try appMinecraftDirectory().appendingPathComponent("versions", isDirectory: true)
    }

    private func versionDirectory(for id: String) throws -> URL {
        let root = try versionsDirectory()
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func libraryDirectory() throws -> URL {
        let directory = try appMinecraftDirectory().appendingPathComponent("libraries", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func assetsDirectory() throws -> URL {
        let directory = try appMinecraftDirectory().appendingPathComponent("assets", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func appMinecraftDirectory() throws -> URL {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw MinecraftVersionInstallerError(message: "Không tìm thấy vùng lưu trữ Hineka.")
        }
        let directory = support.appendingPathComponent("Hineka/Minecraft", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private nonisolated static func fetchData(from url: URL) async throws -> Data {
        try requireAllowedMinecraftURL(url)
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MinecraftVersionInstallerError(message: "Máy chủ tải xuống trả về lỗi HTTP.")
        }
        guard let finalURL = response.url else {
            throw MinecraftVersionInstallerError.invalidDownloadURL
        }
        try requireAllowedMinecraftURL(finalURL)
        return data
    }

    private nonisolated static func downloadVerified(
        url: URL,
        to destination: URL,
        sha1: String?,
        expectedSize: Int64?
    ) async throws {
        try requireAllowedMinecraftURL(url)
        guard let sha1, isSHA1(sha1), let expectedSize, expectedSize >= 0 else {
            throw MinecraftVersionInstallerError.missingIntegrityMetadata
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let existingSize = (attributes[.size] as? NSNumber)?.int64Value
            if existingSize == expectedSize,
               (try? HinekaSHA1FileVerifier.matches(fileAt: destination, expectedSHA1: sha1)) == true {
                return
            }
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MinecraftVersionInstallerError(message: "Không tải được \(url.lastPathComponent).")
        }
        guard let finalURL = response.url else {
            throw MinecraftVersionInstallerError.invalidDownloadURL
        }
        try requireAllowedMinecraftURL(finalURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let downloadedSize = (attributes[.size] as? NSNumber)?.int64Value
        if downloadedSize != expectedSize {
            throw MinecraftVersionInstallerError.sizeMismatch
        }

        guard try HinekaSHA1FileVerifier.matches(fileAt: temporaryURL, expectedSHA1: sha1) else {
            throw MinecraftVersionInstallerError.checksumMismatch
        }

        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private nonisolated static func verify(data: Data, expectedSHA1: String?) throws {
        guard let expectedSHA1, !expectedSHA1.isEmpty else {
            throw MinecraftVersionInstallerError(message: "Thiếu mã SHA-1 để xác minh tệp tải xuống.")
        }
        guard sha1Matches(data, expected: expectedSHA1) else {
            throw MinecraftVersionInstallerError.checksumMismatch
        }
    }

    private nonisolated static func sha1Matches(_ data: Data, expected: String) -> Bool {
        let digest = Insecure.SHA1.hash(data: data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        return actual.caseInsensitiveCompare(expected) == .orderedSame
    }

    private nonisolated static let allowedMinecraftHosts: Set<String> = [
        "piston-meta.mojang.com",
        "launchermeta.mojang.com",
        "piston-data.mojang.com",
        "launcher.mojang.com",
        "libraries.minecraft.net",
        "resources.download.minecraft.net",
        "repo.maven.apache.org",
        "repo1.maven.org"
    ]

    private nonisolated static func requireAllowedMinecraftURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedMinecraftHosts.contains(host) else {
            throw MinecraftVersionInstallerError.invalidDownloadURL
        }
    }

    private nonisolated static func checkedTotalSize(_ sizes: [Int64]) throws -> Int64 {
        var total: Int64 = 0
        for size in sizes {
            guard size >= 0 else {
                throw MinecraftVersionInstallerError.invalidMetadataSize
            }
            let (next, overflow) = total.addingReportingOverflow(size)
            guard !overflow else {
                throw MinecraftVersionInstallerError.invalidMetadataSize
            }
            total = next
        }
        return total
    }

    private func requireAvailableSpace(in directory: URL, estimatedBytes: Int64) throws {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }

        let safetyMargin: Int64 = 200 * 1024 * 1024
        let (requiredWithReserve, overflow) = estimatedBytes.addingReportingOverflow(safetyMargin)
        guard !overflow, available >= requiredWithReserve else {
            throw MinecraftVersionInstallerError.insufficientDiskSpace
        }
    }

    private nonisolated static func isSHA1(_ value: String) -> Bool {
        value.count == 40 && value.allSatisfy { $0.isHexDigit }
    }

    private nonisolated static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
        }
    }

    /// Convert Maven coordinates (group:artifact:version[:classifier][@extension]) to a safe path.
    private nonisolated static func mavenPath(from coordinate: String) -> String? {
        let coordinateParts = coordinate.split(separator: "@", maxSplits: 1).map(String.init)
        let withoutExtension = coordinateParts.first ?? coordinate
        let fileExtension = coordinateParts.count == 2 ? coordinateParts[1] : "jar"
        guard !fileExtension.isEmpty,
              fileExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        let parts = withoutExtension.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts.count <= 4 else { return nil }
        guard parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("..") }) else { return nil }

        let groupPath = parts[0].replacingOccurrences(of: ".", with: "/")
        let artifact = parts[1]
        let version = parts[2]
        let classifier = parts.count == 4 ? "-\(parts[3])" : ""
        return "\(groupPath)/\(artifact)/\(version)/\(artifact)-\(version)\(classifier).\(fileExtension)"
    }

    private nonisolated static func safeDestination(root: URL, relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw MinecraftVersionInstallerError.invalidRelativePath
        }
        let destination = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.standardizedFileURL.path + "/"
        guard destination.path.hasPrefix(rootPath) else {
            throw MinecraftVersionInstallerError.invalidRelativePath
        }
        return destination
    }
}
