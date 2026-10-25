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
        let pointerURL = folder.appendingPathComponent("current-summary.json")
        if !FileManager.default.fileExists(atPath: pointerURL.path) {
            try RecordingRetention.requireContainedRegularFile(folder.appendingPathComponent("summary.json"), in: folder)
            try RecordingRetention.requireContainedRegularFile(folder.appendingPathComponent("summary.md"), in: folder)
            let summary = try PrivateStorage.read(MeetingSummary.self, from: folder.appendingPathComponent("summary.json"))
            guard summary.transcriptHash == hash else { throw LocalError.message("Zusammenfassung ist veraltet; bitte neu erstellen.") }
            return folder.appendingPathComponent("summary.md")
        }
        try RecordingRetention.requireContainedRegularFile(pointerURL, in: folder)
        let pointer = try PrivateStorage.read(Pointer.self, from: pointerURL)
        guard UUID(uuidString: pointer.generation) != nil, pointer.transcriptHash == hash else { throw LocalError.message("Zusammenfassung ist veraltet; bitte neu erstellen.") }
        let markdown = folder.appendingPathComponent("Summaries/\(pointer.generation)/summary.md")
        try RecordingRetention.requireContainedRegularFile(markdown, in: folder)
        return markdown
    }
}
