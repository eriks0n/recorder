import SwiftUI

struct LocalProcessingPreferences: View {
    @Environment(RecorderModel.self) private var model
    @State private var confirmCleanup = false
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Lokale Modelle") {
                Button("Whisper-Modell herunterladen / laden") { model.downloadWhisper() }
                Button("Sprechertrennung herunterladen") { model.downloadModels("diar") }
                Button("Zusammenfassungsmodell herunterladen (ca. 2,5 GB)") { model.downloadModels("llm") }
                if model.modelDownloadRunning {
                    ProgressView().controlSize(.small)
                    Button("Download abbrechen") { model.cancelModelDownload() }
                }
                Text(model.modelDownloadStatus).font(.caption)
                Text("Downloads starten nur hier. Aufnahmen und Transkripte werden ausschließlich lokal verarbeitet. Fehlende Modelle lösen keinen Cloud-Fallback aus.").font(.caption)
            }
            Section("Aufnahmen") {
                Text(RecordingsLibrary.recordingsRoot()?.path ?? "").font(.caption).textSelection(.enabled)
                Button("Aufnahmeordner wählen…") { model.chooseRecordingFolder() }
                if model.synchronizedFolderWarning {
                    Label("Dieser Ordner könnte synchronisiert werden. Für ausschließlich lokale Daten bitte einen lokalen Ordner wählen.", systemImage: "exclamationmark.triangle")
                }
                TextField("Kundenbereich", text: $model.customerScope)
                if let proposal = model.customerScopeSuggestion {
                    Button("Kalendervorschlag übernehmen: \(proposal)") { model.customerScope = proposal }
                }
                Text("Vor der Aufnahme bestätigen. Ohne Zuordnung: default. Profile werden nur innerhalb dieses Bereichs verglichen.").font(.caption)
            }
            Section("Aufbewahrung") {
                Toggle("Audio direkt nach Transkription und Zusammenfassung löschen", isOn: $model.deleteAudioAfterProcessing)
                    .disabled(!MeetingSummaryService.isAvailable)
                Text("Erstellt automatisch auch die lokale Zusammenfassung. Audio wird erst entfernt, wenn Transkript und Zusammenfassung erfolgreich gespeichert sind. Bei Fehlern oder Abbruch bleibt Audio erhalten. Nach dem Löschen ist keine erneute Transkription aus Audio möglich.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Alte Aufnahmedateien automatisch löschen", isOn: $model.retentionEnabled)
                if model.retentionEnabled {
                    Stepper("Nach \(model.retentionDays) Tagen", value: $model.retentionDays, in: 1...3650)
                    Text("Erhalten bleiben die Text-Transkription und Zusammenfassung mit ihren Textdaten (Markdown und JSON). Alle anderen Dateien dieser Aufnahme werden unwiderruflich gelöscht. Ohne fertiges Transkript wird nichts gelöscht.")
                        .font(.caption)
                    Text("Prüfung beim App-Start und stündlich, solange Recorder geöffnet ist. Aktive Aufnahmen und laufende Verarbeitung werden übersprungen.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Jetzt bereinigen…") { confirmCleanup = true }
                        .disabled(model.retentionRunning || model.state != .idle || model.transcriptionState == .running || model.summaryRunning)
                        .confirmationDialog("Alte Aufnahmedateien jetzt endgültig löschen?", isPresented: $confirmCleanup) {
                            Button("Jetzt bereinigen", role: .destructive) { model.runRetentionCleanup() }
                            Button("Abbrechen", role: .cancel) {}
                        } message: {
                            Text("Bei Aufnahmen ab \(model.retentionDays) Tagen bleiben nur Transkript und Zusammenfassung. Audio und übrige Dateien werden endgültig gelöscht.")
                        }
                }
                if let status = model.retentionStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Zusammenfassung") {
                Toggle("Nach dem Offline-Transkript automatisch erstellen", isOn: Binding(
                    get: { model.automaticSummaryEnabled }, set: { model.autoSummary = $0 }))
                    .disabled(model.deleteAudioAfterProcessing)
                Picker("Sprache", selection: $model.summaryLanguage) {
                    Text("Deutsch").tag("Deutsch"); Text("English").tag("English")
                }
                Text(MeetingSummaryService.isAvailable
                     ? "Zusammenfassungen werden vollständig auf diesem Mac erstellt. Das Sprachmodell wird erst nach der Transkription geladen."
                     : "Zusammenfassungen sind in dieser App-Version nicht verfügbar. Bitte die vollständige Recorder-Version verwenden.")
                    .font(.caption)
            }

        }.formStyle(.grouped)
    }
}
