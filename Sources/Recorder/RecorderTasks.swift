import Foundation
import AppKit
import UniformTypeIdentifiers

extension RecorderModel {
    var selectedTasks: [TaskDraft] { taskInbox.data.drafts.filter { $0.selected && $0.exportable && $0.attemptID == nil } }
    func connectTodoist(token: String) {
        guard !todoistBusy else { return }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            todoistStatus = "Bitte einen gültigen Todoist-API-Key eintragen."; return
        }
        todoistBusy = true; todoistStatus = "Verbindung wird geprüft…"
        Task {
            defer { todoistBusy = false }
            do {
                let identity = try await TodoistClient().identity(token: token)
                try TodoistCredential.save(token)
                todoistIdentity = identity
                todoistProjects = []; todoistSections = []; todoistLabels = []
                todoistStatus = "Verbunden als " + (identity.full_name ?? identity.id) + " · API-Key im Schlüsselbund gespeichert."
            } catch { todoistStatus = "Verbindung nicht gespeichert: " + error.localizedDescription }
        }
    }
    func disconnectTodoist() {
        guard !todoistBusy else { return }
        do {
            try TodoistCredential.remove(); todoistProjects = []; todoistSections = []; todoistLabels = []; todoistIdentity = nil
            todoistStatus = "Todoist-Zugang aus dem Schlüsselbund entfernt."
        } catch { todoistStatus = error.localizedDescription }
    }
    func loadTodoistProjects() {
        guard !todoistBusy else { return }
        todoistBusy = true
        Task {
            defer { todoistBusy = false }
            do {
                guard let token = try TodoistCredential.load() else { throw LocalError.message("Bitte zuerst den Todoist-API-Token speichern.") }
                let client = TodoistClient()
                let identity = try await client.identity(token: token)
                let projects = try await client.choices("projects", token: token)
                let sections = try await client.choices("sections", token: token)
                let labels = try await client.choices("labels", token: token)
                todoistIdentity = identity; todoistProjects = projects; todoistSections = sections; todoistLabels = labels
                todoistStatus = "Verbunden als " + (identity.full_name ?? identity.id) + " · Projekte und Tags geladen."
            } catch { todoistStatus = error.localizedDescription }
        }
    }
    func taskMeetingSpeakers(_ id: UUID) -> [(id: String, name: String)] {
        var seen: Set<String> = []
        return taskInbox.data.drafts.filter { $0.meetingID == id }.compactMap { draft in
            guard let id = draft.ownerID, seen.insert(id).inserted else { return nil }
            return (id, draft.ownerName ?? id)
        }
    }
    private func validateTaskSources(_ drafts: [TaskDraft]) throws {
        let entries = RecordingsLibrary.entries(roots: RecordingsLibrary.roots())
        for entry in entries where entry.hasTranscript {
            guard let document = try? TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json")),
                  let meeting = document.meetingRecord, drafts.contains(where: { $0.meetingID == meeting.id }) else { continue }
            if processingQueue.unfinished.contains(where: { $0.folder.standardizedFileURL == entry.folderURL.standardizedFileURL }) {
                throw LocalError.message("Für dieses Meeting steht noch Verarbeitung aus. Bitte zuerst abschließen oder den Auftrag verwerfen.")
            }
            if drafts.contains(where: { $0.meetingID == meeting.id && $0.sourceHash != document.summaryInput.hash }) {
                try taskInbox.invalidate(meetingID: meeting.id)
                throw LocalError.message("Ein Transkript wurde geändert. Bitte Zusammenfassung erneuern und Aufgaben erneut prüfen.")
            }
        }
    }
    func exportTasksCSV(batchID: UUID? = nil, meetingID: UUID? = nil) {
        do {
            let existing = batchID.flatMap { id in taskInbox.data.csvBatches.first { $0.id == id } }
            let tasks = meetingID.map { taskInbox.selectedForMeeting($0) } ?? selectedTasks
            if existing == nil { try validateTaskSources(tasks) }
            let content = try existing?.content ?? TodoistCSV.render(tasks)
            let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = "Recorder-Aufgaben.csv"
            panel.message = "In Todoist im gewählten Zielprojekt importieren. Jede CSV nur einmal importieren; sonst entstehen doppelte Aufgaben."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let batch: TaskCSVBatch
            if let existing { batch = existing }
            else {
                batch = TaskCSVBatch(taskIDs: tasks.map(\.id), content: content)
                try taskInbox.edit { data in
                    for i in data.drafts.indices where batch.taskIDs.contains(data.drafts[i].id) {
                        guard data.drafts[i].exportable, !data.drafts[i].locked else { throw LocalError.message("Aufgabe wurde inzwischen geändert.") }
                        data.drafts[i].exportChannel = "CSV vorbereitet"; data.drafts[i].selected = false
                    }
                    data.csvBatches.append(batch)
                }
            }
            // The frozen batch is durable before writing. A write error can safely re-save the same batch.
            try Data(content.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try taskInbox.edit { data in
                guard let i = data.csvBatches.firstIndex(where: { $0.id == batch.id }) else { return }
                data.csvBatches[i].savedPath = url.path
            }
            taskInboxStatus = "CSV gespeichert. In Todoist im passenden Projekt einmalig importieren. Aufgaben sind für weiteren Versand gesperrt."
        } catch { taskInboxStatus = "CSV: " + error.localizedDescription + " Ein vorbereiteter Export kann erneut gespeichert werden." }
    }
    func sendTasksToTodoist(meetingID: UUID? = nil, taskIDs: [UUID]? = nil, expectedDrafts: [TaskDraft]? = nil, retryID: UUID? = nil) {
        guard !todoistBusy else { return }
        let candidates = meetingID.map { taskInbox.selectedForMeeting($0) } ?? []
        let ids = retryID.map { [$0] } ?? (taskIDs ?? candidates.map(\.id)).filter { id in candidates.contains { $0.id == id } }
        guard !ids.isEmpty else { return }
        todoistBusy = true
        Task {
            defer { todoistBusy = false }
            do {
                guard let token = try TodoistCredential.load() else { throw LocalError.message("Bitte zuerst Todoist in den Einstellungen verbinden.") }
                let count = try await TodoistDelivery(inbox: taskInbox).send(ids: ids, meetingID: meetingID, expectedDrafts: expectedDrafts,
                    retryID: retryID, token: token, validateSource: { [self] drafts in try validateTaskSources(drafts) })
                taskInboxStatus = "\(count) Aufgaben an Todoist übertragen."
            } catch { taskInboxStatus = "Todoist: " + error.localizedDescription + " Bereits bestätigte Aufgaben bleiben als übertragen markiert; weitere ausgewählte Aufgaben bleiben offen." }
        }
    }
}
