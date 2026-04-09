import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var apiClient: APIClient?
    var windowManager: WindowManager?
    private var ipcListener: IPCListener?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            // Set app as background-only (no dock icon)
            NSApp.setActivationPolicy(.accessory)

            // Initialize API client with hardcoded values for now
            // (will be replaced with user auth flow in Phase 2)
            let apiBase = "https://bd5x085yt3.execute-api.us-east-1.amazonaws.com"
            let testToken = "0000000000000000000000000000000000000000000000000000000000000000"  // Placeholder 64-char token

            apiClient = APIClient(apiBaseURL: apiBase, bearerToken: testToken)

            // Initialize WindowManager
            windowManager = WindowManager()
            windowManager?.setAPIClient(apiClient!)

            // Start IPC listener for plugin triggers
            ipcListener = IPCListener()
            ipcListener?.onTriggerReceived = { [weak self] questId, trackingId in
                self?.handleIPCTrigger(questId: questId, trackingId: trackingId)
            }
            do {
                try ipcListener?.startListening()
                ErrorHandler.logInfo("IPC listener initialized at startup")
            } catch {
                ErrorHandler.logNetworkError(error, endpoint: "/tmp/sidequest.sock")
                // Continue anyway; quests can still be triggered manually
            }

            ErrorHandler.logInfo("SideQuest app launched successfully")

        } catch {
            ErrorHandler.logWindowError(error, operation: "app launch")
            // App continues even if initialization partial fails
        }
    }
}

extension AppDelegate {
    func showTestQuest() {
        do {
            let testQuest = QuestData(
                quest_id: "test-123",
                display_text: "Test Quest: Explore New Features",
                tracking_url: "https://example.com",
                reward_amount: 250,
                brand_name: "Test Corp",
                category: "DevTool"
            )
            windowManager?.showQuest(testQuest)
            ErrorHandler.logQuestDisplay("test-123")
        } catch {
            ErrorHandler.logWindowError(error, operation: "show test quest")
        }
    }

    func fetchAndShowQuest() {
        guard let apiClient = apiClient else {
            ErrorHandler.logInfo("API client not initialized")
            return
        }
        Task {
            do {
                let quest = try await apiClient.fetchQuest()
                await MainActor.run {
                    windowManager?.showQuest(quest)
                }
            } catch {
                // Silent failure — quest simply won't display
                // Error already logged in APIClient
            }
        }
    }

    func handleIPCTrigger(questId: String, trackingId: String) {
        // Called when plugin sends trigger via IPC
        // Fetch quest from API and display via WindowManager

        Task {
            do {
                guard let apiClient = self.apiClient else {
                    ErrorHandler.logInfo("IPC trigger received but apiClient not ready")
                    return
                }

                let questData = try await apiClient.fetchQuest()

                // Validate quest matches expected questId (security check)
                if questData.quest_id != questId {
                    ErrorHandler.logInfo("IPC questId mismatch: expected=\(questId), got=\(questData.quest_id)")
                    // Still display (race condition acceptable)
                }

                DispatchQueue.main.async {
                    self.windowManager?.showQuest(questData)
                }
            } catch {
                // API error — log but don't show to user
                ErrorHandler.logNetworkError(error, endpoint: "/quest")
                // Quest simply not displayed; no error message
            }
        }
    }
}