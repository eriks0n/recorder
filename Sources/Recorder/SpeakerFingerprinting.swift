import Foundation

/// A token fences in-flight results when fingerprinting is disabled, re-enabled or reset.
@MainActor
final class SpeakerFingerprinting {
    private(set) var enabled = false
    private var generation = UUID()
    var token: UUID? { enabled ? generation : nil }
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        invalidate()
    }
    func invalidate() { generation = UUID() }
    func accepts(_ token: UUID?) -> Bool { enabled && token != nil && token == generation }
    func analyze(_ token: UUID?, operation: () async throws -> SpeakerAnalysisOutcome) async throws -> SpeakerAnalysisOutcome {
        try Task.checkCancellation()
        guard accepts(token) else { return SpeakerAnalysisOutcome() }
        let result = try await operation()
        try Task.checkCancellation()
        return accepts(token) ? result : SpeakerAnalysisOutcome()
    }
}
