import Foundation
import Security

enum TodoistCredential {
    static let service = "com.tobi.Recorder.todoist"
    static func load() throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "personal-api-token", kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else { throw LocalError.message("Todoist-Zugang konnte nicht aus dem Schlüsselbund gelesen werden (\(status)).") }
        return token
    }
    static func save(_ token: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "personal-api-token"] as [CFString: Any]
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains("\n"), !token.contains("\r") else { throw LocalError.message("Bitte einen gültigen Todoist-API-Token eintragen.") }
        let attributes = [kSecValueData: Data(token.utf8)] as [CFString: Any]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query.merging(attributes) { _, new in new }
            add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LocalError.message("Todoist-Zugang konnte nicht gespeichert werden (\(status)).") }
    }
    static func remove() throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "personal-api-token"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LocalError.message("Todoist-Zugang konnte nicht gelöscht werden (\(status)).") }
    }
}
struct TodoistChoice: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var project_id: String?
}
struct TodoistSyncArguments: Codable, Equatable {
    struct Day: Codable, Equatable { var date: String }
    var content: String
    var description: String
    var project_id: String?
    var section_id: String?
    var labels: [String]
    var priority: Int
    var due: Day?
    var deadline: Day?
    var responsible_uid: String?
    init(_ draft: TaskDraft) {
        content = draft.exportTitle; description = draft.exportDescription
        project_id = draft.projectID.isEmpty ? nil : draft.projectID
        section_id = draft.sectionID.isEmpty ? nil : draft.sectionID
        labels = draft.labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        priority = 5 - draft.priority // Sync API convention: 4 urgent, 1 normal.
        due = draft.scheduled.isEmpty ? nil : Day(date: draft.scheduled)
        deadline = draft.deadline.isEmpty ? nil : Day(date: draft.deadline)
        responsible_uid = draft.assigneeID.isEmpty ? nil : draft.assigneeID
    }
}
struct TodoistSyncCommand: Codable {
    var type = "item_add"
    var uuid: String
    var temp_id: String
    var args: TodoistSyncArguments
}
private final class TodoistNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct TodoistClient {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    var transport: Transport
    init(transport: Transport? = nil) {
        if let transport { self.transport = transport }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 40; configuration.timeoutIntervalForResource = 60
            configuration.httpCookieStorage = nil; configuration.urlCache = nil
            let session = URLSession(configuration: configuration, delegate: TodoistNoRedirect(), delegateQueue: nil)
            self.transport = { request in
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw LocalError.message("Ungültige Todoist-Antwort.") }
                return (data, response)
            }
        }
    }
    private func send(path: String, token: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var url = URLComponents(string: "https://api.todoist.com/api/v1/" + path)!
        url.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: url.url!)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try Task.checkCancellation()
        let (data, response) = try await transport(request)
        guard (200...299).contains(response.statusCode) else {
            let advice = response.statusCode == 401 ? "Zugangsdaten prüfen." : response.statusCode == 429 ? "Später erneut versuchen." : "Projekt und Berechtigungen prüfen."
            throw LocalError.message("Todoist antwortet mit Status \(response.statusCode). \(advice)")
        }
        return data
    }
    func choices(_ path: String, token: String, project: String? = nil) async throws -> [TodoistChoice] {
        guard ["projects", "sections"].contains(path) || (path.hasPrefix("projects/") && path.hasSuffix("/collaborators") && path.split(separator: "/").count == 3) else { throw LocalError.message("Ungültige Todoist-Auswahl.") }
        struct Page: Decodable { var results: [TodoistChoice]; var next_cursor: String? }
        var all: [TodoistChoice] = [], cursor: String?, cursors: Set<String> = []
        repeat {
            var query = [URLQueryItem(name: "limit", value: "200")]
            if let project { query.append(.init(name: "project_id", value: project)) }
            if let cursor { query.append(.init(name: "cursor", value: cursor)) }
            let page = try JSONDecoder().decode(Page.self, from: await send(path: path, token: token, query: query))
            all += page.results; cursor = page.next_cursor
            if let cursor { guard cursors.insert(cursor).inserted, cursors.count < 1000 else { throw LocalError.message("Ungültige Todoist-Seitenfolge.") } }
        } while cursor != nil
        return all
    }
    func create(frozenPayload: Data, token: String) async throws -> String {
        let command = try JSONDecoder().decode(TodoistSyncCommand.self, from: frozenPayload)
        struct Body: Encodable { var commands: [TodoistSyncCommand] }
        let result = try await send(path: "sync", token: token, body: JSONEncoder().encode(Body(commands: [command])))
        guard let json = try JSONSerialization.jsonObject(with: result) as? [String: Any],
              let status = json["sync_status"] as? [String: Any], status[command.uuid] as? String == "ok",
              let mapping = json["temp_id_mapping"] as? [String: String], let id = mapping[command.temp_id], !id.isEmpty else {
            throw LocalError.message("Todoist hat den Auftrag nicht eindeutig bestätigt. Der gespeicherte Versandauftrag bleibt für einen erneuten Versuch erhalten.")
        }
        return id
    }
}
enum TodoistCSV {
    static func cell(_ text: String) -> String {
        var safe = text
        // Prevent formulas when the CSV is opened in a spreadsheet before importing.
        if let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first, "=+-@".contains(first) { safe = "'" + text }
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static func render(_ drafts: [TaskDraft]) throws -> String {
        guard !drafts.isEmpty, drafts.allSatisfy({ $0.exportable && $0.attemptID == nil }), Set(drafts.map(\.projectID)).count == 1 else {
            throw LocalError.message("Für CSV bitte geprüfte Aufgaben aus genau einem Zielprojekt auswählen.")
        }
        let header = ["TYPE", "CONTENT", "DESCRIPTION", "PRIORITY", "INDENT", "RESPONSIBLE", "DATE", "DATE_LANG", "TIMEZONE", "DEADLINE", "DEADLINE_LANG"]
        var rows: [[String]] = [header]
        let sorted = drafts.sorted { ($0.sectionName, $0.meetingDate, $0.title) < ($1.sectionName, $1.meetingDate, $1.title) }
        var lastSection = ""
        for d in sorted {
            if !d.sectionName.isEmpty, d.sectionName != lastSection {
                rows.append(["section", d.sectionName] + Array(repeating: "", count: header.count - 2)); lastSection = d.sectionName
            }
            let labels = d.labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { "@" + $0 }.joined(separator: " ")
            let content = d.exportTitle + (labels.isEmpty ? "" : " " + labels)
            let assignee = d.assigneeID.isEmpty ? "" : "\(d.assigneeName) (\(d.assigneeID))"
            rows.append(["task", content, d.exportDescription, String(d.priority), "1", assignee, d.scheduled, "de", TimeZone.current.identifier, d.deadline, "de"])
        }
        return rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
extension TaskInbox {
    func prepareSend(_ id: UUID) throws -> Data {
        var payload: Data!
        try edit { data in
            guard let i = data.drafts.firstIndex(where: { $0.id == id }), data.drafts[i].exportChannel == nil else { throw LocalError.message("Aufgabe wurde bereits exportiert.") }
            if let frozen = data.drafts[i].frozenPayload { payload = frozen; return }
            guard data.drafts[i].exportable else { throw LocalError.message("Bitte die Aufgabe zuerst prüfen und bestätigen.") }
            let uuid = UUID()
            payload = try JSONEncoder().encode(TodoistSyncCommand(uuid: uuid.uuidString, temp_id: uuid.uuidString, args: TodoistSyncArguments(data.drafts[i])))
            data.drafts[i].attemptID = uuid; data.drafts[i].frozenPayload = payload; data.drafts[i].selected = false
        }
        return payload
    }
    func recordSend(_ id: UUID, remoteID: String?, error: String? = nil) throws {
        try edit { data in
            guard let i = data.drafts.firstIndex(where: { $0.id == id }), data.drafts[i].attemptID != nil else { throw LocalError.message("Versandauftrag fehlt.") }
            data.drafts[i].exportError = error
            if let remoteID { data.drafts[i].remoteID = remoteID; data.drafts[i].exportChannel = "Todoist" }
        }
    }
    func select(_ id: UUID, value: Bool) throws {
        try edit { data in
            guard let i = data.drafts.firstIndex(where: { $0.id == id }), data.drafts[i].exportable, data.drafts[i].attemptID == nil else { throw LocalError.message("Aufgabe ist noch nicht freigegeben oder bereits im Versand.") }
            data.drafts[i].selected = value
        }
    }
    func markCSV(_ ids: Set<UUID>) throws {
        try edit { data in
            for i in data.drafts.indices where ids.contains(data.drafts[i].id) {
                guard data.drafts[i].exportable, !data.drafts[i].locked else { throw LocalError.message("Aufgabe wurde inzwischen geändert.") }
                data.drafts[i].exportChannel = "CSV vorbereitet"; data.drafts[i].selected = false
            }
        }
    }
}
