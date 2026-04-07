# Contributing to HoverMind

## Reporting Bugs

Open an issue with:
- macOS version
- Steps to reproduce
- What you expected vs what happened
- Console output if relevant (`~/Library/Logs/HoverMind/hovermind.log`)

## Suggesting Features

Open an issue describing the use case, not just the feature. "I want to explain error messages in Terminal" is more useful than "add Terminal support."

## Pull Requests

1. Fork the repo
2. Create a branch from `main`
3. Make your changes
4. Run `swift build` to verify
5. Open a PR with a clear description of what changed and why

Keep PRs focused. One feature or fix per PR.

## Code Style

- Follow existing patterns in the codebase
- Use `@MainActor` for anything that touches UI state
- New LLM providers should conform to the `LLMProvider` protocol
- API keys go in the Keychain via `KeychainHelper`, never in UserDefaults

## Architecture

```
App/         → Entry point, central coordinator (AppState)
Services/    → LLM providers, accessibility, screen capture, TTS
Models/      → Data types (ElementContext)
UI/          → SwiftUI views, NSPanel tooltip, settings
```

## Building

```bash
swift build          # debug build
swift build -c release  # release build
./build-and-run.sh   # build, bundle, sign, launch
```
