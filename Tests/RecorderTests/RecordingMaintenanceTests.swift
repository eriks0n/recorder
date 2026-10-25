import XCTest
@testable import Recorder

final class RecordingMaintenanceTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_792_972_800)
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingMaintenance-\(UUID().uuidString)")
        try PrivateStorage.directory(root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func fixture(ageDays: Int = 10, document: Bool = true, summary: Bool = true) throws -> RecordingEntry {
        let folder = root.appendingPathComponent("2026-10-1-1200-original-\(UUID().uuidString)")
        try PrivateStorage.directory(folder)
        let date = now.addingTimeInterval(-Double(ageDays) * 86400)
        let meeting = MeetingRecord(scope: "customer-a", startedAt: date, title: "Original")
        try PrivateStorage.save(meeting, to: folder.appendingPathComponent("meeting.json"))
        if document {
            var doc = TranscriptDocument(meetingTitle: "Original", attendees: [], startedAt: date, audioName: "audio.m4a", model: "fixture", isPolished: true,
                lines: [.init(time: 0, text: "Der Bericht ist fertig.", speakerID: "s1")], speakerNames: ["s1": "Anna"])
            doc.meetingRecord = meeting; doc.schemaVersion = 1; doc.speakerCentroidsID = UUID().uuidString
            _ = try TranscriptRepository.publish(doc, folder: folder)
            if summary {
                let stored = try TranscriptDocument.load(from: folder.appendingPathComponent("transcript.json"))
                let input = stored.summaryInput
                let content = SummaryContent(executiveSummary: [.init(text: "Der Bericht ist fertig.", evidence: [.init(turnID: "T1", quote: "Der Bericht ist fertig.")])], topics: [], actionItems: [], nextSteps: [])
                let value = MeetingSummary(meetingID: meeting.id, transcriptHash: input.hash, modelVersion: "fixture", language: "Deutsch", content: content)
                try SummaryRepository.publish(value, transcript: input, folder: folder)
            }
        }
        for name in ["desktop.caf", "mic.caf", "audio.m4a", "scratch.bin", ".partial-audio"] {
            try Data("disposable fixture".utf8).write(to: folder.appendingPathComponent(name))
        }
        return try XCTUnwrap(RecordingsLibrary.entries(roots: [root]).first { $0.folderURL.standardizedFileURL.path == folder.standardizedFileURL.path })
    }
    private func exists(_ name: String, in entry: RecordingEntry) -> Bool {
        FileManager.default.fileExists(atPath: entry.folderURL.appendingPathComponent(name).path)
    }
    func testExpiredRecordingKeepsOnlyReadableTranscriptAndSummary() throws {
        let entry = try fixture()
        let before = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
        let summaryBefore = try RecordingRetention.summaryFiles(in: entry.folderURL)
        XCTAssertTrue(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: entry.folderURL.path)), RecordingRetention.keptFiles)
        let after = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
        XCTAssertEqual(after.lines, before.lines)
        XCTAssertEqual(after.meetingRecord, before.meetingRecord)
        XCTAssertNil(after.audioName); XCTAssertNil(after.speakerCentroidsID)
        XCTAssertEqual(after.summaryInput.hash, before.summaryInput.hash)
        XCTAssertEqual(try Data(contentsOf: entry.folderURL.appendingPathComponent("summary.md")), summaryBefore.markdown)
        let summary = try SummaryRepository.current(in: entry.folderURL, hash: after.summaryInput.hash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.path))
        let retained = try XCTUnwrap(RecordingsLibrary.entries(roots: [root]).first)
        XCTAssertEqual(retained.title, "Original"); XCTAssertNil(retained.audioURL)
        XCTAssertFalse(try RecordingRetention.clean(retained, afterDays: 7, now: now), "Second cleanup is a no-op")
    }
    func testImmediateCleanupRequiresBothSuccessfulTextResults() throws {
        let entry = try fixture()
        try Data("audio".utf8).write(to: entry.folderURL.appendingPathComponent("extra.WAV"))
        XCTAssertEqual(try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: entry.folderURL), 4)
        for name in ["mic.caf", "desktop.caf", "audio.m4a", "extra.WAV"] { XCTAssertFalse(exists(name, in: entry)) }
        for name in ["transcript.md", "transcript.json", "summary.md", "summary.json", "meeting.json", "scratch.bin"] { XCTAssertTrue(exists(name, in: entry)) }
        let doc = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
        XCTAssertNil(doc.audioName)
        _ = try SummaryRepository.current(in: entry.folderURL, hash: doc.summaryInput.hash)
        XCTAssertEqual(try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: entry.folderURL), 0)
    }
    func testLiveFallbackDoesNotDeleteRecoveryAudio() throws {
        let entry = try fixture()
        var doc = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
        let saved = try RecordingRetention.summaryFiles(in: entry.folderURL)
        doc.isPolished = false
        _ = try TranscriptRepository.publish(doc, folder: entry.folderURL)
        try RecordingRetention.restoreSummaryFiles(saved, in: entry.folderURL)
        XCTAssertThrowsError(try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: entry.folderURL))
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testImmediateCleanupPreservesAudioWhenSummaryMissing() throws {
        let entry = try fixture(summary: false)
        XCTAssertThrowsError(try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: entry.folderURL))
        for name in ["audio.m4a", "mic.caf", "desktop.caf"] { XCTAssertTrue(exists(name, in: entry)) }
    }
    func testImmediateCleanupPreservesAudioForStaleSummary() throws {
        let entry = try fixture()
        var pointer = try PrivateStorage.read(SummaryRepository.Pointer.self, from: entry.folderURL.appendingPathComponent("current-summary.json"))
        pointer.transcriptHash = "outdated"
        try PrivateStorage.save(pointer, to: entry.folderURL.appendingPathComponent("current-summary.json"))
        XCTAssertThrowsError(try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: entry.folderURL))
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testImmediateCleanupRejectsInvalidEvidence() throws {
        let entry = try fixture()
        let doc = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
        let input = doc.summaryInput
        let content = SummaryContent(executiveSummary: [], topics: [], actionItems: [.init(task: "Invented", owner: nil, deadline: nil, kind: "commitment", evidence: [.init(turnID: "T999", quote: "Invented")])], nextSteps: [])
        let summary = MeetingSummary(meetingID: input.meeting.id, transcriptHash: input.hash, modelVersion: "fixture", language: "Deutsch", content: content)
        try SummaryRepository.publish(summary, transcript: input, folder: entry.folderURL)
        XCTAssertThrowsError(try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: entry.folderURL))
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testImmediateCleanupRejectsIncompleteSummaryMarkdown() throws {
        let entry = try fixture()
        let doc = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
        let markdown = try SummaryRepository.current(in: entry.folderURL, hash: doc.summaryInput.hash)
        try Data().write(to: markdown)
        XCTAssertThrowsError(try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: entry.folderURL))
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testCancelledImmediateCleanupLeavesAudio() async throws {
        let entry = try fixture()
        let task = Task { try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: entry.folderURL) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must stop deletion") }
        catch is CancellationError { }
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testImmediateCleanupNeverDeletesLinkedExternalAudio() throws {
        let entry = try fixture()
        let outside = root.appendingPathComponent("outside.wav")
        try Data("keep outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: entry.folderURL.appendingPathComponent("external.wav"), withDestinationURL: outside)
        _ = try RecordingAudioCleanup.removeAfterSuccessfulProcessing(in: entry.folderURL)
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "keep outside")
    }
    func testYoungRecordingIsUntouched() throws {
        let entry = try fixture(ageDays: 2)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: entry.folderURL.path))
        XCTAssertFalse(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: entry.folderURL.path)), before)
    }
    func testExactAgeBoundary() throws {
        let entry = try fixture(ageDays: 7)
        XCTAssertFalse(try RecordingRetention.clean(entry, afterDays: 7, now: now.addingTimeInterval(-1)))
        XCTAssertTrue(try RecordingRetention.clean(entry, afterDays: 7, now: now))
    }
    func testMissingTranscriptPreservesAllAudio() throws {
        let entry = try fixture(document: false, summary: false)
        XCTAssertFalse(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        for name in ["audio.m4a", "mic.caf", "desktop.caf"] { XCTAssertTrue(exists(name, in: entry)) }
    }
    func testBlankLegacyTranscriptPreservesAudio() throws {
        let entry = try fixture(document: false, summary: false)
        try Data(" \n\n ".utf8).write(to: entry.folderURL.appendingPathComponent("transcript.md"))
        XCTAssertFalse(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testMalformedDocumentPreservesAudio() throws {
        let entry = try fixture(document: false, summary: false)
        try Data("broken JSON".utf8).write(to: entry.folderURL.appendingPathComponent("transcript.json"))
        XCTAssertThrowsError(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testIncompleteSummaryPreservesAudio() throws {
        let entry = try fixture()
        let saved = try SummaryRepository.current(in: entry.folderURL, hash: TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json")).summaryInput.hash)
        try FileManager.default.removeItem(at: saved)
        XCTAssertThrowsError(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testInvalidRetentionCannotDeleteFiles() throws {
        let entry = try fixture()
        for days in [0, -1, 3651] { XCTAssertThrowsError(try RecordingRetention.clean(entry, afterDays: days, now: now)) }
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testLinkedTextIsRejectedAndOutsideFileUntouched() throws {
        let entry = try fixture()
        let outside = root.appendingPathComponent("outside.txt")
        try Data("keep outside".utf8).write(to: outside)
        let file = entry.folderURL.appendingPathComponent("transcript.md")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        XCTAssertThrowsError(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "keep outside")
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testDeletingExtraLinkDoesNotFollowItsTarget() throws {
        let entry = try fixture()
        let outside = root.appendingPathComponent("outside")
        try PrivateStorage.directory(outside)
        let protected = outside.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: protected)
        try FileManager.default.createSymbolicLink(at: entry.folderURL.appendingPathComponent("extra-link"), withDestinationURL: outside)
        XCTAssertTrue(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertTrue(FileManager.default.fileExists(atPath: protected.path))
    }
    func testPointerTraversalPreservesAudio() throws {
        let entry = try fixture()
        try PrivateStorage.save(TranscriptRepository.Pointer(generation: "../../outside"), to: entry.folderURL.appendingPathComponent("current-result.json"))
        XCTAssertThrowsError(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testUnrelatedDirectoriesAreNeverCleaned() throws {
        let folder = root.appendingPathComponent("unrelated")
        try PrivateStorage.directory(folder)
        let file = folder.appendingPathComponent("important.txt")
        try Data("keep".utf8).write(to: file)
        let report = RecordingRetention.run(roots: [root], afterDays: 1, now: now)
        XCTAssertEqual(report.cleaned, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testForeignTranscriptFolderIsNotARecorderRecording() throws {
        let folder = root.appendingPathComponent("personal-notes")
        try PrivateStorage.directory(folder)
        try Data("Some text".utf8).write(to: folder.appendingPathComponent("transcript.md"))
        let protected = folder.appendingPathComponent("important.txt")
        try Data("keep".utf8).write(to: protected)
        let entry = RecordingEntry(folderURL: folder, title: nil, date: now.addingTimeInterval(-30 * 86400), audioURL: nil,
                                   transcriptURL: folder.appendingPathComponent("transcript.md"), documentURL: nil)
        XCTAssertFalse(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertTrue(FileManager.default.fileExists(atPath: protected.path))
    }
    func testTextFilenameCaseCannotCauseItsDeletion() throws {
        let entry = try fixture()
        let lower = entry.folderURL.appendingPathComponent("transcript.md")
        let temporary = entry.folderURL.appendingPathComponent("temporary-text")
        let upper = entry.folderURL.appendingPathComponent("TRANSCRIPT.MD")
        try FileManager.default.moveItem(at: lower, to: temporary)
        try FileManager.default.moveItem(at: temporary, to: upper)
        XCTAssertTrue(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lower.path))
        XCTAssertTrue(try String(contentsOf: lower, encoding: .utf8).contains("Der Bericht ist fertig."))
    }
    func testRenamePersistsWithoutMovingFolderOrInvalidatingSummary() throws {
        let entry = try fixture()
        let before = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
        try MeetingNaming.rename(entry, to: "  Projekt   Montag\n ")
        let after = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json"))
        XCTAssertEqual(after.meetingTitle, "Projekt Montag")
        XCTAssertEqual(after.meetingRecord?.title, "Projekt Montag")
        XCTAssertEqual(after.lines, before.lines)
        XCTAssertEqual(after.meetingRecord?.scope, before.meetingRecord?.scope)
        let summary = try SummaryRepository.current(in: entry.folderURL, hash: after.summaryInput.hash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.path))
        let renamed = try XCTUnwrap(RecordingsLibrary.entries(roots: [root]).first)
        XCTAssertEqual(renamed.folderURL, entry.folderURL)
        XCTAssertEqual(renamed.title, "Projekt Montag")
    }
    func testAudioOnlyRecordingCanBeRenamed() throws {
        let entry = try fixture(document: false, summary: false)
        try MeetingNaming.rename(entry, to: "Sprachnotiz")
        XCTAssertEqual(RecordingsLibrary.entries(roots: [root]).first?.title, "Sprachnotiz")
        XCTAssertTrue(exists("audio.m4a", in: entry))
    }
    func testLegacyNameAndTextSurviveCleanup() throws {
        let entry = try fixture(document: false, summary: false)
        let text = "# Transcript\n\n[00:01] Originaltext.\n"
        try Data(text.utf8).write(to: entry.folderURL.appendingPathComponent("transcript.md"))
        try MeetingNaming.rename(entry, to: "Alte Notiz")
        let named = try String(contentsOf: entry.folderURL.appendingPathComponent("transcript.md"), encoding: .utf8)
        XCTAssertTrue(named.contains("[00:01] Originaltext."))
        XCTAssertTrue(try RecordingRetention.clean(entry, afterDays: 7, now: now))
        XCTAssertEqual(try String(contentsOf: entry.folderURL.appendingPathComponent("transcript.md"), encoding: .utf8), named)
        XCTAssertEqual(RecordingsLibrary.entries(roots: [root]).first?.title, "Alte Notiz")
    }
    func testEmptyRenameIsRejected() throws {
        let entry = try fixture()
        XCTAssertThrowsError(try MeetingNaming.rename(entry, to: " \n"))
        XCTAssertEqual(RecordingsLibrary.entries(roots: [root]).first?.title, "Original")
    }
    func testSummaryHashIgnoresAssignmentDictionaryOrder() throws {
        let entry = try fixture()
        var first = try TranscriptDocument.load(from: entry.folderURL.appendingPathComponent("transcript.json")).summaryInput
        first.assignments = [.init(id: "A", name: "Anna", status: .confirmed), .init(id: "B", name: "Ben", status: .confirmed)]
        var second = first; second.assignments.reverse()
        XCTAssertEqual(first.hash, second.hash)
    }
}
