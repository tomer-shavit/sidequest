import SwiftUI

struct QuestCardView: View {
    let questData: QuestData
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Dark purple background (always, no theme adaptation)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.302, green: 0.102, blue: 0.502))  // #4D1A7F
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                // Top section: Treasure chest icon + title
                HStack(alignment: .top, spacing: 12) {
                    // Treasure chest icon (using emoji as placeholder for pixelated asset)
                    VStack {
                        Text("🪙")
                            .font(.system(size: 40))
                    }
                    .frame(width: 60, alignment: .top)

                    // Title and category
                    VStack(alignment: .leading, spacing: 6) {
                        Text(questData.display_text)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            Text(questData.category)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)

                            Text("•")
                                .foregroundColor(.gray)

                            Text("from \(questData.brand_name)")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Spacer()

                // Bottom section: Reward amount
                HStack(spacing: 6) {
                    Text("+\(questData.reward_amount)g")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.843, blue: 0.0))  // Gold #FFD700

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Close/dismiss button (top-right corner)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(8)
            .help("Dismiss without opening")

            // Click-anywhere-to-open overlay
            ZStack {
                Color.clear
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpen()
            }
        }
        .frame(width: 400, height: 250)
    }
}

// Preview for development
#Preview {
    QuestCardView(
        questData: QuestData(
            quest_id: "test-123",
            display_text: "Check out the latest DevTools",
            tracking_url: "https://example.com",
            reward_amount: 250,
            brand_name: "Vercel",
            category: "DevTool"
        ),
        onOpen: { print("Opened") },
        onDismiss: { print("Dismissed") }
    )
    .frame(width: 400, height: 250)
}
