import XCTest
import AppKit
import SwiftUI
@testable import Recorder

@MainActor final class TaskInboxRenderingTests: XCTestCase {
    func testTaskInboxRendersWithSyntheticTask() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try PrivateStorage.directory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = TaskInbox(url: root.appendingPathComponent("inbox.json"))
        var draft = TaskDraft(meetingID: UUID(), meetingTitle: "Projektplanung · Funktionstest", scope: "Beispielkunde", meetingDate: Date(timeIntervalSince1970: 1792922400), sourceHash: "synthetic", sourceKey: "synthetic", sourceTask: "Projektbericht an das Team senden", sourceOwner: "Anna", ownerID: "s1", ownerName: "Anna", sourceDeadline: "bis Freitag", kind: "commitment", evidence: [.init(turnID: "T2", quote: "Ich werde den Projektbericht bis Freitag an das Team senden.")], evidenceTimes: ["00:02:15"], title: "Projektbericht an das Team senden")
        draft.responsibility = .mine; draft.deadline = "2026-10-30"
        try inbox.edit { $0.drafts = [draft]; $0.myName = "Anna" }
        let queue = ProcessingQueue(url: root.appendingPathComponent("queue.json"))
        let model = RecorderModel(processingQueue: queue, taskInbox: inbox)
        let app = NSApplication.shared
        _ = app
        let hosting = NSHostingView(rootView: TaskInboxView(selection: draft.id).environment(model).environment(\.colorScheme, .light))
        let size = NSSize(width: 1120, height: 820)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting; hosting.frame = NSRect(origin: .zero, size: size)
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        // Synthetic fixture only. No user screen or user recording is captured.
        try png.write(to: URL(fileURLWithPath: "/private/tmp/recorder-task-inbox-preview.png"), options: .atomic)
    }
}
