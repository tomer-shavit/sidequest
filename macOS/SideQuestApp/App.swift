import SwiftUI

@main
struct SideQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appDelegate: appDelegate)
        } label: {
            Image("menubar-icon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 18, height: 18)
                .help("SideQuest — Quest notifications")
        }
        .menuBarExtraStyle(.menu)
    }
}
