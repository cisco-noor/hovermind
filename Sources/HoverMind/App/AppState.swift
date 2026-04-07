import SwiftUI

/// Central application state: coordinates hotkey monitoring, AX inspection, Bedrock streaming,
/// and tooltip display. Runs on @MainActor because it drives UI updates.
@MainActor @Observable
final class AppState {
    // MARK: - Observable state
    var isActive = false
    var isHotkeyHeld = false
    var tooltipText = ""
    var isStreaming = false
    var currentElement: ElementContext?
    var permissionGranted = false
    var cacheCount = 0

    // MARK: - Settings (persisted via UserDefaults)
    var providerType: LLMProviderType = .bedrock {
        didSet {
            UserDefaults.standard.set(providerType.rawValue, forKey: "providerType")
            // Set sensible default model when switching providers
            switch providerType {
            case .bedrock: modelId = "us.anthropic.claude-opus-4-6-v1"
            case .anthropic: modelId = "claude-sonnet-4-20250514"
            case .openai: modelId = "gpt-4o"
            case .openaiCompatible: modelId = "llama3.1"
            }
            resetProvider()
        }
    }
    var awsRegion: String = "us-west-2" {
        didSet { UserDefaults.standard.set(awsRegion, forKey: "awsRegion"); resetProvider() }
    }
    var modelId: String = "us.anthropic.claude-opus-4-6-v1" {
        didSet { UserDefaults.standard.set(modelId, forKey: "modelId") }
    }
    var awsProfile: String = "" {
        didSet { UserDefaults.standard.set(awsProfile, forKey: "awsProfile"); resetProvider() }
    }
    var anthropicApiKey: String = "" {
        didSet { KeychainHelper.save(key: "anthropicApiKey", value: anthropicApiKey); resetProvider() }
    }
    var openaiApiKey: String = "" {
        didSet { KeychainHelper.save(key: "openaiApiKey", value: openaiApiKey); resetProvider() }
    }
    var openaiCompatibleBaseURL: String = "http://localhost:11434" {
        didSet { UserDefaults.standard.set(openaiCompatibleBaseURL, forKey: "openaiCompatibleBaseURL"); resetProvider() }
    }
    var openaiCompatibleApiKey: String = "" {
        didSet { KeychainHelper.save(key: "openaiCompatibleApiKey", value: openaiCompatibleApiKey); resetProvider() }
    }
    var debounceMs: Double = 300 {
        didSet { UserDefaults.standard.set(debounceMs, forKey: "debounceMs") }
    }
    var persistTooltips: Bool = false {
        didSet {
            UserDefaults.standard.set(persistTooltips, forKey: "persistTooltips")
            tooltipPanel.viewModel.showDismiss = persistTooltips
        }
    }
    var dualModel: Bool = false {
        didSet { UserDefaults.standard.set(dualModel, forKey: "dualModel") }
    }
    var fastModelId: String = "us.anthropic.claude-sonnet-4-6-v1" {
        didSet { UserDefaults.standard.set(fastModelId, forKey: "fastModelId") }
    }
    var temperature: Float = 0.2 {
        didSet { UserDefaults.standard.set(temperature, forKey: "temperature") }
    }
    var maxTokens: Int = 1024 {
        didSet { UserDefaults.standard.set(maxTokens, forKey: "maxTokens") }
    }
    var fontSize: CGFloat = 12.0 {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "fontSize")
            tooltipPanel.viewModel.fontSize = fontSize
        }
    }
    var webSearchEnabled: Bool = true {
        didSet { UserDefaults.standard.set(webSearchEnabled, forKey: "webSearchEnabled") }
    }
    var webSearchProvider: WebSearchProvider = .duckduckgo {
        didSet {
            UserDefaults.standard.set(webSearchProvider.rawValue, forKey: "webSearchProvider")
            webFetchService.provider = webSearchProvider
        }
    }
    var braveApiKey: String = "" {
        didSet { KeychainHelper.save(key: "braveApiKey", value: braveApiKey); webFetchService.braveApiKey = braveApiKey }
    }
    var googleApiKey: String = "" {
        didSet { KeychainHelper.save(key: "googleApiKey", value: googleApiKey); webFetchService.googleApiKey = googleApiKey }
    }
    var googleSearchEngineId: String = "" {
        didSet { UserDefaults.standard.set(googleSearchEngineId, forKey: "googleSearchEngineId"); webFetchService.googleSearchEngineId = googleSearchEngineId }
    }
    var ttsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(ttsEnabled, forKey: "ttsEnabled") }
    }
    var ttsVoiceId: String = "" {
        didSet {
            UserDefaults.standard.set(ttsVoiceId, forKey: "ttsVoiceId")
            ttsService.voiceIdentifier = ttsVoiceId.isEmpty ? nil : ttsVoiceId
        }
    }
    var ttsVolume: Float = 1.0 {
        didSet {
            UserDefaults.standard.set(ttsVolume, forKey: "ttsVolume")
            ttsService.volume = ttsVolume
        }
    }

    // MARK: - Services
    let hotkeyMonitor = HotkeyMonitor()
    let accessibilityService = AccessibilityService()
    let screenCapture = ScreenCaptureService()
    let tooltipPanel = TooltipPanel()
    let regionOverlay = RegionSelectOverlay()
    let cache = TooltipCache()
    let ttsService = TTSService()
    let webFetchService = WebFetchService()

    /// Returns the web search service if enabled, nil otherwise.
    private var activeWebSearch: WebFetchService? {
        webSearchEnabled ? webFetchService : nil
    }
    private var bedrockService: BedrockService? // Keep for Bedrock-specific ElementContext API
    private var currentProvider: (any LLMProvider)?
    private var debounceTask: Task<Void, Never>?
    private var deepModelTask: Task<Void, Never>?

    private func resetProvider() {
        currentProvider = nil
        bedrockService = nil
    }

    init() {
        let defaults = UserDefaults.standard
        // Provider
        if let pt = defaults.string(forKey: "providerType"),
           let type = LLMProviderType(rawValue: pt) { providerType = type }
        if let region = defaults.string(forKey: "awsRegion") { awsRegion = region }
        if let model = defaults.string(forKey: "modelId") { modelId = model }
        if let profile = defaults.string(forKey: "awsProfile"), !profile.isEmpty {
            awsProfile = profile
        } else if let envProfile = ProcessInfo.processInfo.environment["AWS_PROFILE"] {
            awsProfile = envProfile
        }
        // Load API keys from Keychain
        anthropicApiKey = KeychainHelper.load(key: "anthropicApiKey") ?? ""
        openaiApiKey = KeychainHelper.load(key: "openaiApiKey") ?? ""
        openaiCompatibleApiKey = KeychainHelper.load(key: "openaiCompatibleApiKey") ?? ""
        if let url = defaults.string(forKey: "openaiCompatibleBaseURL"), !url.isEmpty {
            openaiCompatibleBaseURL = url
        }
        // Behavior
        let d = defaults.double(forKey: "debounceMs")
        if d > 0 { debounceMs = d }
        persistTooltips = defaults.bool(forKey: "persistTooltips")
        tooltipPanel.viewModel.showDismiss = persistTooltips
        dualModel = defaults.bool(forKey: "dualModel")
        if let fast = defaults.string(forKey: "fastModelId"), !fast.isEmpty {
            fastModelId = fast
        }
        // Advanced
        let t = defaults.float(forKey: "temperature")
        if t > 0 { temperature = t }
        let mt = defaults.integer(forKey: "maxTokens")
        if mt > 0 { maxTokens = mt }
        // Appearance
        let fs = defaults.double(forKey: "fontSize")
        if fs > 0 { fontSize = CGFloat(fs) }
        tooltipPanel.viewModel.fontSize = fontSize
        // TTS
        // Web search
        if defaults.object(forKey: "webSearchEnabled") != nil {
            webSearchEnabled = defaults.bool(forKey: "webSearchEnabled")
        }
        if let wsp = defaults.string(forKey: "webSearchProvider"),
           let provider = WebSearchProvider(rawValue: wsp) {
            webSearchProvider = provider
            webFetchService.provider = provider
        }
        braveApiKey = KeychainHelper.load(key: "braveApiKey") ?? ""
        webFetchService.braveApiKey = braveApiKey.isEmpty ? nil : braveApiKey
        googleApiKey = KeychainHelper.load(key: "googleApiKey") ?? ""
        webFetchService.googleApiKey = googleApiKey.isEmpty ? nil : googleApiKey
        if let gse = defaults.string(forKey: "googleSearchEngineId"), !gse.isEmpty {
            googleSearchEngineId = gse
            webFetchService.googleSearchEngineId = gse
        }
        // TTS
        ttsEnabled = defaults.bool(forKey: "ttsEnabled")
        ttsVoiceId = defaults.string(forKey: "ttsVoiceId") ?? ""
        if !ttsVoiceId.isEmpty { ttsService.voiceIdentifier = ttsVoiceId }
        let vol = defaults.float(forKey: "ttsVolume")
        if vol > 0 { ttsVolume = vol; ttsService.volume = vol }

        permissionGranted = AccessibilityService.isTrusted
        Log.info("Startup: AX=\(permissionGranted) ScreenRec=\(ScreenCaptureService.hasScreenRecordingPermission)")
        setupCallbacks()
        tooltipPanel.viewModel.onDismiss = { [weak self] in
            Task { @MainActor in self?.dismissTooltip() }
        }

        if permissionGranted {
            Task { @MainActor in self.start() }
        }
    }

    // MARK: - Lifecycle

    func start() {
        permissionGranted = AccessibilityService.isTrusted
        guard permissionGranted else { return }
        hotkeyMonitor.start()
        isActive = true
        initProviderIfNeeded()
    }

    func recheckPermission() {
        permissionGranted = AccessibilityService.isTrusted
        if permissionGranted && !isActive { start() }
    }

    func stop() {
        hotkeyMonitor.stop()
        dismissTooltip()
        debounceTask?.cancel()
        deepModelTask?.cancel()
        isActive = false
    }

    // MARK: - Event handling

    private func setupCallbacks() {
        hotkeyMonitor.onHotkeyStateChanged = { [weak self] held in
            Task { @MainActor in self?.handleHotkeyChange(held) }
        }
        hotkeyMonitor.onMouseMoved = { [weak self] point in
            Task { @MainActor in self?.handleMouseMove(point) }
        }
        hotkeyMonitor.onRegionSelectTriggered = { [weak self] in
            Task { @MainActor in self?.startRegionSelect() }
        }
        regionOverlay.onRegionSelected = { [weak self] rect in
            Task { @MainActor in self?.explainRegion(rect) }
        }
    }

    private func handleHotkeyChange(_ held: Bool) {
        isHotkeyHeld = held
        if held {
            handleMouseMove(NSEvent.mouseLocation)
        } else {
            debounceTask?.cancel()
            deepModelTask?.cancel()
            if persistTooltips && !tooltipText.isEmpty {
                tooltipPanel.viewModel.showDismiss = true
            } else {
                dismissTooltip()
            }
        }
    }

    func dismissTooltip() {
        tooltipPanel.hide()
        ttsService.stop()
        currentElement = nil
        tooltipText = ""
    }

    private func handleMouseMove(_ point: NSPoint) {
        guard isHotkeyHeld else { return }
        debounceTask?.cancel()
        debounceTask = Task { [debounceMs] in
            try? await Task.sleep(for: .milliseconds(debounceMs))
            guard !Task.isCancelled else { return }
            await inspectAndExplain(at: point)
        }
    }

    // MARK: - Core logic

    private func inspectAndExplain(at screenPoint: NSPoint) async {
        guard let element = accessibilityService.elementAt(screenPoint: screenPoint) else {
            Log.info("[HoverMind] No element at cursor position")
            return
        }

        if let current = currentElement, current.cacheKey == element.cacheKey { return }
        currentElement = element

        let appName = element.appName
        let roleName = element.roleDescription ?? element.role
        Log.info("[HoverMind] Inspecting: \(appName) / \(roleName)")

        // Cache hit
        if let cached = cache.get(key: element.cacheKey) {
            tooltipText = cached
            tooltipPanel.updateContent(text: cached, isStreaming: false, appName: appName, elementRole: roleName)
            tooltipPanel.show(near: screenPoint)
            speakIfEnabled(cached)
            return
        }

        initProviderIfNeeded()
        guard currentProvider != nil else {
            tooltipText = "LLM provider not configured. Open Settings to set up a provider."
            tooltipPanel.updateContent(text: tooltipText, isStreaming: false, appName: appName, elementRole: roleName)
            tooltipPanel.show(near: screenPoint)
            return
        }

        // Show loading state
        tooltipText = ""
        isStreaming = true
        tooltipPanel.updateContent(text: "", isStreaming: true, appName: appName, elementRole: roleName)
        tooltipPanel.show(near: screenPoint)

        if dualModel {
            await dualModelExplain(element: element, screenPoint: screenPoint, appName: appName, roleName: roleName)
        } else {
            await singleModelExplain(element: element, screenPoint: screenPoint, appName: appName, roleName: roleName)
        }
    }

    private func singleModelExplain(element: ElementContext, screenPoint: NSPoint, appName: String, roleName: String) async {
        guard let provider = currentProvider else { return }
        let screenshot = await screenCapture.captureWindow(pid: element.pid)

        do {
            for try await chunk in provider.streamExplanation(
                prompt: element.promptDescription,
                systemPrompt: Prompts.system,
                screenshot: screenshot,
                modelId: modelId,
                temperature: temperature,
                maxTokens: maxTokens,
                webSearch: activeWebSearch
            ) {
                guard !Task.isCancelled else { break }
                tooltipText += chunk
                tooltipPanel.updateContent(text: tooltipText, isStreaming: true)
            }
            guard !Task.isCancelled else { return }
            tooltipText = Self.trimToLastSentence(tooltipText)
            isStreaming = false
            if tooltipText.isEmpty {
                tooltipText = "No explanation available for this element."
                Log.info("[HoverMind] Stream completed with empty response")
            }
            tooltipPanel.updateContent(text: tooltipText, isStreaming: false)
            if !tooltipText.isEmpty && tooltipText != "No explanation available for this element." {
                cache.set(key: element.cacheKey, value: tooltipText)
                cacheCount = cache.count
                speakIfEnabled(tooltipText)
            }
        } catch {
            Log.info("[HoverMind] Stream error: \(error)")
            tooltipText = "Error: \(error.localizedDescription)"
            isStreaming = false
            tooltipPanel.updateContent(text: tooltipText, isStreaming: false)
        }
    }

    private func dualModelExplain(element: ElementContext, screenPoint: NSPoint, appName: String, roleName: String) async {
        guard let provider = currentProvider else { return }
        let fastId = fastModelId
        let prompt = element.promptDescription

        // Phase 1: Fast model (no screenshot for speed)
        Log.info("Dual mode: starting fast model (\(fastId))")
        do {
            for try await chunk in provider.streamExplanation(
                prompt: prompt, systemPrompt: Prompts.system,
                screenshot: nil, modelId: fastId,
                temperature: temperature, maxTokens: maxTokens,
                webSearch: activeWebSearch
            ) {
                guard !Task.isCancelled else { break }
                tooltipText += chunk
                tooltipPanel.updateContent(text: tooltipText, isStreaming: true, modelLabel: "Fast")
            }
            guard !Task.isCancelled else { return }
            tooltipText = Self.trimToLastSentence(tooltipText)
            Log.info("Fast model complete, \(tooltipText.count) chars")
        } catch {
            Log.error("Fast model failed: \(error.localizedDescription)")
        }

        if !tooltipText.isEmpty {
            isStreaming = false
            tooltipPanel.updateContent(text: tooltipText, isStreaming: false, modelLabel: "Fast")
            cache.set(key: element.cacheKey, value: tooltipText)
            cacheCount = cache.count
        }

        // Phase 2: Deep model in INDEPENDENT task.
        let capturedCacheKey = element.cacheKey
        deepModelTask?.cancel()
        deepModelTask = Task { [weak self] in
            guard let self else { return }
            Log.info("Dual mode: starting deep model (independent task)")
            let screenshot = await self.screenCapture.captureWindow(pid: element.pid)
            do {
                var deepText = ""
                for try await chunk in provider.streamExplanation(
                    prompt: prompt, systemPrompt: Prompts.system,
                    screenshot: screenshot, modelId: self.modelId,
                    temperature: self.temperature, maxTokens: self.maxTokens,
                    webSearch: self.activeWebSearch
                ) {
                    guard !Task.isCancelled else { return }
                    deepText += chunk
                }
                deepText = Self.trimToLastSentence(deepText)
                guard !Task.isCancelled, !deepText.isEmpty else { return }
                guard self.currentElement?.cacheKey == capturedCacheKey else {
                    Log.info("Deep model complete but element changed, caching only")
                    self.cache.set(key: capturedCacheKey, value: deepText)
                    self.cacheCount = self.cache.count
                    return
                }
                Log.info("Deep model complete, \(deepText.count) chars, replacing fast text")
                self.tooltipText = deepText
                self.isStreaming = false
                self.tooltipPanel.updateContent(text: deepText, isStreaming: false, modelLabel: "Deep")
                self.cache.set(key: capturedCacheKey, value: deepText)
                self.cacheCount = self.cache.count
                self.speakIfEnabled(deepText)
            } catch {
                Log.error("Deep model failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Region select

    private func startRegionSelect() {
        Log.info("[HoverMind] Region select triggered, isActive=\(isActive)")
        guard isActive else {
            Log.info("[HoverMind] Region select skipped: not active")
            return
        }
        dismissTooltip()
        regionOverlay.show()
    }

    private func explainRegion(_ cgRect: CGRect) {
        Task {
            Log.info("[HoverMind] Region selected: \(cgRect)")
            initProviderIfNeeded()
            guard let provider = currentProvider else { return }

            let screenshot = await screenCapture.captureRegion(rect: cgRect)

            guard let screenshot else {
                Log.info("[HoverMind] Region capture returned nil — check Screen Recording permission")
                guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
                let errPoint = NSPoint(x: cgRect.midX, y: primaryHeight - cgRect.maxY)
                tooltipText = "Screen Recording permission required. Grant access in System Settings > Privacy & Security > Screen Recording."
                tooltipPanel.updateContent(text: tooltipText, isStreaming: false, appName: "HoverMind", elementRole: "Error")
                tooltipPanel.show(near: errPoint)
                tooltipPanel.viewModel.showDismiss = true
                return
            }
            Log.info("[HoverMind] Region captured: \(screenshot.count) bytes")

            // Show tooltip near the center of the selection
            guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
            let screenPoint = NSPoint(
                x: cgRect.midX,
                y: primaryHeight - cgRect.maxY
            )

            tooltipText = ""
            isStreaming = true
            tooltipPanel.updateContent(text: "", isStreaming: true, appName: "Region", elementRole: "Screenshot")
            tooltipPanel.show(near: screenPoint)

            do {
                let regionPrompt = "Explain what is shown in this screenshot region. Describe the key elements and their purpose."
                for try await chunk in provider.streamExplanation(
                    prompt: regionPrompt,
                    systemPrompt: Prompts.system,
                    screenshot: screenshot,
                    modelId: modelId,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    webSearch: activeWebSearch
                ) {
                    guard !Task.isCancelled else { break }
                    tooltipText += chunk
                    tooltipPanel.updateContent(text: tooltipText, isStreaming: true)
                }
                isStreaming = false
                if tooltipText.isEmpty {
                    tooltipText = "Could not analyze this region."
                }
                tooltipPanel.updateContent(text: tooltipText, isStreaming: false)
                tooltipPanel.viewModel.showDismiss = true
                speakIfEnabled(tooltipText)
            } catch {
                Log.info("[HoverMind] Region explain error: \(error)")
                tooltipText = "Error: \(error.localizedDescription)"
                isStreaming = false
                tooltipPanel.updateContent(text: tooltipText, isStreaming: false)
                tooltipPanel.viewModel.showDismiss = true
            }
        }
    }

    /// Trims text to the last complete sentence (ending with . ! or ?).
    private static func trimToLastSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        if let last = trimmed.last, ".!?\"".contains(last) { return trimmed }
        // Find the last sentence-ending punctuation
        if let range = trimmed.range(of: "[.!?]", options: .regularExpression, range: nil, locale: nil) {
            var lastEnd = range.upperBound
            var searchRange = lastEnd..<trimmed.endIndex
            while let next = trimmed.range(of: "[.!?]", options: .regularExpression, range: searchRange, locale: nil) {
                lastEnd = next.upperBound
                if lastEnd < trimmed.endIndex {
                    searchRange = lastEnd..<trimmed.endIndex
                } else {
                    break
                }
            }
            return String(trimmed[..<lastEnd])
        }
        return text
    }

    private func initProviderIfNeeded() {
        guard currentProvider == nil else { return }
        do {
            switch providerType {
            case .bedrock:
                let bedrock = try BedrockService(
                    region: awsRegion,
                    modelId: modelId,
                    awsProfile: awsProfile.isEmpty ? nil : awsProfile
                )
                bedrockService = bedrock
                currentProvider = bedrock
            case .anthropic:
                guard !anthropicApiKey.isEmpty else {
                    Log.error("Anthropic API key not configured")
                    return
                }
                currentProvider = AnthropicProvider(apiKey: anthropicApiKey)
            case .openai:
                guard !openaiApiKey.isEmpty else {
                    Log.error("OpenAI API key not configured")
                    return
                }
                currentProvider = OpenAICompatibleProvider(
                    baseURL: "https://api.openai.com",
                    apiKey: openaiApiKey
                )
            case .openaiCompatible:
                currentProvider = OpenAICompatibleProvider(
                    baseURL: openaiCompatibleBaseURL,
                    apiKey: openaiCompatibleApiKey.isEmpty ? nil : openaiCompatibleApiKey
                )
            }
            Log.info("Provider initialized: \(providerType.rawValue)")
        } catch {
            Log.error("Provider init failed: \(error)")
        }
    }

    /// Speak the tooltip text aloud if TTS is enabled.
    private func speakIfEnabled(_ text: String) {
        guard ttsEnabled, !text.isEmpty else { return }
        ttsService.speak(text)
    }
}
