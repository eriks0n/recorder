import XCTest
@testable import Recorder

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
        let summary = try await MeetingSummaryService().generate(transcript, language: "Deutsch") { _ in }
        try SummaryValidator.validate(summary.content, transcript: transcript)
        XCTAssertEqual(summary.transcriptHash, transcript.hash)
        XCTAssertFalse(summary.content.executiveSummary.isEmpty)
        XCTAssertTrue(summary.content.actionItems.contains { $0.kind == "commitment" }, "Explicit commitments must be extracted")
        let markdown = summary.markdown(transcript: transcript)
        for section in ["# Executive Summary", "# Themen", "# Action Items", "# Nächste Schritte"] {
            XCTAssertTrue(markdown.contains(section))
        }
        #else
        throw XCTSkip("Build with MLX to run local generation")
        #endif
    }
}
