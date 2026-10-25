import Foundation

enum TranscriptRepository {
    struct Pointer: Codable { var generation: String }
    static func currentJSON(in folder: URL) throws -> URL? {
        let url = folder.appendingPathComponent("current-result.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let pointer = try PrivateStorage.read(Pointer.self, from: url)
        guard UUID(uuidString: pointer.generation) != nil else { throw LocalError.message("Ungültige Ergebnisreferenz.") }
        return folder.appendingPathComponent("Results/\(pointer.generation)/transcript.json")
    }
    static func publish(_ document: TranscriptDocument, folder: URL) throws -> URL {
        let generation = UUID().uuidString, directory = folder.appendingPathComponent("Results/\(UUID().uuidString)")
        // Use one identifier for the directory and publication pointer.
        let target = directory.deletingLastPathComponent().appendingPathComponent(generation)
        try PrivateStorage.directory(target)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: target) } }
        let json = target.appendingPathComponent("transcript.json"), markdown = target.appendingPathComponent("transcript.md")
        try document.write(jsonTo: json)
        try PrivateStorage.write(Data(document.renderMarkdown().utf8), to: markdown)
        try Task.checkCancellation()
        try PrivateStorage.save(Pointer(generation: generation), to: folder.appendingPathComponent("current-result.json"))
        committed = true
        // Root files are compatibility exports. The atomic pointer is authoritative.
        try? document.write(jsonTo: folder.appendingPathComponent("transcript.json"))
        try? PrivateStorage.write(Data(document.renderMarkdown().utf8), to: folder.appendingPathComponent("transcript.md"))
        for name in ["summary.json", "summary.md"] { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        return markdown
    }
}
extension TranscriptDocument {
    var summaryInput: MeetingTranscript {
        let meeting = meetingRecord ?? MeetingRecord(startedAt: startedAt, title: meetingTitle, attendees: attendees)
        let turns = lines.enumerated().map { index, line in
            SpeakerTurn(id: "T\(index + 1)", speakerID: line.speakerID ?? "Unbekannt",
                        channel: line.channel == "microphone" ? .microphone : .desktop,
                        start: line.time, end: line.endTime ?? line.time, text: line.text, overlap: line.overlap ?? false)
        }
        let assignments = speakerNames.map { SpeakerAssignment(id: $0.key, name: $0.value, status: $0.key == $0.value ? .unknown : .confirmed) }
        return MeetingTranscript(meeting: meeting, modelVersion: model, words: [], turns: turns, assignments: assignments)
    }
}
