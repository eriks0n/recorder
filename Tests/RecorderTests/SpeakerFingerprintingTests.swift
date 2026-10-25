import XCTest
@testable import Recorder

@MainActor
final class SpeakerFingerprintingTests: XCTestCase {
    func testOffSkipsAllAnalysis() async throws {
        let control = SpeakerFingerprinting()
        var called = false
        let result = try await control.analyze(control.token) {
            called = true
            return .init(spans: [.init(start: 0, end: 1, clusterID: 1)], centroids: [1: [1, 0]])
        }
        XCTAssertFalse(called)
        XCTAssertTrue(result.spans.isEmpty); XCTAssertTrue(result.centroids.isEmpty)
        XCTAssertNil(control.token)
    }
    func testOnRunsAnalysis() async throws {
        let control = SpeakerFingerprinting(); control.setEnabled(true)
        let result = try await control.analyze(control.token) {
            .init(spans: [.init(start: 0, end: 1, clusterID: 1)], centroids: [1: [1, 0]])
        }
        XCTAssertEqual(result.spans.count, 1); XCTAssertEqual(result.centroids.count, 1)
    }
    func testTurningOffDiscardsInFlightFingerprints() async throws {
        let control = SpeakerFingerprinting(); control.setEnabled(true)
        let result = try await control.analyze(control.token) {
            control.setEnabled(false)
            return .init(spans: [.init(start: 0, end: 1, clusterID: 1)], centroids: [1: [1, 0]])
        }
        XCTAssertTrue(result.spans.isEmpty); XCTAssertTrue(result.centroids.isEmpty)
    }
    func testOffOnDoesNotReviveOldRun() async throws {
        let control = SpeakerFingerprinting(); control.setEnabled(true)
        let old = control.token
        control.setEnabled(false); control.setEnabled(true)
        var called = false
        _ = try await control.analyze(old) { called = true; return .init() }
        XCTAssertFalse(called); XCTAssertFalse(control.accepts(old)); XCTAssertTrue(control.accepts(control.token))
    }
    func testProfileDeletionInvalidatesPendingResults() async throws {
        let control = SpeakerFingerprinting(); control.setEnabled(true)
        let old = control.token; control.invalidate()
        XCTAssertFalse(control.accepts(old))
    }
    func testDisabledStoreDoesNotLoadAndPreservesSavedProfiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FingerprintStore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SpeakerProfileStore(baseURL: root)
        _ = try store.enroll(centroid: .init(vector: [1, 0], sampleSeconds: 10, addedAt: Date(timeIntervalSince1970: 0)), named: "Person")
        let bytes = try Data(contentsOf: root.appendingPathComponent("profiles.json"))
        let disabled = SpeakerProfileStore(baseURL: root, loadOnInit: false)
        XCTAssertTrue(disabled.profiles.isEmpty); XCTAssertTrue(disabled.hasStoredVoiceData)
        disabled.reload(); XCTAssertEqual(disabled.profiles.count, 1)
        disabled.suspend(); XCTAssertTrue(disabled.profiles.isEmpty)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("profiles.json")), bytes)
    }
    func testProfilesHaveNoInternalExternalOrCalendarRestriction() throws {
        let meeting = MeetingRecord(scope: "area", startedAt: Date(), title: "Meeting", attendeeEmails: [], hasCalendarEvent: true)
        var person = SpeakerProfile(id: UUID(), name: "Person", createdAt: Date(), updatedAt: Date(), centroids: [])
        person.scope = "area"; person.embeddingVersion = SpeakerNaming.embeddingVersion
        person.category = "external"; person.email = "not-in-calendar@example.test"
        XCTAssertEqual(SpeakerNaming.eligible([person], meeting: meeting).map(\.id), [person.id])
        person.scope = "different-area"
        XCTAssertTrue(SpeakerNaming.eligible([person], meeting: meeting).isEmpty)
        person.scope = "area"; person.embeddingVersion = "old-model"
        XCTAssertTrue(SpeakerNaming.eligible([person], meeting: meeting).isEmpty)
    }
    func testConfirmationCreatesGenericProfileWithoutCategory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FingerprintConfirm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SpeakerProfileStore(baseURL: root)
        let pending = PendingSpeakers(id: UUID().uuidString, createdAt: Date(timeIntervalSince1970: 0), clusters: ["s1": .init(vector: [1, 0], speechSeconds: 10)])
        try store.writePending(pending)
        let meeting = MeetingRecord(scope: "area", startedAt: Date(), title: nil)
        try store.confirmVoice(name: "Person", clusterID: "s1", pendingID: pending.id, meeting: meeting)
        let profile = try XCTUnwrap(store.profiles.first)
        XCTAssertNil(profile.category); XCTAssertNil(profile.email)
        XCTAssertEqual(profile.scope, "area")
        XCTAssertEqual(profile.embeddingVersion, SpeakerNaming.embeddingVersion)
    }
}
