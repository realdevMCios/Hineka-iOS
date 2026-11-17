import Foundation

private struct LocalLibraryTestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private struct HinekaLocalLibrarySmokeTests {
    static func main() async throws {
        try await runAll()
    }

    @MainActor
    private static func runAll() throws {
        try testValidImportAndDelete()
        try testRejectsWrongExtension()
        try testRejectsInvalidArchiveSignature()
        try testIgnoresTamperedManifestPath()
        print("Hineka local library safety tests: 4/4 passed")
    }

    @MainActor
    private static func testValidImportAndDelete() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Hineka", isDirectory: true)
        let source = sandbox.appendingPathComponent("sample-mod.jar")
        try archiveHeader.write(to: source)

        let store = HinekaLocalLibraryStore(storageRoot: root)
        let imported = try store.importFiles([source], as: .mod)
        try expect(imported == 1, "A JAR with a ZIP signature was not imported.")
        try expect(store.files.count == 1, "The manifest does not contain the imported JAR.")

        let reloadedStore = HinekaLocalLibraryStore(storageRoot: root)
        try expect(reloadedStore.files.count == 1, "A valid persisted library record was not reloaded.")
        let item = try unwrap(reloadedStore.files.first, "The imported file record is missing.")
        try expect(item.isEnabled, "A newly imported item should start enabled in the profile draft.")

        let storedURL = root
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent(item.storedFileName)
        try expect(FileManager.default.fileExists(atPath: storedURL.path), "The copied JAR is missing.")

        try reloadedStore.delete(item)
        try expect(reloadedStore.files.isEmpty, "Deleting the imported JAR did not update the manifest.")
        try expect(!FileManager.default.fileExists(atPath: storedURL.path), "Deleting the imported JAR left the file behind.")
    }

    @MainActor
    private static func testRejectsWrongExtension() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Hineka", isDirectory: true)
        let source = sandbox.appendingPathComponent("resource-pack.zip")
        try archiveHeader.write(to: source)
        let store = HinekaLocalLibraryStore(storageRoot: root)

        do {
            _ = try store.importFiles([source], as: .mod)
            throw LocalLibraryTestFailure(description: "A .zip file was accepted as a .jar mod.")
        } catch let error as HinekaLocalLibraryError {
            guard case .invalidFileType = error else { throw error }
        }
        try expect(store.files.isEmpty, "An invalid extension created a library record.")
    }

    @MainActor
    private static func testRejectsInvalidArchiveSignature() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Hineka", isDirectory: true)
        let source = sandbox.appendingPathComponent("not-a-real-jar.jar")
        try Data("not a ZIP archive".utf8).write(to: source)
        let store = HinekaLocalLibraryStore(storageRoot: root)

        do {
            _ = try store.importFiles([source], as: .mod)
            throw LocalLibraryTestFailure(description: "A JAR with no ZIP signature was accepted.")
        } catch let error as HinekaLocalLibraryError {
            guard case .invalidArchiveSignature = error else { throw error }
        }
        try expect(store.files.isEmpty, "An invalid archive created a library record.")
    }

    @MainActor
    private static func testIgnoresTamperedManifestPath() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let root = sandbox.appendingPathComponent("Hineka", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let outsideFile = sandbox.appendingPathComponent("outside.jar")
        let sentinel = Data("keep this file".utf8)
        try sentinel.write(to: outsideFile)

        let tamperedItem = HinekaLocalFile(
            id: UUID(),
            kind: .mod,
            originalFileName: "outside.jar",
            storedFileName: "../../outside.jar",
            byteCount: Int64(sentinel.count),
            importedAt: Date(),
            isEnabled: true
        )
        let manifest = try JSONEncoder().encode([tamperedItem])
        try manifest.write(to: root.appendingPathComponent("local-library.json"))

        let store = HinekaLocalLibraryStore(storageRoot: root)
        try expect(store.files.isEmpty, "A manifest entry with a path traversal filename was loaded.")

        do {
            try store.delete(tamperedItem)
            throw LocalLibraryTestFailure(description: "A path traversal filename was accepted for deletion.")
        } catch let error as HinekaLocalLibraryError {
            guard case .invalidStoredFileName = error else { throw error }
        }

        let actual = try Data(contentsOf: outsideFile)
        try expect(actual == sentinel, "A file outside the library root was modified.")
    }

    private static let archiveHeader = Data([
        0x50, 0x4B, 0x03, 0x04,
        0x14, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    ])

    private static func makeSandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HinekaLocalLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw LocalLibraryTestFailure(description: message) }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw LocalLibraryTestFailure(description: message) }
    }
}
