import Foundation

enum MeetingSummaryClient {
    private static let openAIURL = URL(string: "https://api.openai.com/v1/responses")!
    private static let openRouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let defaultOpenAIModel = "gpt-5-mini"
    private static let defaultOpenRouterModel = "openai/gpt-5-mini"

    private static let summaryInstructions = """
    You are a meeting notes assistant. Given a raw meeting transcript, produce structured meeting notes with the following sections:

    ## Meeting Summary
    A 2-3 sentence overview of what was discussed.

    ## Key Discussion Points
    - Bullet points of main topics discussed

    ## Decisions Made
    - Bullet points of any decisions reached

    ## Action Items
    - [ ] Bullet points of tasks assigned or agreed upon, with owners if mentioned

    ## Notable Quotes
    - Any important or notable statements (if applicable)

    Keep it concise and professional. If a section has no content, write "None noted."
    """

    static func summarize(transcript: String, meetingTitle: String, config: AppConfig) async -> String {
        let backend = (config.meetingSummaryBackend.isEmpty ? MeetingSummaryBackendOption.openAI.backend : config.meetingSummaryBackend).lowercased()
        if backend == MeetingSummaryBackendOption.openRouter.backend {
            return await summarizeWithOpenRouter(transcript: transcript, meetingTitle: meetingTitle, config: config)
        }
        return await summarizeWithOpenAI(transcript: transcript, meetingTitle: meetingTitle, config: config)
    }

    private static func summarizeWithOpenAI(transcript: String, meetingTitle: String, config: AppConfig) async -> String {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? config.openAIAPIKey
        guard !apiKey.isEmpty else {
            return rawTranscriptFallback(transcript: transcript, meetingTitle: meetingTitle)
        }

        let body: [String: Any] = [
            "model": config.openAIModel.isEmpty ? (config.summaryModel.isEmpty ? defaultOpenAIModel : config.summaryModel) : config.openAIModel,
            "input": [
                ["role": "system", "content": summaryInstructions],
                ["role": "user", "content": "Meeting title: \(meetingTitle)\n\nRaw transcript:\n\(transcript)"],
            ],
            "reasoning": ["effort": "low"],
            "text": ["verbosity": "low"],
            "max_output_tokens": 1200,
        ]

        var request = URLRequest(url: openAIURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let text = extractOpenAIText(from: json),
                !text.isEmpty
            else {
                return rawTranscriptFallback(transcript: transcript, meetingTitle: meetingTitle)
            }
            return "# \(meetingTitle)\n\n\(text)"
        } catch {
            return rawTranscriptFallback(transcript: transcript, meetingTitle: meetingTitle)
        }
    }

    private static func summarizeWithOpenRouter(transcript: String, meetingTitle: String, config: AppConfig) async -> String {
        let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? config.openRouterAPIKey
        guard !apiKey.isEmpty else {
            return rawTranscriptFallback(transcript: transcript, meetingTitle: meetingTitle)
        }

        let model = config.openRouterModel.isEmpty ? (config.meetingSummaryModel.isEmpty ? defaultOpenRouterModel : config.meetingSummaryModel) : config.openRouterModel
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": summaryInstructions],
                ["role": "user", "content": "Meeting title: \(meetingTitle)\n\nRaw transcript:\n\(transcript)"],
            ],
            "max_tokens": 1200,
        ]

        var request = URLRequest(url: openRouterURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(AppIdentity.displayName, forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let text = extractOpenRouterText(from: json),
                !text.isEmpty
            else {
                return rawTranscriptFallback(transcript: transcript, meetingTitle: meetingTitle)
            }
            return "# \(meetingTitle)\n\n\(text)"
        } catch {
            return rawTranscriptFallback(transcript: transcript, meetingTitle: meetingTitle)
        }
    }

    private static func extractOpenAIText(from payload: [String: Any]) -> String? {
        if let outputText = payload["output_text"] as? String, !outputText.isEmpty {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let output = payload["output"] as? [[String: Any]] ?? []
        for item in output where (item["type"] as? String) == "message" {
            let content = item["content"] as? [[String: Any]] ?? []
            for entry in content {
                if let text = entry["text"] as? String, !text.isEmpty {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    private static func extractOpenRouterText(from payload: [String: Any]) -> String? {
        let choices = payload["choices"] as? [[String: Any]] ?? []
        guard let message = choices.first?["message"] as? [String: Any] else {
            return nil
        }
        if let content = message["content"] as? String, !content.isEmpty {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let content = message["content"] as? [[String: Any]] {
            let parts = content.compactMap { entry -> String? in
                guard (entry["type"] as? String) == "text", let text = entry["text"] as? String, !text.isEmpty else {
                    return nil
                }
                return text
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func rawTranscriptFallback(transcript: String, meetingTitle: String) -> String {
        "# \(meetingTitle)\n\n## Raw Transcript\n\n\(transcript)"
    }
}
