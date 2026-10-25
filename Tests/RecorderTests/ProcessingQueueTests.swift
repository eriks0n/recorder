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

@MainActor final class ProcessingWorkerTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try PrivateStorage.directory(root) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func job(_ title: String) -> ProcessingJob {
        ProcessingJob(folder: root, audio: nil, title: title, attendees: [], startedAt: Date(), whisperModel: "base", language: "de", summaryLanguage: "Deutsch", summarize: false, deleteAudio: false)
    }
    func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(5)) }
        XCTFail("Worker did not reach expected state")
    }
    func testWorkerProcessesSequentiallyAndContinuesAfterFailure() async throws {
        let queue = ProcessingQueue(url: root.appendingPathComponent("queue.json")), inbox = TaskInbox(url: root.appendingPathComponent("inbox.json"))
        let first = job("first"); var second = job("second"); second.folder = root.appendingPathComponent("second"); try PrivateStorage.directory(second.folder)
        try queue.enqueue(first); try queue.enqueue(second)
        var running = 0, maxRunning = 0, order: [String] = []
        let model = RecorderModel(processingQueue: queue, taskInbox: inbox) { job in
            running += 1; maxRunning = max(maxRunning, running); defer { running -= 1 }
            order.append(job.title!)
            try await Task.sleep(for: .milliseconds(10))
            if job.title == "first" { throw LocalError.message("synthetic failure") }
        }
        model.pumpProcessingQueue()
        try await waitUntil { queue.jobs.last?.state == .done }
        XCTAssertEqual(order, ["first", "second"]); XCTAssertEqual(maxRunning, 1)
        XCTAssertEqual(queue.jobs.first?.state, .failed)
    }
    func testCaptureInterruptionRequeuesWithoutOverlapAndResumes() async throws {
        let queue = ProcessingQueue(url: root.appendingPathComponent("queue.json")), inbox = TaskInbox(url: root.appendingPathComponent("inbox.json"))
        let first = job("first"); try queue.enqueue(first)
        var attempts = 0, running = 0, maxRunning = 0
        let model = RecorderModel(processingQueue: queue, taskInbox: inbox) { _ in
            attempts += 1; running += 1; maxRunning = max(maxRunning, running); defer { running -= 1 }
            if attempts == 1 { try await Task.sleep(for: .seconds(30)) }
        }
        model.pumpProcessingQueue(); try await waitUntil { attempts == 1 }
        model.state = .recording; model.cancelProcessing(requeue: true)
        try await waitUntil { running == 0 }
        XCTAssertEqual(queue.jobs[0].state, .waiting); XCTAssertEqual(attempts, 1)
        model.state = .idle; model.pumpProcessingQueue()
        try await waitUntil { queue.jobs[0].state == .done }
        XCTAssertEqual(attempts, 2); XCTAssertEqual(maxRunning, 1)
    }
    func testExplicitCancelDoesNotAutomaticallyRetrySameJob() async throws {
        let queue = ProcessingQueue(url: root.appendingPathComponent("queue.json")), inbox = TaskInbox(url: root.appendingPathComponent("inbox.json"))
        try queue.enqueue(job("first"))
        var running = false
        let model = RecorderModel(processingQueue: queue, taskInbox: inbox) { _ in
            running = true; defer { running = false }; try await Task.sleep(for: .seconds(30))
        }
        model.pumpProcessingQueue(); try await waitUntil { running }
        model.cancelProcessing(); try await waitUntil { !running }
        XCTAssertEqual(queue.jobs[0].state, .failed); XCTAssertNil(queue.next)
    }
}
