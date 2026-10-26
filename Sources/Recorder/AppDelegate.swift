import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only agent app: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)
        Self.installEditingMenu()
    }
    /// AppKit settings windows need a responder-chain Edit menu for text shortcuts.
    @MainActor static func installEditingMenu() {
        let menu = NSApp.mainMenu ?? NSMenu()
        if menu.items.contains(where: { $0.submenu?.items.contains(where: { $0.action == #selector(NSText.paste(_:)) }) == true }) { return }
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] { edit.addItem(withTitle: title, action: action, keyEquivalent: key) }
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit; menu.addItem(item); NSApp.mainMenu = menu
    }
}
