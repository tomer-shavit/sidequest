import SwiftUI

struct MenuContentView: View {
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("SideQuest")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Running")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Divider()

            // Settings button
            HStack {
                Button(action: {
                    // Settings action (future: open preferences window)
                    NSLog("Settings clicked")
                }) {
                    HStack {
                        Image(systemName: "gear")
                            .frame(width: 16)
                        Text("Settings")
                    }
                    .font(.system(size: 13))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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
        .frame(width: 180)
        .padding(0)
    }
}

#Preview {
    MenuContentView()
}
