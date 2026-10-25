import SwiftUI
import AppKit

@MainActor final class TaskInboxWindowController: NSObject, NSWindowDelegate {
    static let shared = TaskInboxWindowController()
    private var window: NSWindow?
    func show(model: RecorderModel) {
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: TaskInboxView().environment(model)))
        window.title = "Recorder Aufgaben-Inbox"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1000, height: 720)); window.minSize = NSSize(width: 850, height: 600)
        window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        self.window = window; window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { window = nil }
}
struct TaskInboxView: View {
    @Environment(RecorderModel.self) private var model
    @State private var selected: UUID?
    @State private var filter = "open"
    @State private var myName = ""
    @State private var confirmSend = false
    var drafts: [TaskDraft] {
        model.taskInbox.data.drafts.filter {
            switch filter {
            case "mine": return $0.responsibility == .mine && !$0.dismissed && $0.exportChannel == nil
            case "waiting": return $0.responsibility == .waiting && !$0.dismissed && $0.exportChannel == nil
            case "exported": return $0.locked
            case "all": return true
            default: return !$0.dismissed && $0.exportChannel == nil
            }
        }.sorted { $0.meetingDate > $1.meetingDate }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Aufgaben aus deinen Meetings").font(.title2)
                Spacer()
                Button("CSV exportieren…") { model.exportTasksCSV() }.disabled(model.selectedTasks.isEmpty || model.todoistBusy)
                Button("An Todoist senden…") { confirmSend = true }.disabled(model.selectedTasks.isEmpty || model.todoistBusy)
                Button("Zusammenfassungen einlesen") { model.importSavedActions() }
            }
            HStack {
                TextField("Mein Name im Transkript", text: $myName).frame(width: 240)
                Button("Merken") {
                    do { try model.taskInbox.edit { $0.myName = myName.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    catch { model.taskInboxStatus = error.localizedDescription }
                }
                Text("Neue Aufgaben mit diesem bestätigten Namen werden als eigene vorgeschlagen.").font(.caption).foregroundStyle(.secondary)
            }
            if let status = model.todoistStatus { Text(status).font(.caption) }
            if model.todoistBusy { ProgressView().controlSize(.small) }
            if !model.taskInbox.data.csvBatches.isEmpty {
                Menu("Vorbereitete CSV-Exporte erneut speichern…") {
                    ForEach(model.taskInbox.data.csvBatches.reversed()) { batch in
                        Button("\(batch.taskIDs.count) Aufgaben · \(batch.id.uuidString.prefix(8))") { model.exportTasksCSV(batchID: batch.id) }
                    }
                }.font(.caption)
            }
            if let error = model.taskInbox.storageError { Text(error).foregroundStyle(.red) }
            if let status = model.taskInboxStatus { Text(status).font(.caption).textSelection(.enabled) }
            HSplitView {
                VStack {
                    Picker("Ansicht", selection: $filter) {
                        Text("Offen").tag("open"); Text("Meine").tag("mine"); Text("Warten auf").tag("waiting"); Text("Exportiert / Versand offen").tag("exported"); Text("Alle").tag("all")
                    }
                    List(drafts, selection: $selected) { draft in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if draft.exportable && draft.attemptID == nil {
                                    Toggle("Auswählen", isOn: Binding(get: { draft.selected }, set: { value in
                                        do { try model.taskInbox.select(draft.id, value: value) } catch { model.taskInboxStatus = error.localizedDescription }
                                    })).labelsHidden()
                                }
                                Text(draft.title).lineLimit(2)
                            }
                            Text(draft.meetingTitle + " · " + (draft.ownerName ?? "Ungeklärt")).font(.caption).foregroundStyle(.secondary)
                            Text(draft.exportChannel ?? (draft.attemptID != nil ? "Versand offen" : draft.stale ? "Quelle geändert" : draft.reviewed ? "Geprüft" : "Bitte prüfen")).font(.caption)
                        }.padding(.vertical, 4).tag(draft.id)
                    }
                }.frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
                if let draft = model.taskInbox.data.drafts.first(where: { $0.id == selected }) {
                    TaskDraftEditor(draft: draft).id(draft.id).frame(minWidth: 450)
                } else {
                    ContentUnavailableView("Aufgabe auswählen", systemImage: "checklist", description: Text("Nach einer lokalen Zusammenfassung erscheinen hier Aufgabenentwürfe. Vor dem Export Zuständigkeit und Termine prüfen."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.padding(16).onAppear { myName = model.taskInbox.data.myName }
        .confirmationDialog("Ausgewählte Aufgaben an Todoist übertragen?", isPresented: $confirmSend) {
            Button("\(model.selectedTasks.count) Aufgaben übertragen") { model.sendTasksToTodoist() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Übertragen werden Titel, Termine, Notizen, Meetingname und kurze Belege dieser Aufgaben:\n" + model.selectedTasks.map { "• " + $0.exportTitle + " → " + ($0.projectName.isEmpty ? "Todoist-Eingang" : $0.projectName) }.joined(separator: "\n"))
        }
    }
}
struct TaskDraftEditor: View {
    @Environment(RecorderModel.self) private var model
    @State var draft: TaskDraft
    var current: TaskDraft { model.taskInbox.data.drafts.first { $0.id == draft.id } ?? draft }
    var body: some View {
        Form {
            Section("Aufgabe prüfen") {
                if current.stale { Text("Die Quelle wurde geändert oder die Aufgabe fehlt in der aktuellen Zusammenfassung. Bitte Zusammenfassung erneuern und Entwurf prüfen.").foregroundStyle(.orange) }
                if draft.kind == "proposal" { Text("Dies wurde nur vorgeschlagen. Mit deiner Bestätigung machst du daraus eine Aufgabe.").font(.caption) }
                if draft.kind == "cancelled" { Text("Diese Aufgabe wurde im Meeting abgesagt und kann nicht exportiert werden.").foregroundStyle(.orange) }
                if let warning = current.duplicateWarning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                    Toggle("Geprüft: Dies ist eine zusätzliche Aufgabe", isOn: Binding(get: { draft.duplicateApproved == true }, set: { draft.duplicateApproved = $0 }))
                }
                TextField("Aufgabe", text: $draft.title)
                Text("Genannte Person: " + (current.ownerName ?? "Nicht zugeordnet")).font(.caption)
                Picker("Zuständigkeit", selection: $draft.responsibility) {
                    Text("Noch ungeklärt").tag(TaskResponsibility.unresolved)
                    Text("Meine Aufgabe").tag(TaskResponsibility.mine)
                    Text("Warten auf andere Person").tag(TaskResponsibility.waiting)
                }
                TextField("Persönliche Notizen", text: $draft.notes, axis: .vertical)
                Toggle("Entwurf ausblenden", isOn: $draft.dismissed)
            }.disabled(current.locked)
            Section("Termine") {
                if let raw = current.sourceDeadline { Text("Im Meeting: \(raw)") }
                if let hint = draft.dateHint { Text(hint).font(.caption).foregroundStyle(.secondary) }
                TextField("Erledigen am (JJJJ-MM-TT, optional)", text: $draft.scheduled)
                TextField("Deadline (JJJJ-MM-TT, optional)", text: $draft.deadline)
                Text("Leer lassen, wenn kein Termin vereinbart ist. Relative Fristen beziehen sich auf den Tag des Meetings.").font(.caption)
            }.disabled(current.locked)
            Section("Todoist-Ziel") {
                Button("Projekte und Abschnitte laden") { model.loadTodoistProjects() }.disabled(model.todoistBusy)
                Picker("Projekt", selection: Binding(get: { draft.projectID }, set: { id in
                    draft.projectID = id; draft.projectName = model.todoistProjects.first { $0.id == id }?.name ?? ""
                    draft.sectionID = ""; draft.sectionName = ""; draft.assigneeID = ""; draft.assigneeName = ""
                })) {
                    Text("Todoist-Eingang").tag("")
                    if !draft.projectID.isEmpty && !model.todoistProjects.contains(where: { $0.id == draft.projectID }) { Text(draft.projectName).tag(draft.projectID) }
                    ForEach(model.todoistProjects) { Text($0.name).tag($0.id) }
                }
                Picker("Abschnitt", selection: Binding(get: { draft.sectionID }, set: { id in
                    draft.sectionID = id; draft.sectionName = model.todoistSections.first { $0.id == id }?.name ?? ""
                })) {
                    Text("Kein Abschnitt").tag("")
                    if !draft.sectionID.isEmpty && !model.todoistSections.contains(where: { $0.id == draft.sectionID }) { Text(draft.sectionName).tag(draft.sectionID) }
                    ForEach(model.todoistSections.filter { $0.project_id == draft.projectID }) { Text($0.name).tag($0.id) }
                }.disabled(draft.projectID.isEmpty)
                Button("Ziel für neue Aufgaben dieses Kundenbereichs merken") { model.rememberTaskProject(draft) }
                TextField("Labels (durch Komma getrennt)", text: $draft.labels)
                Picker("Priorität", selection: $draft.priority) { ForEach(1...4, id: \.self) { Text("P\($0)").tag($0) } }
                Button("Mitglieder dieses Projekts laden") { model.loadTodoistCollaborators(project: draft.projectID) }.disabled(draft.projectID.isEmpty || model.todoistBusy)
                Picker("Todoist-Zuweisung", selection: Binding(get: { draft.assigneeID }, set: { id in
                    draft.assigneeID = id; draft.assigneeName = model.todoistCollaborators.first { $0.id == id }?.name ?? ""
                })) {
                    Text("Keine Zuweisung").tag("")
                    if !draft.assigneeID.isEmpty && !model.todoistCollaborators.contains(where: { $0.id == draft.assigneeID }) { Text(draft.assigneeName).tag(draft.assigneeID) }
                    ForEach(model.todoistCollaborators) { Text($0.name).tag($0.id) }
                }.disabled(draft.projectID.isEmpty)
                Text("Zuweisungen gelten für Mitglieder geteilter Projekte. Eine Meeting-Person wird niemals automatisch einem Todoist-Konto zugeordnet.").font(.caption)
            }.disabled(current.locked)
            if current.locked {
                Section("Exportstatus") {
                    Text(current.exportChannel ?? "Versand noch nicht eindeutig bestätigt")
                    if let id = current.remoteID { Text("Todoist-ID: \(id)").font(.caption).textSelection(.enabled) }
                    if let error = current.exportError { Text(error).font(.caption).foregroundStyle(.orange) }
                    if current.attemptID != nil && current.exportChannel == nil {
                        Button("Denselben Versandauftrag erneut versuchen") { model.sendTasksToTodoist(retryID: current.id) }.disabled(model.todoistBusy)
                        Text("Erneuter Versuch mit unveränderten Daten und derselben Auftragsnummer, um doppelte Aufgaben zu vermeiden.").font(.caption)
                    }
                }
            }
            Section("Quelle") {
                Text(current.meetingTitle + " · " + current.scope)
                ForEach(Array(current.evidence.enumerated()), id: \.offset) { i, ref in
                    Text("\(current.evidenceTimes.indices.contains(i) ? current.evidenceTimes[i] : ref.turnID): \(ref.quote)").font(.caption).textSelection(.enabled)
                }
            }
            HStack {
                Button("Speichern") { model.saveTaskDraft(draft) }.disabled(current.locked)
                Button("Speichern und als geprüft auswählen") { model.saveTaskDraft(draft, review: true) }
                    .disabled(current.locked || current.stale || current.kind == "cancelled")
            }
            Text("Änderungen müssen gespeichert werden. Nur ausdrücklich geprüfte und ausgewählte Aufgaben werden exportiert.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
        .onChange(of: current) { _, value in
            if value.sourceHash != draft.sourceHash || value.sourceKey != draft.sourceKey || value.kind != draft.kind || value.evidence != draft.evidence || value.stale != draft.stale || value.locked != draft.locked || value.reviewed != draft.reviewed { draft = value }
        }
    }
}
