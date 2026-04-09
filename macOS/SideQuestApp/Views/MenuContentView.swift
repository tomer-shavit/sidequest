import SwiftUI

struct MenuContentView: View {
    @Environment(\.openURL) var openURL

    @State private var isEnabled = true
    @State private var historyEvents: [QuestEvent] = []
    @State private var isPaused = false
    @State private var pauseEndTime: Date?

    var eventQueue: EventQueue?
    var stateManager: StateManager?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("SideQuest")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                if isPaused, let endTime = pauseEndTime {
                    Text("Paused until \(formatTime(endTime))")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                } else {
                    Text("Running")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Divider()

            // Toggle section
            HStack {
                Toggle("Quests Enabled", isOn: $isEnabled)
                    .font(.system(size: 12))
                    .onChange(of: isEnabled) { newValue in
                        Task {
                            await stateManager?.setUserEnabled(newValue)
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Recent history section
            if !historyEvents.isEmpty {
                VStack(spacing: 4) {
                    Text("Recent")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(historyEvents.prefix(5), id: \.eventId) { event in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.questId == "unknown" ? event.eventType : event.questId)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text("\(event.eventType) \(formatTimestamp(event.timestamp))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            // Pause options section
            HStack {
                Menu {
                    Button("1 hour") { pauseFor(hours: 1) }
                    Button("4 hours") { pauseFor(hours: 4) }
                    Button("8 hours") { pauseFor(hours: 8) }
                    Button("Until tomorrow") { pauseUntilTomorrow() }
                } label: {
                    HStack {
                        Image(systemName: "pause.circle")
                            .frame(width: 16)
                        Text(isPaused ? "Paused" : "Pause")
                    }
                    .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Test quest button (for development)
            HStack {
                Button(action: {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.showTestQuest()
                    }
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                            .frame(width: 16)
                        Text("Show Test Quest")
                    }
                    .font(.system(size: 13))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Quit button
            HStack {
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Image(systemName: "power")
                            .frame(width: 16)
                        Text("Quit SideQuest")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 240)
        .padding(0)
        .onAppear {
            refreshHistory()
        }
    }

    // MARK: - Helper Methods

    private func refreshHistory() {
        Task {
            let allEvents = await eventQueue?.getPendingEvents() ?? []
            await MainActor.run {
                historyEvents = allEvents
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func pauseFor(hours: Int) {
        let minutes = hours * 60
        pauseFor(minutes: minutes)
    }

    private func pauseUntilTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let tomorrowStart = Calendar.current.startOfDay(for: tomorrow)
        let minutesUntilTomorrow = Int(tomorrowStart.timeIntervalSince(Date()) / 60)
        pauseFor(minutes: minutesUntilTomorrow)
    }

    private func pauseFor(minutes: Int) {
        Task {
            await stateManager?.setUserEnabled(false)
            await MainActor.run {
                isPaused = true
                pauseEndTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
            }

            // Re-enable after delay
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)

            await stateManager?.setUserEnabled(true)
            await MainActor.run {
                isPaused = false
                pauseEndTime = nil
                isEnabled = true
            }

            ErrorHandler.logInfo("Quests resumed after \(minutes) minute pause")
        }

        ErrorHandler.logInfo("Quests paused for \(minutes) minutes")
    }
}

#if DEBUG
struct MenuContentView_Previews: PreviewProvider {
    static var previews: some View {
        MenuContentView()
    }
}
#endif
