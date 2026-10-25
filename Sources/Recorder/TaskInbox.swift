import Foundation
import Observation
import CryptoKit

enum TaskResponsibility: String, Codable, CaseIterable { case mine, waiting, unresolved }
struct TaskDraft: Codable, Identifiable, Equatable {
    var id = UUID()
    var meetingID: UUID
    var meetingTitle: String
    var scope: String
    var meetingDate: Date
    var sourceHash: String
    var sourceKey: String
    var sourceTask: String
    var sourceOwner: String?
    var ownerID: String?
    var ownerName: String?
    var sourceDeadline: String?
    var kind: String
    var evidence: [SummaryEvidence]
    var evidenceTimes: [String]
    var title: String
    var notes = ""
    var responsibility: TaskResponsibility = .unresolved
    var deadline = "" // YYYY-MM-DD; empty explicitly means no deadline.
    var scheduled = ""
    var dateHint: String?
    var reviewed = false
    var selected = false
    var stale = false
    var dismissed = false
    var duplicateWarning: String?
    var duplicateApproved: Bool?
    var projectID = ""
    var projectName = ""
    var sectionID = ""
    var sectionName = ""
    var labels = ""
    var priority = 4 // UI/CSV convention: p1 highest, p4 normal.
    var assigneeID = ""
    var assigneeName = ""
    var exportChannel: String?
    var remoteID: String?
    var exportError: String?
    var attemptID: UUID?
    var frozenPayload: Data?
    var sendAccountID: String?
    var revision: UUID?
    var locked: Bool { exportChannel != nil || attemptID != nil }
    var exportable: Bool { (duplicateWarning == nil || duplicateApproved == true) && reviewed && !stale && !dismissed && kind != "cancelled" && responsibility == .mine && (scheduled.isEmpty || MeetingDateResolver.validISO(scheduled)) && (deadline.isEmpty || MeetingDateResolver.validISO(deadline)) && (1...4).contains(priority) && (sectionID.isEmpty || !projectID.isEmpty) && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && exportChannel == nil }
    var exportTitle: String { responsibility == .waiting ? "Warten auf \(ownerName ?? "Rückmeldung"): \(title)" : title }
    var exportDescription: String {
        var lines = ["Meeting: \(meetingTitle)", "Bereich: \(scope)", "Aufnahme: \(ISO8601DateFormatter().string(from: meetingDate))"]
        if let ownerName { lines.append("Verantwortlich im Meeting: \(ownerName)") }
        if let sourceDeadline { lines.append("Genannte Frist: \(sourceDeadline)") }
        lines.append(contentsOf: zip(evidence, evidenceTimes).map { "\($0.1) [\($0.0.turnID)]: \($0.0.quote)" })
        if !notes.isEmpty { lines.append(notes) }
        lines.append("Recorder-Aufgabe: \(id.uuidString)")
        return lines.joined(separator: "\n")
    }
}

/// Only deterministic suggestions; exporting always requires human review.
enum MeetingDateResolver {
    static func validISO(_ text: String) -> Bool {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f.date(from: text).map { f.string(from: $0) == text } ?? false
    }
    static func suggest(_ raw: String?, meeting: Date, timezone: TimeZone = .current) -> String? {
        guard let raw else { return nil }
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["bis ", "am ", "by ", "on "] where text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        if validISO(text) { return text }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timezone
        var date: Date?
        if ["heute", "today"].contains(text) { date = meeting }
        else if ["morgen", "tomorrow"].contains(text) { date = cal.date(byAdding: .day, value: 1, to: meeting) }
        else if ["übermorgen"].contains(text) { date = cal.date(byAdding: .day, value: 2, to: meeting) }
        else {
            let weekdays = ["sonntag": 1, "sunday": 1, "montag": 2, "monday": 2, "dienstag": 3, "tuesday": 3, "mittwoch": 4, "wednesday": 4, "donnerstag": 5, "thursday": 5, "freitag": 6, "friday": 6, "samstag": 7, "saturday": 7]
            if let weekday = weekdays[text] { date = cal.date(byAdding: .day, value: (weekday - cal.component(.weekday, from: meeting) + 7) % 7, to: meeting) }
            else {
                let f = DateFormatter(); f.calendar = cal; f.timeZone = timezone; f.locale = Locale(identifier: "de_DE"); f.isLenient = false
                f.dateFormat = "dd.MM.yyyy"
                if text.range(of: #"^\d{2}\.\d{2}\.\d{4}$"#, options: .regularExpression) != nil { date = f.date(from: text) }
            }
        }
        guard let date else { return nil }
        let f = DateFormatter(); f.calendar = cal; f.timeZone = timezone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
struct TaskProjectMapping: Codable, Equatable {
    var projectID: String; var projectName: String; var sectionID: String; var sectionName: String
}
struct MeetingTaskSettings: Codable, Equatable {
    var projectID = ""
    var projectName = ""
    var labels = ""
    var ownSpeakerIDs: [String]? // nil leaves individual assignments unchanged; [] explicitly means none.
}
enum TodoistLabels {
    private static func decode(_ text: String) throws -> [String] {
        let chars = Array(text)
        var fields: [String] = [], value = "", quoted = false, i = 0
        while i < chars.count {
            if chars[i] == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { value.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if chars[i] == "," && !quoted { fields.append(value); value = "" }
            else { value.append(chars[i]) }
            i += 1
        }
        guard !quoted else { throw LocalError.message("Ein Tag enthält ein nicht geschlossenes Anführungszeichen.") }
        fields.append(value)
        var seen: Set<String> = []
        return fields.compactMap { part in
            var value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("@") { value.removeFirst() }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && seen.insert(value.lowercased()).inserted ? value : nil
        }
    }
    static func parse(_ text: String) -> [String] { (try? decode(text)) ?? [] }
    static func format(_ labels: [String]) -> String {
        labels.map { label in
            label.contains(",") || label.contains("\"") ? "\"" + label.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : label
        }.joined(separator: ", ")
    }
    static func validate(_ text: String) throws {
        let labels = try decode(text)
        guard !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), labels.allSatisfy({ $0.count <= 128 }) else {
            throw LocalError.message("Tags dürfen höchstens 128 Zeichen lang sein und keine Steuerzeichen enthalten.")
        }
    }
}

struct TaskCSVBatch: Codable, Identifiable {
    var id = UUID()
    var taskIDs: [UUID]
    var content: String
    var savedPath: String?
}
struct TaskInboxData: Codable {
    var schemaVersion = 1
    var drafts: [TaskDraft] = []
    var myName = ""
    var mappings: [String: TaskProjectMapping] = [:]
    var csvBatches: [TaskCSVBatch] = []
    var meetingSettings: [String: MeetingTaskSettings] = [:]
    init() {}
    enum CodingKeys: String, CodingKey { case schemaVersion, drafts, myName, mappings, csvBatches, meetingSettings }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        drafts = try c.decode([TaskDraft].self, forKey: .drafts)
        myName = try c.decodeIfPresent(String.self, forKey: .myName) ?? ""
        mappings = try c.decodeIfPresent([String: TaskProjectMapping].self, forKey: .mappings) ?? [:]
        csvBatches = try c.decodeIfPresent([TaskCSVBatch].self, forKey: .csvBatches) ?? []
        meetingSettings = try c.decodeIfPresent([String: MeetingTaskSettings].self, forKey: .meetingSettings) ?? [:]
    }
}
@MainActor @Observable final class TaskInbox {
    private(set) var data = TaskInboxData()
    private(set) var storageError: String?
    @ObservationIgnored let url: URL
    init(url: URL = PrivateStorage.applicationRoot.appendingPathComponent("TaskInbox/inbox.json")) {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                data = try PrivateStorage.read(TaskInboxData.self, from: url)
                guard data.schemaVersion == 1 else { throw LocalError.message("Unbekannte Aufgaben-Version") }
            } catch { storageError = error.localizedDescription }
        }
    }
    func edit(_ edit: (inout TaskInboxData) throws -> Void) throws {
        guard storageError == nil else { throw LocalError.message("Aufgaben-Inbox konnte nicht gelesen werden: \(storageError!)") }
        let old = data
        do { try edit(&data); try PrivateStorage.save(data, to: url) }
        catch { data = old; throw error }
    }
    func save(_ draft: TaskDraft) throws {
        try edit { data in
            guard let i = data.drafts.firstIndex(where: { $0.id == draft.id }) else { return }
            guard !data.drafts[i].locked else { throw LocalError.message("Exportierte oder bereits gesendete Aufgaben sind gesperrt.") }
            guard data.drafts[i].sourceHash == draft.sourceHash, data.drafts[i].sourceKey == draft.sourceKey,
                  data.drafts[i].kind == draft.kind, data.drafts[i].evidence == draft.evidence else { throw LocalError.message("Die Quelle wurde inzwischen geändert. Bitte den Entwurf neu öffnen.") }
            guard data.drafts[i].revision == draft.revision else { throw LocalError.message("Die Aufgabe wurde inzwischen geändert. Bitte Entwurf neu öffnen.") }
            guard data.drafts[i].ownerID == draft.ownerID, data.drafts[i].ownerName == draft.ownerName else { throw LocalError.message("Die Sprecherzuordnung wurde geändert. Bitte Entwurf neu öffnen.") }
            var draft = draft
            try TodoistLabels.validate(draft.labels)
            draft.labels = TodoistLabels.format(TodoistLabels.parse(draft.labels))
            draft.stale = data.drafts[i].stale
            if data.drafts[i] != draft { draft.reviewed = false; draft.selected = false; draft.revision = UUID() }
            data.drafts[i] = draft
        }
    }
    func review(_ id: UUID) throws {
        try edit { data in
            guard let i = data.drafts.firstIndex(where: { $0.id == id }) else { return }
            let d = data.drafts[i]
            guard !d.locked, !d.stale, d.kind != "cancelled", (d.duplicateWarning == nil || d.duplicateApproved == true), d.responsibility != .unresolved, !d.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  d.deadline.isEmpty || MeetingDateResolver.validISO(d.deadline), d.scheduled.isEmpty || MeetingDateResolver.validISO(d.scheduled), (1...4).contains(d.priority),
                  d.sectionID.isEmpty || !d.projectID.isEmpty else { throw LocalError.message("Bitte Zuständigkeit, Titel, Projekt und Datumsfelder prüfen.") }
            try TodoistLabels.validate(d.labels)
            data.drafts[i].reviewed = true; data.drafts[i].selected = d.responsibility == .mine
        }
    }
    func configureMeeting(_ id: UUID, settings: MeetingTaskSettings) throws {
        try TodoistLabels.validate(settings.labels)
        var settings = settings; settings.labels = TodoistLabels.format(TodoistLabels.parse(settings.labels))
        try edit { data in
            data.meetingSettings[id.uuidString] = settings
            for i in data.drafts.indices where data.drafts[i].meetingID == id && !data.drafts[i].locked {
                let old = data.drafts[i]
                if data.drafts[i].projectID != settings.projectID {
                    data.drafts[i].sectionID = ""; data.drafts[i].sectionName = ""
                    data.drafts[i].assigneeID = ""; data.drafts[i].assigneeName = ""
                }
                data.drafts[i].projectID = settings.projectID; data.drafts[i].projectName = settings.projectName; data.drafts[i].labels = settings.labels
                if let own = settings.ownSpeakerIDs {
                    data.drafts[i].responsibility = data.drafts[i].ownerID.map { own.contains($0) ? .mine : .waiting } ?? .unresolved
                }
                if old != data.drafts[i] { data.drafts[i].reviewed = false; data.drafts[i].selected = false; data.drafts[i].revision = UUID() }
            }
        }
    }
    func selectedForMeeting(_ id: UUID) -> [TaskDraft] {
        data.drafts.filter { $0.meetingID == id && $0.responsibility == .mine && $0.selected && $0.exportable && $0.attemptID == nil }
    }
    func invalidate(meetingID: UUID) throws {
        try edit { data in
            for i in data.drafts.indices where data.drafts[i].meetingID == meetingID && !data.drafts[i].locked {
                data.drafts[i].stale = true; data.drafts[i].reviewed = false; data.drafts[i].selected = false
            }
        }
    }
    func ingest(_ summary: MeetingSummary, transcript: MeetingTranscript) throws {
        guard summary.meetingID == transcript.meeting.id, summary.transcriptHash == transcript.hash else { throw LocalError.message("Aufgabenquelle ist veraltet.") }
        try SummaryValidator.validate(summary.content, transcript: transcript)
        try edit { data in
            let meeting = transcript.meeting
            let actions = summary.content.actionItems
            var seen: Set<UUID> = []
            let priorIDs = Set(data.drafts.map(\.id))
            for action in actions {
                let turns = action.evidence.map(\.turnID).sorted().joined(separator: ",")
                let normalized = action.task.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let key = SHA256.hash(data: Data("\(meeting.id)|\(turns)|\(normalized)".utf8)).map { String(format: "%02x", $0) }.joined()
                let matching = data.drafts.indices.filter { data.drafts[$0].meetingID == meeting.id && data.drafts[$0].evidence.map(\.turnID).sorted().joined(separator: ",") == turns }
                let uniqueSource = actions.filter { $0.evidence.map(\.turnID).sorted().joined(separator: ",") == turns }.count == 1
                let index = data.drafts.firstIndex { $0.sourceKey == key } ?? (matching.count == 1 && uniqueSource ? matching.first : nil)
                let ownerID = action.owner.flatMap { owner -> String? in
                    if transcript.turns.contains(where: { $0.speakerID == owner }) { return owner }
                    let names = transcript.assignments.filter { $0.status == .confirmed && $0.name == owner }
                    return names.count == 1 ? names.first?.id : nil
                }
                let ownerName = ownerID.map { transcript.label($0) } ?? action.owner
                let suggestion = MeetingDateResolver.suggest(action.deadline, meeting: meeting.startedAt)
                let times = action.evidence.map { ref in MeetingTranscript.timestamp(transcript.turns.first { $0.id == ref.turnID }?.start ?? 0) }
                if let i = index {
                    seen.insert(data.drafts[i].id)
                    guard !data.drafts[i].locked else { continue }
                    let changed = data.drafts[i].sourceHash != transcript.hash || data.drafts[i].sourceTask != action.task || data.drafts[i].sourceOwner != action.owner || data.drafts[i].sourceDeadline != action.deadline || data.drafts[i].kind != action.kind || data.drafts[i].evidence != action.evidence
                    if data.drafts[i].ownerID != ownerID || data.drafts[i].ownerName != ownerName {
                        let own = data.meetingSettings[meeting.id.uuidString]?.ownSpeakerIDs
                        data.drafts[i].responsibility = own.flatMap { ids in ownerID.map { ids.contains($0) ? .mine : .waiting } } ?? .unresolved
                    }
                    data.drafts[i].sourceHash = transcript.hash; data.drafts[i].sourceKey = key; data.drafts[i].stale = false
                    data.drafts[i].sourceTask = action.task; data.drafts[i].sourceOwner = action.owner; data.drafts[i].sourceDeadline = action.deadline
                    data.drafts[i].ownerID = ownerID; data.drafts[i].ownerName = ownerName; data.drafts[i].evidence = action.evidence; data.drafts[i].evidenceTimes = times
                    data.drafts[i].meetingTitle = meeting.title ?? "Aufnahme"; data.drafts[i].kind = action.kind
                    if changed { data.drafts[i].reviewed = false; data.drafts[i].selected = false; data.drafts[i].revision = UUID() }
                } else {
                    var d = TaskDraft(meetingID: meeting.id, meetingTitle: meeting.title ?? "Aufnahme", scope: meeting.scope, meetingDate: meeting.startedAt,
                        sourceHash: transcript.hash, sourceKey: key, sourceTask: action.task, sourceOwner: action.owner, ownerID: ownerID, ownerName: ownerName,
                        sourceDeadline: action.deadline, kind: action.kind, evidence: action.evidence, evidenceTimes: times, title: action.task)
                    if matching.contains(where: { priorIDs.contains(data.drafts[$0].id) }) {
                        d.duplicateWarning = "Es gibt bereits Aufgaben aus derselben Textstelle. Bitte vor dem Export prüfen, ob dies eine weitere Aufgabe oder ein Duplikat ist."
                    }
                    d.deadline = suggestion ?? ""; d.dateHint = action.deadline == nil ? nil : suggestion == nil ? "Frist unklar – bitte prüfen" : "Datum aus dem Meetingdatum abgeleitet – bitte bestätigen"
                    if let mapping = data.mappings[meeting.scope] { d.projectID = mapping.projectID; d.projectName = mapping.projectName; d.sectionID = mapping.sectionID; d.sectionName = mapping.sectionName }
                    if let settings = data.meetingSettings[meeting.id.uuidString] {
                        d.projectID = settings.projectID; d.projectName = settings.projectName; d.sectionID = ""; d.sectionName = ""; d.labels = settings.labels
                        if let ids = settings.ownSpeakerIDs { d.responsibility = ownerID.map { ids.contains($0) ? .mine : .waiting } ?? .unresolved }
                    }
                    data.drafts.append(d); seen.insert(d.id)
                }
            }
            for i in data.drafts.indices where data.drafts[i].meetingID == meeting.id && !seen.contains(data.drafts[i].id) && !data.drafts[i].locked {
                data.drafts[i].stale = true; data.drafts[i].reviewed = false; data.drafts[i].selected = false
            }
        }
    }
}
