import Foundation
import AWSBedrockRuntime
import AWSSDKIdentity
@_spi(SmithyDocumentImpl) import Smithy

/// Streams AI explanations for UI elements via AWS Bedrock ConverseStream API.
/// Supports tool use for web research when the model needs additional context.
final class BedrockService: LLMProvider {
    let supportsToolUse = true
    private let client: BedrockRuntimeClient
    private let modelId: String
    // Web search service is now passed per-call via the protocol

    // System prompt is now in Prompts.system (LLMProvider.swift)

    /// Tool definition for web search.
    private static func makeToolConfig() -> BedrockRuntimeClientTypes.ToolConfiguration {
        let queryProps: [String: SmithyDocument] = [
            "type": StringDocument(value: "string"),
            "description": StringDocument(value:
                "Search query, e.g. 'GitHub pull request review documentation'"
            ),
        ]
        let properties: [String: SmithyDocument] = [
            "query": StringMapDocument(value: queryProps),
        ]
        let schema: [String: SmithyDocument] = [
            "type": StringDocument(value: "object"),
            "properties": StringMapDocument(value: properties),
            "required": ListDocument(value: [StringDocument(value: "query")]),
        ]

        let searchTool = BedrockRuntimeClientTypes.ToolSpecification(
            description: "Search the web for documentation about a UI element, application feature, or setting",
            inputSchema: .json(Document(StringMapDocument(value: schema))),
            name: "web_search"
        )

        return BedrockRuntimeClientTypes.ToolConfiguration(
            tools: [.toolspec(searchTool)]
        )
    }

    init(region: String, modelId: String, awsProfile: String? = nil) throws {
        self.modelId = modelId

        if let awsProfile, !awsProfile.isEmpty {
            let resolver = try ProfileAWSCredentialIdentityResolver(profileName: awsProfile)
            let config = try BedrockRuntimeClient.BedrockRuntimeClientConfig(
                awsCredentialIdentityResolver: resolver,
                region: region
            )
            self.client = BedrockRuntimeClient(config: config)
        } else {
            let config = try BedrockRuntimeClient.BedrockRuntimeClientConfig(region: region)
            self.client = BedrockRuntimeClient(config: config)
        }
    }

    // MARK: - LLMProvider conformance

    func streamExplanation(
        prompt: String, systemPrompt: String, screenshot: Data?,
        modelId: String?, temperature: Float, maxTokens: Int,
        webSearch: WebFetchService?
    ) -> AsyncThrowingStream<String, Error> {
        return streamBedrockExplanation(
            prompt: prompt, systemPrompt: systemPrompt,
            screenshot: screenshot, modelId: modelId,
            temperature: temperature, maxTokens: maxTokens,
            webSearch: webSearch
        )
    }

    // MARK: - Bedrock-specific streaming

    /// Streams explanation for an ElementContext (convenience used by AppState).
    func streamExplanation(for element: ElementContext, screenshot: Data? = nil, modelId overrideModelId: String? = nil, webSearch: WebFetchService? = nil) -> AsyncThrowingStream<String, Error> {
        return streamBedrockExplanation(
            prompt: element.promptDescription, systemPrompt: Prompts.system,
            screenshot: screenshot, modelId: overrideModelId,
            temperature: 0.2, maxTokens: 1024,
            webSearch: webSearch
        )
    }

    private func streamBedrockExplanation(
        prompt: String, systemPrompt: String, screenshot: Data?,
        modelId overrideModelId: String?, temperature: Float, maxTokens: Int,
        webSearch: WebFetchService?
    ) -> AsyncThrowingStream<String, Error> {
        let client = self.client
        let modelId = overrideModelId ?? self.modelId
        let webFetch = webSearch
        let toolConfig = webSearch != nil ? Self.makeToolConfig() : nil

        return AsyncThrowingStream { continuation in
            Task {
                // 60-second timeout prevents the stream from leaking if Bedrock hangs
                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(60))
                    continuation.finish(throwing: NSError(
                        domain: "BedrockService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Stream timed out after 60 seconds"]
                    ))
                }
                defer { timeoutTask.cancel() }

                do {
                    // Build initial user message
                    var contentBlocks: [BedrockRuntimeClientTypes.ContentBlock] = []
                    if let screenshot {
                        contentBlocks.append(.image(BedrockRuntimeClientTypes.ImageBlock(
                            format: .png,
                            source: .bytes(screenshot)
                        )))
                    }
                    contentBlocks.append(.text(prompt))

                    var messages: [BedrockRuntimeClientTypes.Message] = [
                        BedrockRuntimeClientTypes.Message(
                            content: contentBlocks,
                            role: .user
                        ),
                    ]

                    Log.info("Bedrock stream start, modelId=\(modelId)")
                    // Up to 3 rounds (initial + 2 tool-use follow-ups)
                    for round in 0..<3 {
                        let input = ConverseStreamInput(
                            inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration(
                                maxTokens: maxTokens,
                                temperature: temperature
                            ),
                            messages: messages,
                            modelId: modelId,
                            system: [.text(systemPrompt)],
                            toolConfig: toolConfig
                        )

                        let output = try await client.converseStream(input: input)
                        guard let stream = output.stream else {
                            continuation.finish()
                            return
                        }

                        // Collect this round's response
                        var assistantBlocks: [BedrockRuntimeClientTypes.ContentBlock] = []
                        var currentText = ""
                        var currentToolUseId: String?
                        var currentToolName: String?
                        var toolInputJson = ""
                        var stopReason: BedrockRuntimeClientTypes.StopReason?

                        for try await event in stream {
                            switch event {
                            case .contentblockstart(let e):
                                if case .tooluse(let t) = e.start {
                                    currentToolUseId = t.toolUseId
                                    currentToolName = t.name
                                    toolInputJson = ""
                                }
                            case .contentblockdelta(let e):
                                if case .text(let text) = e.delta {
                                    continuation.yield(text)
                                    currentText += text
                                } else if case .tooluse(let t) = e.delta {
                                    toolInputJson += t.input ?? ""
                                }
                            case .contentblockstop:
                                if let id = currentToolUseId {
                                    let inputDoc = Self.parseJSON(toolInputJson)
                                    assistantBlocks.append(.tooluse(
                                        BedrockRuntimeClientTypes.ToolUseBlock(
                                            input: inputDoc,
                                            name: currentToolName,
                                            toolUseId: id
                                        )
                                    ))
                                    currentToolUseId = nil
                                    currentToolName = nil
                                } else if !currentText.isEmpty {
                                    assistantBlocks.append(.text(currentText))
                                    currentText = ""
                                }
                            case .messagestop(let e):
                                stopReason = e.stopReason
                            default:
                                break
                            }
                        }

                        // Capture any trailing text
                        if !currentText.isEmpty {
                            assistantBlocks.append(.text(currentText))
                        }

                        Log.info("Bedrock round \(round) done, stopReason=\(String(describing: stopReason))")
                        // If model didn't request a tool, we're done
                        guard stopReason == .toolUse, let webFetch else { break }

                        // Execute tool calls and build the next turn
                        messages.append(BedrockRuntimeClientTypes.Message(
                            content: assistantBlocks, role: .assistant
                        ))

                        var toolResults: [BedrockRuntimeClientTypes.ContentBlock] = []
                        for block in assistantBlocks {
                            if case .tooluse(let toolUse) = block {
                                let query = Self.extractQuery(from: toolInputJson)
                                Log.info("Web search triggered")
                                let result = await webFetch.search(query: query)
                                Log.info("Web search complete, \(result.count) chars")
                                toolResults.append(.toolresult(
                                    BedrockRuntimeClientTypes.ToolResultBlock(
                                        content: [.text(result)],
                                        toolUseId: toolUse.toolUseId
                                    )
                                ))
                            }
                        }
                        messages.append(BedrockRuntimeClientTypes.Message(
                            content: toolResults, role: .user
                        ))
                    }

                    continuation.finish()
                } catch {
                    Log.error("Bedrock stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - JSON / Document helpers

    private static func parseJSON(_ json: String) -> Document {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
        else { return Document(NullDocument()) }
        return Document(toSmithyDocument(obj))
    }

    private static func extractQuery(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = dict["query"] as? String
        else { return "unknown" }
        return query
    }

    private static func toSmithyDocument(_ value: Any) -> SmithyDocument {
        switch value {
        case let dict as [String: Any]:
            return StringMapDocument(value: dict.mapValues { toSmithyDocument($0) })
        case let arr as [Any]:
            return ListDocument(value: arr.map { toSmithyDocument($0) })
        case let str as String:
            return StringDocument(value: str)
        case let num as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(num) {
                return BooleanDocument(value: num.boolValue)
            }
            return DoubleDocument(value: num.doubleValue)
        default:
            return NullDocument()
        }
    }
}
