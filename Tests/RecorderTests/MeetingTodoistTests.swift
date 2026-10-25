import XCTest
@testable import Recorder

@MainActor final class MeetingTodoistTests: XCTestCase {
    var root: URL!
    var inbox: TaskInbox!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try PrivateStorage.directory(root); inbox = TaskInbox(url: root.appendingPathComponent("inbox.json"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func draft(meeting: UUID = UUID(), owner: String = "s1", responsibility: TaskResponsibility = .mine) -> TaskDraft {
        var d = TaskDraft(meetingID: meeting, meetingTitle: "Planning", scope: "customer", meetingDate: Date(timeIntervalSince1970: 0), sourceHash: "hash", sourceKey: UUID().uuidString, sourceTask: "Bericht senden", sourceOwner: owner, ownerID: owner, ownerName: owner, sourceDeadline: nil, kind: "commitment", evidence: [.init(turnID: "T1", quote: "Bericht senden")], evidenceTimes: ["00:00:00"], title: "Bericht senden")
        d.responsibility = responsibility; d.reviewed = true; d.selected = true; d.projectID = "project"; d.projectName = "Projekt"
        d.scheduled = "2026-11-02"; return d
    }
    func testMeetingDefaultsOnlyAffectUnlockedTasksInThatMeetingAndPreserveDates() throws {
        let id = UUID(); let a = draft(meeting: id); var locked = draft(meeting: id); locked.exportChannel = "Todoist"
        let other = draft()
        try inbox.edit { $0.drafts = [a, locked, other] }
        var settings = MeetingTaskSettings(); settings.projectID = "new"; settings.projectName = "Neu"; settings.labels = "@kunde, @followup"; settings.ownSpeakerIDs = ["s1"]
        try inbox.configureMeeting(id, settings: settings)
        let changed = inbox.data.drafts[0]
        XCTAssertEqual(changed.projectID, "new"); XCTAssertEqual(changed.labels, "kunde, followup"); XCTAssertEqual(changed.scheduled, a.scheduled)
        XCTAssertFalse(changed.reviewed); XCTAssertFalse(changed.selected)
        XCTAssertEqual(inbox.data.drafts[1], locked); XCTAssertEqual(inbox.data.drafts[2], other)
        XCTAssertEqual(TaskInbox(url: inbox.url).data.meetingSettings[id.uuidString]?.projectID, "new")
    }
    func testSpeakerSelectionReclassifiesOwnOtherAndUnresolvedTasks() throws {
        let id = UUID(); let mine = draft(meeting: id), other = draft(meeting: id, owner: "s2"); var unknown = draft(meeting: id); unknown.ownerID = nil
        try inbox.edit { $0.drafts = [mine, other, unknown] }
        var settings = MeetingTaskSettings(); settings.ownSpeakerIDs = ["s1"]
        try inbox.configureMeeting(id, settings: settings)
        XCTAssertEqual(inbox.data.drafts.map(\.responsibility), [.mine, .waiting, .unresolved])
        try inbox.review(mine.id); try inbox.review(other.id)
        XCTAssertEqual(inbox.selectedForMeeting(id).map(\.id), [mine.id])
        XCTAssertThrowsError(try inbox.select(other.id, value: true))
        XCTAssertThrowsError(try inbox.prepareSend(other.id, accountID: "me"))
        XCTAssertThrowsError(try TodoistCSV.render([inbox.data.drafts[1]]))
    }
    func testBulkChangeRejectsOldEditorInsteadOfOverwritingProject() throws {
        let d = draft(); try inbox.edit { $0.drafts = [d] }
        var settings = MeetingTaskSettings(); settings.projectID = "new"
        try inbox.configureMeeting(d.meetingID, settings: settings)
        XCTAssertThrowsError(try inbox.save(d)); XCTAssertEqual(inbox.data.drafts[0].projectID, "new")
    }
    func testSameDefaultsKeepReviewedSelectionIntact() throws {
        let d = draft(); try inbox.edit { $0.drafts = [d] }
        var settings = MeetingTaskSettings(); settings.projectID = d.projectID; settings.projectName = d.projectName
        try inbox.configureMeeting(d.meetingID, settings: settings)
        XCTAssertTrue(inbox.data.drafts[0].reviewed); XCTAssertTrue(inbox.data.drafts[0].selected)
    }
    func testLabelsNormalizePrefixesAndDuplicatesAndRejectControls() throws {
        XCTAssertEqual(TodoistLabels.parse(" @Kunde, kunde, @followup, , @"), ["Kunde", "followup"])
        XCTAssertThrowsError(try TodoistLabels.validate("bad\u{0001}tag"))
        XCTAssertThrowsError(try TodoistLabels.validate(String(repeating: "a", count: 129)))
        XCTAssertNoThrow(try TodoistLabels.validate(""))
    }
    func testTagPickerNamesWithCommasAndQuotesRoundTripWithoutSplitting() throws {
        let names = ["kunde, projekt", "say \"hello\"", "normal"]
        let encoded = TodoistLabels.format(names)
        XCTAssertEqual(TodoistLabels.parse(encoded), names); XCTAssertNoThrow(try TodoistLabels.validate(encoded))
        XCTAssertThrowsError(try TodoistLabels.validate("\"unfinished"))
        let d = draft(); try inbox.edit { $0.drafts = [d] }
        var settings = MeetingTaskSettings(); settings.labels = "\"unfinished"
        XCTAssertThrowsError(try inbox.configureMeeting(d.meetingID, settings: settings))
    }
    func testAccountSwitchCannotReuseFrozenCommand() throws {
        let d = draft(); try inbox.edit { $0.drafts = [d] }
        let bytes = try inbox.prepareSend(d.id, accountID: "original")
        XCTAssertThrowsError(try TaskInbox(url: inbox.url).prepareSend(d.id, accountID: "different"))
        XCTAssertEqual(try inbox.prepareSend(d.id, accountID: "original"), bytes)
    }
    func testLegacyUnboundCommandRequiresManualAccountCheck() throws {
        let d = draft(); try inbox.edit { $0.drafts = [d] }
        _ = try inbox.prepareSend(d.id, accountID: "original")
        try inbox.edit { $0.drafts[0].sendAccountID = nil }
        XCTAssertThrowsError(try inbox.prepareSend(d.id, accountID: "original"))
    }
    func testSharedProjectAlwaysAssignsConnectedUserAndPersonalNeverUsesLegacyAssignee() throws {
        var d = draft(); d.assigneeID = "someone-else"; try inbox.edit { $0.drafts = [d] }
        let shared = try JSONDecoder().decode(TodoistSyncCommand.self, from: inbox.prepareSend(d.id, accountID: "me", sharedProject: true))
        XCTAssertEqual(shared.args.responsible_uid, "me")
        try inbox.rejectSend(d.id, error: "synthetic rejection"); try inbox.review(d.id)
        let personal = try JSONDecoder().decode(TodoistSyncCommand.self, from: inbox.prepareSend(d.id, accountID: "me", sharedProject: false))
        XCTAssertNil(personal.args.responsible_uid)
    }
    func testNewTasksInheritMeetingProjectTagsAndExplicitSpeakerMapping() throws {
        let meeting = MeetingRecord(startedAt: Date(timeIntervalSince1970: 0), title: "Planning")
        var settings = MeetingTaskSettings(); settings.projectID = "project"; settings.labels = "@customer"; settings.ownSpeakerIDs = ["s1"]
        try inbox.configureMeeting(meeting.id, settings: settings)
        let transcript = MeetingTranscript(meeting: meeting, modelVersion: "test", words: [], turns: [SpeakerTurn(id: "T1", speakerID: "s1", channel: .microphone, start: 0, end: 5, text: "Bericht senden", overlap: false)])
        let action = MeetingAction(task: "Bericht senden", owner: "s1", kind: "commitment", evidence: [.init(turnID: "T1", quote: "Bericht senden")])
        let summary = MeetingSummary(meetingID: meeting.id, transcriptHash: transcript.hash, modelVersion: "test", language: "Deutsch", content: .init(executiveSummary: [], topics: [], actionItems: [action], nextSteps: []))
        try inbox.ingest(summary, transcript: transcript)
        XCTAssertEqual(inbox.data.drafts[0].responsibility, .mine); XCTAssertEqual(inbox.data.drafts[0].labels, "customer")
        XCTAssertEqual(inbox.data.drafts[0].projectID, "project"); XCTAssertFalse(inbox.data.drafts[0].reviewed)
    }

    func testChangedOwnerRequiresNewAssignmentAndDoesNotKeepMine() throws {
        let meeting = MeetingRecord(startedAt: Date(timeIntervalSince1970: 0), title: "Planning")
        var t = MeetingTranscript(meeting: meeting, modelVersion: "test", words: [], turns: [SpeakerTurn(id: "T1", speakerID: "s1", channel: .microphone, start: 0, end: 5, text: "Bericht senden", overlap: false)], assignments: [.init(id: "s1", name: "Anna", status: .confirmed)])
        let action = MeetingAction(task: "Bericht senden", owner: "s1", kind: "commitment", evidence: [.init(turnID: "T1", quote: "Bericht senden")])
        var summary = MeetingSummary(meetingID: meeting.id, transcriptHash: t.hash, modelVersion: "test", language: "Deutsch", content: .init(executiveSummary: [], topics: [], actionItems: [action], nextSteps: []))
        try inbox.ingest(summary, transcript: t)
        var d = inbox.data.drafts[0]; d.responsibility = .mine; try inbox.save(d); try inbox.review(d.id)
        t.assignments[0].name = "Ben"; summary.transcriptHash = t.hash
        try inbox.ingest(summary, transcript: t)
        XCTAssertEqual(inbox.data.drafts[0].responsibility, .unresolved)
        XCTAssertFalse(inbox.data.drafts[0].selected); XCTAssertFalse(inbox.data.drafts[0].reviewed)
    }
    func testAmbiguousDisplayNameDoesNotGuessSpeakerIdentity() throws {
        let meeting = MeetingRecord(startedAt: Date(timeIntervalSince1970: 0), title: "Planning")
        let turns = [SpeakerTurn(id: "T1", speakerID: "s1", channel: .microphone, start: 0, end: 5, text: "Anna wird den Bericht senden", overlap: false)]
        let t = MeetingTranscript(meeting: meeting, modelVersion: "test", words: [], turns: turns, assignments: [.init(id: "s1", name: "Anna", status: .confirmed), .init(id: "s2", name: "Anna", status: .confirmed)])
        let action = MeetingAction(task: "Bericht senden", owner: "Anna", kind: "commitment", evidence: [.init(turnID: "T1", quote: turns[0].text)])
        let summary = MeetingSummary(meetingID: meeting.id, transcriptHash: t.hash, modelVersion: "test", language: "Deutsch", content: .init(executiveSummary: [], topics: [], actionItems: [action], nextSteps: []))
        var settings = MeetingTaskSettings(); settings.ownSpeakerIDs = ["s1"]; try inbox.configureMeeting(meeting.id, settings: settings)
        try inbox.edit { $0.myName = "Anna" }
        try inbox.ingest(summary, transcript: t)
        XCTAssertNil(inbox.data.drafts[0].ownerID); XCTAssertEqual(inbox.data.drafts[0].responsibility, .unresolved)
    }
    func testInvalidMeetingTagsRollbackEveryTaskAndSettings() throws {
        let d = draft(); try inbox.edit { $0.drafts = [d] }
        var settings = MeetingTaskSettings(); settings.projectID = "changed"; settings.labels = "bad\u{0001}tag"
        XCTAssertThrowsError(try inbox.configureMeeting(d.meetingID, settings: settings))
        XCTAssertEqual(inbox.data.drafts[0], d); XCTAssertNil(inbox.data.meetingSettings[d.meetingID.uuidString])
    }
    func testPreviouslyReviewedMalformedDatesCannotSend() throws {
        var d = draft(); d.scheduled = "2026-02-31"; try inbox.edit { $0.drafts = [d] }
        XCTAssertFalse(d.exportable); XCTAssertThrowsError(try inbox.prepareSend(d.id, accountID: "me"))
        XCTAssertThrowsError(try TodoistCSV.render([d]))
    }
    func testDeletedProjectIsRejectedBeforeFreezingOrPostingTask() async throws {
        var d = draft(); d.projectID = "deleted"; try inbox.edit { $0.drafts = [d] }
        do { _ = try await TodoistDelivery(inbox: inbox, client: client()).send(ids: [d.id], meetingID: d.meetingID, expectedDrafts: [d], retryID: nil, token: "synthetic"); XCTFail() } catch {}
        XCTAssertNil(inbox.data.drafts[0].attemptID); XCTAssertNil(inbox.data.drafts[0].exportChannel)
    }
    func testLabelsEndpointAndIdentityUseAuthenticatedReadRequests() async throws {
        let client = TodoistClient { request in
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic")
            let json = request.url!.path.hasSuffix("/user") ? "{\"id\":\"me\",\"full_name\":\"Anna\"}" : "{\"results\":[{\"id\":\"tag1\",\"name\":\"kunde\"}]}"
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let identity = try await client.identity(token: "synthetic")
        let labels = try await client.choices("labels", token: "synthetic")
        XCTAssertEqual(identity.id, "me"); XCTAssertEqual(labels.first?.name, "kunde")
    }
    func client(failSecond: Bool = false) -> TodoistClient {
        var posts = 0
        return TodoistClient { request in
            let path = request.url!.path
            let data: Data
            if path.hasSuffix("/user") { data = Data("{\"id\":\"me\",\"full_name\":\"Synthetic\"}".utf8) }
            else if path.hasSuffix("/projects") { data = Data("{\"results\":[{\"id\":\"project\",\"name\":\"Projekt\",\"is_shared\":true}]}".utf8) }
            else {
                posts += 1
                if failSecond && posts == 2 { throw URLError(.timedOut) }
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let command = (body["commands"] as! [[String: Any]])[0]
                let args = command["args"] as! [String: Any]
                XCTAssertEqual(args["responsible_uid"] as? String, "me")
                let uuid = command["uuid"] as! String
                data = try JSONSerialization.data(withJSONObject: ["sync_status": [uuid: "ok"], "temp_id_mapping": [uuid: "remote-\(posts)"]])
            }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    func testPartialDeliveryKeepsFirstReceiptAndSecondFrozenAndNeverIncludesOtherMeeting() async throws {
        let id = UUID(), a = draft(meeting: UUID()); let first = draft(meeting: id), second = draft(meeting: id)
        try inbox.edit { $0.drafts = [first, second, a] }
        do { _ = try await TodoistDelivery(inbox: inbox, client: client(failSecond: true)).send(ids: [first.id, second.id], meetingID: id, expectedDrafts: [first, second], retryID: nil, token: "synthetic"); XCTFail() } catch {}
        XCTAssertEqual(inbox.data.drafts[0].exportChannel, "Todoist"); XCTAssertNil(inbox.data.drafts[1].exportChannel)
        XCTAssertNotNil(inbox.data.drafts[1].attemptID); XCTAssertEqual(inbox.data.drafts[2], a)
        let payload = inbox.data.drafts[1].frozenPayload
        let sent = try await TodoistDelivery(inbox: inbox, client: client()).send(ids: [second.id], meetingID: nil, expectedDrafts: nil, retryID: second.id, token: "synthetic")
        XCTAssertEqual(sent, 1); XCTAssertEqual(inbox.data.drafts[1].frozenPayload, payload)
    }
    func testDeliveryRejectsDifferentMeetingAndChangedConfirmation() async throws {
        let d = draft(); try inbox.edit { $0.drafts = [d] }
        let service = TodoistDelivery(inbox: inbox, client: client())
        do { _ = try await service.send(ids: [d.id], meetingID: UUID(), expectedDrafts: [d], retryID: nil, token: "synthetic"); XCTFail() } catch {}
        var expected = d; expected.title = "Another title"
        do { _ = try await service.send(ids: [d.id], meetingID: d.meetingID, expectedDrafts: [expected], retryID: nil, token: "synthetic"); XCTFail() } catch {}
        XCTAssertNil(inbox.data.drafts[0].attemptID)
    }
}
