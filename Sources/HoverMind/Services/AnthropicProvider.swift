import Foundation

/// Streams explanations via the Anthropic Messages API with optional tool use.
final class AnthropicProvider: LLMProvider {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func streamExplanation(
        prompt: String, systemPrompt: String, screenshot: Data?,
        modelId: String?, temperature: Float, maxTokens: Int,
        webSearch: WebFetchService?
    ) -> AsyncThrowingStream<String, Error> {
        let key = apiKey
        let model = modelId ?? "claude-sonnet-4-20250514"

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var content: [[String: Any]] = []
                    if let screenshot {
                        content.append([
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": screenshot.base64EncodedString(),
                            ],
                        ])
                    }
                    content.append(["type": "text", "text": prompt])

                    var messages: [[String: Any]] = [
                        ["role": "user", "content": content],
                    ]

                    let toolDef: [[String: Any]] = webSearch != nil ? [[
                        "name": "web_search",
                        "description": "Search the web for documentation about a UI element or application feature",
                        "input_schema": [
                            "type": "object",
                            "properties": ["query": ["type": "string", "description": "Search query"]],
                            "required": ["query"],
                        ],
                    ]] : []

                    // Up to 3 rounds (initial + 2 tool follow-ups)
                    for _ in 0..<3 {
                        var body: [String: Any] = [
                            "model": model,
                            "max_tokens": maxTokens,
                            "temperature": temperature,
                            "system": systemPrompt,
                            "stream": true,
                            "messages": messages,
                        ]
                        if !toolDef.isEmpty { body["tools"] = toolDef }

                        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                        request.httpMethod = "POST"
                        request.setValue(key, forHTTPHeaderField: "x-api-key")
                        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                        request.setValue("application/json", forHTTPHeaderField: "content-type")
                        request.httpBody = try JSONSerialization.data(withJSONObject: body)

                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                            throw NSError(domain: "AnthropicProvider", code: code,
                                          userInfo: [NSLocalizedDescriptionKey: "API error (HTTP \(code))"])
                        }

                        // Parse SSE, collect tool use blocks
                        var assistantContent: [[String: Any]] = []
                        var currentText = ""
                        var toolUseId: String?
                        var toolName: String?
                        var toolInputJson = ""
                        var stopReason: String?

                        for try await line in bytes.lines {
                            guard !Task.isCancelled else { break }
                            guard line.hasPrefix("data: ") else { continue }
                            let json = String(line.dropFirst(6))
                            guard let data = json.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else { continue }

                            let type = obj["type"] as? String
                            if type == "content_block_start",
                               let cb = obj["content_block"] as? [String: Any],
                               cb["type"] as? String == "tool_use" {
                                toolUseId = cb["id"] as? String
                                toolName = cb["name"] as? String
                                toolInputJson = ""
                            } else if type == "content_block_delta",
                                      let delta = obj["delta"] as? [String: Any] {
                                if let text = delta["text"] as? String {
                                    continuation.yield(text)
                                    currentText += text
                                } else if let partial = delta["partial_json"] as? String {
                                    toolInputJson += partial
                                }
                            } else if type == "content_block_stop" {
                                if let id = toolUseId {
                                    let input = (try? JSONSerialization.jsonObject(
                                        with: toolInputJson.data(using: .utf8) ?? Data()
                                    ) as? [String: Any]) ?? [:]
                                    assistantContent.append([
                                        "type": "tool_use", "id": id,
                                        "name": toolName ?? "web_search", "input": input,
                                    ])
                                    toolUseId = nil
                                } else if !currentText.isEmpty {
                                    assistantContent.append(["type": "text", "text": currentText])
                                    currentText = ""
                                }
                            } else if type == "message_delta",
                                      let delta = obj["delta"] as? [String: Any] {
                                stopReason = delta["stop_reason"] as? String
                            }
                        }
                        if !currentText.isEmpty {
                            assistantContent.append(["type": "text", "text": currentText])
                        }

                        guard stopReason == "tool_use", let ws = webSearch else { break }

                        // Execute tool calls
                        messages.append(["role": "assistant", "content": assistantContent])
                        var toolResults: [[String: Any]] = []
                        for block in assistantContent {
                            guard block["type"] as? String == "tool_use",
                                  let id = block["id"] as? String,
                                  let input = block["input"] as? [String: Any],
                                  let query = input["query"] as? String
                            else { continue }
                            Log.info("Web search triggered")
                            let result = await ws.search(query: query)
                            Log.info("Web search complete, \(result.count) chars")
                            toolResults.append([
                                "type": "tool_result", "tool_use_id": id,
                                "content": result,
                            ])
                        }
                        messages.append(["role": "user", "content": toolResults])
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
