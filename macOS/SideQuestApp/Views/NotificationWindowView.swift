import SwiftUI

struct NotificationWindowView: View {
    let questData: QuestData
    let onOpen: () -> Void
    let onDismiss: () -> Void
    let dismissDuration: Double

    var body: some View {
        QuestCardView(
            questData: questData,
            onOpen: onOpen,
            onDismiss: onDismiss,
            dismissDuration: dismissDuration
        )
        .frame(width: 370, height: 110)
    }
}

#if DEBUG
struct NotificationWindowView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationWindowView(
            questData: QuestData(
                quest_id: "test-123",
                display_text: "Explore new features",
                tracking_url: "https://example.com",
                reward_amount: 150,
                brand_name: "GitHub",
                category: "DevTool"
            ),
            onOpen: { print("Opened") },
            onDismiss: { print("Dismissed") },
            dismissDuration: 12.0
        )
    }
}
#endif
