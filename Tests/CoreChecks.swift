import Foundation

@main
struct CoreChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw NSError(domain: "CoreChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        count += 1
    }
    static func rejects(_ body: () throws -> Void, _ message: String) throws {
        do { try body() } catch { count += 1; return }
        try check(false, message)
    }
    @MainActor
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-core-\(UUID().uuidString)")
        try PrivateStorage.directory(folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let word = TranscriptWord(text: "Hallo", start: 2, end: 3, channel: .microphone, speakerID: "unknown")
        let (words, turns) = TranscriptAssembler.assemble(words: [word], intervals: [
            .init(id: "M1", start: 1, end: 4, channel: .microphone),
            .init(id: "M2", start: 2.5, end: 4, channel: .microphone)
        ])
        try check(words.first?.overlap == true, "Overlap must be visible")
        try check(turns.first?.speakerID == "M1", "Maximum time overlap wins")
        let (_, unknown) = TranscriptAssembler.assemble(words: [word], intervals: [])
        try check(unknown.first?.speakerID.contains("Unbekannt") == true, "Channel does not identify a person")
        let (_, cross) = TranscriptAssembler.assemble(words: [word], intervals: [.init(id: "D1", start: 2, end: 3, channel: .desktop)])
        try check(cross.first?.overlap == true, "Cross-channel overlap remains visible")
        try check(VoiceMatching.cosineDistance([.nan, 1], [1, 0]) == 1, "NaN must not match")
        try check(VoiceMatching.cosineDistance([0, 0], [1, 0]) == 1, "Zero norm must not match")
        try check(VoiceMatching.cosineDistance([1], [1, 0]) == 1, "Different embedding dimensions must not match")
        var meeting = MeetingRecord(scope: "customer-a", startedAt: Date(timeIntervalSince1970: 0), title: "Test", attendeeEmails: ["anna@company.test"], hasCalendarEvent: true)
        func profile(_ name: String, _ vector: [Float], scope: String = "customer-a", category: String = "internal", email: String? = "anna@company.test", version: String = SpeakerNaming.embeddingVersion) -> SpeakerProfile {
            var p = SpeakerProfile(id: UUID(), name: name, createdAt: Date(), updatedAt: Date(), centroids: [.init(vector: vector, sampleSeconds: 10, addedAt: Date())])
            p.scope = scope; p.category = category; p.email = email; p.embeddingVersion = version; return p
        }
        let anna = profile("Anna", [1, 0])
        let all = [anna, profile("Other scope", [1, 0], scope: "customer-b"), profile("External", [1, 0], category: "external"), profile("Old version", [1, 0], version: "old"), profile("Not invited", [1, 0], email: "not@company.test")]
        try check(SpeakerNaming.eligible(all, meeting: meeting).map(\.id) == [anna.id], "Scope, category, roster and version must all match")
        meeting.hasCalendarEvent = false
        try check(SpeakerNaming.eligible(all, meeting: meeting).count == 2, "Without a calendar event, only this scope's internal/self profiles qualify")
        let clusters = ["s1": ClusterEvidence(centroid: [1, 0], speechSeconds: 10)]
        let ambiguous = SpeakerNaming.resolve(clusters: clusters, defaultNames: ["s1": "Speaker 1"], profiles: [anna, profile("Near tie", [1, 0.01])])
        try check(ambiguous["s1"]?.profileID == nil, "Near ties must remain unknown")
        let matched = SpeakerNaming.resolve(clusters: clusters, defaultNames: ["s1": "Speaker 1"], profiles: [anna])
        try check(matched["s1"]?.profileID == anna.id, "Strong unique matches can be proposed")
        let short = SpeakerNaming.resolve(clusters: ["s1": .init(centroid: [1, 0], speechSeconds: 2)], defaultNames: [:], profiles: [anna])
        try check(short["s1"]?.profileID == nil, "Short references cannot match")
        let storeFolder = folder.appendingPathComponent("Speakers")
        let store = SpeakerProfileStore(baseURL: storeFolder)
        let pending = PendingSpeakers(id: UUID().uuidString, createdAt: Date(), clusters: ["s1": .init(vector: [1, 0], speechSeconds: 10)])
        try store.writePending(pending)
        try check(!FileManager.default.fileExists(atPath: storeFolder.path), "Unconfirmed embeddings must remain in memory")
        try rejects({ try store.enrollInternal(name: "External", clusterID: "s1", pendingID: pending.id, meeting: meeting, category: "external", email: nil) }, "External enrollment must fail")
        try store.enrollInternal(name: "Anna", clusterID: "s1", pendingID: pending.id, meeting: meeting, category: "internal", email: "anna@company.test")
        try check(store.profiles.count == 1, "Explicit internal enrollment persists")
        try store.enrollInternal(name: "Anna", clusterID: "s1", pendingID: pending.id, meeting: meeting, category: "internal", email: "anna@company.test")
        try check(store.profiles.first?.centroids.count == 1, "Repeated confirmation must not duplicate references")
        try check((try FileManager.default.attributesOfItem(atPath: storeFolder.path)[.posixPermissions] as? Int) == 0o700, "Private directory permissions")
        try store.deleteAllVoiceData()
        try check(!FileManager.default.fileExists(atPath: storeFolder.path), "Delete all voice data removes persisted embeddings")
        try check(store.loadPending(id: pending.id) == nil, "Delete clears in-memory references")
        try rejects({ try store.writePending(.init(id: "../../escape", createdAt: Date(), clusters: [:])) }, "Pending IDs cannot traverse paths")
        var transcript = MeetingTranscript(meeting: meeting, modelVersion: "test", words: [], turns: [
            .init(id: "T1", speakerID: "s1", channel: .desktop, start: 1, end: 4, text: "Anna sendet den Bericht bis Freitag.", overlap: false)
        ])
        let evidence = SummaryEvidence(turnID: "T1", quote: "Anna sendet den Bericht bis Freitag.")
        let empty = SummaryContent(executiveSummary: [], topics: [], actionItems: [], nextSteps: [])
        try SummaryValidator.validate(empty, transcript: transcript); count += 1
        var summary = empty
        summary.actionItems = [.init(task: "Bericht senden", owner: "Anna", deadline: "Freitag", kind: "commitment", evidence: [evidence])]
        try SummaryValidator.validate(summary, transcript: transcript); count += 1
        summary.actionItems[0].owner = "Ben"
        try rejects({ try SummaryValidator.validate(summary, transcript: transcript) }, "Invented owner rejected")
        summary.actionItems[0].owner = nil; summary.actionItems[0].deadline = "Montag"
        try rejects({ try SummaryValidator.validate(summary, transcript: transcript) }, "Invented deadline rejected")
        summary.actionItems[0].deadline = nil; summary.actionItems[0].evidence = [.init(turnID: "T999", quote: "Missing")]
        try rejects({ try SummaryValidator.validate(summary, transcript: transcript) }, "Unknown turn rejected")
        summary.actionItems[0].evidence = [.init(turnID: "T1", quote: "Not in transcript")]
        try rejects({ try SummaryValidator.validate(summary, transcript: transcript) }, "Fabricated quote rejected")
        summary.actionItems[0].evidence = []
        try rejects({ try SummaryValidator.validate(summary, transcript: transcript) }, "Missing evidence rejected")
        let originalHash = transcript.hash
        transcript.assignments = [.init(id: "s1", name: "Anna", status: .confirmed)]
        try check(transcript.hash != originalHash, "Identity confirmation invalidates old summary hash")
        let document = TranscriptDocument(meetingTitle: "Test", attendees: [], startedAt: Date(), audioName: "audio.m4a", model: "test", isPolished: true, lines: [.init(time: 1, text: "Hallo", speakerID: "s1")], speakerNames: ["s1": "Sprecher 1"])
        let exported = try TranscriptRepository.publish(document, folder: folder)
        try check(FileManager.default.fileExists(atPath: exported.path), "Published generation has a complete Markdown file")
        let loaded = try TranscriptDocument.load(from: folder.appendingPathComponent("transcript.json"))
        try check(loaded == document, "Atomic pointer resolves the complete generation")
        try check(document.renderMarkdown().contains("T1"), "Stable turn IDs are exported")
        try check(document.summaryInput.turns.first?.id == "T1", "Summary turn IDs match export")
        let pointer = folder.appendingPathComponent("current-result.json")
        try PrivateStorage.save(TranscriptRepository.Pointer(generation: "../escape"), to: pointer)
        try rejects({ _ = try TranscriptRepository.currentJSON(in: folder) }, "Result pointer traversal rejected")
        print("Passed \(count) core checks")
    }
}
