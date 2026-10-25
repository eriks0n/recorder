import Foundation
import Observation
import Accelerate
import AVFoundation
import os
import WhisperKit
import SpeakerKit

// MARK: - LocalTranscriptionEngine

/// On-device transcription via WhisperKit (CoreML Whisper on Apple Silicon).
///
/// Owns the model host, the live streaming transcriber, and the offline path that runs
/// a saved `audio.m4a` through the same model with on-device diarization.
@MainActor
@Observable
final class LocalTranscriptionEngine {

    let host: WhisperModelHost
    let live: LiveTranscriber

    init() {
        let host = WhisperModelStorage.makeHost()
        self.host = host
        self.live = LiveTranscriber(host: host)
    }

    // MARK: Model state

    var engineState: ModelLoadState { host.state }
    var modelName: String { host.selectedModel }
    var loadedModelName: String? { host.loadedModel }
    var loadFailureMessage: String? { host.loadFailureMessage }

    func loadModel(_ name: String, downloadIfNeeded: Bool) async {
        await host.loadModel(name, downloadIfNeeded: downloadIfNeeded)
    }

    // MARK: Live surface

    var confirmedLines: [TranscriptLine] { live.confirmedLines }
    var hypothesis: String { live.hypothesis }
    var isSessionActive: Bool { live.isSessionActive }
    var revision: Int { live.revision }
    var hasText: Bool { live.hasText }

    var language: String? {
        get { live.language }
        set { live.language = newValue }
    }

    var labelSpeakers: Bool {
        get { live.labelSpeakers }
        set { live.labelSpeakers = newValue }
    }

    nonisolated var inbox: SampleInbox { live.inbox }

    func beginSession() { live.beginSession() }
    func cancelSession() { live.cancelSession() }

    func endSession() async -> LiveTranscriber.LiveSessionResult {
        await live.endSession()
    }

    func transcript(includeHypothesis: Bool) -> String {
        live.transcript(includeHypothesis: includeHypothesis)
    }

    // MARK: Private state

    @ObservationIgnored private var speakerKit: SpeakerKit?

    private static let log = Logger(subsystem: "com.tobi.Recorder", category: "LocalTranscription")

    private func cleanSegments(_ results: [TranscriptionResult]) -> [TranscriptionSegment] {
        results
            .flatMap { $0.segments }
            .sorted { $0.start < $1.start }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func decodingOptions(forFile: Bool) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: live.language,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: live.language == nil,
            skipSpecialTokens: true,
            wordTimestamps: forFile,
            suppressBlank: true,
            chunkingStrategy: forFile ? .vad : nil
        )
    }

    // MARK: Offline files

    /// Transcribe a saved recording, one channel at a time.
    ///
    /// `StereoMixer` writes desktop to ch0 and mic to ch1, padded by each source's
    /// host-time offset, so the two channels are sample-aligned and their independent
    /// timelines merge by a plain sort. Both channels keep anonymous speaker IDs;
    /// channel origin never establishes a person's identity.
    ///
    /// Serialized against the live tick loop: WhisperKit carries mutable decode state, so
    /// one pipe must never transcribe twice concurrently. The two channel passes
    /// therefore run one after the other.
    var processingStage = ""
    func releaseModels() { host.unload(); speakerKit = nil }

    func transcribeFile(_ url: URL) async throws -> OfflineTranscription {
        var allWords: [TranscriptWord] = [], intervals: [SpeakerInterval] = [], cleanClusters: [String: ClusterEvidence] = [:]
        var warnings: [String] = []
        let channelCount = Self.channelCount(of: url)
        for channel in 0..<min(2, channelCount) {
            try Task.checkCancellation()
            processingStage = "Audio vorbereiten: Kanal \(channel + 1)"
            let samples = try await Self.load(path: url.path, channel: channel)
            guard AudioSignal.hasSignal(samples) else { continue }
            processingStage = "Transkribieren: Kanal \(channel + 1)"
            let text = try await transcribe(samples)
            guard !text.isEmpty else { continue }
            let audioWords = text.map { TranscriptWord(text: $0.text, start: $0.start, end: $0.end,
                                                      channel: channel == 0 ? .desktop : .microphone, speakerID: "unknown") }
            allWords += audioWords
            processingStage = "Sprecher trennen: Kanal \(channel + 1)"
            let analysis = try await OptionalSpeakerAnalysis.run { try await self.diarize(samples) }
            if let warning = analysis.warning, !warnings.contains(warning) { warnings.append(warning) }
            let spans = analysis.spans
            let audioChannel: AudioChannel = channel == 0 ? .desktop : .microphone
            let prefix = channel == 0 ? "D" : "M"
            for span in spans {
                intervals.append(.init(id: "Sprecher-\(prefix)-\(span.clusterID + 1)", start: span.start, end: span.end, channel: audioChannel))
            }
            // Enrollment evidence is re-extracted from a sufficiently long, isolated segment.
            // Never persist a centroid aggregated from overlapping or uncertain segments.
            for clusterID in Set(spans.map(\.clusterID)) {
                try Task.checkCancellation()
                let clean = spans.filter { span in
                    span.clusterID == clusterID && span.end - span.start >= SpeakerNaming.minSpeechSeconds && !spans.contains {
                        $0.clusterID != clusterID && min($0.end, span.end) > max($0.start, span.start)
                    }
                }
                if let span = clean.max(by: { $0.end - $0.start < $1.end - $1.start }) {
                    let first = max(0, Int(span.start * 16000)), last = min(samples.count, Int(min(span.end, span.start + 12) * 16000))
                    if last > first {
                        let reference = try await OptionalSpeakerAnalysis.run { try await self.diarize(Array(samples[first..<last])) }
                        if reference.warning != nil {
                            let warning = "Kein geeignetes Stimmprofil aus dem Referenzabschnitt erstellt. Transkript und vorhandene Sprecherabschnitte bleiben erhalten."
                            if !warnings.contains(warning) { warnings.append(warning) }
                        }
                        if reference.centroids.count == 1, Set(reference.spans.map(\.clusterID)).count == 1, let vector = reference.centroids.values.first {
                            cleanClusters["Sprecher-\(prefix)-\(clusterID + 1)"] = ClusterEvidence(centroid: vector, speechSeconds: Double(last - first) / 16000)
                        }
                    }
                }
            }
        }
        let (_, turns) = TranscriptAssembler.assemble(words: allWords, intervals: intervals)
        // Cross-channel simultaneous speech also makes enrollment conservative.
        for speaker in Set(turns.filter(\.overlap).map(\.speakerID)) { cleanClusters.removeValue(forKey: speaker) }
        let ids = Set(turns.map(\.speakerID))
        return OfflineTranscription(lines: turns.map {
            TranscriptLine(time: $0.start, text: $0.text, speaker: $0.speakerID, endTime: $0.end, channel: $0.channel.rawValue, overlap: $0.overlap)
        }, clusters: cleanClusters, speakerNames: Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) }), warnings: warnings)
    }

    private func transcribe(_ samples: [Float]) async throws -> [TimedText] {
        let options = decodingOptions(forFile: true)
        let results = try await host.withPipe { pipe in
            try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        }
        try Task.checkCancellation()
        return try cleanSegments(results).flatMap { segment -> [TimedText] in
            guard let words = segment.words, !words.isEmpty else { throw LocalError.message("Das Modell lieferte keine Wortzeitstempel. Ergebnis nicht übernommen.") }
            return words.map { TimedText(start: TimeInterval($0.start), end: TimeInterval($0.end), text: $0.word.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    /// Diarization is never allowed to fail the transcription: a failure costs the
    /// speaker labels and nothing else.
    private func diarize(_ samples: [Float]) async throws -> ([DiarizedSpan], [Int: [Float]]) {
        let kit = try await diarizer()
        let result = try await kit.diarize(audioArray: samples, options: PyannoteDiarizationOptions(useExclusiveReconciliation: false))
        let spans = result.segments.compactMap { segment in
            segment.speaker.speakerId.map {
                DiarizedSpan(
                    start: TimeInterval(segment.startTime),
                    end: TimeInterval(segment.endTime),
                    clusterID: $0
                )
            }
        }
        return (spans, result.speakerCentroidEmbeddings)
    }

    private static func load(path: String, channel: Int) async throws -> [Float] {
        try await Task.detached(priority: .utility) {
            try AudioProcessor.loadAudioAsFloatArray(
                fromPath: path,
                channelMode: .specificChannel(channel)
            )
        }.value
    }

    private static func channelCount(of url: URL) -> Int {
        guard let file = try? AVAudioFile(forReading: url) else { return 1 }
        return Int(file.fileFormat.channelCount)
    }

    /// SpeakerKit is optional and loads strictly from the verified local cache.
    private func diarizer() async throws -> SpeakerKit {
        if let speakerKit { return speakerKit }
        guard ModelManager.ready("diar") else { throw SpeakerAnalysisIssue.missingModel }
        let config = PyannoteConfig(
            modelFolder: try ModelManager.verifiedFolder("diar").path,
            download: false,
            load: false,
            verbose: false
        )
        let kit = try await SpeakerKit(config)
        speakerKit = kit
        return kit
    }

}
