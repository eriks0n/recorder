import XCTest
@testable import Recorder

@MainActor final class TaskInboxTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try PrivateStorage.directory(root) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func source(name: String = "Anna", title: String = "Bericht senden", deadline: String? = "morgen", kind: String = "commitment") -> (MeetingTranscript, MeetingSummary) {
        let date = ISO8601DateFormatter().date(from: "2026-10-25T23:30:00Z")!
        let meeting = MeetingRecord(startedAt: date, title: "Planning")
        let text = "Ich werde den Bericht morgen senden."
        let turn = SpeakerTurn(id: "T1", speakerID: "s1", channel: .microphone, start: 2, end: 9, text: text, overlap: false)
        let transcript = MeetingTranscript(meeting: meeting, modelVersion: "test", words: [], turns: [turn], assignments: [.init(id: "s1", name: name, status: .confirmed)])
        let action = MeetingAction(task: title, owner: "s1", deadline: deadline, kind: kind, evidence: [.init(turnID: "T1", quote: text)])
        return (transcript, MeetingSummary(meetingID: meeting.id, transcriptHash: transcript.hash, modelVersion: "test", language: "Deutsch", content: .init(executiveSummary: [], topics: [], actionItems: [action], nextSteps: [])))
    }
    func testIngestIsDurableIdempotentAndNeverPreapproved() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")), (t, s) = source()
        try inbox.ingest(s, transcript: t); try inbox.ingest(s, transcript: t)
        let reopened = TaskInbox(url: inbox.url)
        XCTAssertEqual(reopened.data.drafts.count, 1)
        let d = try XCTUnwrap(reopened.data.drafts.first)
        XCTAssertEqual(d.ownerName, "Anna"); XCTAssertFalse(d.reviewed); XCTAssertFalse(d.selected); XCTAssertFalse(d.exportable)
    }
    func testEditedTaskSurvivesRegenerationAndChangedSourceRequiresNewReview() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")); var (t, s) = source()
        try inbox.ingest(s, transcript: t)
        var d = inbox.data.drafts[0]; d.title = "Eigener Titel"; d.responsibility = .mine
        try inbox.save(d); try inbox.review(d.id)
        t.assignments[0].name = "Lennart"; s.transcriptHash = t.hash
        try inbox.ingest(s, transcript: t)
        XCTAssertEqual(inbox.data.drafts[0].title, "Eigener Titel"); XCTAssertEqual(inbox.data.drafts[0].ownerName, "Lennart")
        XCTAssertFalse(inbox.data.drafts[0].reviewed); XCTAssertEqual(inbox.data.drafts[0].id, d.id)
        XCTAssertThrowsError(try inbox.save(d), "Stale editor must not overwrite the new source")
    }
    func testParaphrasedSingleTaskKeepsStableIdentity() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")); let (t, original) = source(); var s = original
        try inbox.ingest(s, transcript: t); let id = inbox.data.drafts[0].id
        s.content.actionItems[0].task = "Bericht verschicken"
        try inbox.ingest(s, transcript: t)
        XCTAssertEqual(inbox.data.drafts.count, 1); XCTAssertEqual(inbox.data.drafts[0].id, id)
    }
    func testInvalidEvidenceAndStaleSummaryAreRejected() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")); let (t, original) = source(); var s = original
        s.transcriptHash = "stale"; XCTAssertThrowsError(try inbox.ingest(s, transcript: t))
        s = original; s.content.actionItems[0].evidence[0].quote = "hallucination"
        XCTAssertThrowsError(try inbox.ingest(s, transcript: t)); XCTAssertTrue(inbox.data.drafts.isEmpty)
    }
    func testDeletedOrCancelledTaskCannotBeExported() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")); let (t, original) = source(); var s = original
        try inbox.ingest(s, transcript: t)
        var d = inbox.data.drafts[0]; d.responsibility = .mine
        try inbox.save(d); try inbox.review(d.id)
        s.content.actionItems = []; try inbox.ingest(s, transcript: t)
        XCTAssertTrue(inbox.data.drafts[0].stale); XCTAssertFalse(inbox.data.drafts[0].exportable)
        s = original; s.content.actionItems[0].kind = "cancelled"; try inbox.ingest(s, transcript: t)
        XCTAssertThrowsError(try inbox.review(d.id))
    }
    func testReviewRejectsUnresolvedOwnerAndInvalidDate() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")); let (t,s) = source(); try inbox.ingest(s, transcript: t)
        let id = inbox.data.drafts[0].id
        XCTAssertThrowsError(try inbox.review(id))
        var d = inbox.data.drafts[0]; d.responsibility = .waiting; d.deadline = "2026-02-31"
        try inbox.save(d); XCTAssertThrowsError(try inbox.review(id))
        d = inbox.data.drafts[0]; d.deadline = ""; try inbox.save(d); try inbox.review(id)
        XCTAssertFalse(inbox.data.drafts[0].exportable)
    }
    func testDatesUseMeetingTimezoneRatherThanExportDay() {
        let meeting = ISO8601DateFormatter().date(from: "2026-10-25T23:30:00Z")!
        let tz = TimeZone(identifier: "Europe/Berlin")!
        XCTAssertEqual(MeetingDateResolver.suggest("morgen", meeting: meeting, timezone: tz), "2026-10-27")
        XCTAssertEqual(MeetingDateResolver.suggest("bis Freitag", meeting: meeting, timezone: tz), "2026-10-30")
        XCTAssertNil(MeetingDateResolver.suggest("bald", meeting: meeting, timezone: tz))
        XCTAssertNil(MeetingDateResolver.suggest(nil, meeting: meeting, timezone: tz))
        XCTAssertFalse(MeetingDateResolver.validISO("2026-02-31"))
        XCTAssertTrue(MeetingDateResolver.validISO("2028-02-29"))
    }
    func testCorruptInboxIsPreserved() throws {
        let url = root.appendingPathComponent("inbox.json"); try Data("broken".utf8).write(to: url)
        let inbox = TaskInbox(url: url); XCTAssertNotNil(inbox.storageError)
        XCTAssertThrowsError(try inbox.edit { $0.myName = "Anna" })
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken")
    }
    func testAmbiguousRegenerationRequiresExplicitDuplicateReview() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")); let (t, original) = source(); var s = original
        try inbox.ingest(s, transcript: t)
        var d = inbox.data.drafts[0]; d.responsibility = .mine
        try inbox.save(d); try inbox.review(d.id)
        try inbox.edit { $0.drafts[0].exportChannel = "Todoist" }
        var a = s.content.actionItems[0]; a.task = "Bericht verschicken"
        var b = a; b.task = "Bericht abstimmen"
        s.content.actionItems = [a,b]; try inbox.ingest(s, transcript: t)
        let additional = inbox.data.drafts.filter { $0.id != d.id }
        XCTAssertEqual(additional.count, 2); XCTAssertTrue(additional.allSatisfy { $0.duplicateWarning != nil })
        var new = additional[0]; new.responsibility = .mine; try inbox.save(new)
        XCTAssertThrowsError(try inbox.review(new.id))
        new = inbox.data.drafts.first { $0.id == new.id }!; new.duplicateApproved = true; try inbox.save(new); try inbox.review(new.id)
        XCTAssertTrue(inbox.data.drafts.first { $0.id == new.id }!.exportable)
    }
    func testInboxBeforeCSVFeatureDecodesWithEmptyBatches() throws {
        let json = Data("{\"schemaVersion\":1,\"drafts\":[],\"myName\":\"Anna\",\"mappings\":{}}".utf8)
        let data = try JSONDecoder().decode(TaskInboxData.self, from: json)
        XCTAssertEqual(data.myName, "Anna"); XCTAssertTrue(data.csvBatches.isEmpty)
    }

}
