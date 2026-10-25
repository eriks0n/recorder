import Foundation
import Accelerate

struct SpeakerAnalysisOutcome {
    var spans: [DiarizedSpan] = []
    var centroids: [Int: [Float]] = [:]
    var warning: String?
}

enum SpeakerAnalysisIssue: Error { case missingModel }

/// A speaker-analysis failure may remove labels and enrollment evidence, never recognized words.
/// Cancellation still stops the job, including when an SDK reports another error after cancellation.
enum OptionalSpeakerAnalysis {
    static func run(_ operation: () async throws -> ([DiarizedSpan], [Int: [Float]])) async throws -> SpeakerAnalysisOutcome {
        try Task.checkCancellation()
        do {
            let (spans, centroids) = try await operation()
            try Task.checkCancellation()
            return SpeakerAnalysisOutcome(spans: spans, centroids: centroids)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            let warning: String
            if case SpeakerAnalysisIssue.missingModel = error {
                warning = "Das Modell für die Sprechertrennung fehlt. Der Text bleibt erhalten, Sprecher bleiben unbekannt. Optional unter Settings → Local die Sprechertrennung herunterladen und erneut verarbeiten."
            } else {
                warning = "Die Sprechertrennung ist fehlgeschlagen. Der Text bleibt erhalten, Sprecher bleiben unbekannt. Das SpeakerKit-Modell unter Settings → Local prüfen und bei Bedarf erneut verarbeiten."
            }
            return SpeakerAnalysisOutcome(warning: warning)
        }
    }
}

enum AudioSignal {
    static func hasSignal(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        return meanSquare.isFinite && sqrt(meanSquare) > 1e-4
    }
}
