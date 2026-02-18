import SwiftUI
import SwiftData

@main
struct ComputerSolitaireApp: App {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @FocusedValue(\.showSettingsCommand) private var showSettingsCommand
    @FocusedValue(\.showRulesAndScoringCommand) private var showRulesAndScoringCommand

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedGameRecord.self, isAutosaveEnabled: true, isUndoEnabled: false)
        .commands {
#if os(macOS)
            CommandGroup(replacing: .appInfo) {
                Button(action: {
                    openWindow(id: "about")
                }) {
                    Label("About Computer Solitaire", systemImage: "info.circle")
                }
            }
            CommandGroup(replacing: .help) {
                Button {
                    showRulesAndScoringCommand?.wrappedValue = true
                } label: {
                    Label("Rules & Scoring", systemImage: "book")
                }
                .disabled(showRulesAndScoringCommand == nil)
            }
#endif
            CommandGroup(replacing: .appSettings) {
                Button {
                    showSettingsCommand?.wrappedValue = true
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(showSettingsCommand == nil)
            }
        }
#if os(macOS)
        WindowGroup(id: "about") {
            AboutView()
                .navigationTitle("About Computer Solitaire")
                .frame(width: 320, height: 380)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
#endif
    }
}
