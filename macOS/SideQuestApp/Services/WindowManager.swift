import AppKit
import SwiftUI

@MainActor
class WindowManager: NSObject {
    private var notificationWindow: NSWindow?
    private var dismissTimer: Timer?
    private var apiClient: APIClient?
    private var eventQueue: EventQueue?
    private var questQueue: [QuestData] = []
    private var displayStartTime: Date?
    private var currentQuest: QuestData?
    private var userId: String = "unknown"

    override init() {
        super.init()
    }

    deinit {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    func setAPIClient(_ client: APIClient) {
        self.apiClient = client
    }

    func setEventQueue(_ queue: EventQueue) {
        self.eventQueue = queue
    }

    func setUserId(_ id: String) {
        self.userId = id
    }

    // MARK: - Public Interface

    func showQuest(_ questData: QuestData) {
        if notificationWindow != nil {
            if questQueue.count < 3 {
                questQueue.append(questData)
            }
            return
        }

        displayQuest(questData)
    }

    // MARK: - Private Implementation

    private func getActiveScreen() -> NSScreen {
        if let main = NSScreen.main {
            return main
        }
        if let primary = NSScreen.screens.first {
            return primary
        }
        return NSScreen.screens[0]
    }

    private func displayQuest(_ questData: QuestData) {
        let activeScreen = getActiveScreen()
        let screenFrame = activeScreen.visibleFrame

        let x = screenFrame.maxX - 390
        let y = screenFrame.maxY - 100

        let frame = NSRect(x: x, y: y, width: 370, height: 110)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.isMovableByWindowBackground = false

        let dismissSeconds = 8.0
        let contentView = NotificationWindowView(
            questData: questData,
            onOpen: { [weak self] in self?.handleOpen(questData) },
            onDismiss: { [weak self] in self?.handleDismiss() },
            dismissDuration: dismissSeconds
        )

        window.contentView = NSHostingView(rootView: contentView)

        self.notificationWindow = window
        self.displayStartTime = Date()
        self.currentQuest = questData

        animateIn(window)

        // Auto-dismiss after 8 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleDismiss()
            }
        }

        window.makeKeyAndOrderFront(nil)
        ErrorHandler.logQuestDisplay(questData.quest_id)

        // Log quest_shown event
        let trackingId = deriveTrackingId(from: questData)
        let capturedUserId = userId
        Task {
            await self.eventQueue?.addEvent(
                userId: capturedUserId,
                questId: questData.quest_id,
                trackingId: trackingId,
                eventType: "quest_shown",
                metadata: [
                    "display_duration_ms": .int(8000),
                    "position": .string("top-right")
                ]
            )
        }
    }

    private func deriveTrackingId(from questData: QuestData) -> String {
        // Extract tracking_id from tracking_url: e.g. https://api.trysidequest.ai/click/abc123 -> abc123
        if let lastSlash = questData.tracking_url.lastIndex(of: "/") {
            let id = String(questData.tracking_url[questData.tracking_url.index(after: lastSlash)...])
            if !id.isEmpty { return id }
        }
        return questData.quest_id
    }

    private func animateIn(_ window: NSWindow) {
        var frame = window.frame
        frame.origin.x = getActiveScreen().visibleFrame.maxX
        window.setFrame(frame, display: false)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            window.animator().setFrame(
                NSRect(x: window.frame.origin.x - (window.frame.width + 20),
                       y: window.frame.origin.y,
                       width: window.frame.width,
                       height: window.frame.height),
                display: true
            )
        })
    }

    private func handleOpen(_ questData: QuestData) {
        // Log quest_clicked event
        let trackingId = deriveTrackingId(from: questData)
        let capturedUserId = userId
        Task {
            let timeToClick = self.displayStartTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
            await self.eventQueue?.addEvent(
                userId: capturedUserId,
                questId: questData.quest_id,
                trackingId: trackingId,
                eventType: "quest_clicked",
                metadata: [
                    "time_to_click_ms": .double(timeToClick)
                ]
            )
        }

        // Open landing page — validate https scheme
        if let url = URL(string: questData.tracking_url),
           let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            NSWorkspace.shared.open(url)
        }

        handleDismiss()
    }

    private func handleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let window = notificationWindow else { return }

        // Immediately prevent re-entry
        self.notificationWindow = nil

        // Capture values before clearing state
        let capturedDisplayStart = self.displayStartTime
        let quest = currentQuest
        let trackingId = quest.map { deriveTrackingId(from: $0) } ?? "unknown"
        let questId = quest?.quest_id ?? "unknown"
        let capturedUserId = userId

        self.displayStartTime = nil
        self.currentQuest = nil

        // Log quest_dismissed event
        Task {
            let displayDuration = capturedDisplayStart.map { Date().timeIntervalSince($0) * 1000 } ?? 0
            await self.eventQueue?.addEvent(
                userId: capturedUserId,
                questId: questId,
                trackingId: trackingId,
                eventType: "quest_dismissed",
                metadata: [
                    "display_duration_ms": .double(displayDuration)
                ]
            )
        }

        // Hide window. Do NOT nil contentView or close() here — let ARC
        // deallocate window + hosting view together in the next run loop
        // iteration to avoid use-after-free during autorelease pool drain.
        window.orderOut(nil)

        // Defer cleanup to next run loop pass so the current autorelease
        // pool drains without referencing the freed hosting view.
        DispatchQueue.main.async { [weak self] in
            // `window` goes out of scope here — ARC releases it and its
            // contentView (NSHostingView) in a clean autorelease context.
            _ = window

            if let nextQuest = self?.questQueue.first {
                self?.questQueue.removeFirst()
                self?.displayQuest(nextQuest)
            }
        }
    }
}
