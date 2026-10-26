import SwiftUI

struct VocabularyPreferences: View {
    @Environment(RecorderModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Section("Namen, Marken und Fachbegriffe") {
            Text("Ein Begriff pro Zeile, z. B. Secjur, Amin oder Armin. Wichtige Begriffe zuerst. Beide Namen eintragen, wenn beide vorkommen können.").font(.caption)
            TextEditor(text: $model.transcriptionVocabulary)
                .font(.body).frame(minHeight: 100).border(.secondary.opacity(0.3))
                .onChange(of: model.transcriptionVocabulary) { _, value in
                    if value.count > TranscriptionVocabulary.maxCharacters { model.transcriptionVocabulary = String(value.prefix(TranscriptionVocabulary.maxCharacters)) }
                }
            Text("Erkennungshilfe für neue Live- und Offline-Transkriptionen, keine automatische Ersetzung oder Fehlergarantie. Maximal 2.000 Zeichen; im Modell zählen die ersten vollständigen Begriffe bis 200 Tokens. Vorhandene Texte bleiben unverändert.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct SummaryTemplatePreferences: View {
    @Environment(RecorderModel.self) private var model
    @State private var draft = ""
    @State private var status: String?
    var body: some View {
        Section("Markdown-Template") {
            TextEditor(text: $draft).font(.system(.body, design: .monospaced)).frame(minHeight: 140).border(.secondary.opacity(0.3))
            Text("Platzhalter: {{meeting_title}}, {{executive_summary}}, {{topics}}, {{action_items}}, {{next_steps}}. Zusammenfassung ist erforderlich; die anderen Abschnitte sind optional. Aufgaben bleiben unabhängig vom Layout in der Aufgaben-Inbox erhalten.").font(.caption)
            HStack {
                Button("Template speichern") {
                    do { try SummaryTemplate.validate(draft); model.summaryTemplate = draft; status = "Gespeichert. Gilt für neu beauftragte Zusammenfassungen." }
                    catch { status = error.localizedDescription }
                }
                Button("Standard einsetzen") { draft = SummaryTemplate.standard; status = nil }
            }
            Text("Leer speichern verwendet das bisherige Standardlayout. Markdown wird lokal formatiert; das Template führt keine Befehle aus.").font(.caption).foregroundStyle(.secondary)
            if let status { Text(status).font(.caption) }
        }.onAppear { draft = model.summaryTemplate }
    }
}
struct MicrophonePreferences: View {
    @Environment(RecorderModel.self) private var model
    @State private var devices: [MicrophoneDevices.Device] = []
    var body: some View {
        @Bindable var model = model
        Section("Mikrofon") {
            Picker("Eingabequelle", selection: $model.microphoneUID) {
                Text("Systemstandard").tag("")
                ForEach(devices) { device in Text(device.name).tag(device.id) }
                if !model.microphoneUID.isEmpty && !devices.contains(where: { $0.id == model.microphoneUID }) {
                    Text("Gewähltes Mikrofon nicht verfügbar").tag(model.microphoneUID)
                }
            }.disabled(model.state != .idle)
            Button("Quellen aktualisieren") { devices = MicrophoneDevices.inputs() }
            Text("Gilt ab der nächsten Aufnahme. Die beste Quelle hängt von Raum und Gerät ab; Recorder bewertet sie nicht automatisch. Eine feste Quelle muss angeschlossen sein, sonst startet die Aufnahme nicht.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { devices = MicrophoneDevices.inputs() }
    }
}
