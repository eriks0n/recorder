import Foundation
import Observation
import AppKit
import os
import AVFoundation

/// Owns every component and wires their callbacks. The model is @MainActor;
/// audio-thread callbacks hop to main via DispatchQueue.main.async before touching state.
@MainActor
@Observable
final class RecorderModel {

    @ObservationIgnored private var appLaunchObserver: NSObjectProtocol?

    init() {
        // MenuBarExtra content is lazy. Initialize scheduled cleanup even when the panel is never opened.
        appLaunchObserver = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification,
                                                                   object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onAppear() }
        }
    }
    deinit {
        if let observer = appLaunchObserver { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Observable UI state

    var state: RecorderState = .idle
    var desktopLevel: Float = 0      // 0..1 meter (LEFT / desktop)
    var micLevel: Float = 0          // 0..1 meter (RIGHT / mic)
    var meetings: [Meeting] = []
    var currentSession: RecordingSession? = nil
    var elapsed: TimeInterval = 0
    var statusMessage: String? = nil

    /// On-device transcription engine (WhisperKit). Exposed so the panel can
    /// render the live transcript and engine status directly.
    let live = LocalTranscriptionEngine()

    // MARK: - Persisted preferences (mirrored to UserDefaults via Preferences)

    /// Auto-stop after this many seconds of two-channel silence.
    var silenceTimeout: TimeInterval = 300 {
        didSet { Preferences.silenceTimeout = silenceTimeout }
    }
    /// dBFS below which a channel is considered silent.
    var silenceThresholdDB: Float = -50 {
        didSet { Preferences.silenceThresholdDB = silenceThresholdDB }
    }
    /// Whether silence auto-stop runs at all.
    var silenceAutoStopEnabled: Bool = true {
        didSet { Preferences.silenceAutoStop = silenceAutoStopEnabled }
    }
    /// What this recording may leave on disk.
    var audioHandlingMode: AudioHandlingMode = .default {
        didSet { Preferences.audioHandlingMode = audioHandlingMode }
    }
    /// Selected on-device Whisper model. Changing it loads (and downloads,
    /// when missing) the new model immediately, even mid-recording. When the
    /// switch fails, the engine keeps the previous model and the selection is
    /// rolled back to match it.
    var whisperModel: String = WhisperModelOption.defaultModelID {
        didSet {
            Preferences.whisperModel = whisperModel
            guard oldValue != whisperModel else { return }
            let name = whisperModel
            Task { [weak self] in
                guard let self else { return }
                await self.live.loadModel(name, downloadIfNeeded: false)
                if self.live.loadFailureMessage != nil,
                   let loaded = self.live.loadedModelName,
                   self.whisperModel == name, loaded != name {
                    self.whisperModel = loaded
                    self.statusMessage = self.live.loadFailureMessage
                }
            }
        }
    }
    /// Transcription language: ISO code or "auto".
    var transcriptionLanguage: String = "auto" {
        didSet {
            Preferences.language = transcriptionLanguage
            live.language = transcriptionLanguage == "auto" ? nil : transcriptionLanguage
        }
    }
    /// Whether the transcript streams into the panel while recording.
    var liveTranscriptionEnabled: Bool = true {
        didSet { Preferences.liveTranscription = liveTranscriptionEnabled }
    }
    /// Whether transcripts carry speaker labels (live: You/Them by channel;
    /// offline: Speaker N via on-device diarization).
    var speakerLabelsEnabled: Bool = true {
        didSet {
            Preferences.speakerLabels = speakerLabelsEnabled
            live.labelSpeakers = speakerLabelsEnabled
        }
    }
    /// Whether voice profiles are matched and enrolled. Off by default.
    var voiceProfilesEnabled: Bool = false {
        didSet {
            Preferences.voiceProfiles = voiceProfilesEnabled
            live.fingerprinting.setEnabled(voiceProfilesEnabled)
            if voiceProfilesEnabled { speakerStore.reload() }
            else {
                speakerStore.suspend(); live.discardSpeakerModels()
                lastDocument?.proposedNames = nil; lastDocument?.speakerCentroidsID = nil
            }
        }
    }

    /// Saved voiceprints. Observed, so the Speakers pane updates as profiles change.
    let speakerStore = SpeakerProfileStore(loadOnInit: false)

    /// The document behind the transcript currently shown, kept so a rename can
    /// re-render `transcript.md` from its source rather than patching the markdown.
    private(set) var lastDocument: TranscriptDocument?

    // Transcription (post-save).
    var transcriptionState: TranscriptionState = .idle
    var lastTranscriptText: String? = nil
    var lastTranscriptURL: URL? = nil

    /// The most recent recordings on disk (loaded at launch + after changes).
    var recentRecordings: [RecordingEntry] = []

    var recordingNameDraft = ""
    var retentionEnabled = false { didSet { Preferences.retentionEnabled = retentionEnabled } }
    var retentionDays = 30 { didSet { Preferences.retentionDays = retentionDays } }
    var retentionRunning = false
    var retentionStatus: String?
    @ObservationIgnored private var retentionTimer: Timer?
    @ObservationIgnored private var pendingSaveFolders: Set<URL> = []

    var customerScope = "default"
    var summaryStatus: String?
    var summaryRunning = false
    var deleteAudioAfterProcessing = false { didSet { Preferences.deleteAudioAfterProcessing = deleteAudioAfterProcessing } }
    var automaticSummaryEnabled: Bool { autoSummary || deleteAudioAfterProcessing }
    var autoSummary = false { didSet { Preferences.autoSummary = autoSummary } }
    var summaryLanguage = "Deutsch" { didSet { Preferences.summaryLanguage = summaryLanguage } }
    var modelDownloadStatus = ""
    var modelDownloadRunning = false
    var recordingPath = "" { didSet { Preferences.recordingPath = recordingPath } }
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var processingID = UUID()
    @ObservationIgnored private var recordingGeneration = UUID()
    @ObservationIgnored private var referencePlayer: AVAudioPlayer?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    // MARK: - Heavy / audio objects (not observation-tracked)

    @ObservationIgnored private static let log = Logger(subsystem: "com.tobi.Recorder", category: "RecorderModel")

    @ObservationIgnored private let tap = SystemAudioTap()
    @ObservationIgnored private let mic = MicCapture()
    @ObservationIgnored private let calendar = CalendarAccess()
    @ObservationIgnored private let notifications = NotificationManager()
    @ObservationIgnored private var silenceMonitor: SilenceMonitor?

    @ObservationIgnored private var elapsedTimer: Timer?
    @ObservationIgnored private var recordingStartedAt: Date?

    /// The meeting (if any) the current recording is attached to — kept so its
    /// title + attendees are available as transcript context at save time.
    @ObservationIgnored private var activeMeeting: Meeting?

    /// The mode the recording in progress actually started with, which can differ from
    /// `audioHandlingMode` after a mid-recording downgrade.
    @ObservationIgnored private var activeMode: AudioHandlingMode = .default

    /// Everything needed to (re)run a transcription, captured at save time.
    private struct PendingTranscription {
        let audioURL: URL?
        let folderURL: URL
        let meetingTitle: String?
        let attendees: [String]
        let startedAt: Date
    }
    @ObservationIgnored private var lastTranscription: PendingTranscription?
    let processingQueue = ProcessingQueue()
    @ObservationIgnored private var activeProcessingJob: UUID?
    @ObservationIgnored private var queueWorker: Task<Void, Never>?
    var queueStatus: String?


    // MARK: - Lifecycle

    @ObservationIgnored private var initialized = false

    func onAppear() {
        guard !initialized else { return }
        initialized = true
        // Load persisted preferences first so the UI reflects them immediately.
        loadPreferences()

        // Load prior recordings from disk so they survive restarts.
        refreshRecordings()
        startRetentionChecks()
        pumpProcessingQueue()

        // Biometric data should not outlive its purpose: drop voiceprints nobody named.
        if voiceProfilesEnabled { speakerStore.prunePending() }

        // Request permissions concurrently, then load meetings.
        Task { @MainActor in
            _ = await MicCapture.requestAccess()
        }
        Task { @MainActor in
            _ = await calendar.requestAccess()
            refreshMeetings()
        }
        Task { @MainActor in
            await notifications.requestAuthorization()
        }

        // Refetch meetings on calendar changes.
        calendar.onChange = { [weak self] in
            // onChange is delivered on main (CalendarAccess is @MainActor).
            self?.refreshMeetings()
        }

        // A user tapping "Stop Recording" in the meeting-end notification stops + saves.
        notifications.onStopRequested = { [weak self] in
            guard let self else { return }
            if self.state != .idle {
                self.saveAndStop()
            }
        }

        configureCaptures()
    }

    /// Wire the capture callbacks and load the selected model. Split out of `onAppear`
    /// so it can run without the permission and notification setup, which needs a real
    /// app bundle and therefore cannot run under the test runner.
    func configureCaptures() {
        // Surface fatal capture errors to the UI.
        tap.onFatalError = { [weak self] error in
            DispatchQueue.main.async {
                self?.statusMessage = "Desktop audio error: \(error.localizedDescription)"
            }
        }
        mic.onFatalError = { [weak self] error in
            DispatchQueue.main.async {
                self?.statusMessage = "Mic error: \(error.localizedDescription)"
            }
        }

        // Feed both captures into the live-transcription inbox. The inbox is a
        // no-op outside an active session, so the hooks stay wired permanently.
        let inbox = live.inbox
        tap.onSamples = { samples, count, rate in
            inbox.ingest(.desktop, samples, count: count, rate: rate)
        }
        mic.onSamples = { samples, count, rate in
            inbox.ingest(.mic, samples, count: count, rate: rate)
        }

        // Load the selected model into memory if it is already on disk; a
        // missing model downloads on first use instead of at launch.
        let name = whisperModel
        Task { [weak self] in
            await self?.live.loadModel(name, downloadIfNeeded: false)
        }
    }

    /// Pull persisted preferences into the observable properties. The `didSet`
    /// write-backs are idempotent (same value in → same value out).
    private func loadPreferences() {
        silenceTimeout = Preferences.silenceTimeout
        silenceThresholdDB = Preferences.silenceThresholdDB
        silenceAutoStopEnabled = Preferences.silenceAutoStop
        audioHandlingMode = Preferences.audioHandlingMode
        whisperModel = Preferences.whisperModel
        transcriptionLanguage = Preferences.language
        liveTranscriptionEnabled = Preferences.liveTranscription
        speakerLabelsEnabled = Preferences.speakerLabels
        voiceProfilesEnabled = Preferences.voiceProfiles
        recordingPath = Preferences.recordingPath
        deleteAudioAfterProcessing = Preferences.deleteAudioAfterProcessing
        autoSummary = Preferences.autoSummary
        summaryLanguage = Preferences.summaryLanguage
        retentionDays = Preferences.retentionDays
        retentionEnabled = Preferences.retentionEnabled
    }

    // MARK: - Recording control

    func startRecording(meeting: Meeting?) {
        guard state == .idle else { return }
        guard !retentionRunning else { statusMessage = "Dateien werden gerade bereinigt. Bitte kurz warten."; return }

        cancelProcessing(requeue: true)
        recordingGeneration = UUID()
        lastDocument = nil
        let mode = audioHandlingMode
        guard !mode.producesNothing(liveTranscriptionEnabled: liveTranscriptionEnabled) else {
            statusMessage = "Transcript-only mode needs live transcription switched on, otherwise nothing would be saved."
            return
        }

        let now = Date()
        let meetingTitle = MeetingNaming.clean(recordingNameDraft) ?? meeting?.title
        let session: RecordingSession
        do {
            session = try RecordingSession.create(now: now, meetingTitle: meetingTitle, mode: mode)
        } catch {
            statusMessage = "Could not create recording folder: \(error.localizedDescription)"
            return
        }
        currentSession = session
        activeMeeting = meeting
        activeMode = mode
        do {
            let metadata = MeetingRecord(scope: customerScope.isEmpty ? "default" : customerScope, startedAt: now,
                                         title: meetingTitle, attendees: meeting?.attendees ?? [],
                                         attendeeEmails: meeting?.attendeeEmails ?? [], hasCalendarEvent: meeting != nil)
            try PrivateStorage.save(metadata, to: session.folderURL.appendingPathComponent("meeting.json"))
        } catch { currentSession = nil; activeMeeting = nil; statusMessage = error.localizedDescription; return }
        live.live.maxWindowSamples = LiveTranscriber.windowCap(for: mode)

        // Clear any previous recording's transcription UI.
        transcriptionState = .idle
        lastTranscriptText = nil
        lastTranscriptURL = nil
        lastTranscription = nil

        // Silence monitor (auto-stop after prolonged silence on both channels).
        // Only armed when the user has auto-stop enabled.
        if silenceAutoStopEnabled {
            silenceMonitor = SilenceMonitor(
                thresholdDB: silenceThresholdDB,
                timeout: silenceTimeout,
                onTimeout: { [weak self] in
                    // onTimeout is invoked on MAIN per contract.
                    self?.saveAndStop()
                }
            )
        } else {
            silenceMonitor = nil
        }

        // Wire level callbacks (called on audio threads -> hop to main).
        tap.onLevelDB = { [weak self] db in
            DispatchQueue.main.async {
                guard let self else { return }
                self.desktopLevel = meterLevel(fromDB: db)
                self.silenceMonitor?.noteLevel(db)
            }
        }
        mic.onLevelDB = { [weak self] db in
            DispatchQueue.main.async {
                guard let self else { return }
                self.micLevel = meterLevel(fromDB: db)
                self.silenceMonitor?.noteLevel(db)
            }
        }

        // Start both captures.
        do {
            try tap.start(writingTo: session.desktopURL)
            try mic.start(writingTo: session.micURL)
        } catch {
            statusMessage = "Could not start capture: \(error.localizedDescription)"
            _ = tap.stop()
            _ = mic.stop()
            currentSession = nil
            silenceMonitor = nil
            return
        }

        silenceMonitor?.start()

        if liveTranscriptionEnabled {
            live.beginSession()
            let name = whisperModel
            Task { [weak self] in
                await self?.live.loadModel(name, downloadIfNeeded: false)
            }
        }

        // Schedule a meeting-end alert when recording a known meeting.
        if let meeting {
            notifications.scheduleMeetingEndAlert(at: meeting.end, meetingTitle: meeting.title)
        }

        state = .recording
        recordingNameDraft = ""
        statusMessage = nil
        startElapsedTimer(from: now)
    }

    /// Change the audio-handling mode for the recording in progress. Downgrading to
    /// transcript-only closes and deletes the partial audio. Upgrading is refused,
    /// because the earlier audio was never written and a half-recording would
    /// misrepresent itself. Returns whether the change applied to this recording.
    @discardableResult
    func changeAudioHandling(to mode: AudioHandlingMode) -> Bool {
        guard state != .idle, let session = currentSession else {
            audioHandlingMode = mode
            return true
        }

        switch AudioHandlingChange.decide(
            from: activeMode,
            to: mode,
            liveTranscriptionEnabled: liveTranscriptionEnabled
        ) {
        case .refuseNothingProduced:
            statusMessage = "Transcript-only mode needs live transcription switched on."
            return false
        case .refuseUpgrade:
            statusMessage = "Cannot start keeping audio mid-recording: the earlier audio was never saved."
            return false
        case .apply:
            break
        }

        audioHandlingMode = mode

        if AudioHandlingChange.deletesPartialAudio(from: activeMode, to: mode) {
            tap.stopWriting()
            mic.stopWriting()
            for url in [session.desktopURL, session.micURL, session.outputURL].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: url)
            }
            statusMessage = "Switched to transcript only, audio so far deleted"
        }

        activeMode = mode
        live.live.maxWindowSamples = LiveTranscriber.windowCap(for: mode)
        return true
    }

    func togglePause() {
        switch state {
        case .recording:
            tap.setPaused(true)
            mic.setPaused(true)
            silenceMonitor?.stop()
            state = .paused
        case .paused:
            tap.setPaused(false)
            mic.setPaused(false)
            silenceMonitor?.start()
            state = .recording
        case .idle:
            break
        }
    }

    func saveAndStop() {
        guard state != .idle, let session = currentSession else {
            resetToIdle()
            return
        }

        let desktopResult = tap.stop()
        let micResult = mic.stop()

        cancelTimersAndAlerts()
        state = .idle

        let mode = activeMode
        let recordingGeneration = self.recordingGeneration
        let folderURL = session.folderURL
        pendingSaveFolders.insert(folderURL)
        let startedAt = session.startedAt
        let meetingTitle = session.meetingTitle ?? activeMeeting?.title
        let attendees = activeMeeting?.attendees ?? []

        // Finalize the live transcript (transcribes the remaining tail) in
        // parallel with the mix. Only awaited when a transcript will actually
        // be written, so an off toggle or a slow model never delays the save.
        let liveTask: Task<LiveTranscriber.LiveSessionResult, Never>? = live.isSessionActive
            ? Task { [live] in await live.endSession() }
            : nil

        // No audio was ever written, so there is nothing to mix and nothing to polish.
        guard mode.retainsAudio,
              let outputURL = session.outputURL,
              let desktopURL = session.desktopURL,
              let micURL = session.micURL else {
            let pending = PendingTranscription(
                audioURL: nil,
                folderURL: folderURL,
                meetingTitle: meetingTitle,
                attendees: attendees,
                startedAt: startedAt
            )
            lastTranscription = pending
            transcriptionState = .running
            statusMessage = "Finishing the transcript…"
            Task { [weak self] in
                guard let self else { return }
                defer { self.pendingSaveFolders.remove(folderURL); self.pumpProcessingQueue() }
                guard let liveResult = await liveTask?.value, !liveResult.isEmpty else {
                    self.transcriptionState = .failed("Nothing was transcribed, and no audio was kept.")
                    self.statusMessage = "Nothing to save"
                    self.refreshRecordings()
                    return
                }
                self.writeLiveTranscript(liveResult.lines, pending: pending, keepStatus: true)
                self.statusMessage = "Transcript saved, no audio kept"
            }
            currentSession = nil
            activeMeeting = nil
            silenceMonitor = nil
            return
        }

        statusMessage = "Mixing…"
        let pending = PendingTranscription(
            audioURL: outputURL,
            folderURL: folderURL,
            meetingTitle: meetingTitle,
            attendees: attendees,
            startedAt: startedAt
        )
        let needsOfflineTranscription = mode.requiresOfflineTranscription(deleteAudioAfterProcessing: deleteAudioAfterProcessing)
        let wantsTranscript = liveTranscriptionEnabled || needsOfflineTranscription
        if wantsTranscript {
            transcriptionState = .running
        }

        // Mix off the main actor; keep raw CAFs regardless of outcome.
        Task.detached(priority: .utility) { [weak self] in
            defer { Task { @MainActor [weak self] in self?.pendingSaveFolders.remove(folderURL); self?.pumpProcessingQueue() } }
            var mixError: Error? = nil
            do {
                try StereoMixer.mix(
                    desktopURL: desktopURL,
                    micURL: micURL,
                    desktopResult: desktopResult,
                    micResult: micResult,
                    outputURL: outputURL
                )
            } catch {
                mixError = error
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.refreshRecordings()
                guard self.state == .idle, self.recordingGeneration == recordingGeneration else { return }
                self.lastTranscription = pending
                self.statusMessage = mixError == nil
                    ? "Saved \(outputURL.lastPathComponent)"
                    : "Mix failed (raw files kept): \(mixError!.localizedDescription)"
                self.refreshRecordings()
                if !wantsTranscript {
                    self.transcriptionState = .idle
                    if mixError == nil {
                        self.statusMessage = "Saved \(outputURL.lastPathComponent) · transcription off"
                    }
                }
            }
            guard wantsTranscript else { return }

            let liveResult = await liveTask?.value

            await MainActor.run { [weak self] in
                guard let self else { return }
                if mixError == nil, needsOfflineTranscription {
                    self.startTranscription(pending)
                } else if let liveResult, !liveResult.isEmpty, liveResult.complete {
                    self.writeLiveTranscript(liveResult.lines, pending: pending, keepStatus: mixError != nil)
                } else if let liveResult, !liveResult.isEmpty {
                    self.writeLiveTranscript(liveResult.lines, pending: pending, keepStatus: true)
                } else {
                    self.transcriptionState = .failed(
                        "No live transcript, and the audio mix failed, so there is nothing to transcribe."
                    )
                }
            }
        }

        currentSession = nil
        activeMeeting = nil
        silenceMonitor = nil
    }

    func trashAndStop() {
        guard state != .idle else {
            resetToIdle()
            return
        }

        _ = tap.stop()
        _ = mic.stop()
        live.cancelSession()

        cancelTimersAndAlerts()

        if let session = currentSession {
            try? FileManager.default.removeItem(at: session.folderURL)
        }

        state = .idle
        currentSession = nil
        activeMeeting = nil
        silenceMonitor = nil
        statusMessage = "Discarded"
        transcriptionState = .idle
        lastTranscriptText = nil
        lastTranscriptURL = nil
        lastTranscription = nil
        refreshRecordings()
        pumpProcessingQueue()
    }

    func refreshMeetings() {
        let now = Date()
        meetings = calendar.meetingsAroundNow(now)
    }

    /// The meeting currently in progress, if any. All-day events are already
    /// excluded from `meetings`, so this only matches timed meetings. Used as the
    /// default target for the main Record button so recording while you're in a
    /// meeting auto-tags it (folder name + end alert + transcript context).
    var currentMeeting: Meeting? {
        let now = Date()
        return meetings.first(where: { $0.isInProgress(now) })
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func startElapsedTimer(from start: Date) {
        recordingStartedAt = start
        elapsed = 0
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let started = self.recordingStartedAt else { return }
                if self.state == .recording {
                    self.elapsed = Date().timeIntervalSince(started)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func cancelTimersAndAlerts() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordingStartedAt = nil
        silenceMonitor?.stop()
        notifications.cancelMeetingEndAlert()
    }

    private func resetToIdle() {
        cancelTimersAndAlerts()
        state = .idle
        currentSession = nil
        activeMeeting = nil
        silenceMonitor = nil
        elapsed = 0
    }

    // MARK: - Transcription

    /// The speakers of the transcript currently shown, in order of first speech.
    var currentSpeakers: [(id: String, name: String)] {
        guard let document = lastDocument else { return [] }
        return document.speakerIDs.map { ($0, document.displayName(for: $0)) }
    }

    /// Rename one speaker: re-render the transcript from its source, and when voice
    /// profiles are on, teach the store what that person sounds like.
    ///
    /// The markdown is never patched. `transcript.json` is the source of truth, so a
    /// rename re-renders it and stays idempotent across repeated applications.
    func renameSpeaker(id: String, to name: String) {
        guard !retentionRunning else { return }
        cancelProcessing()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let document = lastDocument,
              let pending = lastTranscription else { return }

        writeTranscript(
            document: document.renamingSpeaker(id, to: trimmed),
            pending: pending,
            keepStatus: true
        )
    }

    /// Re-run the last transcription (offline, from the saved audio).
    func retryTranscription() {
        guard let pending = lastTranscription else { return }
        startTranscription(pending)
    }

    /// Transcribe a saved recording's audio with the local model.
    private func startTranscription(_ pending: PendingTranscription) {
        enqueueProcessing(pending, kind: .transcription)
    }
    private func enqueueProcessing(_ pending: PendingTranscription, kind: ProcessingJobKind) {
        let job = ProcessingJob(kind: kind, folder: pending.folderURL, audio: pending.audioURL,
                                title: pending.meetingTitle, attendees: pending.attendees, startedAt: pending.startedAt,
                                whisperModel: whisperModel, language: transcriptionLanguage, summaryLanguage: summaryLanguage,
                                summarize: automaticSummaryEnabled, deleteAudio: deleteAudioAfterProcessing)
        do { try processingQueue.enqueue(job); queueStatus = "Zur Verarbeitung vorgemerkt"; pumpProcessingQueue() }
        catch { queueStatus = error.localizedDescription }
    }
    func retryProcessingJob(_ id: UUID) {
        do { try processingQueue.update(id, state: .waiting); pumpProcessingQueue() }
        catch { queueStatus = error.localizedDescription }
    }
    func pumpProcessingQueue() {
        guard initialized, state == .idle, !retentionRunning, pendingSaveFolders.isEmpty,
              queueWorker == nil, let job = processingQueue.next else { return }
        do { try processingQueue.update(job.id, state: .running) }
        catch { queueStatus = error.localizedDescription; return }
        let operation = UUID(); processingID = operation; activeProcessingJob = job.id
        transcriptionState = .running
        queueStatus = "Verarbeite: " + (job.title ?? "Aufnahme")
        queueWorker = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.processingID == operation {
                    self.activeProcessingJob = nil
                    if self.transcriptionState == .running { self.transcriptionState = .idle }
                    self.summaryRunning = false
                }
                self.queueWorker = nil
                self.live.language = self.transcriptionLanguage == "auto" ? nil : self.transcriptionLanguage
                self.refreshRecordings()
                self.pumpProcessingQueue()
            }
            do {
                try RecordingRetention.requireSafeFolder(job.folder)
                if job.kind == .transcription { try await self.runQueuedTranscription(job, operation: operation) }
                else { try await self.generateQueuedSummary(job, operation: operation) }
                try Task.checkCancellation()
                try self.processingQueue.update(job.id, state: .done)
                self.queueStatus = "Verarbeitung abgeschlossen"
            } catch is CancellationError {
                // The interruption path already persisted waiting/failed before cancelling.
            } catch {
                guard self.processingID == operation, !Task.isCancelled else { return }
                do { try self.processingQueue.update(job.id, state: .failed, error: RecorderModel.describeTranscriptionError(error)) }
                catch { self.queueStatus = error.localizedDescription }
                if self.processingID == operation { self.queueStatus = error.localizedDescription; self.transcriptionState = .failed(error.localizedDescription) }
            }
        }
    }
    private func presentProcessed(_ document: TranscriptDocument, pending: PendingTranscription, markdown: URL) {
        guard state == .idle, lastTranscription == nil || lastTranscription?.folderURL == pending.folderURL else { return }
        lastTranscription = pending; lastDocument = document
        lastTranscriptText = document.renderMarkdown(); lastTranscriptURL = markdown
        transcriptionState = .done(markdown)
    }
    private func runQueuedTranscription(_ job: ProcessingJob, operation: UUID) async throws {
        let pending = PendingTranscription(audioURL: job.audio, folderURL: job.folder, meetingTitle: job.title, attendees: job.attendees, startedAt: job.startedAt)
        let fingerprintToken = live.fingerprinting.token
        guard let audioURL = job.audio else { throw LocalError.message("Kein Audio für erneute Transkription vorhanden.") }
        try RecordingRetention.requireContainedRegularFile(audioURL, in: job.folder)
                try Task.checkCancellation()
                await self.live.loadModel(job.whisperModel, downloadIfNeeded: false)
                try Task.checkCancellation()
                self.live.language = job.language == "auto" ? nil : job.language
                let offline = try await self.live.transcribeFile(audioURL)
                try Task.checkCancellation()
                guard self.processingID == operation else { throw CancellationError() }
                guard !offline.lines.isEmpty else {
                    throw LocalError.message("Die Aufnahme enthält keinen erkennbaren Text.")
                }
                let names = offline.speakerNames
                let record = (try? PrivateStorage.read(MeetingRecord.self, from: pending.folderURL.appendingPathComponent("meeting.json"))) ?? MeetingRecord(scope: "default", startedAt: pending.startedAt, title: pending.meetingTitle)
                var proposals: [String: String] = [:]
                var centroidsID: String?

                if self.voiceProfilesEnabled, self.live.fingerprinting.accepts(fingerprintToken), !offline.clusters.isEmpty {
                    let assignments = SpeakerNaming.resolve(
                        clusters: offline.clusters,
                        defaultNames: offline.speakerNames,
                        profiles: SpeakerNaming.eligible(self.speakerStore.profiles, meeting: record)
                    )
                    for (id, assignment) in assignments {
                        if assignment.profileID != nil { proposals[id] = assignment.name }
                    }

                    // `appliedProfileID` stays nil even where a profile matched: an
                    // automatic match names a speaker but never writes a voiceprint, so
                    // the database only ever grows from a correction the user saw. It also
                    // keeps confirming a correct guess an enrollment rather than a no-op.
                    let voiceprints = PendingSpeakers(
                        id: UUID().uuidString,
                        createdAt: Date(),
                        clusters: offline.clusters.reduce(into: [:]) { result, entry in
                            result[entry.key] = PendingSpeakers.Cluster(
                                vector: entry.value.centroid,
                                speechSeconds: entry.value.speechSeconds,
                                appliedProfileID: nil
                            )
                        }
                    )
                    do {
                        try self.speakerStore.writePending(voiceprints)
                        centroidsID = voiceprints.id
                    } catch {
                        Self.log.error("could not store voiceprints: \(error.localizedDescription)")
                    }
                }

                var document = TranscriptDocument(
                    meetingTitle: pending.meetingTitle,
                    attendees: pending.attendees,
                    startedAt: pending.startedAt,
                    audioName: audioURL.lastPathComponent,
                    model: self.live.loadedModelName ?? self.live.modelName,
                    isPolished: true,
                    lines: offline.lines.map {
                        TranscriptDocument.StoredLine(time: $0.time, text: $0.text, speakerID: $0.speaker, endTime: $0.endTime, channel: $0.channel, overlap: $0.overlap)
                    },
                    speakerNames: names,
                    speakerCentroidsID: centroidsID
                )
                document.schemaVersion = 1; document.meetingRecord = record; document.proposedNames = proposals
                document.processingWarnings = offline.warnings
                let markdown = try TranscriptRepository.publish(document, folder: pending.folderURL)
                document = try TranscriptDocument.load(from: pending.folderURL.appendingPathComponent("transcript.json"))
                self.presentProcessed(document, pending: pending, markdown: markdown)
                self.live.releaseModels()
                if job.summarize {
                    try self.processingQueue.update(job.id, state: .running, kind: .summary)
                    try await self.generateQueuedSummary(job, operation: operation)
                }
    }

    /// Compose the transcript document, write it to transcript.md, and update
    /// the UI state. `keepStatus` leaves the status line untouched (used when a
    /// mix failure message must stay visible).
    /// Wrap live transcript lines in a document and write both files.
    private func writeLiveTranscript(
        _ lines: [TranscriptLine],
        pending: PendingTranscription,
        keepStatus: Bool
    ) {
        var document = TranscriptDocument(live: lines, meetingTitle: pending.meetingTitle, attendees: pending.attendees,
                                          startedAt: pending.startedAt, audioName: pending.audioURL?.lastPathComponent,
                                          model: live.loadedModelName ?? live.modelName)
        do {
            document.schemaVersion = 1
            document.meetingRecord = try PrivateStorage.read(MeetingRecord.self, from: pending.folderURL.appendingPathComponent("meeting.json"))
            let markdown = try TranscriptRepository.publish(document, folder: pending.folderURL)
            document = try TranscriptDocument.load(from: pending.folderURL.appendingPathComponent("transcript.json"))
            presentProcessed(document, pending: pending, markdown: markdown)
            if automaticSummaryEnabled { enqueueProcessing(pending, kind: .summary) }
            refreshRecordings()
        } catch { queueStatus = error.localizedDescription }
    }

    /// Write `transcript.json` and render `transcript.md` from it. The sidecar is written
    /// first so a crash between the two never leaves the markdown ahead of its source.
    private func writeTranscript(
        document: TranscriptDocument,
        pending: PendingTranscription,
        keepStatus: Bool
    ) {
        var document = document
        document.schemaVersion = 1
        if document.meetingRecord == nil {
            document.meetingRecord = (try? PrivateStorage.read(MeetingRecord.self, from: pending.folderURL.appendingPathComponent("meeting.json"))) ?? MeetingRecord(startedAt: pending.startedAt, title: pending.meetingTitle)
        }
        let markdown = document.renderMarkdown()
        let markdownURL: URL
        do {
            markdownURL = try TranscriptRepository.publish(document, folder: pending.folderURL)
        } catch {
            transcriptionState = .failed("Could not write the transcript: \(error.localizedDescription)")
            return
        }
        lastTranscriptText = markdown
        lastTranscriptURL = markdownURL
        // Normalize dates to the persisted representation before hashing for summaries.
        lastDocument = (try? TranscriptDocument.load(from: markdownURL.deletingLastPathComponent().appendingPathComponent("transcript.json"))) ?? document
        transcriptionState = .done(markdownURL)
        if !keepStatus {
            statusMessage = document.processingWarnings?.isEmpty == false
                ? "Transkript gespeichert · mit Hinweis zur Sprechertrennung"
                : "Transcript saved (transcript.md)"
        }
        refreshRecordings()
    }

    private func startRetentionChecks() {
        retentionTimer?.invalidate()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.runRetentionCleanup() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer
        runRetentionCleanup()
    }
    func runRetentionCleanup() {
        guard retentionEnabled, !retentionRunning else { return }
        guard state == .idle, transcriptionState != .running, !summaryRunning,
              pendingSaveFolders.isEmpty, processingQueue.unfinished.isEmpty, referencePlayer?.isPlaying != true else {
            retentionStatus = "Bereinigung wird beim nächsten Prüflauf nach der Aufnahme oder Verarbeitung nachgeholt."
            return
        }
        let roots = RecordingsLibrary.roots(), days = retentionDays
        retentionRunning = true
        retentionStatus = "Alte Aufnahmedateien werden bereinigt…"
        Task {
            let report = await Task.detached(priority: .utility) {
                RecordingRetention.run(roots: roots, afterDays: days)
            }.value
            retentionRunning = false
            retentionStatus = "\(report.cleaned) bereinigt · \(report.skipped) übersprungen" + (report.failed > 0 ? " · \(report.failed) wegen Dateifehlern unverändert" : "")
            refreshRecordings()
            if let pending = lastTranscription {
                let entries = RecordingsLibrary.entries(roots: roots)
                if let entry = entries.first(where: { $0.folderURL.standardizedFileURL.path == pending.folderURL.standardizedFileURL.path }) {
                    lastTranscription = PendingTranscription(audioURL: entry.audioURL, folderURL: entry.folderURL,
                                                            meetingTitle: entry.title, attendees: pending.attendees, startedAt: pending.startedAt)
                    if lastDocument != nil, let url = entry.transcriptURL {
                        lastDocument = try? TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
                        lastTranscriptURL = url
                        lastTranscriptText = lastDocument?.renderMarkdown() ?? (try? String(contentsOf: url, encoding: .utf8))
                        transcriptionState = .done(url)
                    }
                }
            }
        }
    }
    @discardableResult
    func renameRecording(_ entry: RecordingEntry, to name: String) -> Bool {
        guard state == .idle, transcriptionState != .running, !summaryRunning, !retentionRunning,
              !pendingSaveFolders.contains(entry.folderURL) else {
            statusMessage = "Bitte die laufende Verarbeitung zuerst beenden."; return false
        }
        do {
            try MeetingNaming.rename(entry, to: name)
            if let pending = lastTranscription, pending.folderURL.standardizedFileURL.path == entry.folderURL.standardizedFileURL.path {
                lastTranscription = PendingTranscription(audioURL: pending.audioURL, folderURL: entry.folderURL,
                                                        meetingTitle: MeetingNaming.clean(name), attendees: pending.attendees, startedAt: pending.startedAt)
                if lastDocument != nil {
                    lastDocument = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
                    lastTranscriptText = lastDocument?.renderMarkdown()
                    lastTranscriptURL = (try TranscriptRepository.currentJSON(in: entry.folderURL))?.deletingLastPathComponent().appendingPathComponent("transcript.md") ?? entry.transcriptURL
                    if let url = lastTranscriptURL { transcriptionState = .done(url) }
                }
            }
            refreshRecordings(); statusMessage = "Meetingname gespeichert"; return true
        } catch { statusMessage = error.localizedDescription; return false }
    }

    func cancelProcessing(requeue: Bool = false) {
        if let id = activeProcessingJob {
            do { try processingQueue.update(id, state: requeue ? .waiting : .failed, error: requeue ? nil : "Verarbeitung abgebrochen. Erneut starten ist möglich.") }
            catch { queueStatus = error.localizedDescription }
        }
        queueWorker?.cancel()
        activeProcessingJob = nil
        processingTask?.cancel(); processingTask = nil; processingID = UUID()
        playbackTask?.cancel(); referencePlayer?.stop()
        if transcriptionState == .running { transcriptionState = .idle }
        summaryStatus = nil
        summaryRunning = false
    }
    func downloadModels(_ id: String) {
        guard !modelDownloadRunning else { return }
        modelDownloadRunning = true
        downloadTask = Task {
            defer { modelDownloadRunning = false }
            do {
                try await ModelManager.shared.download(id) { message in
                    await MainActor.run { self.modelDownloadStatus = message }
                }
                modelDownloadStatus = "Modell bereit (offline)"
            } catch is CancellationError { modelDownloadStatus = "Download abgebrochen" }
            catch { modelDownloadStatus = error.localizedDescription }
        }
    }
    func downloadWhisper() {
        guard !modelDownloadRunning else { return }
        modelDownloadRunning = true
        downloadTask = Task {
            defer { modelDownloadRunning = false }
            await live.loadModel(whisperModel, downloadIfNeeded: true)
        }
    }
    func cancelModelDownload() { downloadTask?.cancel() }
    func chooseRecordingFolder() {
        guard !retentionRunning else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { recordingPath = url.path; refreshRecordings() }
    }
    var customerScopeSuggestion: String? {
        guard let meeting = currentMeeting else { return nil }
        let internalDomains = Set(speakerStore.profiles.compactMap { $0.email?.split(separator: "@").last.map(String.init) })
        let publicDomains: Set<String> = ["gmail.com", "outlook.com", "hotmail.com", "icloud.com", "gmx.de", "web.de", "yahoo.com"]
        let domains = Set(meeting.attendeeEmails.compactMap { $0.lowercased().split(separator: "@").last.map(String.init) })
            .subtracting(internalDomains).subtracting(publicDomains)
        return domains.count == 1 ? domains.first : nil
    }
    func openSummary() {
        guard let pending = lastTranscription else { return }
        guard let document = lastDocument else { return }
        do { NSWorkspace.shared.open(try SummaryRepository.current(in: pending.folderURL, hash: document.summaryInput.hash)) }
        catch { summaryStatus = error.localizedDescription }
    }
    var synchronizedFolderWarning: Bool {
        let path = (RecordingsLibrary.recordingsRoot()?.resolvingSymlinksInPath().path ?? "").lowercased()
        return ["mobile documents", "clouddocs", "cloudstorage", "onedrive", "dropbox", "google drive"].contains { path.contains($0) }
    }
    func enrollSpeaker(id: String, name: String) {
        guard voiceProfilesEnabled, live.fingerprinting.enabled, !retentionRunning else {
            statusMessage = "Speaker Fingerprinting ist ausgeschaltet."; return
        }
        guard let doc = lastDocument, let centroid = doc.speakerCentroidsID, let record = doc.meetingRecord else { statusMessage = "Bitte erneut verarbeiten und einen sauberen Abschnitt verwenden."; return }
        do {
            try speakerStore.confirmVoice(name: name, clusterID: id, pendingID: centroid, meeting: record)
            renameSpeaker(id: id, to: name)
        } catch { statusMessage = error.localizedDescription }
    }
    func deleteAllVoiceData() {
        live.fingerprinting.invalidate()
        do {
            try speakerStore.deleteAllVoiceData()
            lastDocument?.proposedNames = nil; lastDocument?.speakerCentroidsID = nil
            statusMessage = "Alle Stimmprofile gelöscht"
        } catch { statusMessage = error.localizedDescription }
    }
    func rejectProposal(id: String) {
        guard !retentionRunning else { return }
        guard var document = lastDocument, let pending = lastTranscription else { return }
        document.proposedNames?.removeValue(forKey: id)
        writeTranscript(document: document, pending: pending, keepStatus: false)
    }
    func playReference(id: String) {
        guard !retentionRunning else { return }
        guard let doc = lastDocument, let pending = lastTranscription, let url = pending.audioURL,
              let line = doc.lines.first(where: { $0.speakerID == id && $0.overlap != true && ($0.endTime ?? $0.time) - $0.time >= 3 }) else { statusMessage = "Kein sauberer Referenzabschnitt verfügbar."; return }
        do {
            playbackTask?.cancel(); referencePlayer?.stop()
            let player = try AVAudioPlayer(contentsOf: url)
            player.pan = line.channel == "microphone" ? 1 : -1
            player.currentTime = line.time; player.play(); referencePlayer = player
            playbackTask = Task { try? await Task.sleep(for: .seconds(min(10, (line.endTime ?? line.time) - line.time))); if !Task.isCancelled { player.stop() } }
        } catch { statusMessage = error.localizedDescription }
    }
    func summarize() {
        guard !retentionRunning, let pending = lastTranscription, lastDocument != nil else { return }
        enqueueProcessing(pending, kind: .summary)
    }
    private func generateQueuedSummary(_ job: ProcessingJob, operation: UUID) async throws {
        try Task.checkCancellation()
        guard processingID == operation else { throw CancellationError() }
        let document = try TranscriptDocument.load(from: job.folder.appendingPathComponent("transcript.json"))
        let input = document.summaryInput
        summaryStatus = "Zusammenfassen…"; summaryRunning = true
        defer { if processingID == operation { summaryRunning = false } }
        live.releaseModels()
        let result = try await MeetingSummaryService().generate(input, language: job.summaryLanguage) { message in
            await MainActor.run { [weak self] in if self?.processingID == operation { self?.summaryStatus = message } }
        }
        try Task.checkCancellation()
        let current = try TranscriptDocument.load(from: job.folder.appendingPathComponent("transcript.json"))
        guard processingID == operation, current.summaryInput.hash == input.hash else {
            throw LocalError.message("Transkript wurde geändert. Bitte die Zusammenfassung erneut erstellen.")
        }
        try SummaryRepository.publish(result, transcript: input, folder: job.folder)
        summaryStatus = "Zusammenfassung gespeichert"
        if job.deleteAudio {
            do {
                _ = try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: job.folder)
                summaryStatus = "Texte gespeichert · Audio gelöscht"
            } catch is CancellationError { throw CancellationError() }
            catch { summaryStatus = "Zusammenfassung gespeichert · Audio bleibt: " + error.localizedDescription }
        }
        let refreshed = try TranscriptDocument.load(from: job.folder.appendingPathComponent("transcript.json"))
        let pending = PendingTranscription(audioURL: refreshed.audioName.map { job.folder.appendingPathComponent($0) }, folderURL: job.folder, meetingTitle: job.title, attendees: job.attendees, startedAt: job.startedAt)
        let markdown = (try TranscriptRepository.currentJSON(in: job.folder))?.deletingLastPathComponent().appendingPathComponent("transcript.md") ?? job.folder.appendingPathComponent("transcript.md")
        presentProcessed(refreshed, pending: pending, markdown: markdown)
    }
    func showSavedTranscript(_ entry: RecordingEntry) {
        guard !retentionRunning else { return }
        guard let url = entry.transcriptURL else { return }
        do {
            lastDocument = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
            if !voiceProfilesEnabled { lastDocument?.proposedNames = nil; lastDocument?.speakerCentroidsID = nil }
            lastTranscriptText = lastDocument?.renderMarkdown(); lastTranscriptURL = url
            lastTranscription = PendingTranscription(audioURL: entry.audioURL, folderURL: entry.folderURL, meetingTitle: entry.title, attendees: [], startedAt: entry.date)
            if let document = lastDocument, document.meetingRecord == nil, let pending = lastTranscription {
                writeTranscript(document: document, pending: pending, keepStatus: false)
            } else { transcriptionState = .done(url) }
        } catch { statusMessage = "Altes Markdown-Transkript: bitte zur Bearbeitung erneut verarbeiten." }
    }

    /// Copy the live transcript (confirmed lines + current hypothesis) while
    /// a recording is running.
    func copyLiveTranscript() {
        let text = live.transcript(includeHypothesis: true)
        guard !text.isEmpty else {
            statusMessage = "Nothing transcribed yet"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusMessage = "Live transcript copied"
    }

    /// Copy the transcript text to the clipboard.
    func copyTranscriptText() {
        guard let text = lastTranscriptText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusMessage = "Transcript text copied"
    }

    /// Copy the transcript *file* to the clipboard (paste into Finder / Mail / etc.).
    func copyTranscriptFile() {
        guard let url = lastTranscriptURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        statusMessage = "Transcript file copied"
    }

    /// Reveal the transcript in Finder.
    func revealTranscript() {
        guard let url = lastTranscriptURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Recordings library

    /// Reload the recent-recordings list from disk.
    func refreshRecordings() {
        recentRecordings = RecordingsLibrary.recent(limit: 4)
    }

    /// Transcribe (or re-transcribe) an existing recording's audio.
    func transcribeExisting(_ entry: RecordingEntry) {
        guard let audio = entry.audioURL else {
            statusMessage = "No audio.m4a to transcribe in that folder."
            return
        }
        startTranscription(PendingTranscription(
            audioURL: audio,
            folderURL: entry.folderURL,
            meetingTitle: entry.title,
            attendees: [],
            startedAt: entry.date
        ))
    }

    /// Put a file on the clipboard (paste into Finder / Mail / …).
    func copyFileToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        statusMessage = "Copied \(url.lastPathComponent)"
    }

    /// Put a text file's contents on the clipboard.
    func copyTextOfFile(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            statusMessage = "Could not read \(url.lastPathComponent)"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusMessage = "Copied text of \(url.lastPathComponent)"
    }

    /// Reveal an arbitrary file/folder in Finder.
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Open ~/Documents/Recordings in Finder (creating it if needed).
    func openRecordingsFolder() {
        guard let root = RecordingsLibrary.recordingsRoot() else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    private static func describeTranscriptionError(_ error: Error) -> String {
        if let e = error as? WhisperModelHost.HostError {
            return e.errorDescription ?? "Transcription failed."
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Network error while fetching the model: \(ns.localizedDescription)"
        }
        return error.localizedDescription
    }
}
