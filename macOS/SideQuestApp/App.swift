import SwiftUI
import AppKit

@main
struct SideQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private static let menubarIcon: NSImage = {
        let img = NSImage(named: "menubar-icon") ?? NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "SideQuest"
        )!
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appDelegate: appDelegate)
        } label: {
            Image(nsImage: Self.menubarIcon)
                .help("SideQuest — Quest notifications")
        }
        .menuBarExtraStyle(.menu)
    }
}
