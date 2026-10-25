import XCTest
import SwiftUI
import AppKit
@testable import Recorder

@MainActor final class APIKeyEntryFieldTests: XCTestCase {
    private func findField(_ view: NSView) -> APIKeySecureTextField? {
        if let field = view as? APIKeySecureTextField { return field }
        return view.subviews.lazy.compactMap { self.findField($0) }.first
    }
    private func host(text: Binding<String>, enabled: Bool = true) throws -> (NSWindow, APIKeySecureTextField) {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: APIKeyEntryField(text: text, isEnabled: enabled).frame(width: 400, height: 32))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return (window, try XCTUnwrap(findField(hosting)))
    }
    private func command(_ key: String, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: key,
                                     charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "v" ? 9 : 0))
    }
    func testTypingUpdatesBindingInNativeSecureField() throws {
        var value = ""
        let (window, field) = try host(text: Binding(get: { value }, set: { value = $0 }))
        defer { window.close() }
        XCTAssertTrue(field.isEditable); XCTAssertTrue(field.isBezeled)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("synthetic-ui-value")
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertEqual(value, "synthetic-ui-value")
        XCTAssertEqual(field.stringValue, value)
    }
    func testPasteAndSelectAllWorkWithoutMenuOrReadingRealClipboard() throws {
        var value = "existing-synthetic-value"
        let (window, field) = try host(text: Binding(get: { value }, set: { value = $0 }))
        defer { window.close() }
        field.pasteboardString = { "  synthetic-replacement\n" }
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(window.performKeyEquivalent(with: try command("a", window: window)))
        XCTAssertTrue(window.performKeyEquivalent(with: try command("v", window: window)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertEqual(value, "synthetic-replacement")
    }
    func testDisabledFieldDoesNotReadClipboard() throws {
        var value = ""
        let (window, field) = try host(text: Binding(get: { value }, set: { value = $0 }), enabled: false)
        defer { window.close() }
        var reads = 0
        field.pasteboardString = { reads += 1; return "synthetic" }
        _ = field.performKeyEquivalent(with: try command("v", window: window))
        XCTAssertFalse(field.isEnabled); XCTAssertEqual(reads, 0); XCTAssertEqual(value, "")
    }
    func testSettingsShowVisibleSecureInputInDarkMode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try PrivateStorage.directory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = RecorderModel(processingQueue: ProcessingQueue(url: root.appendingPathComponent("queue.json")),
                                  taskInbox: TaskInbox(url: root.appendingPathComponent("inbox.json")))
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: TodoistPreferences().environment(model).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting; hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 620)
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        hosting.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(findField(hosting))
        XCTAssertTrue(field.isEnabled); XCTAssertTrue(field.isBezeled)
        XCTAssertGreaterThan(field.bounds.width, 150); XCTAssertGreaterThan(field.bounds.height, 20)
        XCTAssertEqual(field.stringValue, "")
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/private/tmp/recorder-todoist-settings-preview.png"), options: .atomic)
    }

}
