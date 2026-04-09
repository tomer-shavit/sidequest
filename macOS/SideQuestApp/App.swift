import SwiftUI

@main
struct SideQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("SideQuest", systemImage: "bell") {
            VStack {
                Text("SideQuest Running")
                Button("Settings") { }
            }
            .padding()
        }
    }
}