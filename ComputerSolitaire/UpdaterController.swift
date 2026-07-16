#if os(macOS) && canImport(Sparkle)
import Combine
import Sparkle
import SwiftUI

/// App-lifetime owner of the Sparkle updater for the direct-download build.
/// Mac App Store builds don't link Sparkle, so this file compiles away and
/// every call site is guarded the same way.
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    @Published private(set) var canCheckForUpdates = false

    private let standardController: SPUStandardUpdaterController

    private init() {
        standardController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        standardController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    var automaticallyChecksForUpdates: Bool {
        get { standardController.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            standardController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        standardController.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = UpdaterController.shared

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}

struct UpdatesSettingsRows: View {
    @ObservedObject private var updater = UpdaterController.shared

    var body: some View {
        Toggle("Automatically check for updates", isOn: automaticallyChecksForUpdates)
            .toggleStyle(.switch)
    }

    private var automaticallyChecksForUpdates: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }
}
#endif
