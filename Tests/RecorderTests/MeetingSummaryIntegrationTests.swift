import XCTest
@testable import Recorder

private actor SyntheticResponses {
    var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func saveDiagnostics() throws {
        // Contains only the hard-coded synthetic fixture above; never used by app code.
        try JSONEncoder().encode(values).write(to: URL(fileURLWithPath: "/private/tmp/recorder-synthetic-summary-responses.json"), options: .atomic)
    }
}

final class MeetingSummaryIntegrationTests: XCTestCase {
    /// Explicit opt-in: uses installed local weights and synthetic meeting data only.
    func testLocalGermanSummaryWithEvidence() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RECORDER_TEST_LLM"] == "1",
                          "Set RECORDER_TEST_LLM=1 to test installed local summary weights")
        #if canImport(MLXLLM)
        try XCTSkipUnless(ModelManager.ready("llm"), "Install the summary model before this check")
        let transcript = MeetingTranscript(
            meeting: MeetingRecord(startedAt: Date(timeIntervalSince1970: 0), title: "Synthetischer Funktionstest"),
            modelVersion: "test-fixture", words: [], turns: [
                SpeakerTurn(id: "T1", speakerID: "A", channel: .microphone, start: 0, end: 5,
                            text: "Wir besprechen heute den Projektbericht und die Zahlenprüfung.", overlap: false),
                SpeakerTurn(id: "T2", speakerID: "A", channel: .microphone, start: 5, end: 10,
                            text: "Ich heiße Anna. Ich werde den Bericht bis Freitag an das Team senden.", overlap: false),
                SpeakerTurn(id: "T3", speakerID: "B", channel: .desktop, start: 10, end: 15,
                            text: "Ich bin Ben und übernehme die Prüfung der Zahlen. Dafür haben wir keinen Termin vereinbart.", overlap: false),
                SpeakerTurn(id: "T4", speakerID: "A", channel: .microphone, start: 15, end: 20,
                            text: "Abgemacht. Wir verwenden die geprüften Zahlen im Projektbericht. Ein weiteres Treffen haben wir nicht vereinbart.", overlap: false)
            ])
        let responses = SyntheticResponses()
        var service = MeetingSummaryService()
        service.responseObserver = {
            await responses.append($0)
            try? await responses.saveDiagnostics()
        }
        let summary: MeetingSummary
        do { summary = try await service.generate(transcript, language: "Deutsch") { _ in } }
        catch { try await responses.saveDiagnostics(); throw error }
        try SummaryValidator.validate(summary.content, transcript: transcript)
        XCTAssertEqual(summary.transcriptHash, transcript.hash)
        XCTAssertFalse(summary.content.executiveSummary.isEmpty)
        let commitments = summary.content.actionItems.filter { $0.kind == "commitment" }
        for expectedTurn in ["T2", "T3"] {
            XCTAssertTrue(commitments.contains { $0.evidence.contains { $0.turnID == expectedTurn } },
                          "Both explicit commitments must be extracted with their source evidence")
        }
        for action in commitments where action.evidence.contains(where: { $0.turnID == "T3" }) {
            XCTAssertNil(action.deadline, "Ben's commitment has no agreed deadline")
        }
        let markdown = summary.markdown(transcript: transcript)
        for section in ["# Executive Summary", "# Themen", "# Action Items", "# Nächste Schritte"] {
            XCTAssertTrue(markdown.contains(section))
        }
        #else
        throw XCTSkip("Build with MLX to run local generation")
        #endif
    }
}
