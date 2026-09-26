import Foundation

/// Optional external provider. The API key is supplied by the user in Settings
/// and stored in the Keychain; nothing is hard-coded. Content is sent to OpenAI
/// only when the user explicitly selects this provider.
struct OpenAISummarizationProvider: SummarizationProvider {
    let displayName = "OpenAI"
    let isExternal = true

    let apiKey: String
    let model: String
    var endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    var session: URLSession = .shared

    /// Keep requests bounded; the tail of very long texts rarely changes the gist.
    let maxInputCharacters = 60_000

    func summarizeForListening(_ text: String, targetDuration: QuickListenDuration) async throws -> String {
        guard !apiKey.isEmpty else { throw SummarizationError.missingAPIKey }
        let input = String(text.prefix(maxInputCharacters))
        let targetWords = targetDuration.targetWords(forSourceWords: ReadingEstimator.wordCount(input))

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": SummarizationPrompt.instructions],
                ["role": "user", "content": SummarizationPrompt.request(for: input, targetWords: targetWords)],
            ],
        ]

        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard status == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw SummarizationError.badResponse(message)
        }
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummarizationError.badResponse("Empty response.")
        }
        return content
    }
}
