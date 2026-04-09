import Foundation
import ServiceManagement

class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    private let service = SMAppService()

    private init() {}

    func registerForLoginItems() {
        do {
            try service.register()
            ErrorHandler.logInfo("App registered for auto-launch at login")
        } catch {
            ErrorHandler.logFileIOError(error, operation: "register login items")
        }
    }

    func unregister() {
        do {
            try service.unregister()
            ErrorHandler.logInfo("App unregistered from auto-launch at login")
        } catch {
            ErrorHandler.logFileIOError(error, operation: "unregister login items")
        }
    }

    func isEnabled() -> Bool {
        return service.status == .enabled
    }
}
