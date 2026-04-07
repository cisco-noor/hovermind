import SwiftUI

struct MenuBarView: View {
    var appState: AppState

    var body: some View {
        if !appState.permissionGranted {
            Label("Accessibility permission required", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button("Open System Settings...") {
                AccessibilityService.openAccessibilitySettings()
            }
            Button("I've granted permission - check again") {
                appState.recheckPermission()
            }
            Divider()
        }

        if appState.isActive {
            Button("Pause HoverMind") {
                appState.stop()
            }
            .keyboardShortcut("p")
        } else {
            Button("Start HoverMind") {
                appState.start()
            }
            .keyboardShortcut("s")
        }

        Divider()

        LabeledContent("Cached") {
            Text("\(appState.cacheCount)")
        }

        Button("Clear Cache") {
            appState.cache.clear()
            appState.cacheCount = 0
        }

        Divider()

        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",")

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
