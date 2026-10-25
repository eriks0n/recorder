import XCTest
@testable import Recorder

@MainActor final class ProcessingQueueTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try PrivateStorage.directory(root) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func job(_ name: String = "one") -> ProcessingJob {
        ProcessingJob(folder: root.appendingPathComponent(name), audio: root.appendingPathComponent("audio.m4a"), title: name, attendees: [], startedAt: Date(), whisperModel: "base", language: "de", summaryLanguage: "Deutsch", summarize: true, deleteAudio: false)
    }
    func testInterruptedJobsResumeInOrderAndKeepSummaryCheckpoint() throws {
        let url = root.appendingPathComponent("queue.json"), first = job(), second = job("two")
        let queue = ProcessingQueue(url: url)
        try queue.enqueue(first); try queue.enqueue(second)
        try queue.update(first.id, state: .running, kind: .summary)
        let resumed = ProcessingQueue(url: url)
        XCTAssertEqual(resumed.next?.id, first.id); XCTAssertEqual(resumed.next?.kind, .summary)
        try resumed.update(first.id, state: .done)
        XCTAssertEqual(resumed.next?.id, second.id)
    }
    func testDeduplicationAndFailedJobsRequireRetry() throws {
        let queue = ProcessingQueue(url: root.appendingPathComponent("queue.json")), first = job()
        try queue.enqueue(first); try queue.enqueue(job())
        XCTAssertEqual(queue.jobs.count, 1)
        try queue.update(first.id, state: .failed, error: "missing model")
        XCTAssertNil(queue.next); XCTAssertEqual(queue.unfinished.count, 1)
        try queue.update(first.id, state: .waiting)
        XCTAssertEqual(queue.next?.id, first.id)
    }
    func testCorruptQueueCannotBeSilentlyOverwritten() throws {
        let url = root.appendingPathComponent("queue.json"), bytes = Data("broken".utf8)
        try bytes.write(to: url)
        let queue = ProcessingQueue(url: url)
        XCTAssertNotNil(queue.storageError); XCTAssertThrowsError(try queue.enqueue(job()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testSnapshotKeepsAudioUntilSuccessfulProcessingPolicy() throws {
        let queue = ProcessingQueue(url: root.appendingPathComponent("queue.json"))
        var first = job(); first.deleteAudio = true
        try queue.enqueue(first)
        XCTAssertTrue(try XCTUnwrap(ProcessingQueue(url: queue.url).next).deleteAudio)
    }
}
