import Foundation
import Network
import os.log

class IPCListener {
    private var listener: NWListener?
    private let socketPath: String = "/tmp/sidequest.sock"
    var onTriggerReceived: ((String, String) -> Void)?
    private let logger = Logger(subsystem: "ai.sidequest.app", category: "ipc")

    // MARK: - Public Interface

    func startListening() throws {
        // Remove stale socket file if it exists
        try? FileManager.default.removeItem(atPath: socketPath)

        // Create NWListener with Unix domain socket parameters
        let parameters = NWParameters.unix
        let listener = try NWListener(using: parameters)

        // Set state update handler for debugging
        listener.stateUpdateHandler = { [weak self] state in
            self?.logListenerState(state)
        }

        // Set handler for new incoming connections
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        // Start listening on Unix domain socket
        try listener.start(on: .unix(path: socketPath))

        self.listener = listener
        logger.info("IPC listener started at \(self.socketPath)")
    }

    func stopListening() {
        listener?.cancel()
        listener = nil

        // Clean up socket file
        try? FileManager.default.removeItem(atPath: socketPath)
        logger.info("IPC listener stopped")
    }

    // MARK: - Private Implementation

    private func handleConnection(_ connection: NWConnection) {
        // Set state update handler for this connection
        connection.stateUpdateHandler = { [weak self] state in
            self?.logConnectionState(state, connection: connection)
        }

        // Set up to receive data when connection is ready
        connection.start(queue: .global())

        // Receive data
        receiveData(from: connection)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, context, isComplete, error in
            // Handle error
            if let error = error {
                self?.logger.warning("IPC connection error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            // Process received data
            if let data = data, !data.isEmpty {
                self?.processReceivedData(data)
            }

            // Close connection
            connection.cancel()
        }
    }

    private func processReceivedData(_ data: Data) {
        do {
            // Try to decode JSON: { "questId": "...", "trackingId": "..." }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                let questId = json["questId"] ?? ""
                let trackingId = json["trackingId"] ?? ""

                // Validate both fields are non-empty
                if !questId.isEmpty && !trackingId.isEmpty {
                    logger.info("IPC trigger received: questId=\(questId), trackingId=\(trackingId)")
                    onTriggerReceived?(questId, trackingId)
                } else {
                    logger.warning("IPC trigger received with empty fields")
                }
            } else {
                logger.warning("IPC message is not valid JSON")
            }
        } catch {
            logger.warning("Failed to parse IPC JSON: \(error.localizedDescription)")
        }
    }

    private func logListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.debug("IPC listener ready")
        case .failed(let error):
            logger.error("IPC listener failed: \(error.localizedDescription)")
        case .cancelled:
            logger.debug("IPC listener cancelled")
        case .waiting(let error):
            logger.debug("IPC listener waiting: \(error.localizedDescription)")
        @unknown default:
            logger.debug("IPC listener state: unknown")
        }
    }

    private func logConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        switch state {
        case .ready:
            logger.debug("IPC connection ready")
        case .failed(let error):
            logger.warning("IPC connection failed: \(error.localizedDescription)")
        case .cancelled:
            logger.debug("IPC connection cancelled")
        case .waiting(let error):
            logger.debug("IPC connection waiting: \(error.localizedDescription)")
        case .preparing:
            logger.debug("IPC connection preparing")
        @unknown default:
            logger.debug("IPC connection state: unknown")
        }
    }
}
