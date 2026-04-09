import AppKit
import SwiftUI

// NSPanel — .nonactivatingPanel lets clicks work without activating the app
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// NSHostingView subclass: accepts first-mouse clicks + NSTrackingArea for hover
class HoverTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChanged: ((Bool) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.pointingHand.push()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.pop()
        onHoverChanged?(false)
    }
}

// Shared hover state — bridges NSView hover detection to SwiftUI progress bar
class QuestHoverState: ObservableObject {
    @Published var isHovered = false
}


@MainActor
class WindowManager: NSObject {
    private var notificationWindow: NSWindow?
    private var dismissTimer: Timer?
    private var apiClient: APIClient?
    private var eventQueue: EventQueue?
    private var displayStartTime: Date?
    private var currentQuest: QuestData?
    private var userId: String = "unknown"
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var dismissRemainingTime: TimeInterval = 0
    private var timerStartDate: Date?
    private var hoverState = QuestHoverState()

    private static let debugLog = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".sidequest/debug.log")

    private static func debug(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugLog.path) {
                if let handle = try? FileHandle(forWritingTo: debugLog) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? FileManager.default.createDirectory(at: debugLog.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: debugLog)
            }
        }
    }

    override init() {
        super.init()
    }

    deinit {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
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
        // Drop if a notification is already showing — no queuing
        if notificationWindow != nil {
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

        let cardWidth: CGFloat = QuestCardView.cardWidth
        let dismissSeconds = 8.0

        // Reset hover state BEFORE creating the view so both share the same instance
        hoverState = QuestHoverState()

        let contentView = NotificationWindowView(
            questData: questData,
            onOpen: { [weak self] in self?.handleOpen(questData) },
            onSave: { [weak self] in self?.handleSave(questData) },
            onDismiss: { [weak self] in self?.handleDismiss() },
            hoverState: hoverState,
            dismissDuration: dismissSeconds
        )

        // Create hosting view with hover tracking via NSTrackingArea
        let hostingView = HoverTrackingHostingView(rootView: contentView)
        hostingView.onHoverChanged = { [weak self] hovering in
            self?.hoverState.isHovered = hovering
            self?.handleHover(hovering)
        }
        let fittingSize = hostingView.fittingSize
        let cardHeight = fittingSize.height

        // Position: flush right, well below macOS notification area
        let x = screenFrame.maxX - cardWidth
        let y = screenFrame.maxY - cardHeight - 150
        let frame = NSRect(x: x, y: y, width: cardWidth, height: cardHeight)

        // NSPanel with .nonactivatingPanel — clicks work without app activation
        let window = FloatingPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true

        hostingView.frame = NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
        window.contentView = hostingView

        // Lock window to computed size — prevents NSHostingView from resizing
        window.setFrame(frame, display: false)
        window.contentMinSize = NSSize(width: cardWidth, height: cardHeight)
        window.contentMaxSize = NSSize(width: cardWidth, height: cardHeight)

        self.notificationWindow = window
        self.displayStartTime = Date()
        self.currentQuest = questData

        installKeyMonitor(questData: questData)
        animateIn(window, to: frame)

        // Auto-dismiss after 8 seconds
        dismissRemainingTime = dismissSeconds
        timerStartDate = Date()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissSeconds, repeats: false) { [weak self] _ in
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

    // MARK: - Global Keyboard Shortcuts

    private func installKeyMonitor(questData: QuestData) {
        removeKeyMonitor()

        let trusted = AXIsProcessTrusted()
        WindowManager.debug("installKeyMonitor — AXIsProcessTrusted: \(trusted)")

        let handler: (NSEvent) -> Void = { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            WindowManager.debug("Key event: flags=\(flags.rawValue) key='\(key)'")

            let isCmdCtrl = flags.contains(.command) && flags.contains(.control)
            guard isCmdCtrl else { return }

            WindowManager.debug("Matched ⌘⌃ + '\(key)'")

            Task { @MainActor in
                guard self?.notificationWindow != nil else { return }
                switch key {
                case "o":
                    self?.handleOpen(questData)
                case "s":
                    self?.handleSave(questData)
                case "d":
                    self?.handleDismiss()
                default:
                    break
                }
            }
        }

        // Global monitor — works from any app (needs Accessibility permission)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)

        // Local monitor — works when notification window is focused (no permission needed)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }

        WindowManager.debug("Monitors installed: global=\(globalKeyMonitor != nil) local=\(localKeyMonitor != nil)")
    }

    private func removeKeyMonitor() {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - Tracking ID

    private func deriveTrackingId(from questData: QuestData) -> String {
        if let lastSlash = questData.tracking_url.lastIndex(of: "/") {
            let id = String(questData.tracking_url[questData.tracking_url.index(after: lastSlash)...])
            if !id.isEmpty { return id }
        }
        return questData.quest_id
    }

    // MARK: - Animation

    private func animateIn(_ window: NSWindow, to targetFrame: NSRect) {
        var startFrame = targetFrame
        startFrame.origin.x = getActiveScreen().visibleFrame.maxX
        window.setFrame(startFrame, display: false)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
        })
    }

    // MARK: - Hover Pause/Resume

    private func handleHover(_ hovering: Bool) {
        if hovering {
            // Pause: record remaining time and invalidate timer
            if let start = timerStartDate {
                let elapsed = Date().timeIntervalSince(start)
                dismissRemainingTime = max(0, dismissRemainingTime - elapsed)
            }
            dismissTimer?.invalidate()
            dismissTimer = nil
            timerStartDate = nil
        } else {
            // Resume: schedule new timer with remaining time
            guard dismissRemainingTime > 0 else {
                handleDismiss()
                return
            }
            timerStartDate = Date()
            dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissRemainingTime, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.handleDismiss()
                }
            }
        }
    }

    // MARK: - Actions

    private func handleOpen(_ questData: QuestData) {
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
                    "time_to_click_ms": .double(timeToClick),
                    "source": .string("keyboard")
                ]
            )
        }

        if let url = URL(string: questData.tracking_url),
           let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            NSWorkspace.shared.open(url)
        }

        handleDismiss()
    }

    private func handleSave(_ questData: QuestData) {
        let trackingId = deriveTrackingId(from: questData)
        let capturedUserId = userId
        Task {
            await self.eventQueue?.addEvent(
                userId: capturedUserId,
                questId: questData.quest_id,
                trackingId: trackingId,
                eventType: "quest_saved",
                metadata: [
                    "source": .string("keyboard")
                ]
            )
        }

        // Persist to saved quests file
        saveToDisk(questData)

        handleDismiss()
    }

    private func saveToDisk(_ questData: QuestData) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sidequest")
        let file = dir.appendingPathComponent("saved-quests.json")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var saved: [[String: String]] = []
            if let data = try? Data(contentsOf: file),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                saved = existing
            }

            saved.append([
                "quest_id": questData.quest_id,
                "display_text": questData.display_text,
                "subtitle": questData.subtitle,
                "tracking_url": questData.tracking_url,
                "brand_name": questData.brand_name,
                "category": questData.category,
                "saved_at": ISO8601DateFormatter().string(from: Date())
            ])

            let json = try JSONSerialization.data(withJSONObject: saved, options: .prettyPrinted)
            try json.write(to: file)
        } catch {
            // Silent failure — never break the user's flow
        }
    }

    private func handleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        removeKeyMonitor()

        guard let window = notificationWindow else { return }

        self.notificationWindow = nil

        let capturedDisplayStart = self.displayStartTime
        let quest = currentQuest
        let trackingId = quest.map { deriveTrackingId(from: $0) } ?? "unknown"
        let questId = quest?.quest_id ?? "unknown"
        let capturedUserId = userId

        self.displayStartTime = nil
        self.currentQuest = nil

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

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)

            window.animator().setFrame(
                NSRect(x: getActiveScreen().visibleFrame.maxX,
                       y: window.frame.origin.y,
                       width: window.frame.width,
                       height: window.frame.height),
                display: true
            )
        }, completionHandler: {
            window.orderOut(nil)

            DispatchQueue.main.async {
                _ = window
            }
        })
    }
}
