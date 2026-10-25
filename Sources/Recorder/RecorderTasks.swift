import Foundation
import AppKit
import UniformTypeIdentifiers

extension RecorderModel {
    var selectedTasks: [TaskDraft] { taskInbox.data.drafts.filter { $0.selected && $0.exportable && $0.attemptID == nil } }
    func connectTodoist(token: String) {
        guard !todoistBusy else { return }
        do { try TodoistCredential.save(token); todoistStatus = "Zugang im Schlüsselbund gespeichert. Projekte können jetzt geladen werden." }
        catch { todoistStatus = error.localizedDescription }
    }
    func disconnectTodoist() {
        guard !todoistBusy else { return }
        do {
            try TodoistCredential.remove(); todoistProjects = []; todoistSections = []; todoistCollaborators = []
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
                todoistProjects = try await client.choices("projects", token: token)
                todoistSections = try await client.choices("sections", token: token)
                todoistStatus = "Projekte und Abschnitte geladen."
            } catch { todoistStatus = error.localizedDescription }
        }
    }
    func loadTodoistCollaborators(project: String) {
        guard !todoistBusy, !project.isEmpty, project.allSatisfy({ $0.isLetter || $0.isNumber }) else { return }
        todoistBusy = true; todoistCollaborators = []
        Task {
            defer { todoistBusy = false }
            do {
                guard let token = try TodoistCredential.load() else { throw LocalError.message("Bitte Todoist verbinden.") }
                todoistCollaborators = try await TodoistClient().choices("projects/\(project)/collaborators", token: token)
                todoistStatus = "Projektmitglieder geladen. Bitte ausdrücklich zuordnen."
            } catch { todoistStatus = error.localizedDescription }
        }
    }
    func rememberTaskProject(_ draft: TaskDraft) {
        do {
            try taskInbox.edit { data in
                data.mappings[draft.scope] = TaskProjectMapping(projectID: draft.projectID, projectName: draft.projectName, sectionID: draft.sectionID, sectionName: draft.sectionName)
            }
            taskInboxStatus = "Zielprojekt für neue Aufgaben im Bereich \(draft.scope) gespeichert."
        } catch { taskInboxStatus = error.localizedDescription }
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
    func exportTasksCSV(batchID: UUID? = nil) {
        do {
            let existing = batchID.flatMap { id in taskInbox.data.csvBatches.first { $0.id == id } }
            let tasks = selectedTasks
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
    func sendTasksToTodoist(retryID: UUID? = nil) {
        guard !todoistBusy else { return }
        let ids = retryID.map { [$0] } ?? selectedTasks.map(\.id)
        guard !ids.isEmpty else { return }
        todoistBusy = true
        Task {
            defer { todoistBusy = false }
            do {
                guard let token = try TodoistCredential.load() else { throw LocalError.message("Bitte zuerst Todoist in den Einstellungen verbinden.") }
                let client = TodoistClient()
                var count = 0
                for id in ids {
                    if retryID == nil, let draft = taskInbox.data.drafts.first(where: { $0.id == id }) { try validateTaskSources([draft]) }
                    let payload = try taskInbox.prepareSend(id)
                    do {
                        let remote = try await client.create(frozenPayload: payload, token: token)
                        try taskInbox.recordSend(id, remoteID: remote); count += 1
                    } catch {
                        try taskInbox.recordSend(id, remoteID: nil, error: error.localizedDescription)
                        throw error
                    }
                }
                taskInboxStatus = "\(count) Aufgaben an Todoist übertragen."
            } catch { taskInboxStatus = "Todoist: " + error.localizedDescription }
        }
    }
}
