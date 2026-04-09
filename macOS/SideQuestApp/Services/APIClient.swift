import Foundation
import os.log

enum APIError: Error {
    case networkError
    case networkTimeout
    case serverError
    case decodingError
    case invalidURL
}

actor APIClient {
    private let apiBaseURL: URL
    private let bearerToken: String
    
    init(apiBaseURL: String, bearerToken: String) {
        guard let url = URL(string: apiBaseURL) else {
            fatalError("Invalid API base URL: \(apiBaseURL)")
        }
        self.apiBaseURL = url
        self.bearerToken = bearerToken
    }
    
    func fetchQuest() async throws -> QuestData {
        // Construct /quest endpoint URL
        let questURL = apiBaseURL.appendingPathComponent("quest")
        
        // Create request with bearer token
        var request = URLRequest(url: questURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5.0  // 5s timeout for responsiveness
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.serverError
            }
            
            guard httpResponse.statusCode == 200 else {
                os_log("API error: HTTP %d", log: .default, type: .error, httpResponse.statusCode)
                throw APIError.serverError
            }
            
            // Decode quest data
            let decoder = JSONDecoder()
            let quest = try decoder.decode(QuestData.self, from: data)
            return quest
            
        } catch URLError.timedOut {
            os_log("API timeout after 5 seconds", log: .default, type: .error)
            throw APIError.networkTimeout
        } catch is DecodingError {
            os_log("Failed to decode quest response", log: .default, type: .error)
            throw APIError.decodingError
        } catch {
            os_log("API error: %@", log: .default, type: .error, error as CVarArg)
            throw APIError.networkError
        }
    }
}