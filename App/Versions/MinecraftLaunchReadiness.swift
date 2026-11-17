import Foundation
import CryptoKit

public struct HinekaLaunchReadiness: Identifiable {
    public var id: String { versionID }

    public let versionID: String
    public let javaMajorVersion: Int?
    public let mainClass: String
    public let clientJarExists: Bool
    public let assetIndexExists: Bool
    public let libraryCount: Int
    public let missingLibraryCount: Int
    public let assetCount: Int
    public let missingAssetCount: Int
    public let nativeClassifierCount: Int
    public let blockers: [String]

    public var vanillaPayloadReady: Bool {
        clientJarExists &&
        assetIndexExists &&
        missingLibraryCount == 0 &&
        missingAssetCount == 0
    }

    public var canLaunch: Bool { blockers.isEmpty }

    public var summary: String {
        var lines = [
            "Phiên bản: \(versionID)",
            "Java yêu cầu: \(javaMajorVersion.map { String($0) } ?? "không xác định")",
            "Client JAR: \(clientJarExists ? "có" : "thiếu")",
            "Thư viện: \(libraryCount - missingLibraryCount)/\(libraryCount)",
            "Assets: \(assetCount - missingAssetCount)/\(assetCount)",
            "Native desktop trong metadata: \(nativeClassifierCount)",
            "Dữ liệu vanilla: \(vanillaPayloadReady ? "đủ" : "chưa đủ")",
            "Có thể chạy: \(canLaunch ? "có" : "chưa")"
        ]
        if !blockers.isEmpty {
            lines.append("")
            lines.append("Các phần còn thiếu:")
            lines.append(contentsOf: blockers.map { "• " + $0 })
        }
        return lines.joined(separator: "\n")
    }
}

/// Audits an installed vanilla profile before Hineka ever enables the Play button.
/// It never starts Java and never treats downloaded desktop native libraries as iOS binaries.
public enum MinecraftLaunchReadinessChecker {
    public static func inspect(versionID: String) throws -> HinekaLaunchReadiness {
        guard isSafeIdentifier(versionID) else {
            throw MinecraftVersionInstallerError.invalidVersionID
        }

        let fileManager = FileManager.default
        guard let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw MinecraftVersionInstallerError(message: "Không tìm thấy vùng lưu trữ Hineka.")
        }

        let gameRoot = support.appendingPathComponent("Hineka/Minecraft", isDirectory: true)
        let versionRoot = gameRoot.appendingPathComponent("versions/\(versionID)", isDirectory: true)
        let metadataURL = versionRoot.appendingPathComponent("\(versionID).json")
        let clientURL = versionRoot.appendingPathComponent("\(versionID).jar")
        let markerURL = versionRoot.appendingPathComponent(".hineka-installed.json")

        guard
            let metadataData = try? Data(contentsOf: metadataURL),
            let metadata = try? JSONDecoder().decode(MinecraftVersionMetadata.self, from: metadataData),
            metadata.id == versionID
        else {
            throw MinecraftVersionInstallerError(message: "Không đọc được metadata của phiên bản đã cài.")
        }

        guard
            let markerData = try? Data(contentsOf: markerURL),
            let marker = try? JSONDecoder().decode(HinekaInstalledVersion.self, from: markerData),
            marker.id == versionID,
            marker.clientJarRelativePath == "\(versionID)/\(versionID).jar"
        else {
            throw MinecraftVersionInstallerError(message: "Thiếu dấu xác nhận cài đặt của Hineka.")
        }

        let librariesRoot = gameRoot.appendingPathComponent("libraries", isDirectory: true)
        var libraryCount = 0
        var missingLibraryCount = 0

        for library in metadata.libraries {
            guard let artifact = library.downloads?.artifact else { continue }
            guard !artifact.url.lastPathComponent.lowercased().contains("natives") else { continue }
            guard let relativePath = artifact.path ?? mavenRelativePath(from: library.name) else { continue }

            let fileURL = try safeDestination(root: librariesRoot, relativePath: relativePath)
            libraryCount += 1
            if !fileMatches(fileURL, sha1: artifact.sha1, size: artifact.size) {
                missingLibraryCount += 1
            }
        }

        let assetIndexID = metadata.assetIndex?.id ?? metadata.assets ?? versionID
        guard isSafeIdentifier(assetIndexID), marker.assetIndexID == assetIndexID else {
            throw MinecraftVersionInstallerError(message: "Asset Index ID không khớp metadata của profile.")
        }
        let assetsRoot = gameRoot.appendingPathComponent("assets", isDirectory: true)
        let indexURL = assetsRoot
            .appendingPathComponent("indexes", isDirectory: true)
            .appendingPathComponent("\(assetIndexID).json")
        let assetIndexExists: Bool
        if let assetInfo = metadata.assetIndex {
            assetIndexExists = fileMatches(indexURL, sha1: assetInfo.sha1, size: assetInfo.size)
        } else {
            assetIndexExists = false
        }

        var assetCount = 0
        var missingAssetCount = 0
        if assetIndexExists,
           let indexData = try? Data(contentsOf: indexURL),
           let assetIndex = try? JSONDecoder().decode(MinecraftAssetIndex.self, from: indexData) {
            var seen = Set<String>()
            let uniqueObjects = assetIndex.objects.values.filter { seen.insert($0.hash).inserted }
            assetCount = uniqueObjects.count
            let objectRoot = assetsRoot.appendingPathComponent("objects", isDirectory: true)
            for object in uniqueObjects {
                guard isSHA1(object.hash) else {
                    missingAssetCount += 1
                    continue
                }
                let fileURL = objectRoot
                    .appendingPathComponent(String(object.hash.prefix(2)), isDirectory: true)
                    .appendingPathComponent(object.hash)
                if !fileMatches(fileURL, sha1: object.hash, size: object.size) {
                    missingAssetCount += 1
                }
            }
        } else {
            missingAssetCount = 1
        }

        let nativeClassifierCount = metadata.libraries.reduce(into: 0) { count, library in
            if library.natives != nil {
                count += 1
            } else {
                let nativeKeys = library.downloads?.classifiers?.keys.filter {
                    $0.hasPrefix("natives-")
                } ?? []
                if !nativeKeys.isEmpty {
                    count += 1
                }
            }
        }

        var blockers: [String] = []
        let clientJarIsValid = fileMatches(
            clientURL,
            sha1: metadata.downloads.client?.sha1,
            size: metadata.downloads.client?.size
        )
        if !clientJarIsValid {
            blockers.append("Minecraft client JAR bị thiếu hoặc không khớp SHA-1/dung lượng.")
        }
        if missingLibraryCount > 0 {
            blockers.append("Thiếu \(missingLibraryCount) thư viện Java.")
        }
        if !assetIndexExists || missingAssetCount > 0 {
            blockers.append("Thiếu Asset Index hoặc \(missingAssetCount) asset.")
        }
        if let javaMajorVersion = metadata.javaVersion?.majorVersion {
            blockers.append("OpenJDK Zero Java \(javaMajorVersion) chưa được xác minh trên thiết bị; cần chạy smoke-test và kiểm tra tương thích.")
        } else {
            blockers.append("Không xác định được phiên bản Java yêu cầu.")
        }
        if nativeClassifierCount > 0 {
            blockers.append("Cần native renderer/LWJGL tương thích iOS; không thể dùng native desktop.")
        }
        blockers.append("Microsoft account/session authentication chưa được tích hợp.")
        blockers.append("JVM bootstrap, tham số khởi chạy và game process supervisor chưa được tích hợp.")

        return HinekaLaunchReadiness(
            versionID: versionID,
            javaMajorVersion: metadata.javaVersion?.majorVersion,
            mainClass: metadata.mainClass,
            clientJarExists: clientJarIsValid,
            assetIndexExists: assetIndexExists,
            libraryCount: libraryCount,
            missingLibraryCount: missingLibraryCount,
            assetCount: assetCount,
            missingAssetCount: missingAssetCount,
            nativeClassifierCount: nativeClassifierCount,
            blockers: blockers
        )
    }

    private static func fileMatches(_ url: URL, sha1: String?, size: Int64?) -> Bool {
        guard let sha1, isSHA1(sha1) else { return false }
        if let size, size < 0 { return false }

        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let actualSize = (attributes[.size] as? NSNumber)?.int64Value,
            let data = try? Data(contentsOf: url)
        else {
            return false
        }

        if let size, actualSize != size { return false }

        return Insecure.SHA1.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
            .caseInsensitiveCompare(sha1) == .orderedSame
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
        }
    }

    private static func isSHA1(_ value: String) -> Bool {
        value.count == 40 && value.allSatisfy { $0.isHexDigit }
    }

    private static func mavenRelativePath(from coordinate: String) -> String? {
        let coordinateParts = coordinate.split(separator: "@", maxSplits: 1).map(String.init)
        let withoutExtension = coordinateParts.first ?? coordinate
        let ext = coordinateParts.count == 2 ? coordinateParts[1] : "jar"
        guard !ext.isEmpty, ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return nil
        }
        let parts = withoutExtension.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts.count <= 4,
              parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("..") }) else {
            return nil
        }
        let group = parts[0].replacingOccurrences(of: ".", with: "/")
        let artifact = parts[1]
        let version = parts[2]
        let classifier = parts.count == 4 ? "-\(parts[3])" : ""
        return "\(group)/\(artifact)/\(version)/\(artifact)-\(version)\(classifier).\(ext)"
    }

    private static func safeDestination(root: URL, relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains(".."),
              !relativePath.contains("\\") else {
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
