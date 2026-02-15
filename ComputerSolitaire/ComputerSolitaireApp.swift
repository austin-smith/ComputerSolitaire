import SwiftUI
import SwiftData

@main
struct ComputerSolitaireApp: App {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

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
#if os(macOS)
        WindowGroup(id: "about") {
            AboutView()
                .navigationTitle("About Computer Solitaire")
                .frame(width: 360, height: 420)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
#endif
    }
}
