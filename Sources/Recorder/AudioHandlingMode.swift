import Foundation

/// Whether audio is captured during a recording and processed afterward.
/// Separate retention settings decide whether it survives successful text processing.
enum AudioHandlingMode: String, CaseIterable, Identifiable {
    case transcriptOnly
    case keepAudio
    case keepAudioAndPolish

    var id: String { rawValue }

    static let `default`: AudioHandlingMode = .keepAudioAndPolish

    var label: String {
        switch self {
        case .transcriptOnly: return "Transcript only"
        case .keepAudio: return "Keep audio"
        case .keepAudioAndPolish: return "Keep audio and run a high-quality pass"
        }
    }

    var detail: String {
        switch self {
        case .transcriptOnly:
            return "No audio is ever written to disk. Saves text, plus a local summary when enabled."
        case .keepAudio:
            return "Saves audio.m4a next to the live transcript."
        case .keepAudioAndPolish:
            return "Saves audio.m4a, then transcribes it with the selected local model."
        }
    }

    var retainsAudio: Bool {
        self != .transcriptOnly
    }

    var runsPolishPass: Bool {
        self == .keepAudioAndPolish
    }

    func requiresOfflineTranscription(deleteAudioAfterProcessing: Bool) -> Bool {
        retainsAudio && (runsPolishPass || deleteAudioAfterProcessing)
    }

    /// True when this mode combined with the live setting would save nothing at all.
    func producesNothing(liveTranscriptionEnabled: Bool) -> Bool {
        self == .transcriptOnly && !liveTranscriptionEnabled
    }
}

/// The outcome of asking to change mode while a recording is in progress.
enum AudioHandlingChange: Equatable {
    case apply
    /// The requested mode would keep audio the recording never wrote.
    case refuseUpgrade
    /// The requested mode combined with the live setting would save nothing.
    case refuseNothingProduced

    static func decide(
        from active: AudioHandlingMode,
        to requested: AudioHandlingMode,
        liveTranscriptionEnabled: Bool
    ) -> AudioHandlingChange {
        if requested.producesNothing(liveTranscriptionEnabled: liveTranscriptionEnabled) {
            return .refuseNothingProduced
        }
        if requested.retainsAudio && !active.retainsAudio {
            return .refuseUpgrade
        }
        return .apply
    }

    /// Whether applying this change means closing and deleting the partial audio.
    static func deletesPartialAudio(
        from active: AudioHandlingMode,
        to requested: AudioHandlingMode
    ) -> Bool {
        active.retainsAudio && !requested.retainsAudio
    }
}

