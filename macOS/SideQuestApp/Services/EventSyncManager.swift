import Foundation
import os.log

class EventSyncManager {
    private let apiClient: APIClient
    private let eventQueue: EventQueue
    private var syncTimer: Timer?
    private let syncIntervalSeconds = 30.0
    private let logger = Logger(subsystem: "ai.sidequest.app", category: "event-sync")

    enum SyncResult {
        case success
        case dropPermanent
        case retry
        case authBroken
    }

    private func classify(_ response: HTTPURLResponse?, error: Error?) -> SyncResult {
        if error != nil { return .retry }
        guard let r = response else { return .retry }
        switch r.statusCode {
        case 200...299: return .success
        case 401:       return .authBroken
        case 400...499: return .dropPermanent
        default:        return .retry
        }
    }

    init(apiClient: APIClient, eventQueue: EventQueue) {
        self.apiClient = apiClient
        self.eventQueue = eventQueue
    }

    deinit {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Public Interface

    func startPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncIntervalSeconds, repeats: true) { [weak self] _ in
            self?.syncEvents()
        }
        ErrorHandler.logInfo("EventSyncManager periodic sync started (every \(syncIntervalSeconds)s)")
    }

    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        ErrorHandler.logInfo("EventSyncManager periodic sync stopped")
    }

    func syncOnTermination() {
        // Final sync attempt — fire-and-forget with 5-second timeout
        Task {
            await self.syncEventsWithTimeout(seconds: 5.0)
        }
    }

    // MARK: - Private Implementation

    private func syncEvents() {
        Task {
            await syncEventsWithTimeout(seconds: 30.0)
        }
    }

    private func syncEventsWithTimeout(seconds: TimeInterval) async {
        let events = await eventQueue.getPendingEvents()

        if events.isEmpty {
            return
        }

        var successCount = 0
        var droppedCount = 0
        for event in events {
            let payload: [String: Any] = {
                var dict: [String: Any] = [
                    "uid": event.userId,
                    "qid": event.questId,
                    "tid": event.trackingId,
                    "event_type": event.eventType,
                ]
                if let metadata = event.metadata {
                    dict["metadata"] = convertMetadataToJSON(metadata)
                }
                return dict
            }()

            var response: HTTPURLResponse?
            var error: Error?
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: payload)

                let baseURL = await apiClient.getBaseURL()
                let eventsURL = baseURL.appendingPathComponent("events")
                var request = URLRequest(url: eventsURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = seconds

                let bearerToken = await apiClient.getBearerToken()
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = jsonData

                let (_, urlResponse) = try await URLSession.shared.data(for: request)
                response = urlResponse as? HTTPURLResponse
            } catch let postError {
                error = postError
            }

            switch classify(response, error: error) {
            case .success:
                await eventQueue.remove(event)
                successCount += 1
            case .dropPermanent:
                await eventQueue.remove(event)
                droppedCount += 1
                ErrorHandler.log("Dropped event \(event.eventId): permanent (HTTP \(response?.statusCode ?? -1))", level: .warning)
            case .retry:
                continue
            case .authBroken:
                await eventQueue.pause()
                ErrorHandler.log("Event sync paused: auth broken (HTTP 401)", level: .error)
                return
            }
        }

        if successCount > 0 || droppedCount > 0 {
            ErrorHandler.logInfo("Events synced (success=\(successCount) dropped=\(droppedCount) total=\(events.count))")
        }
    }

    private func convertMetadataToJSON(_ metadata: [String: AnyCodable]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in metadata {
            result[key] = anyCodableToJSON(value)
        }
        return result
    }

    private func anyCodableToJSON(_ value: AnyCodable) -> Any {
        switch value {
        case .string(let string):
            return string
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .bool(let bool):
            return bool
        case .null:
            return NSNull()
        case .array(let array):
            return array.map { anyCodableToJSON($0) }
        case .object(let object):
            var result: [String: Any] = [:]
            for (key, val) in object {
                result[key] = anyCodableToJSON(val)
            }
            return result
        }
    }
}
