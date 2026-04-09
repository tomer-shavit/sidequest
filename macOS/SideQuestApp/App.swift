import SwiftUI

@main
struct SideQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
        } label: {
            Image(systemName: "bell")
                .help("SideQuest — Quest notifications")
        }
    }
}