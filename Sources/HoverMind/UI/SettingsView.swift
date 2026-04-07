import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            providerTab
                .tabItem { Label("Provider", systemImage: "cloud") }
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "gearshape") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "textformat.size") }
            hotkeysTab
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Provider Tab

    private var providerTab: some View {
        Form {
            Picker("Provider", selection: $appState.providerType) {
                ForEach(LLMProviderType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            switch appState.providerType {
            case .bedrock:
                Section("AWS Bedrock Configuration") {
                    TextField("Region", text: $appState.awsRegion)
                        .help("AWS region (e.g., us-west-2)")
                    TextField("Model ID", text: $appState.modelId)
                        .help("Cross-region inference profile ID (e.g., us.anthropic.claude-opus-4-6-v1)")
                    TextField("AWS Profile", text: $appState.awsProfile, prompt: Text("default"))
                    Text("Profile name from **~/.aws/credentials**. Leave empty for default credential chain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .anthropic:
                Section("Anthropic API Configuration") {
                    SecureField("API Key", text: $appState.anthropicApiKey)
                        .help("Your Anthropic API key from console.anthropic.com")
                    TextField("Model ID", text: $appState.modelId, prompt: Text("claude-sonnet-4-20250514"))
                    Text("Get your API key at **console.anthropic.com/settings/keys**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .openai:
                Section("OpenAI Configuration") {
                    SecureField("API Key", text: $appState.openaiApiKey)
                        .help("Your OpenAI API key from platform.openai.com")
                    TextField("Model ID", text: $appState.modelId, prompt: Text("gpt-4o"))
                    Text("Get your API key at **platform.openai.com/api-keys**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .openaiCompatible:
                Section("OpenAI-Compatible Server") {
                    TextField("Base URL", text: $appState.openaiCompatibleBaseURL)
                    HStack {
                        Text("Presets:")
                            .font(.caption)
                        Button("Ollama") { appState.openaiCompatibleBaseURL = "http://localhost:11434" }
                            .buttonStyle(.link)
                            .font(.caption)
                        Button("LM Studio") { appState.openaiCompatibleBaseURL = "http://localhost:1234" }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                    SecureField("API Key (optional)", text: $appState.openaiCompatibleApiKey)
                        .help("Not needed for most local servers")
                    TextField("Model ID", text: $appState.modelId, prompt: Text("llama3.1"))
                    Text("Works with Ollama, LM Studio, llama.cpp, and any OpenAI-compatible server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Advanced") {
                HStack {
                    Text("Temperature: \(String(format: "%.1f", appState.temperature))")
                    Slider(value: $appState.temperature, in: 0...1, step: 0.1)
                }
                HStack {
                    Text("Max tokens: \(appState.maxTokens)")
                    Slider(value: Binding(
                        get: { Double(appState.maxTokens) },
                        set: { appState.maxTokens = Int($0) }
                    ), in: 256...4096, step: 256)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Behavior Tab

    private var behaviorTab: some View {
        Form {
            Section("Hover") {
                Slider(value: $appState.debounceMs, in: 100...1000, step: 50) {
                    Text("Hover delay: \(Int(appState.debounceMs))ms")
                }
                Toggle("Keep tooltip visible after releasing Option", isOn: $appState.persistTooltips)
            }

            Section("Dual Model") {
                Toggle("Fast + Deep mode", isOn: $appState.dualModel)
                    .help("Show a fast response, then replace with a deeper analysis using screenshots")
                if appState.dualModel {
                    TextField("Fast Model ID", text: $appState.fastModelId)
                        .help("Model for the instant response (can differ from main model)")
                }
            }

            Section("Web Search") {
                Toggle("Enable web search", isOn: $appState.webSearchEnabled)
                    .help("Let the model search the web when it needs documentation about a feature")
                if appState.webSearchEnabled {
                    Picker("Search provider", selection: $appState.webSearchProvider) {
                        ForEach(WebSearchProvider.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    if appState.webSearchProvider == .brave {
                        SecureField("Brave API Key", text: $appState.braveApiKey)
                        Text("Free tier at [brave.com/search/api](https://brave.com/search/api/)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if appState.webSearchProvider == .google {
                        SecureField("Google API Key", text: $appState.googleApiKey)
                        TextField("Search Engine ID", text: $appState.googleSearchEngineId)
                        Text("Set up at [programmablesearchengine.google.com](https://programmablesearchengine.google.com)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Voice") {
                Toggle("Read tooltip aloud", isOn: $appState.ttsEnabled)
                if appState.ttsEnabled {
                    Picker("Voice", selection: $appState.ttsVoiceId) {
                        Text("System Default").tag("")
                        ForEach(TTSService.availableVoices, id: \.id) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    HStack {
                        Text("Volume")
                        Slider(value: $appState.ttsVolume, in: 0...1, step: 0.1)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Section("Tooltip") {
                HStack {
                    Text("Font size: \(Int(appState.fontSize))pt")
                    Slider(value: $appState.fontSize, in: 10...18, step: 1)
                }
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(.system(size: appState.fontSize))
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Hotkeys Tab

    private var hotkeysTab: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Hover tooltip") {
                    Text("Hold **Option** and hover")
                }
                LabeledContent("Region select") {
                    Text("**Cmd+Option**, click two corners")
                }
                LabeledContent("Dismiss tooltip") {
                    Text("Release **Option** or click **X**")
                }
            }
        }
        .formStyle(.grouped)
    }
}
