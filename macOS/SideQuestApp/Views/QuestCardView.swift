import SwiftUI

struct QuestCardView: View {
    let questData: QuestData
    let onOpen: () -> Void
    let onDismiss: () -> Void
    let dismissDuration: Double

    @State private var progressWidth: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Dark purple background with rounded corners
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.15, green: 0.04, blue: 0.28))
                .overlay(
                    // Gold progress bar at bottom
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            HStack {
                                Spacer()
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.85, green: 0.65, blue: 0.0),
                                                Color(red: 1.0, green: 0.843, blue: 0.0)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * progressWidth, height: 3)
                                    .animation(.linear(duration: dismissDuration), value: progressWidth)
                            }
                        }
                        .frame(height: 3)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 14)
                        )
                    }
                )

            // Content
            HStack(spacing: 12) {
                // Lootbox icon (no background)
                LootboxIcon()
                    .frame(width: 72, height: 72)

                // Text content
                VStack(alignment: .leading, spacing: 6) {
                    // Quest title
                    Text(questData.display_text)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    // Category badge + sponsor
                    HStack(spacing: 6) {
                        Text(questData.category.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.15, green: 0.04, blue: 0.28))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(red: 0.9, green: 0.8, blue: 0.4))
                            )

                        Text("•")
                            .foregroundColor(Color.white.opacity(0.4))
                            .font(.system(size: 9))

                        Text("from \(questData.brand_name)")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.7))
                    }

                    // Reward + loot found
                    HStack(spacing: 6) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 1.0, green: 0.843, blue: 0.0))

                        Text("+\(questData.reward_amount)g")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.843, blue: 0.0))

                        Text("LOOT FOUND")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.9, green: 0.8, blue: 0.4).opacity(0.8))
                    }
                }

                Spacer()
            }
            .padding(.leading, 12)
            .padding(.vertical, 12)
            .padding(.trailing, 36)

            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(8)

            // Click-anywhere overlay
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpen()
                }
        }
        .frame(width: 370, height: 110)
        .onAppear {
            // Start the countdown animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                progressWidth = 0.0
            }
        }
    }
}

// MARK: - Lootbox Icon

struct LootboxIcon: View {
    var body: some View {
        if let bundlePath = Bundle.main.path(forResource: "lootbox", ofType: "png"),
           let nsImage = NSImage(contentsOfFile: bundlePath) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Text("🪙")
                .font(.system(size: 30))
        }
    }
}

#if DEBUG
struct QuestCardView_Previews: PreviewProvider {
    static var previews: some View {
        QuestCardView(
            questData: QuestData(
                quest_id: "test-123",
                display_text: "Speed Up Your PostgreSQL Queries",
                tracking_url: "https://example.com",
                reward_amount: 250,
                brand_name: "Supabase",
                category: "DevTool"
            ),
            onOpen: { print("Opened") },
            onDismiss: { print("Dismissed") },
            dismissDuration: 12.0
        )
        .frame(width: 370, height: 110)
    }
}
#endif
