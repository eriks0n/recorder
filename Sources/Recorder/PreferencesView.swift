import SwiftUI

/// The content of the dedicated **Preferences window**.
///
/// The window itself is an AppKit `NSWindow` hosting this view — see
/// `PreferencesWindowController` for why we don't use SwiftUI's `Settings` scene.
///   - **General**: silence auto-stop.
///   - **Recording**: what a recording may leave on disk.
///   - **Transcription**: on-device model, language, live transcription.
///   - **Speakers**: labelling, voice profiles, and the saved voice list.
///
/// Grouped `Form`s in a `TabView` give the standard macOS System-Settings look.
/// The `TabView` is given a single fixed size so the host window doesn't clip
/// the taller tab or leave the window resizing as you switch tabs.
struct PreferencesView: View {
    var body: some View {
        TabView {
            LocalProcessingPreferences()
                .tabItem { Label("Local", systemImage: "internaldrive") }
            GeneralPreferences()
                .tabItem { Label("General", systemImage: "gearshape") }

            RecordingPreferences()
                .tabItem { Label("Recording", systemImage: "waveform") }

            TranscriptionPreferences()
                .tabItem { Label("Transcription", systemImage: "text.bubble") }

            SpeakerPreferences()
                .tabItem { Label("Speakers", systemImage: "person.wave.2") }
        }
        .frame(width: 480, height: 620)
    }
}

// MARK: - General

private struct GeneralPreferences: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Stop automatically after silence", isOn: $model.silenceAutoStopEnabled)

                if model.silenceAutoStopEnabled {
                    Stepper(
                        value: Binding(
                            get: { Int((model.silenceTimeout / 60).rounded()) },
                            set: { model.silenceTimeout = TimeInterval(max(1, $0) * 60) }
                        ),
                        in: 1...60
                    ) {
                        Text("After \(Int((model.silenceTimeout / 60).rounded())) min of silence on both channels")
                            .monospacedDigit()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Silence threshold")
                            Spacer()
                            Text("\(Int(model.silenceThresholdDB)) dB")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.silenceThresholdDB, in: -80 ... -20, step: 1)
                        Text("A channel counts as silent below this level. Lower = more tolerant of quiet rooms.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Auto-stop")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Recording

private struct RecordingPreferences: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Audio handling", selection: $model.audioHandlingMode) {
                    ForEach(AudioHandlingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(model.audioHandlingMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.audioHandlingMode.producesNothing(
                    liveTranscriptionEnabled: model.liveTranscriptionEnabled
                ) {
                    Label(
                        "Transcript-only mode needs live transcription switched on, or nothing would be saved.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Audio handling")
            } footer: {
                Text("Transcript-only never writes audio to disk, not even temporarily, so a crash cannot leave a recording behind. The high-quality pass needs the audio file, so it is only available when audio is kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Transcription

private struct TranscriptionPreferences: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Model", selection: $model.whisperModel) {
                    ForEach(WhisperModelOption.catalog) { option in
                        Text("\(option.label) · \(option.detail)").tag(option.id)
                    }
                }
                engineStatus
            } header: {
                Text("On-device model")
            } footer: {
                Text("Runs fully on this Mac via WhisperKit (CoreML). Each model is downloaded once from Hugging Face into Application Support; switching later is instant. All listed models handle German and English.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: $model.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.options, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                Text("Auto-detect re-checks the language for every window, which handles meetings that mix languages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Language")
            }

            Section {
                Toggle("Stream the transcript live while recording", isOn: $model.liveTranscriptionEnabled)
                Text("Shows the transcript in the panel as it is spoken, with a copy button. Uses more CPU while recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Live transcription")
            }

        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var engineStatus: some View {
        switch model.live.engineState {
        case .downloading(let name, let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .controlSize(.small)
                Text("Downloading \(WhisperModelOption.label(for: name))… \(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loading(let name):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading \(WhisperModelOption.label(for: name))…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ready:
            if let message = model.live.loadFailureMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Model loaded and ready", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .notDownloaded:
            Label("Bitte Download im Reiter Local starten", systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unloaded:
            EmptyView()
        }
    }
}

// MARK: - Speakers

private struct SpeakerPreferences: View {
    @Environment(RecorderModel.self) private var model
    @State private var confirmingDeleteAll = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Quellenhinweise im Live-Transkript", isOn: $model.speakerLabelsEnabled)
                Text("Zeigt Mikrofon/Desktop im optionalen Live-Transkript. Stimmenanalyse und Wiedererkennung werden separat mit Speaker Fingerprinting eingeschaltet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Labels")
            }

            Section {
                Toggle("Speaker Fingerprinting", isOn: $model.voiceProfilesEnabled)
                if model.voiceProfilesEnabled && !ModelManager.ready("diar") {
                    Text("Das Stimmenmodell fehlt noch.").font(.caption)
                    Button("Stimmenmodell herunterladen") { model.downloadModels("diar") }
                        .disabled(model.modelDownloadRunning)
                    if !model.modelDownloadStatus.isEmpty { Text(model.modelDownloadStatus).font(.caption) }
                }
                Text("Ein: Stimmen lokal analysieren und bekannte Stimmen als Namensvorschläge anbieten. Aus: keine Stimmenanalyse, keine Wiedererkennung und keine neuen Stimmprofile; vorhandene Profile bleiben gespeichert und werden nicht geladen. Umbenennen bleibt für dieses Meeting möglich.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Speaker Fingerprinting")
            }

            Section {
                if !model.voiceProfilesEnabled || model.speakerStore.profiles.isEmpty {
                    Text("Noch keine Stimmen geladen. Bei eingeschaltetem Fingerprinting kannst du einen Sprecher ausdrücklich als Stimmprofil bestätigen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.speakerStore.profiles.filter { $0.scope == model.customerScope }) { profile in
                        HStack {
                            TextField("Name", text: Binding(get: { profile.name }, set: { value in try? model.speakerStore.renameProfile(profile.id, to: value) }))
                            Spacer()
                            Text("\(profile.centroids.count) sample\(profile.centroids.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                try? model.speakerStore.delete(profileID: profile.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete \(profile.name)'s voice profile")
                        }
                    }

                }
                if model.speakerStore.hasStoredVoiceData {
                    Button("Delete all voice data", role: .destructive) {
                        confirmingDeleteAll = true
                    }
                    .confirmationDialog(
                        "Delete every saved voiceprint?",
                        isPresented: $confirmingDeleteAll,
                        titleVisibility: .visible
                    ) {
                        Button("Delete all voice data", role: .destructive) {
                            model.deleteAllVoiceData()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes every profile and every stored voiceprint, including ones waiting to be named. Transcripts keep the names already written into them.")
                    }
                }

            } header: {
                Text("Saved voices")
            }
        }
        .formStyle(.grouped)
    }
}
