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
#if DEBUG
            // Screenshot capture (`-screenshotWindowSize`): pin the content
            // area to the exact requested size; windowResizability below
            // makes the window conform, so the capture UI test gets exact
            // App Store pixels without any window manipulation.
            if let size = ScreenshotFixtures.requestedWindowSize {
                ContentView()
                    .frame(width: size.width, height: size.height)
            } else {
                mainWindowContent
            }
#else
            mainWindowContent
#endif
        }
        .windowResizability(mainWindowResizability)
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

#if os(macOS)
    private var mainWindowContent: some View {
        ContentView()
            .frame(minWidth: MainWindowMetrics.minWidth, minHeight: MainWindowMetrics.minHeight)
    }

    private var mainWindowResizability: WindowResizability {
#if DEBUG
        ScreenshotFixtures.requestedWindowSize != nil ? .contentSize : .automatic
#else
        .automatic
#endif
    }
#endif

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
        GameMenuCommands()
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
