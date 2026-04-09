import SwiftUI

@main
struct SideQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(
                eventQueue: appDelegate.eventQueue,
                stateManager: appDelegate.stateManager
            )
        } label: {
            Image(systemName: "bell")
                .help("SideQuest — Quest notifications")
        }
    }
}
