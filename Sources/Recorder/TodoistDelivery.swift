import Foundation

/// Account lookup, project validation and each frozen command share the same token snapshot.
/// A batch can partially succeed; each receipt is durable before the next request starts.
@MainActor struct TodoistDelivery {
    let inbox: TaskInbox
    var client = TodoistClient()
    func send(ids: [UUID], meetingID: UUID?, expectedDrafts: [TaskDraft]?, retryID: UUID?, token: String,
              validateSource: ([TaskDraft]) throws -> Void = { _ in }) async throws -> Int {
        guard !ids.isEmpty, Set(ids).count == ids.count else { throw LocalError.message("Bitte eine eindeutige Aufgabenauswahl treffen.") }
        let account = try await client.identity(token: token)
        let projects = try await client.choices("projects", token: token)
        var count = 0
        for id in ids {
            guard let draft = inbox.data.drafts.first(where: { $0.id == id }), draft.responsibility == .mine else { throw LocalError.message("Nur eigene Aufgaben dürfen synchronisiert werden.") }
            if retryID == nil {
                if let expectedDrafts {
                    guard let expected = expectedDrafts.first(where: { $0.id == id }), draft == expected else { throw LocalError.message("Eine Aufgabe wurde nach der Bestätigung geändert. Bitte Auswahl erneut bestätigen.") }
                }
                guard draft.meetingID == meetingID, draft.selected, draft.exportable, draft.attemptID == nil else { throw LocalError.message("Die Auswahl wurde geändert. Bitte erneut prüfen.") }
                try validateSource([draft])
                if !draft.projectID.isEmpty, !projects.contains(where: { $0.id == draft.projectID }) { throw LocalError.message("Das Zielprojekt ist nicht mehr verfügbar. Bitte ein anderes Projekt wählen.") }
            } else {
                guard ids.count == 1, retryID == id, draft.attemptID != nil else { throw LocalError.message("Kein offener Versandauftrag vorhanden.") }
            }
            let shared = projects.first { $0.id == draft.projectID }?.is_shared == true
            let payload = try inbox.prepareSend(id, accountID: account.id, sharedProject: shared)
            do {
                let remote = try await client.create(frozenPayload: payload, token: token)
                try inbox.recordSend(id, remoteID: remote); count += 1
            } catch {
                if error is TodoistRejected { try inbox.rejectSend(id, error: error.localizedDescription) }
                else { try inbox.recordSend(id, remoteID: nil, error: error.localizedDescription) }
                throw error
            }
        }
        return count
    }
}
