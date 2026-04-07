import SwiftUI

@main
struct HoverMindApp: App {
    @State private var appState = AppState()

    init() {
        // Menu bar-only app: no dock icon, no main window
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.isActive ? "eye.fill" : "eye")
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}
