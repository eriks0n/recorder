import SwiftUI

struct LocalProcessingPreferences: View {
    @Environment(RecorderModel.self) private var model
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
            Section("Zusammenfassung") {
                Toggle("Nach dem Offline-Transkript automatisch erstellen", isOn: $model.autoSummary)
                Picker("Sprache", selection: $model.summaryLanguage) {
                    Text("Deutsch").tag("Deutsch"); Text("English").tag("English")
                }
                Text("MLX benötigt einen mit vollständigem Xcode und Metal gebauten Recorder (RECORDER_WITH_MLX=1). Dieser Modus lädt das LLM erst nach der Transkription.").font(.caption)
            }
            Section("Sprecherprofile") {
                Toggle("Namensvorschläge aktivieren (nach eigener Kalibrierung)", isOn: $model.matchingCalibrated)
                Text("Konservative Startschwellen sind noch nicht an deinen Aufnahmen kalibriert. Vorschläge werden nie automatisch bestätigt. Interne Kalenderpersonen benötigen eine passende Profil-E-Mail-Adresse.").font(.caption)
            }
        }.formStyle(.grouped)
    }
}
