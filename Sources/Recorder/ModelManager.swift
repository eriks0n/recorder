import Foundation
import CryptoKit


struct ModelSpec: Codable, Identifiable {
    var id: String
    var repository: String
    var revision: String
    var files: [String]
}
/// The only network-enabled component in the local pipeline. Never receives meeting data.
actor ModelManager {
    static let shared = ModelManager()
    static var catalog: [ModelSpec] {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url), let specs = try? JSONDecoder().decode([ModelSpec].self, from: data) else { return [] }
        return specs
    }
    nonisolated static func folder(_ id: String) throws -> URL {
        guard let spec = catalog.first(where: { $0.id == id }) else { throw LocalError.message("Unbekanntes Modell.") }
        return PrivateStorage.applicationRoot.appendingPathComponent("Models/\(id)-\(spec.revision)", isDirectory: true)
    }
    nonisolated static func ready(_ id: String) -> Bool {
        guard let spec = catalog.first(where: { $0.id == id }), let folder = try? folder(id),
              let manifest = try? PrivateStorage.read([String: String].self, from: folder.appendingPathComponent("installed.json")) else { return false }
        return spec.files.allSatisfy { manifest[$0] != nil && FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }
    private var downloading = false
    func download(_ id: String, progress: @escaping @Sendable (String) async -> Void) async throws {
        guard !downloading else { throw LocalError.message("Ein Modelldownload läuft bereits.") }
        downloading = true; defer { downloading = false }
        guard let spec = Self.catalog.first(where: { $0.id == id }) else { throw LocalError.message("Modell fehlt im Katalog.") }
        if Self.ready(id) { return }
        let destination = try Self.folder(id)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".download-\(UUID().uuidString)")
        try PrivateStorage.directory(staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120; config.timeoutIntervalForResource = 7200
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var hashes: [String: String] = [:]
        for (index, path) in spec.files.enumerated() {
            try Task.checkCancellation()
            guard Self.safeRelativePath(path) else { throw LocalError.message("Ungültiger Modellpfad.") }
            await progress("\(id): Datei \(index + 1)/\(spec.files.count)")
            let url = URL(string: "https://huggingface.co/\(spec.repository)/resolve/\(spec.revision)/\(path)")!
            let (temporary, response) = try await session.download(from: url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw LocalError.message("Modelldownload fehlgeschlagen. Bitte erneut versuchen.") }
            let target = staging.appendingPathComponent(path)
            try PrivateStorage.directory(target.deletingLastPathComponent())
            try FileManager.default.moveItem(at: temporary, to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            hashes[path] = try Self.digest(target)
        }
        try Task.checkCancellation()
        try PrivateStorage.save(hashes, to: staging.appendingPathComponent("installed.json"))
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: staging, to: destination)
    }
    nonisolated static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    nonisolated static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func verifiedFolder(_ id: String) throws -> URL {
        guard ready(id), let spec = catalog.first(where: { $0.id == id }) else { throw LocalError.message("Lokales Modell fehlt. Bitte in den Einstellungen herunterladen; kein Cloud-Fallback.") }
        let url = try folder(id)
        let hashes = try PrivateStorage.read([String: String].self, from: url.appendingPathComponent("installed.json"))
        for path in spec.files {
            guard try digest(url.appendingPathComponent(path)) == hashes[path] else { throw LocalError.message("Modell beschädigt. Modellordner entfernen und erneut herunterladen.") }
        }
        return url
    }
}
