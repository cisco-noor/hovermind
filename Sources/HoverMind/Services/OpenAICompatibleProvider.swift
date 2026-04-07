import Foundation

/// Streams explanations via OpenAI-compatible chat completions API with optional function calling.
/// Works with OpenAI, Ollama (localhost:11434), LM Studio (localhost:1234),
/// and any server implementing /v1/chat/completions.
final class OpenAICompatibleProvider: LLMProvider {
    private let baseURL: String
    private let apiKey: String?

    init(baseURL: String, apiKey: String? = nil) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
    }

    func streamExplanation(
        prompt: String, systemPrompt: String, screenshot: Data?,
        modelId: String?, temperature: Float, maxTokens: Int,
        webSearch: WebFetchService?
    ) -> AsyncThrowingStream<String, Error> {
        let url = baseURL
        let key = apiKey
        let model = modelId ?? "gpt-4o"

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var userContent: [[String: Any]] = []
                    if let screenshot {
                        userContent.append([
                            "type": "image_url",
                            "image_url": ["url": "data:image/png;base64,\(screenshot.base64EncodedString())"],
                        ])
                    }
                    userContent.append(["type": "text", "text": prompt])

                    var messages: [[String: Any]] = [
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": userContent],
                    ]

                    let toolDef: [[String: Any]] = webSearch != nil ? [[
                        "type": "function",
                        "function": [
                            "name": "web_search",
                            "description": "Search the web for documentation about a UI element or application feature",
                            "parameters": [
                                "type": "object",
                                "properties": ["query": ["type": "string", "description": "Search query"]],
                                "required": ["query"],
                            ],
                        ],
                    ]] : []

                    for _ in 0..<3 {
                        var body: [String: Any] = [
                            "model": model,
                            "max_tokens": maxTokens,
                            "temperature": temperature,
                            "stream": true,
                            "messages": messages,
                        ]
                        if !toolDef.isEmpty { body["tools"] = toolDef }

                        var request = URLRequest(url: URL(string: "\(url)/v1/chat/completions")!)
                        request.httpMethod = "POST"
                        request.setValue("application/json", forHTTPHeaderField: "content-type")
                        if let key, !key.isEmpty {
                            request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
                        }
                        request.httpBody = try JSONSerialization.data(withJSONObject: body)
                        request.timeoutInterval = 30

                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                            throw NSError(domain: "OpenAICompatibleProvider", code: code,
                                          userInfo: [NSLocalizedDescriptionKey: "API error (HTTP \(code))"])
                        }

                        // Parse SSE, collect function calls
                        var toolCallId: String?
                        var toolCallName: String?
                        var toolCallArgs = ""
                        var hasToolCall = false

                        for try await line in bytes.lines {
                            guard !Task.isCancelled else { break }
                            guard line.hasPrefix("data: ") else { continue }
                            let json = String(line.dropFirst(6))
                            guard json != "[DONE]",
                                  let data = json.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                  let choices = obj["choices"] as? [[String: Any]],
                                  let delta = choices.first?["delta"] as? [String: Any]
                            else { continue }

                            // Text content
                            if let text = delta["content"] as? String {
                                continuation.yield(text)
                            }

                            // Tool/function call
                            if let toolCalls = delta["tool_calls"] as? [[String: Any]],
                               let tc = toolCalls.first {
                                hasToolCall = true
                                if let fn = tc["function"] as? [String: Any] {
                                    if let name = fn["name"] as? String { toolCallName = name }
                                    if let args = fn["arguments"] as? String { toolCallArgs += args }
                                }
                                if let id = tc["id"] as? String { toolCallId = id }
                            }

                            // Check finish reason
                            if let finish = choices.first?["finish_reason"] as? String,
                               finish == "tool_calls" || finish == "function_call" {
                                hasToolCall = true
                            }
                        }

                        guard hasToolCall, let ws = webSearch,
                              let id = toolCallId else { break }

                        // Execute the function call
                        let args = (try? JSONSerialization.jsonObject(
                            with: toolCallArgs.data(using: .utf8) ?? Data()
                        ) as? [String: Any]) ?? [:]
                        let query = args["query"] as? String ?? "unknown"
                        Log.info("Web search triggered")
                        let result = await ws.search(query: query)
                        Log.info("Web search complete, \(result.count) chars")

                        messages.append([
                            "role": "assistant",
                            "tool_calls": [[
                                "id": id, "type": "function",
                                "function": ["name": toolCallName ?? "web_search", "arguments": toolCallArgs],
                            ]],
                        ])
                        messages.append([
                            "role": "tool", "tool_call_id": id, "content": result,
                        ])
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
