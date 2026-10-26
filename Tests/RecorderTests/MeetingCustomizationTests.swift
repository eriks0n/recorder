import XCTest
import CoreML
import WhisperKit
@testable import Recorder

final class MeetingCustomizationTests: XCTestCase {
    func testVocabularyKeepsAmbiguousNamesSeparateAndDeduplicates() {
        XCTAssertEqual(TranscriptionVocabulary.terms(" Secjur \nAmin\nArmin\nsecjur\n\n"), ["Secjur", "Amin", "Armin"])
        XCTAssertNil(TranscriptionVocabulary.promptTokens("", tokenizer: nil))
        XCTAssertLessThanOrEqual(TranscriptionVocabulary.terms(String(repeating: "x", count: 5000)).joined().count, 2000)
    }
    func testTemplateValidationAndSinglePassSubstitution() throws {
        try SummaryTemplate.validate("")
        try SummaryTemplate.validate(SummaryTemplate.standard)
        XCTAssertThrowsError(try SummaryTemplate.validate("{{executive_summary}} {{unknown}}"))
        XCTAssertThrowsError(try SummaryTemplate.validate("# Static text"))
        XCTAssertThrowsError(try SummaryTemplate.validate("{{executive_summary}}" + String(repeating: "x", count: 20001)))
        XCTAssertEqual(SummaryTemplate.render("{{meeting_title}}\n{{executive_summary}}", values: [
            "meeting_title": "{{executive_summary}}", "executive_summary": "Belegte Aussage"
        ]), "{{executive_summary}}\nBelegte Aussage")
    }
    func testTemplateRetainsEvidenceAndDoesNotChangeTasks() throws {
        let record = MeetingRecord(startedAt: Date(timeIntervalSince1970: 0), title: "Secjur")
        let turn = SpeakerTurn(id: "T1", speakerID: "A", channel: .microphone, start: 10, end: 15,
                               text: "Ich werde den Bericht senden.", overlap: false)
        let transcript = MeetingTranscript(meeting: record, modelVersion: "fixture", words: [], turns: [turn])
        let evidence = [SummaryEvidence(turnID: "T1", quote: turn.text)]
        let content = SummaryContent(executiveSummary: [.init(text: "Bericht vereinbart", evidence: evidence)], topics: [],
                                     actionItems: [.init(task: "Bericht senden", owner: "A", kind: "commitment", evidence: evidence)], nextSteps: [])
        var summary = MeetingSummary(meetingID: record.id, transcriptHash: transcript.hash, modelVersion: "fixture", language: "Deutsch", content: content)
        XCTAssertTrue(summary.markdown(transcript: transcript).contains("# Action Items"))
        summary.markdownTemplate = "# {{meeting_title}}\n{{executive_summary}}"
        let result = summary.markdown(transcript: transcript)
        XCTAssertTrue(result.contains("# Secjur")); XCTAssertTrue(result.contains("[T1 00:00:10]"))
        XCTAssertFalse(result.contains("Bericht senden"))
        XCTAssertEqual(summary.content.actionItems.count, 1)
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(summary)) as? [String: Any])
        object.removeValue(forKey: "markdownTemplate")
        let legacy = try JSONDecoder().decode(MeetingSummary.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.markdownTemplate)
    }
    func testPromptAlignmentRebasesCorrectRowsAndKeepsBackingStorageAlive() throws {
        var options = DecodingOptions(promptTokens: [10, 11, 999])
        XCTAssertEqual(VocabularySegmentSeeker.alignmentOffset(options: options, specialToken: 100), 3)
        options.promptTokens = []
        XCTAssertEqual(VocabularySegmentSeeker.alignmentOffset(options: options, specialToken: 100), 0)
        options.promptTokens = [10]; options.usePrefillPrompt = false
        XCTAssertEqual(VocabularySegmentSeeker.alignmentOffset(options: options, specialToken: 100), 0)
        func shifted() throws -> MLMultiArray {
            let source = try MLMultiArray(shape: [8, 3], dataType: .float16)
            for i in 0..<24 { source[i] = NSNumber(value: i) }
            XCTAssertTrue(try VocabularySegmentSeeker.rebase(source, offset: 0) === source)
            return try VocabularySegmentSeeker.rebase(source, offset: 3)
        }
        let rebased = try shifted()
        XCTAssertEqual(rebased.shape, [5, 3]); XCTAssertEqual(rebased[0].intValue, 9)
        XCTAssertEqual(rebased[14].intValue, 23)
        XCTAssertThrowsError(try VocabularySegmentSeeker.rebase(rebased, offset: 5))
    }
    func testLegacyQueueDecodesWithoutNewSettingsAndNewJobRoundTrips() throws {
        var job = ProcessingJob(folder: URL(fileURLWithPath: "/tmp/synthetic"), attendees: [], startedAt: Date(),
                                whisperModel: "fixture", language: "de", summaryLanguage: "Deutsch", summarize: true, deleteAudio: false)
        let encoder = JSONEncoder()
        let legacy = try JSONDecoder().decode(ProcessingJob.self, from: encoder.encode(job))
        XCTAssertNil(legacy.vocabulary); XCTAssertNil(legacy.summaryTemplate)
        job.vocabulary = "Secjur\nAmin\nArmin"; job.summaryTemplate = SummaryTemplate.standard
        let restored = try JSONDecoder().decode(ProcessingJob.self, from: encoder.encode(job))
        XCTAssertEqual(restored.vocabulary, job.vocabulary); XCTAssertEqual(restored.summaryTemplate, job.summaryTemplate)
    }
    func testUnknownMicrophoneFailsWithoutTouchingHardware() throws {
        XCTAssertThrowsError(try MicrophoneDevices.select("synthetic-missing-microphone-uid", unit: nil))
        XCTAssertNoThrow(try MicrophoneDevices.requireSelected("", unit: nil))
        XCTAssertThrowsError(try MicrophoneDevices.requireSelected("synthetic-missing-microphone-uid", unit: nil))
    }
}

@MainActor final class VocabularyModelIntegrationTests: XCTestCase {
    /// Only explicitly supplied synthetic audio; never reads a user's recordings.
    func testVocabularyWithRealModelKeepsWordTimesInsideShortClip() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RECORDER_TEST_VOCABULARY"] == "1")
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["RECORDER_VOCABULARY_AUDIO"])
        let engine = LocalTranscriptionEngine()
        engine.fingerprinting.setEnabled(false)
        await engine.loadModel(WhisperModelOption.defaultModelID, downloadIfNeeded: false)
        XCTAssertEqual(engine.engineState, .ready)
        let result = try await engine.transcribeFile(URL(fileURLWithPath: path), vocabulary: "Secjur\nAmin\nArmin")
        XCTAssertFalse(result.lines.isEmpty)
        // Synthetic fixture lasts about 10 seconds; upstream #542 shifts words to ~30 s.
        XCTAssertLessThan(try XCTUnwrap(result.lines.first).time, 5)
        XCTAssertLessThan(try XCTUnwrap(result.lines.last?.endTime), 20)
        try await engine.host.withPipe { pipe in
            let tokens = try XCTUnwrap(TranscriptionVocabulary.promptTokens(String(repeating: "Secjur Amin Armin Fachwort\n", count: 100), tokenizer: pipe.tokenizer))
            XCTAssertLessThanOrEqual(tokens.count, 200)
            XCTAssertTrue(tokens.allSatisfy { $0 < pipe.tokenizer!.specialTokens.specialTokenBegin })
        }
    }
}
