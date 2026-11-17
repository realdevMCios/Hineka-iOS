import Foundation
import Combine

public enum HinekaLocalFileKind: String, Codable, CaseIterable, Identifiable {
    case mod
    case resourcePack

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mod: return "Mods (.jar)"
        case .resourcePack: return "Resource Packs (.zip)"
        }
    }

    fileprivate var folderName: String {
        switch self {
        case .mod: return "Mods"
        case .resourcePack: return "ResourcePacks"
        }
    }

    fileprivate var expectedExtension: String {
        switch self {
        case .mod: return "jar"
        case .resourcePack: return "zip"
        }
    }
}

public struct HinekaLocalFile: Codable, Identifiable, Hashable {
    public let id: UUID
    public let kind: HinekaLocalFileKind
    public let originalFileName: String
    public let storedFileName: String
    public let byteCount: Int64
    public let importedAt: Date
    public var isEnabled: Bool
}

/// Imports files into Hineka's private app container.
/// This does not yet install mods into a Minecraft profile or activate them in a JVM.
@MainActor
public final class HinekaLocalLibraryStore: ObservableObject {
    @Published public private(set) var files: [HinekaLocalFile] = []

    private let fileManager = FileManager.default
    private let maximumFileSize: Int64 = 250 * 1024 * 1024

    public init() {
        reload()
    }

    public func reload() {
        guard let manifestURL = try? manifestURL(),
              let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([HinekaLocalFile].self, from: data) else {
            files = []
            return
        }
        files = decoded.sorted { $0.importedAt > $1.importedAt }
    }

    @discardableResult
    public func importFiles(_ urls: [URL], as kind: HinekaLocalFileKind) throws -> Int {
        var importedCount = 0

        for sourceURL in urls {
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let ext = sourceURL.pathExtension.lowercased()
            guard ext == kind.expectedExtension else {
                throw HinekaLocalLibraryError.invalidFileType(expected: kind.expectedExtension)
            }

            let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw HinekaLocalLibraryError.notRegularFile
            }
            guard let fileSize = values.fileSize, fileSize > 0 else {
                throw HinekaLocalLibraryError.emptyFile
            }

            let byteCount = Int64(fileSize)
            guard byteCount <= maximumFileSize else {
                throw HinekaLocalLibraryError.fileTooLarge
            }
            try Self.validateZIPSignature(at: sourceURL)

            let folder = try directory(for: kind)
            let storedName = UUID().uuidString + "." + kind.expectedExtension
            let destinationURL = folder.appendingPathComponent(storedName, isDirectory: false)

            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            do {
                let copiedValues = try destinationURL.resourceValues(forKeys: [.fileSizeKey])
                guard copiedValues.fileSize == fileSize else {
                    throw HinekaLocalLibraryError.copySizeMismatch
                }
            } catch {
                try? fileManager.removeItem(at: destinationURL)
                throw error
            }

            let item = HinekaLocalFile(
                id: UUID(),
                kind: kind,
                originalFileName: sourceURL.lastPathComponent,
                storedFileName: storedName,
                byteCount: byteCount,
                importedAt: Date(),
                isEnabled: true
            )
            files.insert(item, at: 0)
            do {
                try saveManifest()
            } catch {
                files.removeAll { $0.id == item.id }
                try? fileManager.removeItem(at: destinationURL)
                throw error
            }
            importedCount += 1
        }

        return importedCount
    }

    public func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].isEnabled = enabled
        try? saveManifest()
    }

    public func delete(_ item: HinekaLocalFile) throws {
        let folder = try directory(for: item.kind)
        let fileURL = folder.appendingPathComponent(item.storedFileName, isDirectory: false)

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        files.removeAll { $0.id == item.id }
        try saveManifest()
    }

    private static func validateZIPSignature(at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        let signature: Data
        do {
            signature = try handle.read(upToCount: 4) ?? Data()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        let acceptedSignatures = [
            Data([0x50, 0x4B, 0x03, 0x04]),
            Data([0x50, 0x4B, 0x05, 0x06]),
            Data([0x50, 0x4B, 0x07, 0x08])
        ]
        guard acceptedSignatures.contains(signature) else {
            throw HinekaLocalLibraryError.invalidArchiveSignature
        }
    }
    private func directory(for kind: HinekaLocalFileKind) throws -> URL {
        guard let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw HinekaLocalLibraryError.storageUnavailable
        }

        let root = support.appendingPathComponent("Hineka", isDirectory: true)
        let folder = root.appendingPathComponent(kind.folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func manifestURL() throws -> URL {
        guard let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw HinekaLocalLibraryError.storageUnavailable
        }

        let root = support.appendingPathComponent("Hineka", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("local-library.json", isDirectory: false)
    }

    private func saveManifest() throws {
        let url = try manifestURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(files)
        try data.write(to: url, options: .atomic)
    }
}

public enum HinekaLocalLibraryError: LocalizedError {
    case invalidFileType(expected: String)
    case notRegularFile
    case emptyFile
    case invalidArchiveSignature
    case fileTooLarge
    case copySizeMismatch
    case storageUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidFileType(let expected):
            return "Tệp không đúng định dạng .\(expected)."
        case .notRegularFile:
            return "Chỉ có thể nhập một tệp thông thường, không phải thư mục hoặc liên kết."
        case .emptyFile:
            return "Tệp rỗng hoặc không đọc được dung lượng."
        case .invalidArchiveSignature:
            return "Nội dung tệp không có chữ ký ZIP/JAR hợp lệ."
        case .fileTooLarge:
            return "Tệp vượt quá giới hạn 250 MB."
        case .copySizeMismatch:
            return "Dung lượng tệp sau khi sao chép không khớp tệp gốc."
        case .storageUnavailable:
            return "Không thể truy cập vùng lưu trữ của Hineka."
        }
    }
}
