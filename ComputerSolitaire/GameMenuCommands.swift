import SwiftUI

#if os(macOS)
struct GameMenuActions {
    var newGame: () -> Void
    var redeal: () -> Void
    var undo: () -> Void
    var autoFinish: () -> Void
    var hint: () -> Void
    var showStatistics: () -> Void
}

struct GameMenuState {
    var canUndo: Bool
    var canAutoFinish: Bool
    var canHint: Bool
    var isAutoFinishing: Bool
}

private struct GameMenuActionsFocusedKey: FocusedValueKey {
    typealias Value = GameMenuActions
}

private struct GameMenuStateFocusedKey: FocusedValueKey {
    typealias Value = GameMenuState
}

extension FocusedValues {
    var gameMenuActions: GameMenuActions? {
        get { self[GameMenuActionsFocusedKey.self] }
        set { self[GameMenuActionsFocusedKey.self] = newValue }
    }

    var gameMenuState: GameMenuState? {
        get { self[GameMenuStateFocusedKey.self] }
        set { self[GameMenuStateFocusedKey.self] = newValue }
    }
}

struct GameMenuCommands: Commands {
    @FocusedValue(\.gameMenuActions) private var actions
    @FocusedValue(\.gameMenuState) private var state

    var body: some Commands {
        CommandMenu("Game") {
            Button {
                actions?.newGame()
            } label: {
                Label("New Game", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button {
                actions?.redeal()
            } label: {
                Label("Redeal", systemImage: "arrow.clockwise")
            }
            .disabled(actions == nil)

            Divider()

            Button {
                actions?.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(!(state?.canUndo ?? false))

            Button {
                actions?.autoFinish()
            } label: {
                Label(state?.isAutoFinishing == true ? "Stop Auto Finish" : "Auto Finish", systemImage: "bolt")
            }
            .disabled(!(state?.canAutoFinish ?? false))

            Button {
                actions?.hint()
            } label: {
                Label("Hint", systemImage: "lightbulb")
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(!(state?.canHint ?? false))

            Divider()

            Button {
                actions?.showStatistics()
            } label: {
                Label("Statistics…", systemImage: "chart.bar")
            }
            .disabled(actions == nil)
        }
    }
}
#endif
