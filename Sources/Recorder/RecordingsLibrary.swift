import Foundation

/// One past recording on disk (a folder under ~/Documents/Recordings).
struct RecordingEntry: Identifiable, Equatable {
    /// Folder path — stable identity.
    var id: String { folderURL.path }
    let folderURL: URL
    /// Parsed meeting title (nil for ad-hoc recordings).
    let title: String?
    /// Best timestamp for the recording (parsed from the folder name, else file date).
    let date: Date
    /// audio.m4a, if it exists.
    let audioURL: URL?
    /// transcript.md, if it exists.
    let transcriptURL: URL?
    /// transcript.json, the structured source the markdown is rendered from.
    let documentURL: URL?

    var hasTranscript: Bool { transcriptURL != nil }
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "Recording"
    }
}

/// Reads the on-disk recordings library so the panel can show prior recordings
/// (and their transcripts) after a restart — the in-memory list doesn't survive
/// relaunches.
enum RecordingsLibrary {

    /// ~/Documents/Recordings (not created here).
    static func recordingsRoot() -> URL? {
        if !Preferences.recordingPath.isEmpty { return URL(fileURLWithPath: Preferences.recordingPath, isDirectory: true) }
        return PrivateStorage.applicationRoot.appendingPathComponent("Recordings", isDirectory: true)
    }

    static func roots() -> [URL] {
        Array(Set([recordingsRoot(), FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Recordings")].compactMap { $0 }))
    }
    static func recent(limit: Int) -> [RecordingEntry] {
        Array(entries(roots: roots()).sorted { $0.date > $1.date }.prefix(max(0, limit)))
    }
    private struct DocumentIndex: Decodable {
        var meetingTitle: String?
        var startedAt: Date?
    }
    static func entries(roots: [URL]) -> [RecordingEntry] {
        let fm = FileManager.default
        return Array(Set(roots)).flatMap { root -> [RecordingEntry] in
            let items = (try? fm.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            return items.compactMap { folder -> RecordingEntry? in
                guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { return nil }
                let rootJSON = folder.appendingPathComponent("transcript.json")
                let currentJSON = try? TranscriptRepository.currentJSON(in: folder)
                let document = currentJSON ?? rootJSON
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let index: DocumentIndex? = (try? Data(contentsOf: document)).flatMap { try? decoder.decode(DocumentIndex.self, from: $0) }
                let metadata = try? PrivateStorage.read(MeetingRecord.self, from: folder.appendingPathComponent("meeting.json"))
                let currentMarkdown = document.deletingLastPathComponent().appendingPathComponent("transcript.md")
                let rootMarkdown = folder.appendingPathComponent("transcript.md")
                let markdown = fm.fileExists(atPath: currentMarkdown.path) ? currentMarkdown : rootMarkdown
                let audio = folder.appendingPathComponent("audio.m4a")
                let hasAudio = fm.fileExists(atPath: audio.path)
                let hasTranscript = fm.fileExists(atPath: markdown.path)
                let hasDocument = fm.fileExists(atPath: document.path)
                let hasRaw = ["desktop.caf", "mic.caf"].contains { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
                guard hasAudio || hasTranscript || hasDocument || hasRaw else { return nil }
                let (parsedDate, folderTitle) = parseFolderName(folder.lastPathComponent)
                let title = index?.meetingTitle ?? metadata?.title ?? (hasTranscript ? MeetingNaming.markdownTitle(markdown) : nil) ?? folderTitle
                let date = index?.startedAt ?? metadata?.startedAt ?? parsedDate ?? values.creationDate ?? values.contentModificationDate ?? .distantPast
                return RecordingEntry(folderURL: folder, title: title, date: date,
                                      audioURL: hasAudio ? audio : nil, transcriptURL: hasTranscript ? markdown : nil,
                                      documentURL: hasDocument ? document : nil)
            }
        }
    }

    /// Parse "yyyy-M-d-HHmm[-title][-N]" into (date, title). Best-effort.
    static func parseFolderName(_ name: String) -> (Date?, String?) {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              parts[3].count == 4, let hhmm = Int(parts[3]) else {
            return (nil, name.isEmpty ? nil : name)
        }

        guard (1970...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hhmm / 100), (0...59).contains(hhmm % 100) else { return (nil, name) }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hhmm / 100
        components.minute = hhmm % 100
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)
        guard let date, calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else { return (nil, name) }

        // Title is everything after the date/time, minus a trailing numeric
        // collision suffix (e.g. "-2") added when two recordings share a minute.
        var titleParts = Array(parts.dropFirst(4))
        if let last = titleParts.last, last.count <= 3, !last.isEmpty, last.allSatisfy(\.isNumber) {
            titleParts.removeLast()
        }
        let title = titleParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (date, title.isEmpty ? nil : title)
    }
}
