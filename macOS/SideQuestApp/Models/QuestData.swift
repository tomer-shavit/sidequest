import Foundation

struct QuestData: Codable {
    let quest_id: String
    let display_text: String
    let tracking_url: String
    let reward_amount: Int        // NEW: gold amount (e.g., 250)
    let brand_name: String        // NEW: company/brand name (e.g., "Vercel")
    let category: String          // NEW: quest category (e.g., "DevTool")
    
    enum CodingKeys: String, CodingKey {
        case quest_id
        case display_text
        case tracking_url
        case reward_amount
        case brand_name
        case category
    }
}

// For logging purposes (optional)
extension QuestData {
    var description: String {
        return "Quest(\(quest_id), '\(display_text)', reward=\(reward_amount)g, from=\(brand_name))"
    }
}