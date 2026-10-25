import Foundation

// MARK: - Model catalog

/// One selectable on-device Whisper model. All entries are multilingual
/// (German + English included); English-only `.en` variants are deliberately
/// excluded from the catalog.
struct WhisperModelOption: Identifiable, Equatable {
    /// WhisperKit variant name in the `argmaxinc/whisperkit-coreml` repo.
    let id: String
    let label: String
    let detail: String

    static let catalog: [WhisperModelOption] = [
        WhisperModelOption(
            id: "openai_whisper-tiny",
            label: "Tiny",
            detail: "~110 MB, fastest, lowest accuracy"
        ),
        WhisperModelOption(
            id: "openai_whisper-base",
            label: "Base",
            detail: "~150 MB, fast, fine for quick notes"
        ),
        WhisperModelOption(
            id: "openai_whisper-small_216MB",
            label: "Small (compressed)",
            detail: "~220 MB, good accuracy"
        ),
        WhisperModelOption(
            id: "openai_whisper-small",
            label: "Small",
            detail: "~490 MB, good accuracy"
        ),
        WhisperModelOption(
            id: "openai_whisper-large-v3-v20240930_turbo_632MB",
            label: "Large v3 Turbo (compressed)",
            detail: "~630 MB, best accuracy"
        ),
    ]

    static let defaultModelID = "openai_whisper-base"

    static func label(for id: String) -> String {
        catalog.first(where: { $0.id == id })?.label ?? id
    }
}

/// Selectable transcription languages. "auto" detects the language per window,
/// which handles mixed German/English meetings.
enum TranscriptionLanguage {
    static let options: [(id: String, label: String)] = [
        ("auto", "Auto-detect"),
        ("de", "German"),
        ("en", "English"),
        ("fr", "French"),
        ("es", "Spanish"),
        ("it", "Italian"),
    ]
}

