# HoverMind

Hold Option, hover over anything on your Mac, get an AI explanation. Buttons, links, settings, error messages, selected text. Every app.

## How it works

You hold Option and hover. A floating tooltip streams an explanation of whatever you're pointing at. HoverMind uses the macOS Accessibility API to read the element's role, label, and hierarchy, then sends that context (plus a window screenshot) to the LLM.

For web apps in a browser, HoverMind reads the URL bar so it can distinguish between the web app's UI and the browser's own controls.

### Features

- **Option + hover** on any element in any app
- **Highlighted text**: select text first, then hover to get it explained in context
- **Region capture** (Cmd+Option, click two corners): screenshot a rectangle and ask the LLM about it
- **Dual model**: get a fast answer in 1-2 seconds, watch it upgrade to a deeper one
- **Web lookup**: fetches documentation when the model doesn't recognize a feature
- **Read aloud**: macOS text-to-speech, configurable voice
- **Bring your own model**: AWS Bedrock, Anthropic API, OpenAI, Ollama, LM Studio, or any OpenAI-compatible endpoint

## Requirements

- macOS 14 (Sonoma) or later
- An LLM provider (see below)

## Install

1. Download **HoverMind-v0.1.0-macOS.zip** from the [latest release](https://github.com/cisco-noor/hovermind/releases/latest)
2. Unzip and move **HoverMind.app** to your Applications folder
3. Open HoverMind.app
4. Grant **Accessibility** permission when prompted (System Settings > Privacy & Security > Accessibility)
5. For region select and screenshots: also grant **Screen Recording** (System Settings > Privacy & Security > Screen Recording)

### Build from source

If you prefer to build it yourself:

```bash
git clone https://github.com/cisco-noor/hovermind.git
cd hovermind
swift build
./build-and-run.sh
```

Requires Swift 5.9+.

### Configure an LLM provider

Open Settings from the menu bar eye icon.

**Anthropic API**:
- Get an API key at [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
- Select "Anthropic API", paste the key
- Default model: `claude-sonnet-4-20250514`

**OpenAI**:
- Get an API key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
- Select "OpenAI", paste the key
- Default model: `gpt-4o`

**Ollama** (local, free, private):
- Install [Ollama](https://ollama.com), run `ollama pull llama3.1`
- Select "OpenAI-Compatible (Local)", click the Ollama preset
- Model: `llama3.1`

**LM Studio** (local):
- Install [LM Studio](https://lmstudio.ai), download a model, start the server
- Select "OpenAI-Compatible (Local)", click the LM Studio preset

**AWS Bedrock**:
- Configure credentials in `~/.aws/credentials`
- Select "AWS Bedrock", set region and model ID

## Usage

| Action | Hotkey |
|--------|--------|
| Hover tooltip | Hold **Option**, hover over any element |
| Region select | **Cmd+Option**, click two corners |
| Dismiss | Release **Option** or click **X** |

### Settings

- **Dual model**: fast answer first, replaced by a deeper one seconds later
- **Font size**: 10-18pt
- **Read aloud**: speaks the tooltip using a macOS voice you pick
- **Temperature**: 0.0 (deterministic) to 1.0 (creative)
- **Max tokens**: cap response length (256-4096)

## Architecture

```
Sources/HoverMind/
  App/
    HoverMindApp.swift              Entry point, menu bar scene
    AppState.swift                  Central coordinator
  Models/
    ElementContext.swift             Accessibility element data
  Services/
    LLMProvider.swift               Provider protocol and shared prompts
    BedrockService.swift            AWS Bedrock provider
    AnthropicProvider.swift         Anthropic Messages API provider
    OpenAICompatibleProvider.swift  OpenAI, Ollama, LM Studio provider
    AccessibilityService.swift      macOS AXUIElement inspection
    ScreenCaptureService.swift      Window and region screenshots
    HotkeyMonitor.swift             Global hotkey detection
    WebFetchService.swift           Web search for AI context
    TTSService.swift                Text-to-speech
    KeychainHelper.swift            Secure API key storage
    TooltipCache.swift              LRU cache with TTL
    Logger.swift                    Debug logging
  UI/
    TooltipPanel.swift              NSPanel positioning
    TooltipView.swift               SwiftUI tooltip content
    SettingsView.swift              Tabbed preferences
    MenuBarView.swift               Menu bar dropdown
    RegionSelectOverlay.swift       Click-click region selection
```

API keys go into the macOS Keychain.

## Privacy

HoverMind runs locally on your Mac. Here's what leaves your machine and what stays:

**Sent to your LLM provider** (only when you hover with Option held):
- Accessibility metadata: element role, label, title, value, parent hierarchy
- Browser URL bar content (for identifying web apps)
- Selected text (if any is highlighted)
- A screenshot of the focused window (for visual context)

**Sent to a search engine** (only when web search is enabled and the LLM requests it):
- A search query the model constructs from the element context
- Search provider is configurable: DuckDuckGo (default, no API key), Brave Search, or Google Custom Search

**Stored locally**:
- API keys in macOS Keychain (`~/Library/Keychains/`)
- Settings in UserDefaults (no secrets)
- Debug logs at `~/Library/Logs/HoverMind/` (app name, element role, timing data only — no element content, screenshots, or API keys)

**Not stored**: screenshots, tooltip text, and API responses are held in memory only and discarded when the tooltip is dismissed. The LRU cache holds recent responses in memory for 5 minutes, then evicts them.

If you use a local provider (Ollama, LM Studio) with web search disabled, nothing leaves your machine.

## License

MIT
