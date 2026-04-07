import Foundation

/// Supported LLM provider types.
enum LLMProviderType: String, CaseIterable, Codable {
    case bedrock = "AWS Bedrock"
    case anthropic = "Anthropic API"
    case openai = "OpenAI"
    case openaiCompatible = "OpenAI-Compatible (Local)"
}

/// Common interface for all LLM providers.
protocol LLMProvider {
    /// Streams explanation text chunks given a prompt and optional screenshot.
    /// When webSearch is provided and the model requests a search, the provider
    /// executes the search and feeds results back to the model.
    func streamExplanation(
        prompt: String,
        systemPrompt: String,
        screenshot: Data?,
        modelId: String?,
        temperature: Float,
        maxTokens: Int,
        webSearch: WebFetchService?
    ) -> AsyncThrowingStream<String, Error>
}

/// Shared system prompt used by all providers.
enum Prompts {
    static let system = """
        You explain macOS UI elements. You receive accessibility metadata about the element \
        under the user's cursor, and often a screenshot of the window for visual context.

        Identification:
        - The Browser URL (if provided) is the strongest signal for identifying web applications. \
          For example: github.com = GitHub, console.aws.amazon.com = AWS Console, \
          linear.app = Linear.
        - Use the screenshot to confirm the application context. The URL bar, page content, \
          and visible UI all help identify the actual application.
        - A button inside a browser tab belongs to the WEB APPLICATION shown, not to the browser.

        Research:
        - You have a web_search tool available but should RARELY use it. \
          Most UI elements can be explained from the metadata, screenshot, and URL alone.
        - Only search when you encounter a genuinely unfamiliar application-specific feature \
          that you cannot explain from the visible context.
        - Default to answering directly without searching.

        Selected text:
        - If selected text is provided, explain that text in the context of the application \
          and the element it appears in. What does it mean? Why is it relevant?
        - If the selected text is code, a config value, or an error message, explain it specifically.

        Region screenshot:
        - If you receive only a screenshot with no element metadata, describe what you see \
          in the captured region and explain it in context.

        Format:
        - First sentence: what this element (or selected text, or region) means in context.
        - Second sentence (if helpful): why someone would use it or change it.
        - Third sentence (only for destructive or risky actions): what happens if activated.
        - Use the parent chain for additional hierarchy context.
        - Max 3 sentences. Write like a tooltip, not a conversation.
        - Never say "I" or refer to yourself.
        """
}
