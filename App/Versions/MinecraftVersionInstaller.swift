import Foundation
import CryptoKit

struct MinecraftVersionInstallerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static let invalidVersionID = Self(message: "Mã phiên bản Minecraft không hợp lệ.")
    static let missingClientDownload = Self(message: "Manifest không có tệp Minecraft client.")
    static let missingAssetIndex = Self(message: "Manifest không có Asset Index.")
    static let invalidAssetHash = Self(message: "Asset Index chứa mã SHA-1 không hợp lệ.")
    static let checksumMismatch = Self(message: "Tệp tải về không khớp SHA-1 do Mojang cung cấp.")
    static let invalidRelativePath = Self(message: "Đường dẫn tệp trong manifest không hợp lệ.")
    static let invalidDownloadURL = Self(message: "Manifest chứa URL tải xuống không phải HTTPS.")
}

struct MinecraftVersionMetadata: Decodable {
    struct VerifiedDownload: Decodable {
        let sha1: String?
        let size: Int64?
        let url: URL
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
    }

    struct Library: Decodable {
        let name: String
        let downloads: LibraryDownloads?
    }

    struct JavaVersion: Decodable {
        let component: String
        let majorVersion: Int
    }

    let id: String
    let mainClass: String
    let assets: String?
    let assetIndex: AssetIndexInfo?
    let downloads: VersionDownloads
    let libraries: [Library]
    let javaVersion: JavaVersion?
}

struct MinecraftAssetIndex: Decodable {
    struct AssetObject: Decodable {
        let hash: String
        let size: Int64
    }

    let objects: [String: AssetObject]
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
            let marker = directory.appendingPathComponent(".hineka-installed.json")
            guard fileManager.fileExists(atPath: marker.path) else { return nil }
            return directory.lastPathComponent
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
            try Self.requireHTTPS(metadataURL)
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

            var artifacts: [(URL, URL, String?)] = []
            let clientURL = versionRoot.appendingPathComponent("\(versionID).jar")
            artifacts.append((client.url, clientURL, client.sha1))

            let librariesRoot = try libraryDirectory()
            for library in metadata.libraries {
                guard let artifact = library.downloads?.artifact else { continue }
                guard artifact.url.pathExtension.lowercased() == "jar" else { continue }
                guard !artifact.url.lastPathComponent.lowercased().contains("natives") else { continue }
                let relativePath = URL(fileURLWithPath: artifact.url.path).lastPathComponent
                _ = relativePath // Path is derived from Maven coordinates below, not from an arbitrary URL path.
                guard let mavenPath = Self.mavenPath(from: library.name) else { continue }
                let destination = try Self.safeDestination(root: librariesRoot, relativePath: mavenPath)
                artifacts.append((artifact.url, destination, artifact.sha1))
            }

            progress = 0.03
            let totalFixed = max(artifacts.count + 2, 1)
            var completed = 0

            for (url, destination, sha1) in artifacts {
                statusMessage = "Đang tải \(destination.lastPathComponent)…"
                try await Self.downloadVerified(url: url, to: destination, sha1: sha1)
                completed += 1
                progress = min(0.03 + (Double(completed) / Double(totalFixed)) * 0.42, 0.45)
            }

            try Self.requireHTTPS(assetInfo.url)
            statusMessage = "Đang tải Asset Index…"
            let assetIndexData = try await Self.fetchData(from: assetInfo.url)
            try Self.verify(data: assetIndexData, expectedSHA1: assetInfo.sha1)
            let assetIndex = try JSONDecoder().decode(MinecraftAssetIndex.self, from: assetIndexData)

            let assetIndexID = assetInfo.id ?? metadata.assets ?? versionID
            let indexesRoot = try assetsDirectory().appendingPathComponent("indexes", isDirectory: true)
            try fileManager.createDirectory(at: indexesRoot, withIntermediateDirectories: true)
            try assetIndexData.write(
                to: indexesRoot.appendingPathComponent("\(assetIndexID).json"),
                options: .atomic
            )

            let objectsRoot = try assetsDirectory().appendingPathComponent("objects", isDirectory: true)
            try fileManager.createDirectory(at: objectsRoot, withIntermediateDirectories: true)
            let objects = Array(assetIndex.objects.values)
            let assetURLs: [(URL, URL, String)] = try objects.map { object in
                guard Self.isSHA1(object.hash) else {
                    throw MinecraftVersionInstallerError.invalidAssetHash
                }
                let folder = String(object.hash.prefix(2))
                let destination = objectsRoot.appendingPathComponent(folder, isDirectory: true)
                    .appendingPathComponent(object.hash)
                let url = URL(string: "https://resources.download.minecraft.net/\(folder)/\(object.hash)")!
                return (url, destination, object.hash)
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
                            try await Self.downloadVerified(url: item.0, to: item.1, sha1: item.2)
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
                            try await Self.downloadVerified(url: next.0, to: next.1, sha1: next.2)
                        }
                    }
                }
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
        try requireHTTPS(url)
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MinecraftVersionInstallerError(message: "Máy chủ tải xuống trả về lỗi HTTP.")
        }
        return data
    }

    private nonisolated static func downloadVerified(url: URL, to destination: URL, sha1: String?) async throws {
        try requireHTTPS(url)
        if let sha1, FileManager.default.fileExists(atPath: destination.path) {
            let existing = try Data(contentsOf: destination)
            if sha1Matches(existing, expected: sha1) { return }
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MinecraftVersionInstallerError(message: "Không tải được \(url.lastPathComponent).")
        }

        if let sha1 {
            let data = try Data(contentsOf: temporaryURL)
            try verify(data: data, expectedSHA1: sha1)
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

    private nonisolated static func requireHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw MinecraftVersionInstallerError.invalidDownloadURL
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
        let withoutExtension = coordinate.split(separator: "@", maxSplits: 1).first.map(String.init) ?? coordinate
        let parts = withoutExtension.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts.count <= 4 else { return nil }
        guard parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("..") }) else { return nil }

        let groupPath = parts[0].replacingOccurrences(of: ".", with: "/")
        let artifact = parts[1]
        let version = parts[2]
        let classifier = parts.count == 4 ? "-\(parts[3])" : ""
        return "\(groupPath)/\(artifact)/\(version)/\(artifact)-\(version)\(classifier).jar"
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
