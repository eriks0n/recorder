import Foundation

enum MeetingNaming {
    static func clean(_ name: String) -> String? {
        let text = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let cleaned = String(text.filter { !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }.prefix(200))
        return cleaned.isEmpty ? nil : cleaned
    }
    static func markdownTitle(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), let first = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines).first else { return nil }
        for prefix in ["# Transcript: ", "# Transcript — ", "# Transkript: "] where first.hasPrefix(prefix) {
            return clean(String(first.dropFirst(prefix.count)))
        }
        return nil
    }
    static func rename(_ entry: RecordingEntry, to name: String) throws {
        guard let title = clean(name) else { throw LocalError.message("Bitte einen Meetingnamen eingeben.") }
        let folder = entry.folderURL
        try RecordingRetention.requireSafeFolder(folder)
        let json = folder.appendingPathComponent("transcript.json")
        let pointer = folder.appendingPathComponent("current-result.json")
        let hasDocument = FileManager.default.fileExists(atPath: json.path) || FileManager.default.fileExists(atPath: pointer.path)
        var document: TranscriptDocument? = hasDocument ? try TranscriptDocument.load(from: json) : nil
        let oldHash = document?.summaryInput.hash
        let savedSummary = try RecordingRetention.summaryFiles(in: folder)
        let metadataURL = folder.appendingPathComponent("meeting.json")
        var metadata = document?.meetingRecord
            ?? (try? PrivateStorage.read(MeetingRecord.self, from: metadataURL))
            ?? MeetingRecord(startedAt: entry.date, title: entry.title)
        metadata.title = title
        if document != nil {
            document?.meetingTitle = title; document?.meetingRecord = metadata
            if let document {
                _ = try TranscriptRepository.publish(document, folder: folder)
                if var summary = savedSummary.summary, summary.transcriptHash == oldHash {
                    summary.transcriptHash = document.summaryInput.hash
                    summary.meetingID = metadata.id
                    try SummaryRepository.publish(summary, transcript: document.summaryInput, folder: folder)
                } else {
                    try RecordingRetention.restoreSummaryFiles(savedSummary, in: folder)
                }
            }
        } else {
            let markdown = folder.appendingPathComponent("transcript.md")
            if FileManager.default.fileExists(atPath: markdown.path) {
                try RecordingRetention.requireContainedRegularFile(markdown, in: folder)
                let text = try String(contentsOf: markdown, encoding: .utf8)
                var lines = text.components(separatedBy: .newlines)
                if lines.first?.hasPrefix("# Transcript") == true || lines.first?.hasPrefix("# Transkript") == true {
                    lines[0] = "# Transcript: " + title
                } else { lines.insert("# Transcript: " + title + "\n", at: 0) }
                try PrivateStorage.write(Data(lines.joined(separator: "\n").utf8), to: markdown)
            }
        }
        try PrivateStorage.save(metadata, to: metadataURL)
    }
}

struct RetentionReport {
    var cleaned = 0
    var skipped = 0
    var failed = 0
}

enum RecordingRetention {
    static let keptFiles: Set<String> = ["transcript.md", "transcript.json", "summary.md", "summary.json"]
    struct SummaryFiles {
        var json: Data?
        var markdown: Data?
        var summary: MeetingSummary? { json.flatMap { try? JSONDecoder().decode(MeetingSummary.self, from: $0) } }
    }
    static func requireSafeFolder(_ folder: URL) throws {
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw LocalError.message("Aufnahmeordner ist kein regulärer Ordner.") }
    }
    static func requireContainedRegularFile(_ file: URL, in folder: URL) throws {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else {
            throw LocalError.message("Unsichere Dateireferenz im Aufnahmeordner; Bereinigung übersprungen.")
        }
    }
    static func summaryFiles(in folder: URL) throws -> SummaryFiles {
        let fm = FileManager.default
        var source = folder
        let pointerURL = folder.appendingPathComponent("current-summary.json")
        if fm.fileExists(atPath: pointerURL.path) {
            try requireContainedRegularFile(pointerURL, in: folder)
            let pointer = try PrivateStorage.read(SummaryRepository.Pointer.self, from: pointerURL)
            guard UUID(uuidString: pointer.generation) != nil else { throw LocalError.message("Ungültige Zusammenfassungsreferenz.") }
            source = folder.appendingPathComponent("Summaries/\(pointer.generation)")
        }
        var result = SummaryFiles()
        for name in ["summary.json", "summary.md"] {
            let file = source.appendingPathComponent(name)
            if fm.fileExists(atPath: file.path) {
                try requireContainedRegularFile(file, in: folder)
                if name == "summary.json" { result.json = try Data(contentsOf: file) }
                else { result.markdown = try Data(contentsOf: file) }
            } else if source != folder { throw LocalError.message("Zusammenfassung unvollständig; Bereinigung übersprungen.") }
        }
        return result
    }
    static func restoreSummaryFiles(_ summary: SummaryFiles, in folder: URL) throws {
        if let json = summary.json { try PrivateStorage.write(json, to: folder.appendingPathComponent("summary.json")) }
        if let markdown = summary.markdown { try PrivateStorage.write(markdown, to: folder.appendingPathComponent("summary.md")) }
    }
    /// Caller excludes active jobs. No files are removed until complete text copies have been saved and verified.
    static func clean(_ entry: RecordingEntry, afterDays days: Int, now: Date = Date()) throws -> Bool {
        guard (1...3650).contains(days) else { throw LocalError.message("Aufbewahrung muss zwischen 1 und 3650 Tagen liegen.") }
        let folder = entry.folderURL, fm = FileManager.default
        try requireSafeFolder(folder)
        let rootJSON = folder.appendingPathComponent("transcript.json")
        let currentJSON = try TranscriptRepository.currentJSON(in: folder)
        let documentURL = currentJSON ?? (fm.fileExists(atPath: rootJSON.path) ? rootJSON : nil)
        var document: TranscriptDocument?
        if let documentURL {
            try requireContainedRegularFile(documentURL, in: folder)
            document = try TranscriptDocument.load(from: documentURL)
        }
        let metadata = try? PrivateStorage.read(MeetingRecord.self, from: folder.appendingPathComponent("meeting.json"))
        guard document != nil || metadata?.schemaVersion == 1 || RecordingsLibrary.parseFolderName(folder.lastPathComponent).0 != nil else { return false }
        let recordedAt = document?.startedAt ?? metadata?.startedAt ?? entry.date
        guard recordedAt <= now.addingTimeInterval(-Double(days) * 86400) else { return false }
        let rootMarkdown = folder.appendingPathComponent("transcript.md")
        let text: String
        if let document {
            guard document.lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
            text = document.renderMarkdown()
        } else {
            guard fm.fileExists(atPath: rootMarkdown.path) else { return false }
            try requireContainedRegularFile(rootMarkdown, in: folder)
            text = try String(contentsOf: rootMarkdown, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }
        // Reject output symlinks before writing any compacted copies.
        for name in keptFiles {
            let file = folder.appendingPathComponent(name)
            if (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw LocalError.message("Verknüpfte Textdatei; Bereinigung übersprungen.")
            }
        }
        let summary = try summaryFiles(in: folder)
        let expectedChildren = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let removed = expectedChildren.filter { !keptFiles.contains($0.lastPathComponent.lowercased()) }
        guard !removed.isEmpty else { return false }
        if document != nil {
            document?.audioName = nil
            document?.speakerCentroidsID = nil
            if let document { try document.write(jsonTo: rootJSON) }
        }
        let keptText = document?.renderMarkdown() ?? text
        try PrivateStorage.write(Data(keptText.utf8), to: rootMarkdown)
        try restoreSummaryFiles(summary, in: folder)
        guard try String(contentsOf: rootMarkdown, encoding: .utf8) == keptText else { throw LocalError.message("Textkopie konnte nicht bestätigt werden.") }
        if let json = summary.json {
            guard try Data(contentsOf: folder.appendingPathComponent("summary.json")) == json else { throw LocalError.message("Zusammenfassungskopie unvollständig.") }
        }
        if let markdown = summary.markdown {
            guard try Data(contentsOf: folder.appendingPathComponent("summary.md")) == markdown else { throw LocalError.message("Zusammenfassungskopie unvollständig.") }
        }
        // Remove pointers first so readers immediately fall back to the verified root text files.
        let ordered = removed.sorted { a, b in
            let aPointer = a.lastPathComponent.hasPrefix("current-")
            let bPointer = b.lastPathComponent.hasPrefix("current-")
            return aPointer && !bPointer
        }
        for file in ordered { try fm.removeItem(at: file) } // removes links themselves, never their targets
        return true
    }
    static func run(roots: [URL], afterDays days: Int, now: Date = Date()) -> RetentionReport {
        var report = RetentionReport()
        for entry in RecordingsLibrary.entries(roots: roots) {
            do {
                if try clean(entry, afterDays: days, now: now) { report.cleaned += 1 }
                else { report.skipped += 1 }
            } catch { report.failed += 1 }
        }
        return report
    }
}
