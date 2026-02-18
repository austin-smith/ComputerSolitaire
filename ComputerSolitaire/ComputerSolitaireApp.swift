import SwiftUI
import SwiftData

#if os(macOS)
private enum MainWindowMetrics {
    static let minWidth: CGFloat = 452
    static let minHeight: CGFloat = 460
}
#endif

@main
struct ComputerSolitaireApp: App {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    var body: some Scene {
#if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: MainWindowMetrics.minWidth, minHeight: MainWindowMetrics.minHeight)
        }
        .modelContainer(for: SavedGameRecord.self, isAutosaveEnabled: true, isUndoEnabled: false)
        .commands {
            appCommands
        }
        WindowGroup(id: "about") {
            AboutView()
                .navigationTitle("About Computer Solitaire")
                .frame(width: 320, height: 380)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
#else
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedGameRecord.self, isAutosaveEnabled: true, isUndoEnabled: false)
        .commands {
            appCommands
        }
#endif
    }

    @CommandsBuilder
    private var appCommands: some Commands {
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
                NotificationCenter.default.post(name: .openRulesAndScoring, object: nil)
            } label: {
                Label("Rules & Scoring", systemImage: "book")
            }
        }
#endif
        CommandGroup(replacing: .appSettings) {
            Button {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
