import Foundation

/// Deletes audio only after both authoritative text results have been verified.
/// Other attachments, metadata and text generations are not part of this option.
enum RecordingAudioCleanup {
    static let audioExtensions: Set<String> = ["caf", "m4a", "wav", "mp3", "flac", "aac", "ogg", "opus", "aiff", "aif"]
    @discardableResult
    static func removeAfterSuccessfulProcessing(in folder: URL) throws -> Int {
        try RecordingRetention.requireSafeFolder(folder)
        let rootJSON = folder.appendingPathComponent("transcript.json")
        let currentJSON = try TranscriptRepository.currentJSON(in: folder) ?? rootJSON
        try RecordingRetention.requireContainedRegularFile(currentJSON, in: folder)
        var document = try TranscriptDocument.load(from: currentJSON)
        guard document.lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LocalError.message("Kein vollständiges Transkript; Audio bleibt erhalten.")
        }
        let input = document.summaryInput
        let summaryMarkdown = try SummaryRepository.current(in: folder, hash: input.hash)
        try RecordingRetention.requireContainedRegularFile(summaryMarkdown, in: folder)
        let summaryJSON = summaryMarkdown.deletingLastPathComponent().appendingPathComponent("summary.json")
        try RecordingRetention.requireContainedRegularFile(summaryJSON, in: folder)
        let summary = try PrivateStorage.read(MeetingSummary.self, from: summaryJSON)
        guard summary.meetingID == input.meeting.id, summary.transcriptHash == input.hash else {
            throw LocalError.message("Zusammenfassung ist nicht aktuell; Audio bleibt erhalten.")
        }
        try SummaryValidator.validate(summary.content, transcript: input)
        guard !(try Data(contentsOf: summaryMarkdown)).isEmpty else {
            throw LocalError.message("Zusammenfassung ist unvollständig; Audio bleibt erhalten.")
        }
        try Task.checkCancellation()
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let audio = try files.filter { file in
            guard audioExtensions.contains(file.pathExtension.lowercased()) else { return false }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true || values.isSymbolicLink == true
        }
        guard audio.isEmpty || document.isPolished else {
            throw LocalError.message("Der vollständige Offline-Durchlauf fehlt; Audio bleibt zur Wiederherstellung erhalten.")
        }
        for file in audio {
            try Task.checkCancellation()
            // A symbolic link is removed itself; its destination is never followed or deleted.
            try FileManager.default.removeItem(at: file)
        }
        if document.audioName != nil || !audio.isEmpty {
            document.audioName = nil
            _ = try TranscriptRepository.publish(document, folder: folder)
            try SummaryRepository.publish(summary, transcript: document.summaryInput, folder: folder)
        }
        return audio.count
    }
}
