import Foundation
import Observation

enum ProcessingJobState: String, Codable { case waiting, running, failed, done }
enum ProcessingJobKind: String, Codable { case transcription, summary }
struct ProcessingJob: Codable, Identifiable {
    var id = UUID()
    var kind: ProcessingJobKind = .transcription
    var state: ProcessingJobState = .waiting
    var folder: URL
    var audio: URL?
    var title: String?
    var attendees: [String]
    var startedAt: Date
    var whisperModel: String
    var language: String
    var summaryLanguage: String
    var summarize: Bool
    var deleteAudio: Bool
    var error: String?
}

/// Durable queue: interrupted work becomes waiting on restart; failures require an explicit retry.
@MainActor @Observable final class ProcessingQueue {
    private(set) var jobs: [ProcessingJob] = []
    private(set) var storageError: String?
    @ObservationIgnored let url: URL
    init(url: URL = PrivateStorage.applicationRoot.appendingPathComponent("processing-queue.json")) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            jobs = try PrivateStorage.read([ProcessingJob].self, from: url)
            for i in jobs.indices where jobs[i].state == .running { jobs[i].state = .waiting }
            try persist()
        } catch { storageError = error.localizedDescription }
    }
    var unfinished: [ProcessingJob] { jobs.filter { $0.state != .done } }
    var next: ProcessingJob? { jobs.first { $0.state == .waiting } }
    func enqueue(_ job: ProcessingJob) throws {
        if jobs.contains(where: { $0.folder.standardizedFileURL == job.folder.standardizedFileURL && [.waiting, .running].contains($0.state) }) { return }
        try change { $0.append(job) }
    }
    func update(_ id: UUID, state: ProcessingJobState, error: String? = nil, kind: ProcessingJobKind? = nil) throws {
        try change { jobs in
            guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[i].state = state; jobs[i].error = error
            if let kind { jobs[i].kind = kind }
        }
    }
    private func change(_ edit: (inout [ProcessingJob]) -> Void) throws {
        guard storageError == nil else { throw LocalError.message("Warteschlange konnte nicht gelesen werden: \(storageError!)") }
        let old = jobs; edit(&jobs)
        do { try persist() } catch { jobs = old; throw error }
    }
    private func persist() throws { try PrivateStorage.save(jobs, to: url) }
}
