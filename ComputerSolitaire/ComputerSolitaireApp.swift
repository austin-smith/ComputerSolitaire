import SwiftUI
import SwiftData

@main
struct ComputerSolitaireApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedGameRecord.self, isAutosaveEnabled: true, isUndoEnabled: false)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
