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
    @State private var meeting = ""
    @State private var confirmedTasks: [TaskDraft] = []
    @State private var confirmSend = false
    init(selection: UUID? = nil) { _selected = State(initialValue: selection) }
    var meetingID: UUID? { UUID(uuidString: meeting) }
    var meetings: [TaskDraft] {
        var ids: Set<UUID> = []
        return model.taskInbox.data.drafts.sorted { $0.meetingDate > $1.meetingDate }.filter { ids.insert($0.meetingID).inserted }
    }
    var selectedTasks: [TaskDraft] { meetingID.map { model.taskInbox.selectedForMeeting($0) } ?? [] }
    var drafts: [TaskDraft] {
        model.taskInbox.data.drafts.filter {
            if let meetingID, $0.meetingID != meetingID { return false }
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
                Button("CSV exportieren…") { model.exportTasksCSV(meetingID: meetingID) }.disabled(selectedTasks.isEmpty || model.todoistBusy)
                Button("Mit Todoist synchronisieren…") { confirmedTasks = selectedTasks; confirmSend = true }.disabled(selectedTasks.isEmpty || model.todoistBusy)
                Button("Zusammenfassungen einlesen") { model.importSavedActions() }
            }
            Picker("Meeting", selection: $meeting) {
                Text("Alle Meetings ansehen").tag("")
                ForEach(meetings) { item in
                    Text(item.meetingTitle + " · " + item.meetingDate.formatted(date: .abbreviated, time: .shortened)).tag(item.meetingID.uuidString)
                }
            }
            if let meetingID {
                MeetingTodoistControls(meetingID: meetingID).id(meetingID)
            } else {
                Text("Zum Synchronisieren ein Meeting auswählen. Ausschließlich deine geprüften, angehakten Aufgaben werden übertragen.").font(.caption).foregroundStyle(.secondary)
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
        }.padding(16).background(Color(nsColor: .windowBackgroundColor)).onAppear {
            meeting = model.taskInbox.data.drafts.first { $0.id == selected }?.meetingID.uuidString ?? meetings.first?.meetingID.uuidString ?? ""
        }
        .onChange(of: meeting) { _, _ in
            if let selected, model.taskInbox.data.drafts.first(where: { $0.id == selected })?.meetingID != meetingID { self.selected = nil }
        }
        .confirmationDialog("Ausgewählte Aufgaben an Todoist übertragen?", isPresented: $confirmSend) {
            Button("\(confirmedTasks.count) eigene Aufgaben übertragen") {
                model.sendTasksToTodoist(meetingID: confirmedTasks.first?.meetingID, taskIDs: confirmedTasks.map(\.id), expectedDrafts: confirmedTasks)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Übertragen werden Titel, Termine, Notizen, Meetingname und kurze Belege dieser Aufgaben:\n" + confirmedTasks.map { "• " + $0.exportTitle + " → #" + ($0.projectName.isEmpty ? "Todoist-Eingang" : $0.projectName) + ($0.scheduled.isEmpty ? "" : " · fällig " + $0.scheduled) + ($0.labels.isEmpty ? "" : " · @" + TodoistLabels.parse($0.labels).joined(separator: " @")) }.joined(separator: "\n"))
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
                if !current.locked, let error = current.exportError { Text(error).font(.caption).foregroundStyle(.orange) }
                TextField("Aufgabe", text: $draft.title)
                Text("Genannte Person: " + (current.ownerName ?? "Nicht zugeordnet")).font(.caption)
                if current.responsibility != .mine { Text("Diese Aufgabe wird nicht an dein Todoist übertragen. Bei Bedarf ausdrücklich dir selbst zuweisen.").font(.caption).foregroundStyle(.secondary) }
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
                OptionalTaskDateField(title: "Todoist-Fälligkeitsdatum", value: $draft.scheduled)
                OptionalTaskDateField(title: "Verbindliche Deadline", value: $draft.deadline)
                Text("Leer lassen, wenn kein Termin vereinbart ist. Relative Fristen beziehen sich auf den Tag des Meetings.").font(.caption)
            }.disabled(current.locked)
            Section("Todoist-Ziel dieses Meetings") {
                Text("# " + (current.projectName.isEmpty ? "Todoist-Eingang" : current.projectName))
                Text(current.labels.isEmpty ? "Keine Tags" : "@" + TodoistLabels.parse(current.labels).joined(separator: " @"))
                if !current.sectionName.isEmpty { Text("Abschnitt: " + current.sectionName).font(.caption) }
                Text("Projekt und Tags oben für das Meeting übernehmen. Bereits übertragene Aufgaben behalten ihr ursprüngliches Ziel.").font(.caption).foregroundStyle(.secondary)
                Picker("Priorität", selection: $draft.priority) { ForEach(1...4, id: \.self) { Text("P\($0)").tag($0) } }.disabled(current.locked)
            }
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
                Button(draft.responsibility == .mine ? "Prüfen und für Todoist auswählen" : "Als geprüft speichern") { model.saveTaskDraft(draft, review: true) }
                    .disabled(current.locked || current.stale || current.kind == "cancelled")
            }
            Text("Änderungen müssen gespeichert werden. Nur ausdrücklich geprüfte und ausgewählte Aufgaben werden exportiert.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
        .onChange(of: current) { _, value in
            if value.revision != draft.revision || value.sourceHash != draft.sourceHash || value.sourceKey != draft.sourceKey || value.kind != draft.kind || value.evidence != draft.evidence || value.stale != draft.stale || value.locked != draft.locked || value.reviewed != draft.reviewed { draft = value }
        }
    }
}

struct MeetingTodoistControls: View {
    @Environment(RecorderModel.self) private var model
    let meetingID: UUID
    @State private var settings = MeetingTaskSettings()
    @State private var speakers: [(id: String, name: String)] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("# Projekt für dieses Meeting", selection: Binding(get: { settings.projectID }, set: { id in
                    settings.projectID = id; settings.projectName = model.todoistProjects.first { $0.id == id }?.name ?? ""
                })) {
                    Text("# Todoist-Eingang").tag("")
                    if !settings.projectID.isEmpty && !model.todoistProjects.contains(where: { $0.id == settings.projectID }) { Text("# " + settings.projectName).tag(settings.projectID) }
                    ForEach(model.todoistProjects) { Text("# " + $0.name).tag($0.id) }
                }
                Button("Projekte und Tags laden") { model.loadTodoistProjects() }.disabled(model.todoistBusy)
            }
            HStack {
                TextField("@ Tags für alle Aufgaben (Komma getrennt)", text: $settings.labels)
                Menu("@ Tag auswählen") {
                    if model.todoistLabels.isEmpty { Text("Zuerst Projekte und Tags laden") }
                    ForEach(model.todoistLabels) { label in
                        Button("@" + label.name) { settings.labels = TodoistLabels.format(Array(Set(TodoistLabels.parse(settings.labels) + [label.name])).sorted()) }
                    }
                }
                Menu("Ich bin im Meeting…") {
                    ForEach(speakers, id: \.id) { speaker in
                        Toggle(speaker.name + " (" + speaker.id + ")", isOn: Binding(get: { settings.ownSpeakerIDs?.contains(speaker.id) == true }, set: { value in
                            var ids = Set(settings.ownSpeakerIDs ?? []); if value { ids.insert(speaker.id) } else { ids.remove(speaker.id) }
                            settings.ownSpeakerIDs = ids.sorted()
                        }))
                    }
                    Button("Keine automatische Zuordnung") { settings.ownSpeakerIDs = nil }
                }
                Button("Für Meeting übernehmen") {
                    do { try model.taskInbox.configureMeeting(meetingID, settings: settings); model.taskInboxStatus = "Projekt, Tags und Sprecherzuordnung übernommen. Geänderte Aufgaben bitte erneut prüfen." }
                    catch { model.taskInboxStatus = error.localizedDescription }
                }
            }
            Text("Gilt für alle noch nicht exportierten Aufgaben dieses Meetings und für neu erkannte Aufgaben. Termine bleiben je Aufgabe erhalten. Bereits gesendete Aufgaben werden nicht verändert.").font(.caption).foregroundStyle(.secondary)
            if let own = settings.ownSpeakerIDs {
                Text("Meine Sprecher: " + (own.isEmpty ? "keine ausgewählt" : speakers.filter { own.contains($0.id) }.map(\.name).joined(separator: ", "))).font(.caption)
            }
        }.padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if let saved = model.taskInbox.data.meetingSettings[meetingID.uuidString] { settings = saved }
            else if let draft = model.taskInbox.data.drafts.first(where: { $0.meetingID == meetingID && !$0.locked }) {
                settings.projectID = draft.projectID; settings.projectName = draft.projectName; settings.labels = draft.labels
            }
            speakers = model.taskMeetingSpeakers(meetingID)
        }
        .onChange(of: model.taskInbox.data.drafts) { _, _ in speakers = model.taskMeetingSpeakers(meetingID) }
    }
}

struct OptionalTaskDateField: View {
    let title: String
    @Binding var value: String
    private var formatter: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f
    }
    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { !value.isEmpty }, set: { enabled in value = enabled ? formatter.string(from: Date()) : "" }))
            if !value.isEmpty {
                DatePicker(title, selection: Binding(get: { formatter.date(from: value) ?? Date() }, set: { value = formatter.string(from: $0) }), displayedComponents: [.date])
                    .labelsHidden().datePickerStyle(.field)
            }
        }
    }
}
