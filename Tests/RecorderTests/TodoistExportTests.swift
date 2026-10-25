import XCTest
@testable import Recorder

@MainActor final class TodoistExportTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try PrivateStorage.directory(root) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func draft() -> TaskDraft {
        var d = TaskDraft(meetingID: UUID(), meetingTitle: "Planung", scope: "kunde", meetingDate: Date(timeIntervalSince1970: 1_792_972_800), sourceHash: "hash", sourceKey: UUID().uuidString, sourceTask: "Bericht senden", sourceOwner: "Anna", ownerID: "s1", ownerName: "Anna", sourceDeadline: "morgen", kind: "commitment", evidence: [.init(turnID: "T1", quote: "Ich sende den Bericht morgen.")], evidenceTimes: ["00:02:00"], title: "Bericht senden")
        d.responsibility = .mine; d.reviewed = true; d.selected = true; d.priority = 1
        d.projectID = "project1"; d.projectName = "Kunde"; d.sectionID = "section1"; d.sectionName = "Offen"
        return d
    }
    func testCSVQuotesUnicodeNewlinesAndUsesTodoistColumns() throws {
        var d = draft(); d.title = "Bericht, \"Änderung\"\nprüfen"; d.deadline = "2026-10-30"; d.labels = "arbeit, follow-up"
        let csv = try TodoistCSV.render([d])
        XCTAssertTrue(csv.contains("\"TYPE\",\"CONTENT\",\"DESCRIPTION\",\"PRIORITY\""))
        XCTAssertTrue(csv.contains("Bericht, \"\"Änderung\"\"\nprüfen")); XCTAssertTrue(csv.contains("@arbeit @follow-up"))
        XCTAssertTrue(csv.contains("\"section\",\"Offen\"")); XCTAssertTrue(csv.contains("2026-10-30"))
        XCTAssertTrue(csv.contains("Recorder-Aufgabe:")); XCTAssertTrue(csv.contains("00:02:00 [T1]"))
    }
    func testCSVRejectsUnreviewedMixedProjectAndAlreadyExportedTasks() {
        var a = draft(), b = draft(); b.projectID = "other"
        XCTAssertThrowsError(try TodoistCSV.render([a,b]))
        a.reviewed = false; XCTAssertThrowsError(try TodoistCSV.render([a]))
        a.reviewed = true; a.exportChannel = "Todoist"; XCTAssertThrowsError(try TodoistCSV.render([a]))
        XCTAssertThrowsError(try TodoistCSV.render([]))
        XCTAssertEqual(TodoistCSV.cell("  =HYPERLINK(\"bad\")"), "\"'  =HYPERLINK(\"\"bad\"\")\"")
    }
    func testSyncMappingSeparatesScheduleDeadlinePriorityAndAssignee() {
        var d = draft(); d.scheduled = "2026-10-29"; d.deadline = "2026-10-30"; d.assigneeID = "123"
        let args = TodoistSyncArguments(d)
        XCTAssertEqual(args.priority, 4); XCTAssertEqual(args.due?.date, "2026-10-29"); XCTAssertEqual(args.deadline?.date, "2026-10-30")
        XCTAssertEqual(args.responsible_uid, "123")
        d.priority = 4; d.deadline = ""; d.scheduled = ""; d.projectID = ""; d.sectionID = ""; d.assigneeID = ""
        let empty = TodoistSyncArguments(d)
        XCTAssertEqual(empty.priority, 1); XCTAssertNil(empty.deadline); XCTAssertNil(empty.due); XCTAssertNil(empty.project_id); XCTAssertNil(empty.responsible_uid)
    }
    func testFrozenSendSurvivesRestartAndUsesIdenticalPayload() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")), d = draft()
        try inbox.edit { $0.drafts = [d] }
        let first = try inbox.prepareSend(d.id)
        let reopened = TaskInbox(url: inbox.url)
        let second = try reopened.prepareSend(d.id)
        XCTAssertEqual(first, second); XCTAssertNotNil(reopened.data.drafts[0].attemptID)
        XCTAssertThrowsError(try reopened.save(d))
        try reopened.recordSend(d.id, remoteID: "remote123")
        XCTAssertThrowsError(try reopened.prepareSend(d.id)); XCTAssertEqual(reopened.data.drafts[0].remoteID, "remote123")
    }
    func testFailedSendRetainsFrozenAttemptAndBlocksCSV() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")), d = draft()
        try inbox.edit { $0.drafts = [d] }
        let payload = try inbox.prepareSend(d.id)
        try inbox.recordSend(d.id, remoteID: nil, error: "timeout")
        XCTAssertEqual(try inbox.prepareSend(d.id), payload)
        XCTAssertThrowsError(try TodoistCSV.render(inbox.data.drafts))
    }
    func testCSVReceiptPreventsDirectSendAndSurvivesRestart() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")), d = draft()
        try inbox.edit { $0.drafts = [d] }; try inbox.markCSV([d.id])
        XCTAssertThrowsError(try TaskInbox(url: inbox.url).prepareSend(d.id))
    }
    func testSelectionRequiresReviewedCurrentSource() throws {
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json")); var d = draft(); d.reviewed = false
        try inbox.edit { $0.drafts = [d] }
        XCTAssertThrowsError(try inbox.select(d.id, value: true))
        try inbox.review(d.id); try inbox.select(d.id, value: false)
        XCTAssertFalse(inbox.data.drafts[0].selected)
    }
    func testClientUsesFixedHostAndFrozenCommandAndMapsReceipt() async throws {
        let d = draft(), uuid = UUID().uuidString
        let command = TodoistSyncCommand(uuid: uuid, temp_id: uuid, args: TodoistSyncArguments(d))
        let frozen = try JSONEncoder().encode(command)
        let client = TodoistClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.todoist.com/api/v1/sync")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
            XCTAssertEqual(request.httpMethod, "POST")
            let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let commands = json["commands"] as! [[String: Any]]
            XCTAssertEqual(commands[0]["uuid"] as? String, uuid)
            let response = try JSONSerialization.data(withJSONObject: ["sync_status": [uuid: "ok"], "temp_id_mapping": [uuid: "remote"]])
            return (response, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await client.create(frozenPayload: frozen, token: "synthetic-test-token")
        XCTAssertEqual(result, "remote")
    }
    func testUnconfirmedResponseDoesNotBecomeSuccess() async throws {
        let d = draft(), uuid = UUID().uuidString
        let payload = try JSONEncoder().encode(TodoistSyncCommand(uuid: uuid, temp_id: uuid, args: TodoistSyncArguments(d)))
        let client = TodoistClient { request in (Data("{\"sync_status\":{}}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) }
        do { _ = try await client.create(frozenPayload: payload, token: "synthetic"); XCTFail("Missing receipt cannot succeed") } catch {}
    }
    func testPaginationFollowsCursorAndNeverLeaksTokenIntoURL() async throws {
        let client = TodoistClient { request in
            XCTAssertEqual(request.url?.host, "api.todoist.com")
            XCTAssertFalse(request.url!.absoluteString.contains("secret"))
            let second = request.url!.query!.contains("cursor=next")
            let json = second ? "{\"results\":[{\"id\":\"b\",\"name\":\"B\"}]}" : "{\"results\":[{\"id\":\"a\",\"name\":\"A\"}],\"next_cursor\":\"next\"}"
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let values = try await client.choices("projects", token: "secret")
        XCTAssertEqual(values.map(\.id), ["a", "b"])
    }
    func testHTTPErrorDoesNotExposeResponseBodyOrToken() async throws {
        let client = TodoistClient { request in (Data("sensitive body".utf8), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!) }
        do { _ = try await client.choices("projects", token: "secret"); XCTFail() }
        catch { XCTAssertFalse(error.localizedDescription.contains("sensitive")); XCTAssertFalse(error.localizedDescription.contains("secret")) }
    }
}
