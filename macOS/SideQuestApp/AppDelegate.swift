import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var apiClient: APIClient?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app as background-only (no dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize API client with hardcoded values for now
        // (will be replaced with user auth flow in Phase 2)
        let apiBase = "https://bd5x085yt3.execute-api.us-east-1.amazonaws.com"
        let testToken = "0000000000000000000000000000000000000000000000000000000000000000"  // Placeholder 64-char token
        
        apiClient = APIClient(apiBaseURL: apiBase, bearerToken: testToken)
        
        print("SideQuest app launched with API client")
    }
}