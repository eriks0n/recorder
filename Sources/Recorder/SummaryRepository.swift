import Foundation

enum SummaryRepository {
    struct Pointer: Codable { var generation: String; var transcriptHash: String }
    static func publish(_ summary: MeetingSummary, transcript: MeetingTranscript, folder: URL) throws {
        guard summary.transcriptHash == transcript.hash else { throw LocalError.message("Zusammenfassung ist veraltet.") }
        let generation = UUID().uuidString
        let target = folder.appendingPathComponent("Summaries/\(generation)")
        try PrivateStorage.directory(target)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: target) } }
        try PrivateStorage.save(summary, to: target.appendingPathComponent("summary.json"))
        try PrivateStorage.write(Data(summary.markdown(transcript: transcript).utf8), to: target.appendingPathComponent("summary.md"))
        try Task.checkCancellation()
        try PrivateStorage.save(Pointer(generation: generation, transcriptHash: transcript.hash), to: folder.appendingPathComponent("current-summary.json"))
        committed = true
        try? PrivateStorage.save(summary, to: folder.appendingPathComponent("summary.json"))
        try? PrivateStorage.write(Data(summary.markdown(transcript: transcript).utf8), to: folder.appendingPathComponent("summary.md"))
    }
    static func current(in folder: URL, hash: String) throws -> URL {
        let pointer = try PrivateStorage.read(Pointer.self, from: folder.appendingPathComponent("current-summary.json"))
        guard UUID(uuidString: pointer.generation) != nil, pointer.transcriptHash == hash else { throw LocalError.message("Zusammenfassung ist veraltet; bitte neu erstellen.") }
        return folder.appendingPathComponent("Summaries/\(pointer.generation)/summary.md")
    }
}
